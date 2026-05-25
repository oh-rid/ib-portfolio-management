# ib-portfolio-management

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin for working
with Interactive Brokers from the terminal — lifecycle for the Client Portal
Gateway, IB REST + Flex Web Service skills, an options strategy framework,
portfolio reporting / rebalance / tax-loss-harvest workflows, and an
order-blocking hook so the assistant cannot accidentally place a trade.

**Read-only by design.** The `block-orders.sh` PreToolUse hook denies any
Bash call that hits an order or order-reply endpoint. Orders go through TWS
Desktop or the IB mobile app — never through this plugin.

Not affiliated with Interactive Brokers.

## Two IB APIs — and why you need both

IB exposes account state through two completely different APIs. This plugin
wraps both because each fills a gap the other can't.

| API | What it gives you | What it can't | Setup cost |
|---|---|---|---|
| **CP Gateway** (`localhost:5000`) | Live quotes, option chains, current positions, account state, margin metrics, Greeks. Authenticated by your normal IB login + 2FA every ~24h | **Only the last 7 days of trades.** No tax-year history, no closed-lots P&L, no realized FIFO across years | Required. Step 5-6 in install |
| **Flex Web Service** (`ndcdyn.interactivebrokers.com`) | **Full trade history**, closed lots with cost basis, realized P&L, dividends, fees — anything you'd put in an accountant's report. Server-side, long-lived token, no 2FA | No live quotes, no real-time prices, no order book. Updates once daily at EOD | Optional. Only needed for tax-year reports or analysis of pre-7-day history. Step 7 in install |

If you only want `/finance` to answer "how's my portfolio looking right now,
am I at liquidation risk, what's the option chain for AAPL" — Steps 1-6 are
enough and you can skip Flex. If you want EUR-converted tax-year XLSX
reports or to analyze closed positions from last quarter — also do Step 7.

---

## Contents

- [What's in the box](#whats-in-the-box)
- [Components — what each piece does](#components--what-each-piece-does)
  - [The `/finance` command and `portfolio-agent`](#the-finance-command-and-portfolio-agent-subagent)
  - [The `/ib-gateway` command](#the-ib-gateway-command)
  - [Hooks](#hooks)
  - [Skills (auto-loaded by Claude)](#skills-auto-loaded-by-claude)
  - [Scripts (CLI utilities)](#scripts-cli-utilities)
- [Install from scratch](#install-from-scratch)
- [Daily usage](#daily-usage)
- [How read-only is enforced](#how-read-only-is-enforced)
- [Layout](#layout)
- [Security notes](#security-notes)

---

## What's in the box

| Component | Path | What it does |
|---|---|---|
| `/ib-gateway` command | `commands/ib-gateway.md` | `start`, `stop`, `status`, `setup`, `update` for the local CP Gateway |
| `/finance` command | `commands/finance/COMMAND.md` | Spawns the `portfolio-agent` subagent for portfolio questions |
| `portfolio-agent` | `agents/portfolio-agent.md` | Pulls live IB state + applies the loaded skills |
| `ib-connector` skill | `skills/ib-connector/` | Live REST endpoint reference for the CP Gateway |
| `ib-reference` skill | `skills/ib-reference/` | Flex Web Service schema, common mistakes, Closed-Lots semantics |
| `options` skill | `skills/options/` | Options strategy framework, Greeks, spread mechanics |
| `portfolio-report` skill | `skills/portfolio-report/` | Snapshot report — P&L, allocation, key metrics from live IB data |
| `portfolio-rebalance` skill | `skills/portfolio-rebalance/` | Drift analysis against a target allocation |
| `tax-loss-harvest` skill | `skills/tax-loss-harvest/` | Scan positions for tax-loss harvesting opportunities |
| `flex_query.py` | `scripts/` | IB Flex Web Service runner (SendRequest → poll GetStatement) |
| `closed_lots_to_xlsx.py` | `scripts/` | Flex XML → accountant-ready EUR XLSX with ECB rate conversion |
| `block-orders.sh` hook | `hooks/scripts/` | PreToolUse — denies any Bash call to `/iserver/account/*/order*` or `/iserver/reply/*` |
| `check-gateway.sh` hook | `hooks/scripts/` | SessionStart — tells Claude whether the Gateway is up and authenticated |

---

## Components — what each piece does

### The `/finance` command and `portfolio-agent` subagent

`/finance <your question>` is the main entry point for portfolio-level
questions. It spawns the `portfolio-agent` subagent in a fresh context. The
agent has read-only tools (`Read`, `Grep`, `Glob`, `Bash`) — it can run curl
against the local Gateway, parse output, read files, but cannot edit code or
write outside `portfolio/ib/`.

What's preloaded into the agent:

- **`ib-connector`** — knows every CP Gateway REST endpoint, the gotchas, the
  response shapes. Lets it pull live quotes, chains, positions, margin
  metrics, performance.
- **`ib-reference`** — knows the Flex Web Service, common IB data mistakes,
  Closed-Lots `<Lot>` schema, futures-symbol semantics, multi-currency FX
  handling.
- **`options`** — options strategy framework (spreads, Greeks, money
  management, expiration mechanics).
- **`portfolio-report`** — generates portfolio snapshots (P&L, allocation,
  margin headroom).
- **`portfolio-rebalance`** — drift analysis against a target allocation.
- **`tax-loss-harvest`** — scans positions for unrealized losses, suggests
  harvest candidates respecting wash-sale rules.

When you write `/finance check my margin headroom and tell me if I'm at
liquidation risk`, the agent typically does:

1. SessionStart hook has already reported whether the Gateway is up. If not,
   the agent asks you to `/ib-gateway start` first.
2. `GET /portfolio/accounts` → pick `accountId`.
3. `GET /portfolio/{accountId}/summary` → read `netliquidationvalue`,
   `maintmarginreq`, `excessliquidity`, `cushion`.
4. Applies the cushion/excess-liquidity interpretation from the
   `ib-connector` skill (cushion 0.33 = 33% distance to liquidation).
5. Tells you the answer with numbers, in your language. No tools state.

You can also call the IB REST endpoints from any plain Bash in the main
session — the `ib-connector` skill auto-loads when you mention things like
"option chain", "live market data", "positions", "margin metrics".

### The `/ib-gateway` command

Manages the local IB Client Portal Gateway (the Java process IB ships for
their REST API). Subcommands:

| Subcommand | What it does |
|---|---|
| `setup` | Downloads the Gateway zip from IB (~23M of jars + configs), extracts to `gateway/`, patches `conf.yaml`, saves a version checksum, optionally walks you through Flex Web Service setup |
| `start [TIMEOUT_MIN]` | Starts the Gateway in the background. Default auto-stop is 30 min — pass an int to override (e.g. `/ib-gateway start 120` for 2h) |
| `stop` | Stops the Gateway process and the auto-kill timer |
| `status` | Reports running/stopped, authenticated/not, brokerage-connected/not |
| `update` | Compares your installed Gateway checksum against IB's current download; if changed, stops, replaces the binary, preserves your `conf.yaml` |

All subcommands delegate to `scripts/gateway.sh`. The 30-min auto-stop on
`start` is deliberate — an idle authenticated Gateway is a long-lived auth
cookie sitting on your laptop.

### Hooks

Two hooks ship enabled in `hooks/hooks.json`.

**`block-orders.sh` — PreToolUse, matcher `Bash`.**
Reads every Bash invocation and `permissionDecision: deny`s the call if the
command contains any of:

- `POST /iserver/account/{id}/order` — place an order
- `POST /iserver/account/{id}/orders` — place multiple orders
- `DELETE /iserver/account/{id}/order/{orderId}` — cancel an order
- `POST /iserver/reply/{replyid}` — confirm order execution after the 2-step
  challenge

This is a tool-level safety net. Even if Claude were prompted to place a
trade, the hook blocks the curl before it runs.

**`check-gateway.sh` — SessionStart, matcher `*`.**
On every Claude Code session start: checks whether the Gateway process is
running, and if so whether the IB session is authenticated. Outputs a
`systemMessage` so Claude sees the state before you ask anything — it knows
to suggest `/ib-gateway start` instead of trying curl and getting
`Connection refused`.

### Skills (auto-loaded by Claude)

Skills are markdown files that Claude loads when the conversation matches
trigger phrases listed in the skill's frontmatter. You don't invoke them
explicitly. The plugin ships these:

| Skill | Auto-loads when you mention | What it knows |
|---|---|---|
| `ib-connector` | "live market data", "option chain", "show positions", "margin metrics", "am I at risk of liquidation", "buying power", "session status" | All CP Gateway endpoints, response shapes, pagination, every documented gotcha |
| `ib-reference` | "parse Flex XML", "calculate P&L from IB data", "reconcile balances", "handle multi-currency", "verify a ticker", "fxRateToBase" | Flex Web Service protocol, Closed-Lots schema, futures-symbol traps (MET ≠ Micro E-mini!), MTM vs FIFO, currency handling |
| `options` | "analyze option positions", "select an option strategy", "construct a spread", "evaluate volatility", "interpret Greeks", "iron condor", "ratio spread" | Strategy menu, Greeks, spread mechanics, Kelly sizing, expiration management |
| `portfolio-report` | "portfolio report", "portfolio summary", "how's my portfolio", "show me my positions", "P&L report" | Compact snapshot format — P&L attribution, allocation, key risk metrics |
| `portfolio-rebalance` | "rebalance", "portfolio drift", "allocation check", "am I overweight", "am I underweight" | Drift detection against a target allocation, trade list generation |
| `tax-loss-harvest` | "tax loss harvest", "TLH", "harvest losses", "what can I sell for a tax loss", "year-end tax planning" | Unrealized loss scanning, wash-sale rule logic, harvest candidate ranking |

Skills are independent — you can use them outside the `portfolio-agent` too.
Anywhere in a Claude Code conversation, mention an option chain and
`ib-connector` will load.

### Scripts (CLI utilities)

Live in `scripts/`. Two kinds, talking to two different IB APIs:

- **`gateway.sh`** — orchestrates the CP Gateway (Java process, localhost
  REST). Called via `/ib-gateway`.
- **`flex_query.py`** — talks to the IB Flex Web Service (server-side
  reporting, HTTP, long-lived token). Pulls trade history beyond CP
  Gateway's 7-day window.
- **`closed_lots_to_xlsx.py`** — converts Flex Closed-Lots XML into an
  accountant-ready EUR XLSX using ECB reference rates. Multi-sheet output:
  Closed Lots / Summary by Symbol / Manual Review Required / ECB Rates
  Audit / Metadata.

Full conventions and the tax-year workflow in
[`scripts/README.md`](scripts/README.md).

---

## Install from scratch

This walks you through a fresh setup — you've never used Claude Code, you've
never used the IB Client Portal Gateway, you don't have a Flex token. Time:
~30 min, most of which is waiting for IB account verification on a first-time
account.

### Step 0 — IB account

You need an Interactive Brokers account with:

- **Working login** to the [Client Portal](https://www.interactivebrokers.com/portal)
  (the web app at `interactivebrokers.com/portal`, not TWS Desktop).
- **2FA set up.** IB will not let the Gateway API authenticate without it.
  Easiest: install the **IB Key** app on your phone and enroll. SMS and
  hardware token also work.
- **Trading permissions for what you want to read.** IB gates market data by
  instrument class and region — Client Portal → Settings → Account Settings
  → **Trading Permissions**. Without options permission, you can't pull
  option chains even read-only.
- **Market-data subscriptions** for any non-free instruments (most
  international exchanges, US options, futures depth). Client Portal →
  Settings → Account Settings → **Market Data Subscriptions**. The CP
  Gateway returns nothing for instruments you're not subscribed to.

A **paper account** (ID prefix `DU`) is free and works identically to live
for everything in this plugin — same Gateway, same Flex, same APIs. If
you're trying the plugin out, use paper. Open one from Client Portal →
Settings → Account Settings → **Paper Trading Account**.

### Step 1 — System dependencies

The plugin needs three things:

```bash
# macOS (Homebrew)
brew install openjdk python jq
# openjdk is keg-only; the plugin's setup will find it at the Homebrew path

# Debian / Ubuntu
sudo apt update
sudo apt install default-jre python3 python3-pip jq

# Fedora / RHEL
sudo dnf install java-latest-openjdk python3 python3-pip jq
```

Then the one Python package for the Flex → XLSX converter:

```bash
pip3 install openpyxl   # or: pip install openpyxl
```

On macOS specifically: `/usr/bin/java` is a **stub that doesn't work** — it
exists but launches an "install Java" dialog. The scripts check with
`java -version` (not `command -v java`) so they correctly fall through to
the Homebrew path when needed.

### Step 2 — Install Claude Code

If you don't have it yet, follow [the official install guide](https://docs.claude.com/en/docs/claude-code/quickstart).
TL;DR for macOS / Linux:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Open a fresh terminal so `claude` is on your PATH.

### Step 3 — Clone the plugin

```bash
git clone https://github.com/oh-rid/ib-portfolio-management \
  ~/.claude/plugins/local/plugins/ib-portfolio-management
```

The directory name (`ib-portfolio-management`) matters — the plugin's
manifest expects that exact name and the gateway-fallback path in
`scripts/gateway.sh` looks here too.

### Step 4 — Enable the plugin in Claude Code

Edit `~/.claude/settings.json` (create it if it doesn't exist):

```json
{
  "enabledPlugins": {
    "ib-portfolio-management@local": true
  },
  "sandbox": {
    "allowLocalBinding": true,
    "allowedDomains": ["localhost"]
  }
}
```

Both sandbox lines matter. The CP Gateway listens on `https://localhost:5000`
and Claude Code's sandbox blocks local binding by default — without
`allowLocalBinding: true`, listing `localhost` alone does nothing and your
subagent will get connection-refused on every curl.

Restart Claude Code. In a fresh session you should see `/ib-gateway` and
`/finance` in the slash-command list, and on session start a system message
about the Gateway state ("not running" the first time).

### Step 5 — Download the IB Client Portal Gateway binary

This is IB's own Java app (~23M of jars, keystores, configs). The plugin
does not ship it — `setup` fetches it fresh from IB's CDN:

```
/ib-gateway setup
```

This downloads, extracts to `~/.claude/plugins/local/plugins/ib-portfolio-management/gateway/`,
patches the listen port into `conf.yaml`, and saves a version checksum so
`/ib-gateway update` later can tell when IB ships a new build.

### Step 6 — First start + log in

```
/ib-gateway start
```

The Gateway boots in the background. The command prints a URL like
`https://localhost:5000`. Open it in your normal browser:

1. **Browser warning** — the Gateway uses a self-signed cert. Click through
   ("Advanced → Proceed to localhost"). This is expected. Per IB's design
   it's a localhost-only service; no public CA is involved.
2. **Username / password** — same credentials as the Client Portal web app.
3. **2FA challenge** — approve from IB Key, type the SMS code, or use your
   hardware token.

Then verify the session:

```
/ib-gateway status
```

You want to see `Session: AUTHENTICATED` and `Brokerage: CONNECTED`. If you
see authenticated-but-not-connected, click through the additional consent
screen in the browser tab.

#### If the API stays 401 after a successful browser login

This happens sometimes — the SSO succeeds but the Dispatcher handoff that
mints the API session cookie doesn't fire. Force it:

```bash
curl -sk https://localhost:5000/sso/Dispatcher
```

That single call wakes the Dispatcher and gives you `Client login succeeds`.
Re-run `/ib-gateway status` and authentication should be live.

#### The Gateway will auto-stop in 30 minutes

By design. Restart it with `/ib-gateway start` (you'll have to log in again
— IB rotates the session). For longer windows: `/ib-gateway start 120` (2h),
`/ib-gateway start 480` (8h, full workday). IB tightens its own session
expiry independently — you'll be asked to reauth every 6-24h regardless.

### Step 7 — (Optional) Flex Web Service for full trade history

The CP Gateway returns only the last **7 days** of trades. For annual tax
reports or any historical analysis you need IB Flex Web Service. One-time
setup:

1. Client Portal → **Performance & Statements** → **Flex Queries** →
   **Flex Web Service** → click **Configure** → generate a token.
   The token is long-lived (renews when you regenerate). No 2FA, just the
   token. Treat it like a password — it can read your full trade history.
2. Still in **Flex Queries** → **Activity Statement** → **New Activity
   Statement**. Configure:
   - **Period**: `Custom Date Range` (so the script can override per call)
   - **Sections**: enable **Trades**
   - **Inside Trades**: enable **Options → Closed Lots ✓** (this is what the
     tax-year XLSX workflow needs)
   - **Format**: XML
   - **Fields**: keep the standard identifier set, plus `openDateTime`,
     `fxRateToBase`, `costBasis`, `fifoPnlRealized`, `openCloseIndicator`,
     `notes`. The `ib-reference` skill has the full required-fields list.
3. Note the **Query ID** (integer, top-right of the saved query).
4. Copy `.env.example` → `.env` and fill in:
   ```
   IB_FLEX_TOKEN="<the token from step 1>"
   IB_FLEX_QUERY_TRADES="<query id from step 3>"
   IB_FLEX_QUERY_CLOSED_LOTS="<same id if it has Closed Lots, or a separate query>"
   ```

`.env` is in `.gitignore` — it stays on your machine.

5. For the EUR conversion you need ECB historical rates (one-time download):
   ```bash
   mkdir -p data/ecb && cd data/ecb && \
   curl -sSLO https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.zip && \
   unzip -o eurofxref-hist.zip
   ```

Now you can pull a tax year:

```bash
/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/flex_query.py --year 2025
#   → portfolio/ib/tax/2025/closed_lots_2025.xml

/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/closed_lots_to_xlsx.py --year 2025
#   → portfolio/ib/tax/2025/Closed_Lots_2025_EUR.xlsx
```

The XLSX has a `Manual Review Required` sheet for any lots where IB's
recorded cost basis is non-derivable (transferred-in positions, crypto-trust
spin-offs, option rolls with carry-over basis). The `Metadata` sheet
documents the methodology so an accountant can audit without reading code.

---

## For Claude Code agents — automated install + verification

If a user asks you (the agent) to install this plugin, work through this
recipe. Each step has an explicit verification command — if it doesn't
match the `# Expect:` line, stop and report instead of barrelling on.

### Step 1 — Check prerequisites

```bash
# Java
java -version 2>&1 | head -1 || \
  ls /opt/homebrew/opt/openjdk/bin/java /usr/local/opt/openjdk/bin/java 2>/dev/null
# Expect: a Java version line, or a Homebrew Java path

# Python + openpyxl (only needed for the tax XLSX workflow)
/usr/bin/python3 -c "import openpyxl; print(openpyxl.__version__)"
# Expect: a version like "3.1.x" — if it errors, run: pip3 install openpyxl

command -v jq
# Expect: a path like /opt/homebrew/bin/jq
```

If anything is missing: tell the user the exact `brew install` / `apt install`
command from the [Step 1 — System dependencies](#step-1--system-dependencies)
section above. Do NOT install system packages on the user's behalf without
asking.

### Step 2 — Clone the plugin

```bash
PLUGIN_DIR="$HOME/.claude/plugins/local/plugins/ib-portfolio-management"

# Refuse to overwrite an existing install — ask the user first
if [ -e "$PLUGIN_DIR" ]; then
  echo "ALREADY INSTALLED at $PLUGIN_DIR — ask user before touching"
else
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  git clone https://github.com/oh-rid/ib-portfolio-management "$PLUGIN_DIR"
fi

# Verify
test -f "$PLUGIN_DIR/.claude-plugin/plugin.json" && echo OK
# Expect: OK
```

### Step 3 — Enable in `~/.claude/settings.json` (non-destructive merge)

Never overwrite `settings.json` — the user may have other plugins or
unrelated config. Merge with jq:

```bash
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"   # backup, just in case

jq '
  .enabledPlugins["ib-portfolio-management@local"] = true
  | .sandbox = ((.sandbox // {}) + {
      "allowLocalBinding": true,
      "allowedDomains": ((.sandbox.allowedDomains // []) + ["localhost"] | unique)
    })
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

# Verify
jq -r '.enabledPlugins["ib-portfolio-management@local"], .sandbox.allowLocalBinding' "$SETTINGS"
# Expect: two lines, both "true"
```

### Step 4 — Ask the user to restart Claude Code

You cannot restart the host yourself. Tell the user:

> "Restart Claude Code (`/exit` then relaunch) so the plugin loads. After
> restart, say `ready` and I'll verify the rest."

When the user comes back, sanity-check the plugin is visible:

```bash
test -f "$HOME/.claude/plugins/local/plugins/ib-portfolio-management/scripts/gateway.sh" && echo OK
# Expect: OK   (you can't introspect Claude's slash-command registry directly)
```

### Step 5 — Download the IB Gateway binary

```bash
PLUGIN_DIR="$HOME/.claude/plugins/local/plugins/ib-portfolio-management"
bash "$PLUGIN_DIR/scripts/gateway.sh" "$PLUGIN_DIR" setup

# Verify
test -f "$PLUGIN_DIR/gateway/bin/run.sh" && echo OK
# Expect: OK   (file appears after ~5-10 sec download from IB CDN)
```

### Step 6 — Start the Gateway

```bash
bash "$PLUGIN_DIR/scripts/gateway.sh" "$PLUGIN_DIR" start

# Verify process is alive
sleep 5 && pgrep -f clientportal.gw && echo "PROCESS_OK"
# Expect: a PID, then "PROCESS_OK"

# Verify port responding (will be 401 until login — that's fine, we just need a response)
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost:5000/v1/api/tickle
# Expect: 401 (unauthenticated, but Gateway is up) — NOT "000" (connection refused)
```

### Step 7 — User logs in via browser

Tell the user:

> "Open https://localhost:5000 in your browser, accept the self-signed cert
> warning ('Advanced → Proceed'), log in with your IB credentials and 2FA.
> Say `logged in` when done."

When they confirm, verify auth:

```bash
curl -sk https://localhost:5000/v1/api/tickle | jq -r '.iserver.authStatus.authenticated // false'
# Expect: true
```

If `false` after browser login, the SSO handoff stalled — kick it:

```bash
curl -sk https://localhost:5000/sso/Dispatcher
# Expect: "Client login succeeds"

# Re-verify
curl -sk https://localhost:5000/v1/api/tickle | jq -r '.iserver.authStatus.authenticated'
# Expect: true
```

### Step 8 — End-to-end smoke test

Prove the connector actually returns real data:

```bash
# Account ID
ACCOUNT_ID=$(curl -sk https://localhost:5000/v1/api/portfolio/accounts | jq -r '.[0].accountId')
echo "Account: $ACCOUNT_ID"
# Expect: U + 7 digits (live) or DU + 7 digits (paper)

# A real quote (SPY conid is 756733)
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/snapshot?conids=756733&fields=31,84,86" \
  | jq '.[0] | {symbol: ._updated, last: ."31", bid: ."84", ask: ."86"}'
# Expect: an object with numeric last/bid/ask. NOTE: first snapshot call sometimes
# returns empty — call again after 1 second if so (documented gotcha in ib-connector skill).

# Portfolio summary
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCOUNT_ID/summary" \
  | jq '{nlv: .netliquidationvalue.amount, cushion: .cushion.amount}'
# Expect: numeric NLV and cushion fields
```

If all three return real numbers, the install is live. Report success to
the user with the account ID and NLV, and tell them they can now use
`/finance <question>` for portfolio analysis.

### Step 9 — (Optional) Flex Web Service setup

Only do this if the user wants more than the last 7 days of trades
(tax-year reports, historical P&L, closed-lots → EUR XLSX). If they just
want live data and `/finance` questions, Steps 1-8 are enough.

You **cannot** click through the IB Client Portal web UI on the user's
behalf. Walk them through it, then take the values they paste back and
write them to `.env`.

**Tell the user, verbatim:**

> Open https://www.interactivebrokers.com/portal in a browser and log in.
> Then:
>
> **1. Generate a Flex token**
> - Top menu → **Performance & Statements** → **Flex Queries**
> - Scroll to **Flex Web Service** → click **Configure**
> - Click **Enable** (or **Generate New Token** if already enabled)
> - Copy the token (long numeric string, ~24 digits). It's shown ONCE —
>   save it now or regenerate later.
>
> **2. Create an Activity Flex Query for trades**
> - Same page → **Flex Queries** → **Activity Flex Query** → **New Activity Statement**
> - **Format**: XML
> - **Period**: `Custom Date Range` (lets the script override dates with `--year` / `--from` / `--to`)
> - **Sections**: enable **Trades**
> - Inside **Trades** → set **Level of Detail = Execution**
> - **Save**. Note the **Query ID** (integer, ~7 digits, shown next to the
>   query name in the list).
>
> **3. (Optional) Create a Closed-Lots query for tax workflow**
> - Same flow → **New Activity Statement**
> - Same settings as above, plus inside **Trades** → enable **Options → Closed Lots ✓**
>   and set **Level of Detail = Closed Lot**
> - Required fields: `openDateTime`, `fxRateToBase`, `costBasis`,
>   `fifoPnlRealized`, `openCloseIndicator`, `notes` (plus the standard
>   identifier set IB enables by default). See `skills/ib-reference/SKILL.md`
>   for the rationale on each field.
> - **Save**. Note the second **Query ID**.
>
> Paste back: the token, the Trades query ID, and (optionally) the
> Closed-Lots query ID.

**When the user returns with the values**, write them to `.env` using the
Write tool (NOT a shell heredoc — `cat > .env <<EOF` will echo the token
into shell history):

- File path: `$PLUGIN_DIR/.env` (i.e. inside the plugin directory itself).
  This is where `flex_query.py` looks by default — see
  `scripts/flex_query.py` `default_env` logic.
- Format (use `.env.example` as the exact template):
  ```
  IB_FLEX_TOKEN="<token from step 1>"
  IB_FLEX_QUERY_TRADES="<query id from step 2>"
  IB_FLEX_QUERY_CLOSED_LOTS="<query id from step 3, or leave blank>"
  ```
- After writing, confirm `.env` is gitignored — `cat $PLUGIN_DIR/.gitignore | grep -q '^\.env$' && echo OK` should print `OK`. (It already is, but verify.)
- Do **not** echo the token back to the user in your reply. Confirm by
  saying "saved to .env" without quoting the value.

**Verify the credentials actually work** with a single SendRequest
(rate-limit is 1 req/sec / 10 req/min — keep it to one call):

```bash
PLUGIN_DIR="$HOME/.claude/plugins/local/plugins/ib-portfolio-management"
set -a; . "$PLUGIN_DIR/.env"; set +a

curl -s -A "ib-portfolio-mgmt-install-test/1.0" \
  "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest?t=${IB_FLEX_TOKEN}&q=${IB_FLEX_QUERY_TRADES}&v=3" \
  | python3 -c "import sys,xml.etree.ElementTree as ET; r=ET.fromstring(sys.stdin.read()); print('STATUS:', r.findtext('Status'), '| CODE:', r.findtext('ErrorCode') or '-', '| REF:', (r.findtext('ReferenceCode') or '-')[:8])"
# Expect: STATUS: Success | CODE: - | REF: <8-char ref>
# If STATUS: Warn / Fail and CODE: 1003 (Invalid token) or 1004 (Invalid query) — creds are wrong, ask the user to recheck
```

If `Success` — the token is valid and the query exists. End-to-end
behavior (XML actually produced) is then exercised by the user's first
real `flex_query.py --year` call; don't burn rate-limit budget here.

### Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `connection refused` on curl | Gateway not running, or port mismatch | `pgrep -f clientportal.gw`; check `conf.yaml` for actual `listenPort` |
| `authenticated: false` after browser login | SSO handoff didn't fire | `curl -sk https://localhost:5000/sso/Dispatcher` |
| `Gateway not installed` from setup | Java missing or download failed | Check Step 1, re-run setup |
| Snapshot returns `{}` first call | IB requires preflight | Call snapshot a second time after 1 sec |
| `/finance` not in slash list | Plugin not enabled or Claude not restarted | Re-check Step 3 + ask user to restart |
| 30 min later, all curls return 401 | Auto-stop kicked in | Tell user to re-`start` (and re-login) |
| Flex `ErrorCode 1003` | Invalid token | Token was rotated / mistyped — regenerate in Client Portal |
| Flex `ErrorCode 1004` | Invalid query ID | Query was deleted or ID typo — recheck the Query ID column in IB UI |
| Flex `ErrorCode 1012` | Token expired | Regenerate in Client Portal → Flex Web Service → Configure |
| Flex `ErrorCode 1019` on GetStatement | Report still generating | Retry GetStatement after a few seconds (the runner does this automatically) |

If you hit something not in this table, read the `ib-connector` skill —
it has the full gotcha list.

---

## Daily usage

### Most common loop

```
/ib-gateway start                                 # log in via browser
/finance how's my portfolio, anything to hedge?   # ask the agent
/ib-gateway stop                                  # done
```

### Useful one-liners (agent or you, in plain Bash)

```bash
# Account list
curl -sk https://localhost:5000/v1/api/portfolio/accounts

# Set ACCOUNT_ID once
export ACCOUNT_ID=U1234567

# Margin headroom
curl -sk https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/summary | jq '{
  netliq: .netliquidationvalue.amount,
  maint:  .maintmarginreq.amount,
  excess: .excessliquidity.amount,
  cushion: .cushion.amount
}'

# Current positions
curl -sk https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/positions/0

# Quote
curl -sk "https://localhost:5000/v1/api/iserver/secdef/search?symbol=AAPL&secType=STK"
# pick conid from the response
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/snapshot?conids=265598&fields=31,84,85,86"
```

All endpoints + gotchas documented in
[`skills/ib-connector/SKILL.md`](skills/ib-connector/SKILL.md).

### Example agent prompts

```
/finance check my margin headroom and tell me if I'm at liquidation risk
/finance pull a portfolio snapshot, group by asset class
/finance what's my biggest unrealized loss, would TLH make sense?
/finance my target is 60/30/10 stocks/bonds/cash — how far have I drifted?
/finance walk me through the AAPL option chain for next month's expiration
```

### Tax workflow

```bash
/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/flex_query.py --year 2025
/usr/bin/python3 $CLAUDE_PLUGIN_ROOT/scripts/closed_lots_to_xlsx.py --year 2025
```

Outputs go to `portfolio/ib/tax/2025/` in your current working directory.

---

## How read-only is enforced

Two layers:

1. **Skill text** — `ib-connector` and `portfolio-agent` say NO ORDERS in
   capital letters.
2. **PreToolUse hook** — `block-orders.sh` reads every Bash invocation and
   denies it if the command matches `/iserver/account/{id}/order*` or
   `/iserver/reply/*`. Even if Claude were tricked into trying to place an
   order, the hook returns `permissionDecision: deny` before the call runs.

Both layers ship enabled by `hooks/hooks.json`. If you actively want to send
orders through code, you should not use this plugin — IB's TWS Desktop has a
manual confirmation dialog by design; the CP Gateway does not.

---

## Layout

```
ib-portfolio-management/
├── .claude-plugin/plugin.json   # plugin manifest
├── .env.example                 # copy to .env and fill in your Flex creds
├── .gitignore                   # .env, gateway/, *.log, etc.
├── LICENSE                      # MIT
├── README.md
├── agents/portfolio-agent.md
├── commands/
│   ├── finance/COMMAND.md       # /finance <question>
│   └── ib-gateway.md            # /ib-gateway <subcommand>
├── hooks/
│   ├── hooks.json
│   └── scripts/
│       ├── block-orders.sh      # PreToolUse — deny order endpoints
│       └── check-gateway.sh     # SessionStart — report Gateway state
├── scripts/
│   ├── README.md                # scripts conventions + tax workflow
│   ├── gateway.sh               # unified start/stop/status/setup/update
│   ├── flex_query.py            # IB Flex Web Service runner
│   └── closed_lots_to_xlsx.py   # Flex XML → EUR XLSX
└── skills/                      # auto-loaded by Claude on matching phrases
    ├── ib-connector/            # live REST reference
    ├── ib-reference/            # Flex schema + common mistakes
    ├── options/                 # options framework
    ├── portfolio-report/
    ├── portfolio-rebalance/
    └── tax-loss-harvest/
```

The IB Gateway binary distribution (`gateway/`, ~23M of jars + configs) is
downloaded fresh by `/ib-gateway setup` and never checked in.

---

## Security notes

- The CP Gateway listens on `https://localhost:5000` with a self-signed cert
  (so `curl -sk` everywhere). Keep it on localhost. Do not expose to the
  network — there is no extra auth layer.
- The Flex token in `.env` reads activity reports. It cannot place trades and
  cannot move funds, but it can read your full trade history — treat it like
  a password.
- The 30-minute auto-stop on `/ib-gateway start` is deliberate: an idle
  authenticated Gateway is a long-lived session cookie sitting on your
  laptop.
- IB Key 2FA approval lives in your phone — losing your phone without backup
  2FA codes locks you out of the Gateway just like the web Portal.

---

## Contributing

PRs welcome. If you find an IB endpoint that's wrong / undocumented / has a
new gotcha, the `ib-connector` and `ib-reference` skills are the right place
to put it.

## License

MIT — see [LICENSE](LICENSE).
