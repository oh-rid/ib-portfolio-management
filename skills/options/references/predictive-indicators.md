# Predictive Indicators & Seasonal Patterns

## Put-Call Ratio

- **Standard**: put volume / call volume
- **Weighted** (superior): sum(put_vol x put_price) / sum(call_vol x call_price)
- Use **21-day moving average** (yields ~6-8 signals/year)
- **DYNAMIC interpretation**: peaks = buy signals, valleys = sell signals (NEVER use fixed levels)
- **Equity-only ratio** is purest (range ~0.30-0.55); index ratio distorted by hedging
- **Bear market warning**: put-call can give premature buy signals. Monitor PUT VOLUME alone — when put volume peaks and starts declining, that marks the actual bottom

## Option Volume as Predictor

Alert trigger: daily option volume >= 2x average AND concentrated in near-term OTM options AND no public news.

## VIX Interpretation

- VIX spike to local maximum = contrarian BUY signal (fear exhaustion)
- VIX at extreme low = imminent large move (direction unknown, NOT necessarily bearish)
- NEVER use fixed VIX levels — always interpret relative to recent history
- Rare: VIX drops below HV of underlying index = extreme events (1987, 1997, 1998) — all turned out to be buy points after resolution

---

## Seasonal Patterns

### VIX Annual Cycle (18-year study)

| Month | VIX Tendency | Reliability | Strategy |
|---|---|---|---|
| July | Annual LOW | 83% (15/18) | BUY straddles (cheapest vol) |
| October | Annual PEAK | 78% (14/18) | SELL volatility |
| Nov-Dec | Sharp decline | 83% (15/18) | Buy straddles in December |
| August-Sep | Rising sharply | High | Hold long vol from July entry |

### Calendar Trades

| Window | Trade | Record |
|---|---|---|
| Late Jul/Aug 1 | Buy 3-month ATM OEX straddles | 22/23 years had significant moves |
| Oct 27 → Nov 2 | BUY S&P at close Oct 27, sell close Nov 2 | 24/25 years profitable, avg +1.84% |
| ~Dec 18 → ~Jan 5 | Buy small-cap, sell large-cap (January Effect) | Historical edge, use options |
| Early Oct → mid-Jan | Short heating oil / Long unleaded gas (HUG/HOG) | 8/12 years profitable |

### Sep-Oct Correction (31 years of data)
- Scenario 1 (19/31): Top near Labor Day, bottom mid-late Sep
- Scenario 2 (6/31): Top mid-late Sep, bottom early Oct
- Scenario 3 (5/31): Top early Oct, bottom early Nov
- Use put-call ratios + breadth oscillator for timing confirmation. Do NOT buy puts blindly before Labor Day.
