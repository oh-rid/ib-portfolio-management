---
name: ib-connector
description: This skill should be used when the user asks to "get live market data", "fetch option chain", "check current price", "show positions", "get account summary", "search for a contract", "get historical bars", "check session status", "check margin requirements", "am I at risk of liquidation", "what's my buying power", "run a market scan", or mentions IB, IBKR, Interactive Brokers, IB CP Gateway, secdef, conid, market data snapshot, portfolio ledger, or margin metrics in the context of real-time data, current positions, or live account state. Requires CP Gateway running on localhost:5000.
---

# IB Client Portal Gateway — Live Data Reference

## Official Documentation

- **Swagger (full endpoint list)**: https://interactivebrokers.github.io/cpwebapi/ (requires JS)
- **IBKR Campus API hub**: https://www.interactivebrokers.com/campus/ibkr-api-page/cpapi-v1/
- **Institutional CP API PDF**: https://www.interactivebrokers.com/download/CP_API.pdf
- **Web API Changelog**: https://www.interactivebrokers.com/campus/ibkr-api-page/web-api-changelog/

Base URL for all requests: `https://localhost:5000/v1/api`

All requests use `curl -sk` (self-signed cert, silent).

**Placeholder convention:** `${ACCOUNT_ID}` in curl examples is your IB account
identifier (looks like `U1234567` or `DU1234567` for paper). Fetch it once with
`curl -sk https://localhost:5000/v1/api/portfolio/accounts` and either export it
(`export ACCOUNT_ID=U1234567`) or substitute it into the URLs.

## SAFETY — NO ORDERS

This plugin is for **read-only market data** only.

NEVER call these endpoints:
- `POST /iserver/account/{id}/order` — places a live order
- `POST /iserver/account/{id}/orders` — places multiple orders
- `DELETE /iserver/account/{id}/order/{orderId}` — cancels order
- `POST /iserver/reply/{replyid}` — confirms order execution

Orders through CP Gateway go **straight to market** after a 2-step API confirmation (no UI dialog like TWS Desktop). There is no undo.

If the user asks to place an order, tell them to use TWS Desktop or IB mobile app.

---

## 1. Session Management

### Check session (ALWAYS do first)

```bash
curl -sk https://localhost:5000/v1/api/tickle
```

Response includes `iserver.authStatus.authenticated` (true/false).

- `"authenticated":true` — proceed
- `"authenticated":false` — tell user: "Open https://localhost:5000 in browser and log in again"
- Connection refused — Gateway not running, tell user: run `/ib-start`

### Auth status (detailed)

```bash
curl -sk -X POST https://localhost:5000/v1/api/iserver/auth/status
```

Returns: `authenticated`, `competing`, `connected`, `serverInfo`.

### SSO validate

```bash
curl -sk https://localhost:5000/v1/api/sso/validate
```

Returns `USER_NAME`, `USER_ID`, `RESULT`, `features`, `region`.

### Competition warning

If user is logged into TWS/mobile with the same account, `"competing":true` appears.
The CP Gateway session will kick out the other session. The `competing` flag in `/tickle` response indicates this is happening.

### Session lifetime

- Sessions last ~24h, then require browser re-login
- Laptop sleep kills the session
- Call `/tickle` periodically to keep alive (the Gateway handles this internally)
- Weekend: IB servers down Friday ~23:45 UTC to Sunday ~17:00 UTC

### Logout

```bash
curl -sk -X POST https://localhost:5000/v1/api/logout
```

---

## 2. Contract Search & Security Definitions

### Search by symbol (POST)

```bash
curl -sk -X POST https://localhost:5000/v1/api/iserver/secdef/search \
  -H "Content-Type: application/json" \
  -d '{"symbol":"AAPL","secType":"STK"}'
```

Returns array with `conid`, `companyName`, `companyHeader`, `sections` (lists derivative types: OPT, FUT, CFD, WAR, BAG).

**GOTCHA**: Search returns multiple matches. The first result is usually the US-listed version. Check `companyHeader` for the exchange (e.g., "ARCA", "NASDAQ.NMS", "MEXI").

**`sections` structure** — indicates what derivatives exist:
- `secType: "OPT"` — options available, includes `months` (semicolon-separated `MMMYY` format) and `exchange` list
- `secType: "FUT"` — futures available
- `secType: "CFD"` — CFD available, includes its own `conid`

### Contract details by conid

```bash
curl -sk https://localhost:5000/v1/api/iserver/contract/265598/info
```

Returns: `symbol`, `company_name`, `instrument_type`, `currency`, `exchange`, `valid_exchanges`, `industry`, `category`, `con_id`, `trading_class`, `multiplier`, `expiry_full`, `r_t_h` (regular trading hours supported).

### Stock search (multiple symbols at once)

```bash
curl -sk "https://localhost:5000/v1/api/trsrv/stocks?symbols=AAPL,MSFT,SPY"
```

Returns object keyed by symbol, each containing array of contracts across exchanges.

### Futures search

```bash
curl -sk "https://localhost:5000/v1/api/trsrv/futures?symbols=ES,NQ"
```

Returns object keyed by symbol. Each entry is an array of futures contracts with `conid`, `expirationDate` (YYYYMMDD), `ltd` (last trading day), `underlyingConid`.

### Bulk security definitions (POST, by conid list)

```bash
curl -sk -X POST https://localhost:5000/v1/api/trsrv/secdef \
  -H "Content-Type: application/json" \
  -d '{"conids":[265598,756733]}'
```

Returns definitions for a list of conids.

---

## 3. Option Chain Flow (3 Steps)

### Step 1: Search underlying (get conid + available months)

```bash
curl -sk -X POST https://localhost:5000/v1/api/iserver/secdef/search \
  -H "Content-Type: application/json" \
  -d '{"symbol":"SPY","secType":"STK"}'
```

From response, extract `conid` (e.g., 756733) and from `sections` where `secType:"OPT"`, get `months` (e.g., `"MAR26;APR26;MAY26;..."`) and `exchange`.

### Step 2: Get strikes for a specific month

```bash
curl -sk "https://localhost:5000/v1/api/iserver/secdef/strikes?conid=756733&sectype=OPT&month=MAR26&exchange=SMART"
```

Returns `{"call":[...], "put":[...]}` — arrays of available strike prices.

**Month format**: `MMMYY` (e.g., `MAR26`, `APR26`, `JUN26`, `DEC26`).

### Step 3: Get specific option contract

```bash
curl -sk "https://localhost:5000/v1/api/iserver/secdef/info?conid=756733&sectype=OPT&month=MAR26&strike=570&right=C"
```

- `right=C` for calls, `right=P` for puts
- Returns the option's own conid, expiry, multiplier, etc.
- Use this conid for market data snapshot

---

## 4. Market Data Snapshots

### CRITICAL: Preflight behavior

**First call for a new conid returns empty/minimal data** — it initiates the subscription. **Second call (after ~1 sec) returns actual data.**

```bash
# Call 1: initiates subscription (returns mostly empty)
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/snapshot?conids=265598&fields=31,84,86"

sleep 1

# Call 2: returns real data
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/snapshot?conids=265598&fields=31,84,86"
```

### Parameters

- `conids` — comma-separated, **max 100** per request
- `fields` — comma-separated field codes, **max 50**

### Field Codes (verified on live Gateway)

| Code | Key in response | Meaning |
|------|----------------|---------|
| 31 | `31` | Last price |
| 55 | `55` | Symbol |
| 70 | `70` | Day high |
| 71 | `71` | Day low |
| 82 | `82` | Change (price) |
| 83 | `83` | Change (%) |
| 84 | `84` | Bid price |
| 85 | `85` | Ask size |
| 86 | `86` | Ask price |
| 87 | `87` | Volume (formatted, e.g. "38.2M") |
| 88 | `88` | Bid size |
| 6008 | `6008` | Contract ID |
| 6070 | `6070` | Security type (STK, OPT, FUT...) |
| 6119 | `6119` | Server ID |
| 6457 | `6457` | Underlying conid |
| 6509 | `6509` | Market data availability code |
| 7221 | `7221` | Listing exchange |
| 7282 | `7282` | Day volume (formatted, e.g. "48.3M") |
| 7283 | `7283` | ? (returned "27.692%" in test — possibly day range %) |
| 7284 | `7284` | ? (returned "26.940%" in test) |
| 7289 | `7289` | Market cap |
| 7290 | `7290` | P/E ratio |
| 7291 | `7291` | Volume |
| 7295 | `7295` | Previous close / settlement |
| 7308-7311 | — | Option computations / Greeks. **Verify against your Gateway version** — these codes are unstable across IB releases. The legacy fields 7633-7637 (IV / Delta / Gamma / Vega / Theta) appear in older docs but may not return data on current Gateway. Test with a known liquid option (e.g. SPY ATM call) before relying. |

**GOTCHA — `6509` market data availability codes**:
- `R` = Real-time
- `D` = Delayed (15 min)
- `Z` = Frozen
- `Y` = Frozen delayed
- `P` = Delayed snapshot only (no streaming)
- Combinations like `RpB` = Real-time with snapshot data

**GOTCHA — formatted vs raw values**: Volume fields (87, 7282) return formatted strings like `"38.2M"`. The raw numeric value is in `87_raw`, `7282_raw` etc.

**GOTCHA — field codes 7282-7284**: These are NOT well-documented. The official Swagger says to expand the "Model" section for the full list, but many codes are undocumented. Always test on live Gateway before relying on a code.

### Unsubscribe market data

```bash
# Single conid
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/265598/unsubscribe"

# All
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/unsubscribeall"
```

---

## 5. Historical Market Data (OHLCV)

```bash
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/history?conid=265598&period=5d&bar=1d"
```

### Parameters

| Param | Required | Values |
|-------|----------|--------|
| `conid` | yes | Contract ID |
| `period` | yes | `1d`, `2d`, `1w`, `2w`, `1m`, `2m`, `3m`, `6m`, `1y`, `2y`, `3y`, `5y` |
| `bar` | yes | `1min`, `2min`, `3min`, `5min`, `10min`, `15min`, `30min`, `1h`, `2h`, `3h`, `4h`, `8h`, `1d`, `1w`, `1m` |
| `outsideRth` | no | `true`/`false` (include extended hours, default false) |
| `startTime` | no | `YYYYMMDD-HH:MM:SS` format |

### Response

```json
{
  "symbol": "AAPL",
  "text": "APPLE INC",
  "timePeriod": "5d",
  "barLength": 86400,
  "mdAvailability": "S",
  "data": [
    {"o": 274.88, "c": 272.95, "h": 276.11, "l": 270.79, "v": 152314.91, "t": 1772116200000}
  ]
}
```

- `o/c/h/l` = open/close/high/low
- `v` = volume (in units defined by `volumeFactor`)
- `t` = timestamp (epoch ms)

**GOTCHA — max 5 concurrent history requests**. If exceeded, returns HTTP 429. Space requests.

**GOTCHA — `priceFactor` and `volumeFactor`**: Prices and volumes in `high`/`low` summary fields use these factors. The `data[]` array contains already-adjusted values.

---

## 6. Portfolio & Account

### List accounts (MUST call first)

```bash
curl -sk https://localhost:5000/v1/api/portfolio/accounts
```

**IMPORTANT**: This endpoint MUST be called before any other `/portfolio/` endpoint. It initializes the portfolio backend.

Returns: `id`, `accountId`, `currency`, `type`, `tradingType`, `displayName`.

### Positions (paginated, 30 per page)

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/positions/0"
```

Page numbers start at 0. Returns array with: `conid`, `contractDesc`, `position`, `mktPrice`, `mktValue`, `avgCost`, `avgPrice`, `realizedPnl`, `unrealizedPnl`, `currency`, `assetClass`, `expiry`, `putOrCall`, `strike`, `multiplier`.

**GOTCHA**: Returns positions from all currency segments. `mktValue` is in the position's `currency`, NOT in account base currency.

### Account summary

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/summary"
```

Returns object keyed by metric name. Each value has `amount`, `currency`, `timestamp`.
Key fields: `netliquidationvalue`, `availablefunds`, `buyingpower`, `equitywithloanvalue`, `excessliquidity`, `cushion`, `accruedcash`.

**Key margin metrics explained**:
- **Init Margin Req** (`initmarginreq`) — equity required to OPEN new positions. Higher than maintenance. If available funds < init margin → can't open new trades.
- **Maint Margin Req** (`maintmarginreq`) — equity required to HOLD existing positions. If NLV drops below this → margin call / liquidation.
- **Excess Liquidity** (`excessliquidity`) — NLV minus Maint Margin. The **distance to liquidation**. If it hits 0 → IB starts liquidating.
- **Available Funds** (`availablefunds`) — NLV minus Init Margin. The amount available to open NEW positions.
- **Cushion** (`cushion`) — Excess Liquidity as % of NLV. E.g., 0.33 = 33% buffer before liquidation.

### Cash balances (ledger) — multi-currency

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/ledger"
```

Returns object keyed by currency (e.g., `"USD"`, `"EUR"`, `"HKD"`, `"BASE"`).
Each contains: `cashbalance`, `settledcash`, `netliquidationvalue`, `stockmarketvalue`, `unrealizedpnl`, `realizedpnl`, `exchangerate`.

`BASE` key = account totals converted to base currency.

### Invalidate position cache

```bash
curl -sk -X POST "https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/positions/invalidate"
```

Call this if positions seem stale. Forces backend refresh.

### Allocation

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/${ACCOUNT_ID}/allocation"
```

Returns allocation breakdown by asset class, sector, group.

---

## 7. PnL & Trades

### PnL by account

```bash
curl -sk "https://localhost:5000/v1/api/iserver/account/pnl/partitioned"
```

Returns `upnl` object with unrealized PnL grouped by account/model.
Fields: `dpl` (daily P&L), `upl` (unrealized P&L), `nl` (net liquidation), `el` (excess liquidity), `mv` (market value).

**GOTCHA**: May return `{"upnl":{}}` if no active positions or if the market data subscription hasn't been initialized.

### Recent trades (last 7 days only)

```bash
curl -sk "https://localhost:5000/v1/api/iserver/account/trades"
```

Returns trades from current day + 6 prior trading days. Empty array `[]` if no trades.
Per the official Swagger docs: "Lists trades for current day + 6 prior".

### Transaction history by position (up to any period)

```bash
curl -sk -X POST "https://localhost:5000/v1/api/pa/transactions" \
  -H "Content-Type: application/json" \
  -d '{"acctIds":["${ACCOUNT_ID}"],"conids":[265598],"currency":"USD","days":365}'
```

Returns full buy/sell/dividend/transfer history for specific conids.

Response includes `transactions` array with: `date`, `rawDate`, `pr` (price), `qty`, `type` (Buy/Sell/Dividend), `amt` (amount in requested currency), `fxRate`, `cur` (original currency), `desc`, `conid`, `acctid`.
Also includes `rpnl` (realized P&L).

**GOTCHA — parameter types are strict**:
- `days` MUST be a number (`365`), NOT a string (`"365"`) — returns 400 otherwise
- `conids` MUST be a non-empty array of numbers (`[265598]`), NOT empty `[]` — returns 400 otherwise
- The conid(s) must be known upfront — no "give me all transactions" option
- To get all transactions: first call `/portfolio/{id}/positions/0` to get all conids, then call `/pa/transactions` for each

**GOTCHA — mixed asset types return incomplete data**:
- When querying stocks + options conids together, only stock trades may return
- **Always query option conids separately** (one at a time or in option-only batches)
- This is a silent failure — no error, just missing data

**GOTCHA — expired/closed positions**:
- `/pa/transactions` requires conids, but expired options and closed positions disappear from `/iserver/secdef/search` and `/iserver/secdef/info`
- There is NO endpoint on CP Gateway to discover historical/expired conids
- For closed position history → use Flex Web Service (see `ib-reference` skill)

### Account performance (cumulative returns over time)

```bash
curl -sk -X POST "https://localhost:5000/v1/api/pa/performance" \
  -H "Content-Type: application/json" \
  -d '{"acctIds":["${ACCOUNT_ID}"],"freq":"M","period":"1Y"}'
```

- `freq`: `D` (daily), `M` (monthly), `Q` (quarterly)
- `period`: `1M`, `3M`, `6M`, `1Y`, `2Y`, `3Y`, `5Y`

Returns:
- `cps.data[].returns` — cumulative return series (daily array)
- `tpps.data[].returns` — per-period returns (monthly/quarterly)
- `nav.data[].navs` — NAV (net asset value) series in base currency
- `nav.data[].startNAV` — starting NAV with date

### PA summary (balance chart)

```bash
curl -sk -X POST "https://localhost:5000/v1/api/pa/summary" \
  -H "Content-Type: application/json" \
  -d '{"acctIds":["${ACCOUNT_ID}"]}'
```

Returns: `total` with `startVal`, `endVal`, `chg`, `rtn` (return %), and `balanceByDate` time series.

---

## 8. Market Scanner

### Get available scan types

```bash
curl -sk "https://localhost:5000/v1/api/iserver/scanner/params"
```

Returns: `scan_type_list` (563 scan types), `instrument_list` (18 instruments), `filter_list` (597 filters), `location_tree` (17 regions).

### Run a scan

```bash
curl -sk -X POST https://localhost:5000/v1/api/iserver/scanner/run \
  -H "Content-Type: application/json" \
  -d '{"instrument":"STK","type":"TOP_PERC_GAIN","location":"STK.US.MAJOR","filter":[{"code":"priceAbove","value":10}]}'
```

---

## 9. Rate Limits

- **10 requests per second** across all endpoints combined
- **5 concurrent** `/iserver/marketdata/history` requests (HTTP 429 if exceeded)
- **100 conids** max per `/iserver/marketdata/snapshot` request
- **50 fields** max per snapshot request
- Space requests with `sleep 0.1` when making multiple calls

---

## 10. Common Errors

### REST API errors

| Error | Meaning | Fix |
|-------|---------|-----|
| `{"error":"no bridge"}` | Brokerage session not ready | Call `/iserver/auth/status`, re-auth in browser |
| `"not authenticated"` | Session expired (24h or sleep) | Re-login in browser |
| Connection refused | Gateway not running | Run `/ib-start` |
| HTTP 429 | Rate limit exceeded | Wait and retry, space requests |
| `{"error":"..."}` with empty data | Preflight call (normal for snapshot) | Call again after 1 sec |

For WTE error codes, see **`references/error-codes.md`**.

---

## 11. Ticker Verification

**CRITICAL — ZERO ASSUMPTIONS RULE**: NEVER assume what asset a ticker represents based on its name. ALWAYS call `/iserver/contract/{conid}/info` and verify `company_name` and `instrument_type` BEFORE mentioning the asset to the user. This applies to:

- Displaying positions or trades
- Summarizing P&L by instrument
- Any analysis that names an asset

Even if the ticker was seen before, even if the mapping was written previously — **verify every time**. Getting a ticker wrong in a financial report is unacceptable.

### Known naming traps

**Canonical list lives in [`ib-reference`](../ib-reference/SKILL.md)** —
DERIVATIVES → "Verify Futures Tickers Before Interpreting" section (richer
table, futures-symbol-structure decoder, mandatory verification process).
Don't maintain a duplicate here.

### Verification command

```bash
curl -sk "https://localhost:5000/v1/api/iserver/contract/{conid}/info" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d.get('symbol')} = {d.get('company_name')} ({d.get('instrument_type')})\")"
```

---

## Quick Reference: All Read-Only Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/tickle` | Keep-alive, session check |
| POST | `/iserver/auth/status` | Auth status |
| GET | `/sso/validate` | SSO session info |
| POST | `/logout` | End session |
| POST | `/iserver/secdef/search` | Search contracts by symbol |
| GET | `/iserver/secdef/strikes` | Option strikes for month |
| GET | `/iserver/secdef/info` | Specific option/future contract |
| GET | `/iserver/contract/{conid}/info` | Full contract details |
| GET | `/trsrv/stocks?symbols=X` | Stock search |
| GET | `/trsrv/futures?symbols=X` | Futures search |
| POST | `/trsrv/secdef` | Bulk security definitions |
| GET | `/iserver/marketdata/snapshot` | Real-time quotes (preflight!) |
| GET | `/iserver/marketdata/{conid}/unsubscribe` | Unsubscribe single |
| GET | `/iserver/marketdata/unsubscribeall` | Unsubscribe all |
| GET | `/iserver/marketdata/history` | Historical OHLCV bars |
| GET | `/portfolio/accounts` | List accounts (call first!) |
| GET | `/portfolio/{id}/positions/{page}` | Positions (paginated, 30/page, iterate 0,1,2... until []) |
| GET | `/portfolio/{id}/position/{conid}` | Single position |
| GET | `/portfolio/{id}/summary` | Account summary |
| GET | `/portfolio/{id}/ledger` | Cash balances by currency |
| GET | `/portfolio/{id}/allocation` | Allocation breakdown |
| POST | `/portfolio/{id}/positions/invalidate` | Force position refresh |
| GET | `/iserver/account/pnl/partitioned` | PnL breakdown |
| GET | `/iserver/account/trades` | Recent trades (7 days) |
| POST | `/pa/transactions` | Transaction history by conid (any period) |
| POST | `/pa/performance` | Account performance / NAV curve |
| POST | `/pa/summary` | Balance summary with chart |
| GET | `/iserver/scanner/params` | Scanner types & filters |
| POST | `/iserver/scanner/run` | Run market scanner |
| GET | `/fyi/unreadnumber` | Unread notification count |
| GET | `/fyi/notifications` | Notification list |

---

## 12. Gateway Limitations Summary

What CP Gateway **CANNOT** do (confirmed by exhaustive testing):

1. **Full trade history** — only 7 days via `/iserver/account/trades`. `/pa/transactions` works for longer periods but requires known conids.
2. **Discover historical conids** — expired options, delisted stocks, closed futures positions are gone from secdef search. No endpoint returns them.
3. **OAuth 2.0 / Unified Web API** (`/gw/api/v1/*`) — exists at `api.ibkr.com` but requires OAuth 2.0 with `private_key_jwt`. **Institutional accounts only** — NOT available for retail/individual accounts. IB says "being considered for individual access, no ETA."
4. **Positions history** — `/portfolio/{id}/positions/history` exists (undocumented) but returns same data as current positions, NOT historical.
5. **Order history beyond current session** — `/iserver/account/orders` only shows orders from current brokerage session.

**Bottom line**: For anything historical beyond 7 days → use Flex Web Service (see `ib-reference` skill). It's not a workaround, it's the designed solution for retail accounts.

---

## Additional Resources

- **`references/websocket-streaming.md`** — Websocket connection, market data and chart subscriptions, tick rates
- **`references/error-codes.md`** — WTE error codes from CP API (for debugging connection/auth issues)
