# Trading Systems

## Breadth Oscillator
```
M_today = 0.9 x M_yesterday + 0.1 x (NYSE_Advances - NYSE_Declines)
```
- Oversold: < -200 → BUY when climbs back above -180
- Overbought: > +200 → SELL when falls back below +180
- **Record (1984-2003)**: 62% win rate (109/176), median trade +5.30 OEX points
- Use "stocks only" advance-decline data (NYSE totals distorted by preferreds/bonds)
- "Overbought does not mean sell" — wait for REVERSAL

## TICKI Day-Trading System
- TICKI = net upticks of 30 Dow stocks (range -30 to +30)
- Buy program: TICKI >= +22 → when drops to +12: SELL S&P futures
- Sell program: TICKI <= -22 → when rises to -12: BUY S&P futures
- Stop: 0.20 pts beyond program extreme; trailing stop 1.70-1.80 pts
- No trades after 3:30 PM; 2 consecutive losses = stop for the day
- ~50% win rate, avg winner ~70% larger than avg loser

## Post-Expiration Reversal System
- Market reverses expiration-week direction ~80% of the time
- If buy programs (positive move): SHORT post-expiration week
- If sell programs (negative move): LONG post-expiration week
- Minimum threshold: |move| > 1.50 OEX points
- Trailing stop: 2.20-3.10 points. Use OEX options (limited risk)

---

## Expiration Effects

### Stock Pinning
Near expiration, stock near a strike with large open interest → market maker arbitrage pins stock to that strike. Only works with no significant news.

### Index Expiration
- ITM open interest > 40,000 contracts → expect significant expiration-related moves
- Arbs short stock + long ITM calls → expect BUY programs at close (bullish)
- Arbs long stock + short ITM puts → expect SELL programs at close (bearish)
- Wednesday/Thursday early unwinding increasingly common
- **Trading rule**: Wait until 3:30+ PM, only enter if market moving WITH expected programs, EXIT same day
