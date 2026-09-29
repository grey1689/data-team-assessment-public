{{ config(
    alias="games_clean",
    materialized="table"
) }}

-- Clean games dimension (clean.games_clean).
-- Trims identifiers/labels and casts launch_date so downstream models can
-- rely on typed columns rather than proxy CSV text/date inference.

select
    btrim(game_id) as game_id,
    btrim(game_name) as game_name,
    btrim(platform) as platform,
    btrim(primary_region) as primary_region,
    launch_date::date as launch_date
from {{ source('proxy', 'games_proxy') }}
