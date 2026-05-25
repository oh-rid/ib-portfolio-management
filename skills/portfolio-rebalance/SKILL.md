---
name: portfolio-rebalance
description: Analyze portfolio drift against target allocation and suggest rebalancing trades. Triggers on "rebalance", "portfolio drift", "allocation check", "am I overweight", "am I underweight", "rebalance my portfolio", "check my allocation", or "portfolio balance".
---

# Portfolio Rebalance — Solo Trader

Compare current IB portfolio allocation to target weights. Show drift. Suggest trades.

## Prerequisites

The user must have target allocations defined. If not, ask them to provide targets
as a simple table:

```
Asset class / ticker : target %
```

If they say "I don't have targets" — help them define simple ones based on what
they currently hold. Don't impose a model. This is their portfolio.

## Workflow

### Step 0: Session check

```bash
curl -sk https://localhost:5000/v1/api/tickle
```

### Step 1: Get account and NLV

```bash
curl -sk https://localhost:5000/v1/api/portfolio/accounts
```

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/summary"
```

Extract Net Liquidation Value (NLV) from summary. This is the denominator for all % calculations.

### Step 2: Pull all positions

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/positions/0"
```

For each position: `ticker`, `assetClass`, `mktValue`, `position`, `unrealizedPnl`.

### Step 3: Classify holdings

Group positions by the user's target categories. Common groupings:
- By asset class: stocks, bonds, cash, options, futures
- By sector: tech, financials, energy, etc.
- By ticker (if targets are per-position)
- By geography: US, international, EM

Use the grouping that matches the user's targets. If targets are per-ticker, use per-ticker.
If targets are by asset class, aggregate.

### Step 4: Calculate drift

For each category:

```python
current_pct = category_mkt_value / nlv * 100
drift = current_pct - target_pct
dollar_drift = drift / 100 * nlv
```

ALL arithmetic via `python3 -c`. No mental math.

### Step 5: Cash and buying power

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/ledger"
```

Check cash balance. If rebalancing requires buying, verify cash is available.
If not, rebalancing means selling overweight to fund underweight.

### Step 6: Generate trade suggestions

For each category outside the rebalancing band (default: +/- 3% drift):
- Overweight: suggest selling $X to bring to target
- Underweight: suggest buying $X to bring to target

Prioritize:
1. Sell overweight positions with losses (rebalance + harvest)
2. Sell overweight positions with long-term gains (lower tax rate)
3. Avoid selling positions with large short-term gains if possible

Convert dollar amounts to approximate share counts using current prices.

### Step 7: Get current prices for trade sizing

For positions that need trading, get live prices:

```bash
curl -sk "https://localhost:5000/v1/api/iserver/marketdata/snapshot?conids={conid1},{conid2}&fields=31,84,85,86"
```

Field 31 = last price. Use this to calculate share counts.

**GOTCHA**: First snapshot call often returns empty. Call twice with a 1-second gap.

## Output format

One markdown block, max 1 page:

```
## Portfolio Rebalance — {date}

**NLV**: ${nlv} | **Cash**: ${cash}

### Allocation Drift

| Category | Target | Current | Drift | $ Over/Under |
|----------|--------|---------|-------|-------------|
| Tech     | 30%    | 38%     | +8%   | +$4,200     |
| ...      |        |         |       |             |

### Suggested Trades

| Action | Ticker      | Shares | ~Amount | Reason               |
|--------|-------------|--------|---------|----------------------|
| Sell   | {TECH_STOCK}| 5      | ~$3,100 | Reduce tech overweight |
| Buy    | {BOND_ETF}  | 20     | ~$1,800 | Add bond underweight   |

### Tax notes
- {any positions where selling triggers significant ST gains}

### Summary
{1-2 sentences: what's most out of balance, what to do first}
```

## Save output

Always save the rebalance analysis to the research directory:

```bash
mkdir -p portfolio/ib
# Save to: portfolio/ib/{YYYY-MM-DD}_rebalance.md
```

## Self-validation checks

1. Did the session authenticate? Stop early if not.
2. Does NLV match the sum of all position mktValues + cash (approximately)? If off by more than 5%, flag it.
3. Do all percentages sum to ~100%? If not, there's an unclassified bucket — show it.
4. ALL drift math via `python3 -c`. Verify: drift % * NLV = dollar drift.
5. Did we get the user's targets before calculating? Never assume a 60/40 or any model.
6. Are trade suggestions sized to real share counts at real prices? No "$X of stock" — give share counts.
7. Is output under 1 page? Summarize if > 15 positions.
8. Did we avoid placing any orders? Read-only. User executes in TWS.
