{{ config(
    alias="monthly_rewards_by_game_channel",
    materialized="table"
) }}

-- canonical.monthly_rewards_by_game_channel
--
-- Product output (the requirement)
-- Monthly earned value, redeemed value, and outstanding float, broken out
-- by game and redemption channel, in USD, ready to hand to a stakeholder.
--
-- Required vs optional
-- This is the only canonical model the README ask strictly needs. The
-- other canonical tables are transforms that feed this grain.
--
-- Grain: report_month (month start date) + game_id + channel.
--
-- Metric definitions
--   earned_value_usd
--     Sum of earn_value_usd.amount_usd in that month / game / channel.
--   redeemed_value_usd
--     Sum of redeem_value_usd.signed_amount_usd (settled positive,
--     reversed negative). Can be negative if reversals dominate the month.
--   outstanding_float_usd
--     Running sum of (earned - redeemed) through this month end, reset
--     per game_id + channel. Quiet months still appear so float does not
--     disappear when there is no new activity.
--
-- Spine
-- Cross-join every month between the first and last observed activity
-- with every (game_id, channel) pair that ever appears in earns or
-- redeems. Missing facts coalesce to 0. Inner join games_clean for the
-- display name Product expects.
--
-- Known limitations to confirm with Product
-- 1. Earn channel is attributed, not observed (see earn_value_usd).
-- 2. Redeem game is the player's primary game, not an event-level game.
-- 3. Pending (requested) redemptions remain inside float until settled.
-- 4. USD uses the month-start FX snapshot, not a daily rate.
--
-- Sources: canonical.earn_value_usd, canonical.redeem_value_usd,
--          clean.games_clean.
--
-- Supporting models that feed this rollup can be ephemeral instead of
-- tables if canonical should only contain this Product relation.

with earn_months as (
    -- What: earned USD summed to report_month + game_id + channel.
    -- Why: Product's earned_value_usd is a monthly total at that grain,
    -- not event-level detail.
    select
        report_month,
        game_id,
        channel,
        sum(amount_usd) as earned_value_usd
    from {{ ref('earn_value_usd') }}
    group by 1, 2, 3
),

redeem_months as (
    -- What: net redeemed USD (settled minus reversed) at the same grain.
    -- Why: Product's redeemed_value_usd is monthly net outflow, aligned
    -- to the same keys as earned so float can be earned - redeemed.
    select
        report_month,
        game_id,
        channel,
        sum(signed_amount_usd) as redeemed_value_usd
    from {{ ref('redeem_value_usd') }}
    group by 1, 2, 3
),

activity_months as (
    -- What: every month that has at least one earn or redeem total.
    -- Why: a single list of dates so we can take min/max without
    -- duplicating the union inside month_bounds.
    select report_month from earn_months
    union all
    select report_month from redeem_months
),

month_bounds as (
    -- What: first and last activity month in the extract.
    -- Why: the report calendar should cover the full observed window,
    -- not only months that happen to have both earns and redeems.
    select
        min(report_month) as start_month,
        max(report_month) as end_month
    from activity_months
),

report_months as (
    -- What: one row per month from start_month through end_month inclusive.
    -- Why: outstanding float is a running balance. Without a dense month
    -- spine, a quiet month would drop out and look like float reset to zero.
    select generate_series(
        start_month,
        end_month,
        interval '1 month'
    )::date as report_month
    from month_bounds
),

game_channels as (
    -- What: distinct (game_id, channel) pairs from earns and redeems.
    -- Why: every pair that ever had activity needs a row in every report
    -- month so channel-level float can carry forward.
    select game_id, channel from earn_months
    union
    select game_id, channel from redeem_months
),

spine as (
    -- What: Cartesian product of report months and game/channel pairs.
    -- Why: this is the Product grain. Left-joining facts onto the spine
    -- fills inactive months with 0 earned/redeemed instead of omitting them.
    select
        report_months.report_month,
        game_channels.game_id,
        game_channels.channel
    from report_months
    cross join game_channels
)

-- What: attach game name, monthly metrics, and running float.
-- Why: this SELECT is the stakeholder table — dimensions Product can
-- slice, plus the three requested measures in USD rounded to cents.
select
    spine.report_month,
    spine.game_id,
    games.game_name,
    spine.channel,
    round(coalesce(earn_months.earned_value_usd, 0), 2) as earned_value_usd,
    round(coalesce(redeem_months.redeemed_value_usd, 0), 2) as redeemed_value_usd,
    -- What: cumulative (earned - redeemed) per game and channel.
    -- Why: outstanding float is a stock, not a flow. Round after the
    -- window so cent rounding does not accumulate month to month.
    round(
        sum(
            coalesce(earn_months.earned_value_usd, 0)
            - coalesce(redeem_months.redeemed_value_usd, 0)
        ) over (
            partition by spine.game_id, spine.channel
            order by spine.report_month
            rows between unbounded preceding and current row
        ),
        2
    ) as outstanding_float_usd
from spine
inner join {{ ref('games_clean') }} as games
    on spine.game_id = games.game_id
left join earn_months
    on spine.report_month = earn_months.report_month
    and spine.game_id = earn_months.game_id
    and spine.channel = earn_months.channel
left join redeem_months
    on spine.report_month = redeem_months.report_month
    and spine.game_id = redeem_months.game_id
    and spine.channel = redeem_months.channel
