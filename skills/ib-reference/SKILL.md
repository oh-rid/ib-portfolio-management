---
name: ib-reference
description: This skill should be used when the user asks to "parse Flex XML report", "calculate P&L from IB data", "reconcile IB balances", "fetch trade history via Flex", "handle multi-currency positions", "convert IB FX rates", "verify a ticker symbol", or discusses IB, IBKR, Interactive Brokers in the context of data parsing, Flex Web Service, Flex queries, IB report formats, MTM vs FIFO P&L, fxRateToBase, multiplier logic, or IB report reconciliation. Reference layer for IB data formats, common mistakes, and the Flex API.
---

# Interactive Brokers Reference

Quick-scan reference for avoiding common mistakes when working with IB data.

## TOP AGENT MISTAKES

| # | Mistake | Reality |
|---|---------|---------|
| 1 | **Guessing what a futures ticker means** | IB futures symbols are NOT obvious. MET = Micro **Ether**, NOT Micro E-mini. MSL = Micro **SOL** (Solana), NOT Micro Silver. SIL = Micro Silver. MES = Micro E-mini S&P. **ALWAYS verify on cmegroup.com before interpreting.** |
| 2 | Treating MTM P&L as net profit | MTM shows commissions as **separate line**. FIFO includes them in cost basis. You MUST subtract commissions from MTM to get true net. |
| 3 | Ignoring `multiplier` for derivatives | Options: multiply by 100 (usually). Futures: contract-specific. Formula: `quantity * price * multiplier = value`. |
| 4 | Applying `fxRateToBase` wrong | It is a **multiplier**: `amount_in_trade_ccy * fxRateToBase = amount_in_base_ccy`. NOT a divisor. |
| 5 | Assuming one timezone | IB uses exchange-local for P&L reset, EST for statement cutoffs, no single "IB timezone". |
| 6 | Confusing Ending Cash with available money | Ending Cash = trade-date basis (includes unsettled). Ending Settled Cash = what you actually have. Interest accrues on settled only. |
| 7 | **Misreading Closed Lots `<Lot>` schema** | `tradePrice` in `<Lot>` is the **OPEN** price, NOT the close price. `cost` = opening cost basis. `buySell` = **closing trade direction** universally (SELL=closed long, BUY=closed short) — same rule for STK, OPT, FOP, FUT. Close price is NOT stored — derive from `realized`. **Always cross-check interpretation against Activity Flex (executions-level) before trusting Closed Lots labels.** |
| 8 | Assuming account base is USD | Many EU accounts have **base = EUR**. Check Account Information section or read CashReport `BASE_SUMMARY`. When base IS EUR, `fxRateToBase` for a USD trade is ~0.85-0.88 ("1 USD → N EUR"). |

---

## FLEX WEB SERVICE

### How It Works (Two-Step)

**Step 1 — SendRequest:**
```
GET https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest
    ?t={TOKEN}&q={QUERY_ID}&v=3
```
Returns XML with `<ReferenceCode>`. Optional: `&fd=yyyymmdd&td=yyyymmdd` for date override, `&p={DAYS}` for period.

**Step 2 — GetStatement:**
```
GET https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/GetStatement
    ?t={TOKEN}&q={REFERENCE_CODE}&v=3
```
Returns the Flex report (XML or TEXT). May need polling — error 1019 = "still generating".

**Required:** `User-Agent` header (e.g. `Python/3.11`). Without it, requests silently fail.

### Data Freshness

| Query Type | Update Frequency | Delay |
|-----------|-----------------|-------|
| Activity Flex Query | Once daily at EOD | T+0 EOD, reliable next morning by 5am ET |
| Trade Confirmation Flex Query | Throughout day | 5-10 min after execution |

Activity data subsystems (settlement, FIFO P&L, MTM P&L) each become ready at different times post-close. Errors 1005-1008 mean specific data isn't ready yet.

### Rate Limits

- 1 request/second per token
- 10 requests/minute per token
- Violation = 10-minute penalty box. Repeat = permanent block.
- NOT designed for active polling. Pull once daily or a few times for Trade Confirmations.

### Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| 1001, 1004, 1009, 1019, 1021 | Server busy / generating | Retry with backoff |
| 1005-1008 | Specific data not ready (settlement/FIFO/MTM) | Retry later |
| 1012 | Token expired | Regenerate in Client Portal |
| 1013 | IP restriction | Check IP whitelist |
| 1015 | Invalid token | Verify token |
| 1018 | Rate limited | Wait 10 min, reduce frequency |
| 1014, 1016, 1017 | Invalid query/account/ref | Fix configuration |

### Token Management

- Generated in Client Portal: Performance & Reports > Flex Queries > Flex Web Service Configuration
- Lifetime: 6 hours to 1 year (configurable)
- New token invalidates previous one (no overlap)
- Optional IP restriction
- Historical data: 4 previous calendar years + current YTD

---

## XML FIELDS & SIGN CONVENTIONS

### Trade Record Key Fields

| Field | Meaning | Watch Out |
|-------|---------|-----------|
| `proceeds` | **Negative for buys, positive for sells** | Counterintuitive sign |
| `costBasis` | Includes proceeds + commission + tax | Inverse sign of proceeds |
| `realizedPnl` | proceeds + costBasis of closing trade | Only meaningful for closing trades |
| `mtmPnl` | Close price vs trade price (NO commissions) | Add commission separately for true net |
| `netCash` | proceeds + tax + commissions | Actual cash impact |
| `fxRateToBase` | Multiplier: trade_ccy * rate = base_ccy | NOT a divisor |
| `ibCommissionCurrency` | May differ from trade `currency` | Convert separately |
| `multiplier` | 1 for stocks, 100 for US options, varies for futures | MUST use in value calculations |
| `openCloseIndicator` | O, C, **C;O** (close+open simultaneously), or `-` | Don't assume only O or C |
| `buySell` | BUY, SELL, **BUY (Ca.)**, **SELL (Ca.)** | Cancelled trades have (Ca.) suffix |
| `conid` | IB's unique contract ID | ONLY reliable identifier. Symbol is NOT unique. |
| `underlyingConid` | For options: underlying's conid; for stocks: same as conid | Use for joining options to underliers |

### Notes/Codes Field (semicolon-delimited)

Key codes: `O` open, `C` close, `P` partial, `A` assignment, `Ex` exercise, `Ep` expired, `L` liquidation by IB, `Ca` cancelled, `Co` corrected, `R` dividend reinvest, `W` wash sale, `LT` long-term, `ST` short-term, `LD` loss disallowed (wash). Full list: 57+ codes.

### XML Structure
```
FlexQueryResponse
  FlexStatements
    FlexStatement (accountId, fromDate, toDate)
      OpenPositions > OpenPosition
      Trades > Trade            ← Executions / Orders / Symbol Summary level
      Trades > Lot              ← Closed Lots level (different element!)
      CashTransactions > CashTransaction
      CashReport > CashReportCurrency
      ... (other sections)
```

---

## CLOSED LOTS — schema (verified empirically against Activity executions, May 2026)

Closed Lots queries return `<Lot>` children of `<Trades>` (NOT `<Trade>` elements
with `levelOfDetail="CLOSED_LOT"` as some docs suggest). Field semantics differ
non-obviously from regular `<Trade>` records.

### Field meanings in `<Lot>` (universal across STK / OPT / FOP / FUT)

| Field | Meaning | Sign / Direction |
|-------|---------|------------------|
| `tradePrice` | **OPENING-trade price** (per unit/share, at the original buy/sell) | Always positive |
| `cost` | `qty × tradePrice × mult` = **OPENING cost basis** (paid for long, received as premium for short) | Always positive |
| `buySell` | **CLOSING-trade direction** (universal across all asset classes) | `SELL` = closed long. `BUY` = closed short. |
| `openDateTime` | Opening trade datetime (when the lot was originally created) | — |
| `tradeDate` / `dateTime` | **Closing** trade date/datetime (when the lot was realized) | — |
| `fifoPnlRealized` | Signed realized P&L in trade currency, already commission-netted per IB docs | Positive = profit, negative = loss |
| `holdingPeriodDateTime` | Holding-period start date (tax-relevant; LT/ST classification cutoff) | — |
| `quantity` | Lot quantity in absolute units | Always positive in `<Lot>` (direction comes from `buySell`) |

### What is NOT stored — derive from accounting identity

`<Lot>` does NOT contain the closing trade price. Derive from realized P&L:

- **LONG**:  `close_price = open_price + realized / (qty × mult)`
- **SHORT**: `close_price = open_price - realized / (qty × mult)`

### Direction mapping cheat-sheet

```
buySell="SELL" → "sold to close"  → was LONG  → close_value = open + realized
buySell="BUY"  → "bought to cover" → was SHORT → close_value = open - realized
```

### Mandatory cross-check before trusting Closed Lots labels

The asymmetry of meanings between `<Trade>` and `<Lot>` schemas is a well-known
source of bugs. **Before basing any P&L decomposition on `<Lot>` interpretation,
cross-check at least one position against the Activity Flex query** (same period,
Executions-level detail). If buy/sell counts and per-unit prices don't reconcile
to the Closed Lots interpretation, the interpretation is wrong — not the data.

Example reconciliation (illustrative):
```
ACME 260116C00100000 in Closed Lots:  N <Lot> rows, all buySell=SELL,
                                      tradePrice=$10.00, fifoPnlRealized > 0
Activity Flex (same period, executions): M BUY  fills at ~$10.00 (opened)
                                         M SELL fills at ~$25.00 (closed)
→ buySell=SELL on the <Lot> means the position WAS LONG (closed by selling).
→ tradePrice on <Lot> matches the BUY fills, not the SELL fills, which
  confirms tradePrice is the OPEN price (not the close).
→ Lot-row count (N) may be less than execution-row count (M) — IB aggregates
  same-price fills into a single closed lot.
```

(Numbers above are illustrative. Run this kind of reconciliation against your
own account on any options position before trusting the Closed-Lots labels —
do not rely on the schema interpretation in isolation.)

### Anomaly handling

Under correct interpretation, derived close_price is rarely negative. If it is
(close < 0), that's a real anomaly — likely a corporate action or basis
adjustment. Flag for manual review; fall back to IB's `fifoPnlRealized` at
close-date FX rate for EUR conversion.

### Futures (FUT) — special EUR conversion methodology

Even with correct schema interpretation, futures need different EUR handling
than stocks/options. Reason: futures settle daily via variation margin — the
"open notional" cash was never actually paid. Converting open_notional × open_FX
creates phantom FX gain/loss on cash that never moved.

**For FUT**: use `EUR_pnl = realized_USD ÷ close_date_ECB_rate` (single-date
conversion). For STK/OPT/FOP: use per-leg conversion (open at open-date rate,
close at close-date rate), which correctly captures FX-translation on real
cash flows.

### Required Flex Query fields for Closed Lots

Without these the lot data is incomplete:
- `openDateTime`, `holdingPeriodDateTime` (tax-relevant dates)
- `tradePrice`, `cost`, `quantity`, `multiplier` (the open-side numerics)
- `buySell`, `openCloseIndicator`, `notes` (classification)
- `fifoPnlRealized` (authoritative P&L)
- `fxRateToBase`, `currency` (FX context)
- Standard identifiers: `symbol`, `description`, `conid`, `isin`, `assetCategory`

The query must have **Options → Closed Lots = ✓** checked in Client Portal,
otherwise the relevant `openDateTime` field isn't returned even if checked
under Fields list (the option-level checkbox gates field availability).

---

## CURRENCIES

### fxRateToBase
**Direction:** `amount_in_trade_currency * fxRateToBase = amount_in_base_currency`

Example: Base=USD, trade in EUR, fxRateToBase=1.08 → EUR 1000 * 1.08 = USD 1080

### Commission Currency
`ibCommissionCurrency` can differ from trade `currency`. Convert both amounts separately when aggregating to base currency.

### FX Translation Gain/Loss
The Cash Report includes an "FX Translation Gain/Loss" line — this is an **accounting entry** reflecting exchange rate changes on held non-base currency cash. NOT a real cash flow. Do not include in cash reconciliation of actual movements.

### Forex Positions (CASH)
IB shows forex in TWO places:
- **FX Portfolio** — virtual positions from IDEALPRO trades (may NOT reflect actual balances)
- **Real FX Balances** — actual cash per currency

Use FXCONV for pure currency conversion (only affects Real FX Balances). IDEALPRO creates persistent virtual positions.

---

## BALANCES

### Key Account Values

| Metric | Formula | Use For |
|--------|---------|---------|
| **NLV** (Net Liquidation Value) | Cash + Stocks + Options + Bonds + Funds | "What is my account worth" |
| **ELV** (Equity with Loan Value) | Cash + Stocks + Bonds + Funds + EU/Asian Options (excl. US options, futures) | Margin calculations |
| **NAV** (Net Asset Value) | Positions by asset class + Cash + Accruals (excl. futures) | Activity statement |

Futures are excluded from NAV because futures P&L settles into cash nightly.

### Cash Types

| Field | Meaning |
|-------|---------|
| Ending Cash | Trade-date basis — includes unsettled proceeds |
| Ending Settled Cash | Only actually received/settled cash |
| Available Funds | ELV - Initial Margin Requirement |
| Excess Liquidity | ELV - Maintenance Margin Requirement |
| Buying Power | Available Funds * leverage factor |

**Interest accrues on SETTLED balances only.** Selling stock gives you Ending Cash immediately but Ending Settled Cash only after T+1.

### Cash Report vs Statement of Funds vs NAV

| Report | Purpose | Granularity |
|--------|---------|-------------|
| Cash Report | Cash change summary (start→end) | One line per category |
| Statement of Funds | Every individual cash movement | Per-transaction ledger |
| NAV Summary | Total account value by asset class | Asset class rows |

Cash Report Ending Cash = "Cash" line in NAV = Statement of Funds closing balance (per currency). Rounding can cause $1 discrepancy.

### Segments
Cash is split into **Securities** (SEC-regulated) and **Commodities** (CFTC-regulated) segments. Total = sum of both.

---

## P&L METHODS

### MTM (Mark-to-Market)

`MTM P/L = Position MTM + Transaction MTM - Commissions (separate line)`

- Position MTM: (today's close - yesterday's close) * quantity. Resets daily.
- Transaction MTM: (close - trade price) for buys; (trade price - prior close) for sells
- **Commissions are NOT netted in** — they appear as a separate line
- No lot matching. Every day is a fresh start.

### FIFO / LIFO (Realized/Unrealized)

- Closing trades matched to opening trades by chosen method
- **Commissions ARE included** in cost basis
- Wash sales tracked and disallowed losses added back
- Default is FIFO, changeable per-trade until 8:30 PM ET same day (Tax Optimizer)

### Reconciliation
MTM total and FIFO total should converge over the life of a closed position. Period-by-period they **diverge** because MTM resets daily while FIFO carries lots.

---

## TIME

### Timezone Rules

| Context | Timezone |
|---------|----------|
| P&L daily reset | 5 min before midnight in **instrument's exchange timezone** |
| Activity statement cutoff | 5:15 PM EST (commodities), 8:20 PM EST (securities) |
| Statement availability | By 5:00 AM ET next day |
| TWS API historical data | Must specify explicitly (exchange TZ, TWS TZ, or UTC) |

### Settlement Cycles

| Product | Settlement |
|---------|-----------|
| US stocks | T+1 (since May 2024) |
| US options | T+1 |
| Futures | T+0 (daily cash settlement) |
| Forex | T+2 |

---

## DERIVATIVES

### CRITICAL: Verify Futures Tickers Before Interpreting

**NEVER guess what a futures symbol means.** IB futures tickers are short codes that are misleading:

| Symbol | You might think | Actually is |
|--------|----------------|-------------|
| MET | Micro E-mini something | **Micro Ether** (Ethereum) |
| MSL | Micro Silver | **Micro SOL** (Solana) |
| MBT | Micro Bitcoin? | **Micro Bitcoin** (correct, but verify) |
| SIL | Silver? | **Micro Silver** (1,000 oz) |
| MGC | ? | **Micro Gold** |
| MES | ? | **Micro E-mini S&P 500** |
| MNQ | ? | **Micro E-mini Nasdaq-100** |
| MYM | ? | **Micro E-mini Dow** |
| M2K | ? | **Micro E-mini Russell 2000** |
| VXM | VIX micro? | **Mini VIX** (CFE) |

**Mandatory process:** When encountering an unfamiliar futures symbol, search `site:cmegroup.com {SYMBOL}` or `site:cboe.com {SYMBOL}` BEFORE reporting to the user. One wrong ticker = completely wrong analysis.

**Futures symbol structure:** `{ROOT}{MONTH_CODE}{YEAR_DIGIT}` — e.g. METV5 = Micro Ether, October 2025. Month codes: F=Jan, G=Feb, H=Mar, J=Apr, K=May, M=Jun, N=Jul, Q=Aug, U=Sep, V=Oct, X=Nov, Z=Dec.

### Options Identification
Requires: `symbol` + `expiry` + `strike` + `putCall` (P/C) + `multiplier` + `exchange`. Or just use `conid`.

### Futures
- P&L settles to cash daily (appears as "Cash Settling MTM" in Cash Report)
- Not included in NAV asset breakdown (already in cash)
- Each contract has a specific multiplier and notional value

### Corporate Actions
Appear in Corporate Actions section, NOT Trades. Types: FS (forward split), RS (reverse split), CD (cash dividend), TC (merger), SO (spin-off), DW (delist worthless), etc. **Always check Corporate Actions when positions don't reconcile.**

---

## INTEREST & FEES

- **Margin interest:** Daily accrual on settled balances, posted monthly (first days of next month)
- **Day count:** 360 days for USD/EUR/CHF/JPY; 365 for AUD/GBP
- **Bond accrued interest:** Increases NAV daily between coupon dates, reverses on payment
- **Interest accruals < $1** are tracked internally but NOT shown on statements
- **Short borrow fees:** Can spike daily for hard-to-borrow stocks. Offset partially by short credit interest.

---

## WHAT FLEX CANNOT DO

| Need | Use Instead |
|------|------------|
| Real-time market data | TWS API (via `ib_async`, successor to `ib_insync`) |
| Order placement | TWS API or Client Portal API |
| Streaming quotes | TWS API (100-1100 concurrent lines) |
| Intraday positions (< 5 min) | TWS API or Client Portal API |
| Historical OHLCV bars | TWS API |
| Contract/instrument lookup | TWS API or Client Portal API |

**Flex is for:** EOD reconciliation, P&L tracking, fee accounting, tax reporting, historical position analysis.

### API Comparison

| | Flex | Client Portal API | TWS API |
|---|---|---|---|
| Type | HTTP reporting | REST + WebSocket | TCP socket |
| Trading | No | Yes | Yes (fullest) |
| Auth | Token (simple) | Gateway + browser login (24h re-auth) | TWS/Gateway login |
| Setup | Very low | Medium | Medium-High |
| Python lib | `ibflex` | `requests`/`httpx` | `ib_async` |
| Best for | Reports, reconciliation | Light trading, dashboards | Algo trading |

### Python Libraries

| Library | For | Status |
|---------|-----|--------|
| `ibflex` | Parsing Flex XML | Active |
| `ib_async` | TWS API (full features) | Active, successor to ib_insync |
| `ib_insync` | TWS API | **Archived** (March 2024, creator passed away) |
| `ibapi` | TWS API (official, raw callbacks) | Active but verbose |

---

## AVAILABLE DATA SECTIONS IN FLEX

**Positions:** Open Positions, Prior Period Positions, Net Stock Position Summary
**Trading:** Trades (Executions/Orders/Symbol Summary/Closed Lots/Wash Sales), Commission Details
**Cash:** Cash Report, Cash Transactions, Statement of Funds, Forex Balances
**P&L:** MTM Performance Summary, Realized/Unrealized Performance Summary, MTD/YTD Performance, NAV Summary, Change in NAV
**Income:** Interest Details (Tiers), Interest Accruals, Dividend Accruals
**Fees:** Client Fees, Transaction Fees, Borrow Fee Details
**Other:** Corporate Actions, Currency Conversion Rates, Forex P/L Details, Transfers, Options Exercises/Assignments/Expirations, Account Information, Financial Instrument Information
