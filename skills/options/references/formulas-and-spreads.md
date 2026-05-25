# Key Formulas

```python
# Intrinsic Value
call_intrinsic = max(0, S - K)
put_intrinsic = max(0, K - S)

# Break-Evens
long_call_BE = K + premium
long_put_BE = K - premium
straddle_BE = K +/- total_premium
bull_spread_BE = lower_K + debit

# Hedge Sizing
adjusted_net_worth = sum(stock_value_i * (stock_vol_i / index_vol_i))
num_puts = adjusted_net_worth / (100 * put_strike)

# Kelly Sizing
kelly_fraction = ((avg_win/avg_loss + 1) * win_rate - 1) / (avg_win/avg_loss)

# Skew Detection
skew_significance = stdev(IVs_across_strikes) / mean(IVs_across_strikes)
# > 0.15 = tradeable skew

# Breadth Oscillator
M1 = 0.9 * M0 + 0.1 * (advances - declines)

# Index Futures Fair Value
fair_value = index * (1 + r)^t - PV(dividends)

# Expected Return
E[return] = sum(P(price_i) * PnL(price_i)) / investment

# Gamma PnL approximation
gamma_pnl = 0.5 * gamma * deltaS^2 - theta * deltaT
```

---

# Intermarket Spreads Reference

| Spread | Instruments | Entry Signal | Window |
|---|---|---|---|
| HUG/HOG | Feb unleaded gas vs Feb heating oil | Early October | Oct → mid-Jan |
| January Effect | Small-cap vs large-cap | ~Dec 18-19 | Dec 18 → Jan 5 |
| Gold stocks/Gold | XAU vs gold futures | Ratio > 30 (sell XAU) or < 20 (buy XAU) | Any |
| Oil stocks/Crude | XOI vs crude oil | Ratio near 150 (buy XOI) | Any |
| Utilities/T-Bonds | UTY vs T-bond futures | Ratio at extremes | Any |

**Sizing formula**: `Quotient = (P1/P2) x (Unit1/Unit2) x (Vol1/Vol2) x (Delta1/Delta2)`

**Always prefer options over futures** for intermarket spreads — a second profit path from volatility even if convergence fails.

---

# Collar Quick Reference

No-cost collar strike relationship (LEAPS, 5% rate, put at-the-money):

| Volatility | 1.5yr Call Strike | 2.5yr Call Strike |
|---|---|---|
| 15% | 117% of put | 130% of put |
| 30% | 119% | 134% |
| 50% | 121% | 141% |

At 2% rates: shrinks dramatically (30% vol, 2.5yr = only 113% vs 134%).
High dividends further compress. Subtract PV(dividends) from stock price first.
