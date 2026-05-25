---
name: tax-loss-harvest
description: Scan IB positions for tax-loss harvesting opportunities. Triggers on "tax loss harvest", "TLH", "harvest losses", "unrealized losses", "what can I sell for a tax loss", "tax-loss opportunities", or "year-end tax planning".
---

# Tax-Loss Harvest — Solo Trader

Scan live IB positions for unrealized losses worth harvesting. Quick, actionable output.

## Workflow

### Step 0: Session check

```bash
curl -sk https://localhost:5000/v1/api/tickle
```

If not authenticated, stop and tell user to log in.

### Step 1: Get account ID

```bash
curl -sk https://localhost:5000/v1/api/portfolio/accounts
```

Extract `id` from the first account. Store as `$ACCT`.

### Step 2: Pull all positions with P&L

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/positions/0"
```

Each position returns: `ticker`, `conid`, `position`, `mktValue`, `avgCost`, `avgPrice`,
`unrealizedPnl`, `realizedPnl`, `assetClass`.

### Step 3: Filter harvest candidates

From the positions response, select positions where:
- `unrealizedPnl < 0` (has a loss)
- `assetClass` = `STK` or `ETF` (stocks and ETFs only, skip options/futures)
- Loss > $100 (ignore dust)

Sort by largest absolute loss first.

### Step 4: Get YTD realized gains

```bash
curl -sk "https://localhost:5000/v1/api/portfolio/$ACCT/summary"
```

Look for realized P&L fields. If not available in summary, note that the user
should check their IB Activity Statement for YTD realized gains.

### Step 5: Estimate tax context

Calculate:
- **Total harvestable losses** = sum of all negative unrealizedPnl from candidates
- **Net gain offset** = min(harvestable losses, YTD realized gains) if realized gains known
- **Ordinary income offset** = min($3,000, remaining losses after gain offset)
- **Estimated tax savings** = gains offset x estimated cap gains rate + ordinary income offset x marginal rate

**Tax jurisdiction matters.** This skill defaults to US-style assumptions
(IRS § 1091 wash sale, long/short-term distinction at 1 year, federal
brackets). If the user is in another jurisdiction (EU, UK, etc.) the rules
are different — UK uses 30-day "bed-and-breakfast", Germany has FIFO and
different holding periods, etc. **Always confirm jurisdiction before
producing a final estimate.** If unclear, ask.

US defaults if confirmed: 15% for long-term capital gains, 32% for ordinary
income / short-term. Ask if the user wants different rates.

### Step 6: Wash sale check

The IRS § 1091 wash-sale window is **61 days total — 30 days before AND 30
days after the loss sale**. Buying a "substantially identical" security
inside that window disallows the loss (it gets added to the cost basis of
the replacement instead). For each candidate, flag:

- Did you buy the same (or substantially identical) security in the 30
  days *before* the candidate sale date? (Check IB trade history; if not
  available, ask.)
- Will you need to avoid buying it back for 30 days *after* the sale?
- Any DRIP / auto-reinvestment active that would silently repurchase
  inside the window?
- Any related option positions on the same underlying — long calls /
  short puts can also trigger the rule.

Note: IB does not expose more than 7 days of trade history via CP Gateway
(`/iserver/account/trades`). For the full 30-days-back window pull a Flex
Activity query, or warn the user to check the Activity Statement manually.

### Step 7: Suggest replacements (if asked)

Only if the user asks for replacement ideas. Keep it simple:

| Sell | Replace With | Why |
|------|-------------|-----|
| SPY | VOO or IVV | Same S&P 500, different fund, no wash sale |
| QQQ | QQQM or VGT | Similar tech exposure |
| Individual stock | Sector ETF | Broader, no wash sale risk |
| Bond ETF | Similar duration ETF from different family | Maintain duration |

Do NOT generate replacement suggestions by default. The user is a trader, not a passive investor.

## Output format

One markdown block, max 1 page:

```
## Tax-Loss Harvest Scan — {date}

**Account**: {account_id}

### Candidates (sorted by loss)

| Ticker | Shares | Avg Cost | Mkt Price | Unrealized Loss | % Loss |
|--------|--------|----------|-----------|-----------------|--------|
| XYZ    | 100    | $45.20   | $38.50    | -$670           | -14.8% |
| ...    |        |          |           |                 |        |

**Total harvestable**: ${sum}
**YTD realized gains**: ${gains} (or "check Activity Statement")
**Est. tax savings**: ${savings} (at {rates})

### Wash sale notes
- {any flags}

### Action
{1-2 sentences: what to do, ranked by impact}
```

## Save output

Always save the TLH scan to the research directory:

```bash
mkdir -p portfolio/ib
# Save to: portfolio/ib/{YYYY-MM-DD}_tlh.md
```

## Self-validation checks

1. Did the session authenticate? If not, stop early with clear message.
2. Are there actually positions with losses? If all green, say "nothing to harvest" and stop.
3. Is every number from the API, not fabricated? Cross-check: unrealizedPnl should roughly equal (mktValue - avgCost * position).
4. Did arithmetic use `python3 -c`? Never mental math on tax estimates.
5. Is output under 1 page? If the candidate list is huge, show top 10 and summarize the rest.
6. Did we avoid suggesting order placement? This is read-only. User executes in TWS.
