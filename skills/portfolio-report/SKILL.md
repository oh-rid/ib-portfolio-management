---
name: portfolio-report
description: Generate a concise portfolio snapshot with P&L, allocation, and key metrics from live IB data. Triggers on "portfolio report", "portfolio summary", "how's my portfolio", "show me my positions", "portfolio snapshot", "account overview", "what am I holding", or "P&L report".
---

# Portfolio Report — Solo Trader

Pull live IB account data and produce a one-page portfolio snapshot.
Not a 10-page client report. A trader's dashboard in markdown.

## Workflow

### Step 0: Session check

```bash
curl -sk https://localhost:5000/v1/api/tickle
```

### Step 1: Get account ID

```bash
curl -sk https://localhost:5000/v1/api/portfolio/accounts
```

### Step 2: Account summary

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/summary"
```

Extract:
- **NLV** (Net Liquidation Value)
- **Buying power** (available margin or cash)
- **Gross position value**
- **Maintenance margin** (if on margin)
- **Cushion** (excess liquidity / NLV — how far from margin call)

### Step 3: Pull all positions

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/positions/0"
```

For each position: `ticker`, `assetClass`, `position` (qty), `mktValue`,
`avgCost`, `avgPrice`, `unrealizedPnl`, `realizedPnl`, `currency`.

### Step 4: Currency breakdown

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/ledger"
```

Shows cash balances per currency and settled/unsettled.

### Step 5: Calculate derived metrics

All via `python3 -c`:

- **Total unrealized P&L** = sum of all unrealizedPnl
- **Total realized P&L** = sum of all realizedPnl
- **Concentration** = largest position mktValue / NLV (flag if > 25%)
- **Position count** = number of open positions
- **Long/short split** = sum of long mktValue vs short mktValue
- **Asset class breakdown** = aggregate mktValue by assetClass (STK, OPT, FUT, CASH, BOND)

### Step 6: Identify notable positions

Flag:
- **Biggest winner**: position with highest unrealizedPnl
- **Biggest loser**: position with most negative unrealizedPnl
- **Most concentrated**: position with highest % of NLV
- **Deep underwater**: any position with > 20% loss

## Output format

One markdown block, max 1 page:

```
## Portfolio Snapshot — {date} {time}

### Account: {account_id}

| Metric           | Value     |
|------------------|-----------|
| Net Liquidation  | $XXX,XXX  |
| Buying Power     | $XX,XXX   |
| Margin Used      | $XX,XXX   |
| Cushion          | XX%       |
| Unrealized P&L   | +$X,XXX   |
| Realized P&L     | +$X,XXX   |
| Open Positions   | XX        |

### Allocation

| Asset Class | Value     | % of NLV |
|-------------|-----------|----------|
| Stocks      | $XXX,XXX  | XX%      |
| Options     | $X,XXX    | X%       |
| Cash        | $XX,XXX   | XX%      |

### Positions (by size)

| Ticker | Qty  | Mkt Value | Unreal P&L | % of NLV | % P&L  |
|--------|------|-----------|------------|----------|--------|
| AAPL   | 100  | $17,500   | +$1,200    | 12%      | +7.4%  |
| ...    |      |           |            |          |        |

### Notable
- Biggest winner: {ticker} (+${pnl}, +X%)
- Biggest loser: {ticker} (-${pnl}, -X%)
- Concentration: {ticker} at {X}% of NLV {warning if >25%}

### Cash by Currency
| Currency | Settled  | Total    |
|----------|----------|----------|
| USD      | $XX,XXX  | $XX,XXX  |
```

## Save output

Always save the portfolio snapshot to the research directory:

```bash
mkdir -p portfolio/ib
# Save to: portfolio/ib/{YYYY-MM-DD}_snapshot.md
```

This creates a historical record of portfolio state over time.
Filenames are date-stamped — multiple snapshots per day overwrite (latest wins).

## Self-validation checks

1. Did the session authenticate? Stop early if not.
2. Is NLV > 0? If account is empty, say so and stop.
3. Does sum of position mktValues + cash approximately equal NLV? Flag discrepancy > 5%.
4. ALL arithmetic via `python3 -c`. Every percentage, every sum.
5. Are positions sorted by mktValue descending (largest first)?
6. If > 20 positions, show top 15 and summarize the rest as "X smaller positions totaling $Y".
7. Is output under 1 page? If not, compress the positions table.
8. Every number comes from the API response. Never fabricate. If a field is missing, say "N/A".
9. Currency: if multi-currency account, show the ledger breakdown. Don't hide FX exposure.
