# Exercise, Assignment & Practical Execution

## Assignment Decision Tree
```
American style? → NO (European): only at expiration
  YES →
    ITM? → NO: very low risk
      YES →
        Dividend approaching? → YES: HIGH risk for ITM calls (day before ex-div)
          If time value < dividend → expect exercise
        At or below parity? → YES: HIGH risk (arbs will exercise)
        Tender offer? → VERY HIGH risk for all ITM calls
```

## Key Assignment Risks

| Risk | Mitigation |
|---|---|
| OEX spread (American + cash-settled) | Can be assigned on short side anytime; long side still just an option. Dangerous for spreads. |
| Weekend assignment | Close or roll ITM short options before Friday close |
| Futures options calendar spread | Options on DIFFERENT underlying futures — basis risk exists |

## The "90% Expire Worthless" Myth
CBOE data: ~30% expire worthless, ~60% closed before expiration, ~10% exercised. Credit spreads have NO inherent statistical edge.

---

## Order Entry

- **ALWAYS use limit orders** for options (except emergencies in liquid markets)
- Enter spreads as single spread orders, not separate legs
- Check theoretical value with model BEFORE every trade
- For near-expiration ITM options: compare selling at bid vs sell-stock-and-exercise

## Stops on Options

- Do NOT place stop orders on option prices (wide bid-ask triggers false stops)
- Use MENTAL stops on the UNDERLYING's price
- 20-day SMA as closing stop (underlying must violate at CLOSE, not intraday)
- Two-day variant: must close below stop for two consecutive days

## Emergency Procedures

- Fast market / crash: use FUTURES as hedge (always know where they trade)
- One futures contract per ~5 net naked puts converts to synthetic covered puts
- Gap through stop: accept loss, use market order, do NOT average down
- After large loss: stay alert for next opportunity but don't force it

---

## Trading Philosophy (McMillan's Core Rules)

1. **Trade within comfort level** — match strategy to temperament
2. **Always use a model** — never trade without checking fair value
3. **Don't always use options** — sometimes underlying is better (when IV high, markets wide)
4. **Avoid buying OTM options** — #1 reason option buyers lose money. Buy ITM for directional bets.
5. **Don't buy more time than needed** — excess time premium reduces delta and profits
6. **Know equivalent strategies** — use the most capital-efficient form
7. **Trade all markets** — equities, indices, AND futures
8. **Have humility** — don't confuse brains with a bull market
9. **Operate consistently** — don't change strategy after one loss
10. **The biggest mistake**: too much hope, too little realism. Use models, manage positions, be realistic.
