# Written brief — monthly rewards by game and channel

**Date:** 2026-09-29  
**Audience:** hiring team / Product discussion prep  
**Companion artifacts:** `20260929_monthly_rewards_by_game_channel.html` and `.csv`

This note covers modeling assumptions, data quality, questions I would ask stakeholders, how AI was used, and what I would do with more time.

---

## Assumptions

**USD as the reporting currency.** Earns and redeems arrive in USD, EUR, GBP, and BRL. Product needs a single comparable number, so every amount is converted with that month’s `fx_rates` snapshot (`rate_date` is the first of the month). There is no daily FX series in the extract.

**Redeemed value is net cash that left (or returned to) the program.** The redeem table is a *status log*, not one row per request. I count:

- `settled` as positive redeemed in the settle month  
- `reversed` as negative redeemed in the reverse month  
- `requested` as still outstanding (still in float)  
- `failed` as never having left the balance  

Amount, currency, and channel do not change across logs for a given `redemption_id` in this extract.

**Game on redemptions.** Redeem logs have no `game_id`. I use `players.primary_game_id`. For earns that join to a player, `earn.game_id` always equals that primary game in this extract.

**Channel on earns.** Earn events have no channel, but Product asked for earned, redeemed, *and* float by game **and** channel. I assign each player a “home” channel: the channel they *settled* on most often (ties broken by channel name). Players with no settled redemption, and earn events whose `player_id` is missing from `players`, go to **`unallocated`**. Redeemed value still uses the channel on the log.

**Outstanding float** is a stock: cumulative earned minus cumulative net redeemed through month end, at game × channel. Months with no new activity are still in the spine so float does not look like it reset to zero.

**Grain of earns.** I keep every `event_id`. Duplicate `earn_id` values exist; I treat the pipeline record as the grain rather than collapsing them.

**Clean layer does not drop rows.** Proxy is a faithful load. Clean only types, trims, and normalizes case.

---

## Data quality issues and how they were handled

| Issue | Handling |
| --- | --- |
| Redeem events are logs (`requested → settled`, `requested → failed`, `requested → settled → reversed`), not a current-state table. | Modeled as signed movements. Only settled/reversed change redeemed and float. |
| 52 earn events have a `player_id` with no matching player. | Kept. Game still comes from the earn event. Channel is `unallocated`. |
| `earn_id` is not unique (250 ids with multiple events). | Unique/not-null tests sit on `event_id`, not `earn_id`. |
| No `game_id` on redemptions. | `primary_game_id` from players. All redeems in this extract have a player. |
| No channel on earns. | Modal settled channel, or `unallocated`. Documented as attribution, not source truth. |
| Source IDs are strings (`G001`, `P100001`). | Stored as text. No invented surrogate keys. |
| No foreign keys in source. | Not enforced at proxy load. Clean/canonical tests add uniqueness, accepted values, and relationships where they hold. Earn `player_id` is *not* relationship-tested because of the 52 orphans. |
| FX is monthly, not daily. | Join on `date_trunc('month', event timestamp) = rate_date`. Every earn and redeem in this extract matched a rate. |

I did **not** hard-code proxy row counts as tests. Loads can grow; tests require at least one row plus key integrity.

---

## What I would confirm with stakeholders

1. **Float definition.** Is outstanding float “earned minus settled (net of reversals),” or should requested-but-not-settled be a separate pending bucket that *leaves* earned float?
2. **Channel on earns.** Is modal settled channel acceptable, or should all unredeemed earn sit in `unallocated` until it is actually paid out on a channel?
3. **Game on redeems.** Is `primary_game_id` the right attribution, or should we allocate by the player’s earn mix that month?
4. **Duplicate `earn_id`s.** Are these retries, corrections, or true extra value? Should they be deduped?
5. **The 52 orphan earn players.** Source bug, delayed player dimension, or events we should exclude?
6. **Failed redemptions.** Confirm they should not reduce float (my default).
7. **FX.** Month-start snapshot vs mid-month vs settle-date rate for redemptions.
8. **Reporting window.** Inclusive of quiet months on the spine? Calendar month vs game-local timezone?
9. **`unallocated`.** Should Product see it as a first-class channel in the chart, or only as a footnote?

---

## How AI tools were used

This exercise was done in Cursor with an AI coding assistant (Grok). I used it to:

- Scaffold the repo layout (`.env` / `.gitignore`, dbt project, Python loaders, macros)  
- Draft SQL/YAML for proxy, clean, and canonical models and tests  
- Profile the CSVs in Postgres (status paths, FX coverage, orphans)  
- Produce the ERD markdown and the first pass of the stakeholder HTML/CSV  

I directed the modeling choices: three schemas, `_proxy` / `_clean` naming, status-log accounting, channel attribution, no hardcoded row-count tests, and what to persist vs comment as ephemeral. I reviewed generated SQL and tests against the dictionary and query results, and I fixed issues the model missed (for example KPI `$` amounts stripped by PowerShell when generating HTML).

AI did not replace judgment on float, grain, or which relationships were safe to test.

---

## What I would do with more time

- **Pending vs settled float.** Split requested balance from settled outflow so Product can see “in flight” separately from “paid.”  
- **Channel attribution v2.** Sensitivity table: modal channel vs last settled channel vs 100% unallocated until redeem.  
- **Dedup / SCD.** Confirm `earn_id` duplicates with engineering; consider player/game as slowly changing if `updated_at` is a real SCD column.  
- **Tests.** Anomaly tests (float never wildly negative at company level unless reversals dominate), FX completeness as a store-level test, and a reconciliation: sum of monthly earned = sum of `earn_value_usd`.  
- **Stakeholder pack.** Filterable HTML, and a one-page “by game” view without channel so totals are easier to narrate.  
- **Ops.** Documented `dbt run` / `dbt test` entrypoint that loads `.env` without a one-liner; optional ephemeral materialization for supporting canonical models so only the Product table lands in `canonical`.  
- **Timeboxed live queries.** A short SQL cheat sheet for the interview (orphan earns, redemption paths, float walk-forward for one game).

---

*End of brief.*
