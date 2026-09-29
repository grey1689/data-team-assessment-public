{{ config(
    alias="redeem_value_usd",
    materialized="table"
) }}

-- canonical.redeem_value_usd
--
-- Why this model exists
-- Turns the redemption status log into signed USD movements that change
-- outstanding float. This is a fact table used by the monthly Product
-- rollup, not the Product output itself.
--
-- Required vs optional
-- Intermediate. Could be inlined in the monthly model. Kept as a table so
-- settled vs reversed timing can be queried during the live discussion.
--
-- Grain: log_id, filtered to status in (settled, reversed) only.
--
-- Status rules (float accounting)
--   requested  — still a liability; do not treat as redeemed.
--   failed     — never left the balance; ignore.
--   settled    — value left the system; +amount in the settle month.
--   reversed   — value returned; -amount in the reverse month.
-- Paths in this extract: requested>settled, requested>failed,
-- requested>settled>reversed. Amount/currency/channel do not change
-- across logs for a given redemption_id.
--
-- Game
-- redeem_events have no game_id. Use players.primary_game_id. Every
-- redeem log has a matching player in this extract.
--
-- Channel
-- Taken from the log (the actual payout path), not the player's modal
-- channel. A player can redeem on a different channel than their mode;
-- earned value still sits on the modal/unallocated channel.
--
-- USD conversion
-- Same monthly FX snapshot as earns, keyed on status_changed_at's month.
--
-- Source: clean.redeem_events_clean, clean.players_clean,
--         clean.fx_rates_clean.
--
-- Materialization
-- Currently a table in schema canonical. This is a supporting model, not
-- the Product output. It can be materialized as ephemeral
-- (`{{ config(materialized='ephemeral') }}`) so dbt inlines the SQL and
-- no relation is created in canonical.

select
    r.log_id,
    r.redemption_id,
    r.player_id,
    p.primary_game_id as game_id,
    r.channel,
    date_trunc('month', r.status_changed_at)::date as report_month,
    r.status_changed_at,
    r.status,
    case
        when r.status = 'settled' then r.amount
        when r.status = 'reversed' then -1 * r.amount
    end as signed_amount,
    r.currency,
    f.rate_to_usd,
    (
        case
            when r.status = 'settled' then r.amount
            when r.status = 'reversed' then -1 * r.amount
        end * f.rate_to_usd
    )::numeric(18, 4) as signed_amount_usd
from {{ ref('redeem_events_clean') }} as r
inner join {{ ref('players_clean') }} as p
    on r.player_id = p.player_id
inner join {{ ref('fx_rates_clean') }} as f
    on r.currency = f.currency
    and date_trunc('month', r.status_changed_at)::date = f.rate_date
where r.status in ('settled', 'reversed')
