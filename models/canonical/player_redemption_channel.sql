{{ config(
    alias="player_redemption_channel",
    materialized="table"
) }}

-- canonical.player_redemption_channel
--
-- Why this model exists
-- Product asked for earned, redeemed, and float by game AND redemption
-- channel. Earn events have no channel. This lookup assigns each player a
-- single "home" channel so earn value can sit on the same grain as
-- redemptions without double-counting.
--
-- Required vs optional
-- Not required by the Product grain itself. It is an intermediate so the
-- channel-attribution rule is testable and can be queried in the live
-- discussion. The same logic could live as a CTE inside earn_value_usd.
--
-- Grain: one row per player_id who has at least one settled redemption.
-- Players who only requested/failed, or never redeemed, are absent here.
-- earn_value_usd left-joins this table and coalesces missing channels to
-- `unallocated`.
--
-- Attribution rule
-- Count settled logs only (value that actually left the system). Rank
-- channels per player by that count descending; ties break on channel
-- name so the choice is deterministic.
--
-- Source: clean.redeem_events_clean (status-log grain).
--
-- Materialization
-- Currently a table in schema canonical. This is a supporting model, not
-- the Product output. It can be materialized as ephemeral
-- (`{{ config(materialized='ephemeral') }}`) so dbt inlines the SQL and
-- no relation is created in canonical.

with settled_by_channel as (
    -- What: count of settled redemption logs per player and channel.
    -- Why: "home" channel is defined as the path the player actually
    -- settled on most often, not requested/failed activity.
    select
        player_id,
        channel,
        count(*) as settled_log_count
    from {{ ref('redeem_events_clean') }}
    where status = 'settled'
    group by player_id, channel
),

ranked_channels as (
    -- What: rank each player's channels by settled volume.
    -- Why: we need exactly one channel per player. Count desc picks the
    -- mode; channel name is a stable tie-break.
    select
        player_id,
        channel,
        row_number() over (
            partition by player_id
            order by settled_log_count desc, channel
        ) as channel_rank
    from settled_by_channel
)

-- What: keep rank 1 only.
-- Why: earn_value_usd joins a unique player_id -> channel map.
select
    player_id,
    channel as primary_redemption_channel
from ranked_channels
where channel_rank = 1
