{{ config(
    alias="earn_value_usd",
    materialized="table"
) }}

-- canonical.earn_value_usd
--
-- Why this model exists
-- Converts each earn event to USD and tags it with game + channel so the
-- monthly Product table can sum earned_value_usd. This is a fact table,
-- not the Product output.
--
-- Required vs optional
-- Intermediate. The Product requirement is the monthly rollup. This table
-- exists so FX conversion, channel attribution, and unmatched players can
-- be inspected row-by-row in the live session.
--
-- Grain: event_id (pipeline record). Duplicate earn_id values are kept
-- because the collection pipeline assigned distinct event_ids.
--
-- Game
-- Taken from the earn event (earn_events.game_id), not the player's
-- primary_game_id. Those two match for every earn that has a player row.
-- 52 events have a player_id with no players_clean row; they still have
-- a game_id and are retained.
--
-- Channel
-- Earns have no channel in source. Join player_redemption_channel. If the
-- player never settled a redemption (or is missing from players), channel
-- is `unallocated`. That is an explicit modeling choice for Product.
--
-- USD conversion
-- fx_rates_clean is a monthly snapshot (rate_date = first of month).
-- Join currency + date_trunc(month, earned_at). Inner join: every earn
-- in this extract has a matching rate; a missed rate would drop the row
-- and should fail tests / be visible as a count mismatch vs clean.
--
-- Source: clean.earn_events_clean, clean.fx_rates_clean,
--         canonical.player_redemption_channel.
--
-- Materialization
-- Currently a table in schema canonical. This is a supporting model, not
-- the Product output. It can be materialized as ephemeral
-- (`{{ config(materialized='ephemeral') }}`) so dbt inlines the SQL and
-- no relation is created in canonical.

select
    e.event_id,
    e.earn_id,
    e.player_id,
    e.game_id,
    -- Missing lookup => player never settled (or unknown player).
    coalesce(pc.primary_redemption_channel, 'unallocated') as channel,
    date_trunc('month', e.earned_at)::date as report_month,
    e.earned_at,
    e.amount,
    e.currency,
    f.rate_to_usd,
    (e.amount * f.rate_to_usd)::numeric(18, 4) as amount_usd,
    e.earn_type
from {{ ref('earn_events_clean') }} as e
inner join {{ ref('fx_rates_clean') }} as f
    on e.currency = f.currency
    and date_trunc('month', e.earned_at)::date = f.rate_date
left join {{ ref('player_redemption_channel') }} as pc
    on e.player_id = pc.player_id
