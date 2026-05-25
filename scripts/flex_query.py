#!/usr/bin/env python3
"""
IB Flex Web Service runner.

Two-step protocol:
  1. SendRequest  -> ReferenceCode
  2. GetStatement -> XML report (poll if not ready)

Reads IB_FLEX_TOKEN and a query-id env var from plugins/ib-gateway/.env.
Output: raw XML written to stdout or --out file.

Usage:
  # Convenience: fetch full calendar year, auto-place in portfolio/ib/tax/{YYYY}/
  flex_query.py --year 2025
  flex_query.py --year 2025 --query-env IB_FLEX_QUERY_CLOSED_LOTS  # explicit query

  # Manual: explicit dates and output path
  flex_query.py --query-env IB_FLEX_QUERY_CLOSED_LOTS \\
                --from 20250101 --to 20251231 --out path/to/file.xml
  flex_query.py --query-id 1234567   # explicit query id (placeholder)

Convention: outputs go to portfolio/ib/tax/{YYYY}/closed_lots_{YYYY}.xml by
default when --year is used. See plugins/ib-gateway/scripts/README.md.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

BASE = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"
USER_AGENT = "finance-flex-runner/1.0"
TRANSIENT_ERRORS = {"1001", "1004", "1005", "1006", "1007", "1008", "1009", "1019", "1021"}


def load_env(env_path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not env_path.exists():
        return out
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def http_get(url: str, timeout: int = 30) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8")


def send_request(token: str, query_id: str,
                 from_date: str | None = None,
                 to_date: str | None = None) -> str:
    params = {"t": token, "q": query_id, "v": "3"}
    if from_date:
        params["fd"] = from_date
    if to_date:
        params["td"] = to_date
    qs = urllib.parse.urlencode(params)
    body = http_get(f"{BASE}/SendRequest?{qs}")
    root = ET.fromstring(body)
    status = (root.findtext("Status") or "").strip()
    if status != "Success":
        code = (root.findtext("ErrorCode") or "").strip()
        msg = (root.findtext("ErrorMessage") or "").strip()
        raise RuntimeError(f"SendRequest failed: status={status} code={code} msg={msg}")
    ref = (root.findtext("ReferenceCode") or "").strip()
    if not ref:
        raise RuntimeError(f"SendRequest returned no ReferenceCode: {body[:300]}")
    return ref


def get_statement(token: str, ref: str, max_wait_s: int = 240) -> str:
    """Poll GetStatement until ready. Retry on transient errors (1019 etc)."""
    qs = urllib.parse.urlencode({"t": token, "q": ref, "v": "3"})
    url = f"{BASE}/GetStatement?{qs}"
    deadline = time.time() + max_wait_s
    delay = 3.0
    attempt = 0
    while True:
        attempt += 1
        body = http_get(url)
        # If body is a Flex status XML, it's still generating or errored.
        # Real statements start with <FlexQueryResponse ...> (or are CSV-like).
        if body.lstrip().startswith("<FlexQueryResponse"):
            return body
        # Parse status envelope
        try:
            root = ET.fromstring(body)
            status = (root.findtext("Status") or "").strip()
            code = (root.findtext("ErrorCode") or "").strip()
            msg = (root.findtext("ErrorMessage") or "").strip()
        except ET.ParseError:
            status, code, msg = "?", "?", body[:200]
        if status == "Success":
            # Sometimes Success but content not in <FlexQueryResponse> root — return as-is
            return body
        if code in TRANSIENT_ERRORS and time.time() < deadline:
            print(f"[{attempt}] not ready (code={code} {msg[:80]}), retry in {delay:.0f}s",
                  file=sys.stderr)
            time.sleep(delay)
            delay = min(delay * 1.5, 20.0)
            continue
        raise RuntimeError(f"GetStatement failed: status={status} code={code} msg={msg}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--query-env", default="IB_FLEX_QUERY_TRADES",
                   help="Env var name holding query id (default IB_FLEX_QUERY_TRADES)")
    p.add_argument("--query-id", help="Explicit query id (overrides --query-env)")
    p.add_argument("--token-env", default="IB_FLEX_TOKEN")
    # Default .env location: $CLAUDE_PLUGIN_ROOT/.env when invoked through the
    # plugin runtime, otherwise next to this script's parent (sibling of scripts/).
    default_env = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if default_env:
        default_env = str(Path(default_env) / ".env")
    else:
        default_env = str(Path(__file__).resolve().parent.parent / ".env")
    p.add_argument("--env-file", default=default_env,
                   help="Path to .env (parsed manually, no python-dotenv dep)")
    p.add_argument("--out", help="Write XML to file; otherwise stdout")
    p.add_argument("--max-wait", type=int, default=240,
                   help="Max polling seconds (default 240)")
    p.add_argument("--from", dest="from_date",
                   help="fromDate override (YYYYMMDD) for Custom Date Range queries")
    p.add_argument("--to", dest="to_date",
                   help="toDate override (YYYYMMDD) for Custom Date Range queries")
    p.add_argument("--year", type=int,
                   help="Shortcut: full calendar year. Sets --from, --to, --out automatically. "
                        "Output: portfolio/ib/tax/{YEAR}/closed_lots_{YEAR}.xml (creates dir). "
                        "Also defaults --query-env to IB_FLEX_QUERY_CLOSED_LOTS if not set.")
    args = p.parse_args()

    # --year shortcut: derives dates, output path, and default query env
    if args.year:
        if not args.from_date:
            args.from_date = f"{args.year}0101"
        if not args.to_date:
            args.to_date = f"{args.year}1231"
        if not args.out:
            out_dir = Path("portfolio/ib/tax") / str(args.year)
            out_dir.mkdir(parents=True, exist_ok=True)
            args.out = str(out_dir / f"closed_lots_{args.year}.xml")
        # Default to Closed-Lots query when --year is used (most common use case)
        if args.query_env == "IB_FLEX_QUERY_TRADES":
            args.query_env = "IB_FLEX_QUERY_CLOSED_LOTS"

    env = load_env(Path(args.env_file))
    # Process env overrides file
    env = {**env, **{k: v for k, v in os.environ.items() if k in (args.token_env, args.query_env)}}

    token = env.get(args.token_env)
    if not token:
        print(f"ERROR: {args.token_env} not set", file=sys.stderr)
        return 2
    query_id = args.query_id or env.get(args.query_env)
    if not query_id:
        print(f"ERROR: query id not provided (--query-id or {args.query_env})", file=sys.stderr)
        return 2

    date_note = f" fd={args.from_date} td={args.to_date}" if args.from_date or args.to_date else ""
    print(f"SendRequest query={query_id}{date_note} ...", file=sys.stderr)
    ref = send_request(token, query_id, args.from_date, args.to_date)
    print(f"ReferenceCode={ref}", file=sys.stderr)
    print(f"GetStatement (poll up to {args.max_wait}s) ...", file=sys.stderr)
    xml = get_statement(token, ref, max_wait_s=args.max_wait)
    if args.out:
        Path(args.out).write_text(xml)
        print(f"Wrote {len(xml):,} bytes -> {args.out}", file=sys.stderr)
    else:
        print(xml)
    return 0


if __name__ == "__main__":
    sys.exit(main())
