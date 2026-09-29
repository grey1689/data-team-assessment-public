{{ config(
    alias="players_clean",
    materialized="table"
) }}

-- Clean player accounts (clean.players_clean).
-- Trims keys and attributes, lowercases status, and casts signup/update
-- timestamps. Orphan primary_game_id values are left in place so the clean
-- layer does not drop source rows.

select
    btrim(player_id) as player_id,
    signup_date::date as signup_date,
    btrim(region) as region,
    btrim(primary_game_id) as primary_game_id,
    lower(btrim(status)) as status,
    updated_at::timestamp as updated_at
from {{ source('proxy', 'players_proxy') }}
