{{ config(
    alias="earn_events_clean",
    materialized="table"
) }}

-- Clean earn event records (clean.earn_events_clean).
-- Trims keys, uppercases ISO currency codes, lowercases earn_type, and casts
-- amount/earned_at. Duplicate earn_id values are retained because event_id is
-- the pipeline grain. Unmatched player keys are retained; this layer does
-- not filter facts.

select
    btrim(event_id) as event_id,
    btrim(earn_id) as earn_id,
    btrim(player_id) as player_id,
    btrim(game_id) as game_id,
    earned_at::timestamp as earned_at,
    amount::numeric(18, 4) as amount,
    upper(btrim(currency)) as currency,
    lower(btrim(earn_type)) as earn_type
from {{ source('proxy', 'earn_events_proxy') }}
