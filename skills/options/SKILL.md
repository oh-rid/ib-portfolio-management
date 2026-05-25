---
name: options
description: This skill should be used when the user asks about options strategy, position construction, or interpretation — "analyze option positions", "select an option strategy", "construct a spread", "vertical spread", "credit spread", "iron condor", "butterfly", "covered call", "ratio spread", "calendar spread", "backspread", "collar", "interpret Greeks", "delta hedge", "evaluate volatility", "skew", "term structure", "should I sell premium", "assignment risk", "rolling an option", "expiration management", "wash sale on options", "size an options position", or any question about call/put strategy selection, risk, or sizing. Does NOT apply to raw IB API data fetching for options — that's the `ib-connector` skill.
---

# Options — strategy framework

A framework for thinking about and constructing option positions. Based on
McMillan's *Options as a Strategic Investment* (5e), Natenberg's *Option
Volatility & Pricing*, and a handful of practitioner sources cited in the
reference files.

## Scope

This skill is the **strategy layer**:

- Which structure fits which view (direction × magnitude × volatility × time)
- How to size and stop
- How to read Greeks
- When to roll / close / let expire
- Common spread mechanics and break-evens
- Predictive indicators (put-call ratio, VIX, skew)

For **live option data** (chains, strikes, Greeks via IB) — use the
`ib-connector` skill. Don't duplicate that logic here.

## Workflow

When the user brings an options question:

1. **Identify what they're actually asking.** Strategy selection?
   Risk/sizing? Greek interpretation? Roll decision? Assignment handling?
   Each goes to a different reference.
2. **Check regime** — implied vol level (vs realized, vs history),
   skew direction, term structure. A sell-premium thesis only works in
   one regime; a buy-vol thesis only in another. (Pull realized vol
   from the underlying's price history; compare to current IV before
   committing.)
3. **Pick structure** with explicit reasoning about max gain / max loss /
   break-even / margin requirement / commission drag.
4. **Size by Kelly fraction × your conviction tier**, not by max-loss
   tolerance. See `references/formulas-and-spreads.md` (Kelly section).
5. **Pre-mortem**: what does the position look like at -50% of remaining
   credit? At +50%? At 21 DTE? What's the assignment risk if assigned
   tonight? Don't enter without answers.

## When to consult which reference

| User is asking about | Open this reference |
|---|---|
| Margin, assignment, roll mechanics, McMillan's 10 rules | [`references/execution-and-philosophy.md`](references/execution-and-philosophy.md) |
| Intrinsic/extrinsic, break-even formulas, Kelly sizing, intermarket spreads, collar tables | [`references/formulas-and-spreads.md`](references/formulas-and-spreads.md) |
| Put-call ratio, VIX interpretation, seasonal patterns, term-structure reading | [`references/predictive-indicators.md`](references/predictive-indicators.md) |
| Breadth oscillator, TICKI, post-expiration reversal, systematic entry signals | [`references/trading-systems.md`](references/trading-systems.md) |

Always pull the right reference into context **before** committing to a
recommendation. Don't reason from memory — the reference files have the
exact formulas and rules.

## Hard rules

- **Never recommend opening a position without naming all four**: max gain,
  max loss, break-even, capital at risk. If you can't compute them, you
  don't understand the structure well enough to recommend it.
- **Always check assignment risk** for short options ≤ 21 DTE, especially
  short calls on dividend-paying underlyings before ex-div.
- **Multi-leg orders are not single-fill atomic in CP Gateway.** This plugin
  is read-only and does NOT place orders (the `block-orders.sh` hook blocks
  it), but if the user asks "should I leg into this in TWS?" — McMillan's
  guidance is in `references/execution-and-philosophy.md`.
- **Implied vol mean-reverts; realized vol clusters.** A sell-premium
  thesis assumes you're paid for vol > realized. Pull the actual realized
  vol (~21d annualized) before assuming IV > RV.

## What this skill does NOT cover

- Raw IB API option-chain fetching → use `ib-connector` skill
- IRS wash-sale rule on options → use `tax-loss-harvest` skill
- Whether to even hold options as part of your overall portfolio
  strategy — out of scope for this skill (a separate reasoning-layer
  skill, if installed, would handle that)
