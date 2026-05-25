# Scripts

CLI utilities for Interactive Brokers data ingestion and processing.

For schema / protocol / quirks knowledge (Closed Lots field semantics, Flex
error codes, P&L methods, etc.) see the [`ib-reference`](../skills/ib-reference/SKILL.md)
skill. For live REST endpoints see [`ib-connector`](../skills/ib-connector/SKILL.md).

## Two distinct IB APIs (not interchangeable)

| Script | API | Purpose |
|---|---|---|
| `gateway.sh` | **CP Gateway** (localhost:5000) | Live market data — quotes, chains, positions, account state. Requires 2FA via browser every 24h. This plugin is **read-only** — the `block-orders.sh` hook denies any order endpoint. |
| `flex_query.py`, `closed_lots_to_xlsx.py` | **Flex Web Service** (HTTP, long-lived token) | EOD reporting — trades, closed lots, statements. No 2FA, just a token in `.env`. |

`gateway.sh <PLUGIN_ROOT> <start|stop|status|setup|update>` is the unified entry
point used by the `/ib-gateway` slash command. The single-purpose wrappers
remain for ad-hoc shell use.

## Output convention

All outputs go to `portfolio/ib/` in the **current working directory** (your
project root, not the plugin install dir):

```
portfolio/ib/
├── {YYYY-MM-DD}_snapshot.{json,md}        # ad-hoc CP Gateway snapshots
├── tax/{YYYY}/
│   ├── closed_lots_{YYYY}.xml              # flex_query.py output
│   └── Closed_Lots_{YYYY}_EUR.xlsx         # closed_lots_to_xlsx.py output
├── statements/                              # raw monthly/annual statements
└── drills/                                  # ad-hoc analyses
```

The convention is portable — load the plugin into any project and the same
`portfolio/ib/` tree is created at that project's root.

## Tax-year closed-lots workflow (EU-style EUR reporting)

### One-time setup

1. **Flex token** — Client Portal → Settings → Reporting → Flex Web Service
   Configuration. Store in `.env` at the plugin root:
   ```
   IB_FLEX_TOKEN="..."
   ```

2. **Activity Flex Query** with Trades section, **Options → Closed Lots ✓**,
   Period = Custom Date Range. Store the query ID:
   ```
   IB_FLEX_QUERY_CLOSED_LOTS="..."
   ```

   Required fields: `openDateTime`, `fxRateToBase`, `costBasis`,
   `fifoPnlRealized`, `openCloseIndicator`, `notes`, plus the standard
   identifiers (symbol/conid/ISIN/etc.). See the `ib-reference` skill for the
   full list.

3. **ECB historical rates** (one-time, for EUR conversion of trades in other
   currencies):
   ```bash
   mkdir -p data/ecb && cd data/ecb && \
   curl -sSLO https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.zip && \
   unzip -o eurofxref-hist.zip
   ```

### Pull a tax-year report

From your project root:

```bash
/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/flex_query.py --year 2025
/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/closed_lots_to_xlsx.py --year 2025
```

`--year YYYY` auto-resolves dates and paths under `portfolio/ib/tax/{YYYY}/`.
Override individually via `--from`/`--to`/`--out`/`--xml`.

`$CLAUDE_PLUGIN_ROOT` is set by Claude Code when the plugin is loaded; outside
the plugin runtime, use the absolute install path
(`~/.claude/plugins/local/plugins/ib-portfolio-management/scripts/...`).

## Sanity-check policy

The `closed_lots_to_xlsx.py` output should always be cross-checked against the
Activity Flex query (executions-level) before sending to an accountant. The
`<Lot>` schema has non-obvious field semantics — see the **CLOSED LOTS — schema**
section in the `ib-reference` skill. At minimum verify:

1. Per-symbol P&L sum matches between Closed Lots and Activity queries.
2. Total realized P&L USD matches IB's own total.
3. For at least one option position: buy/sell counts in Activity match the
   `LONG`/`SHORT` direction shown in Closed Lots (e.g., 10 buys + 10 sells
   implies a LONG that was closed, should be labeled `Direction=LONG`).
