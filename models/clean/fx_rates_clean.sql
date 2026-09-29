{{ config(
    alias="fx_rates_clean",
    materialized="table"
) }}

-- Clean FX rate snapshots (clean.fx_rates_clean).
-- Grain is currency + rate_date. Uppercases currency codes and casts the
-- rate/date so later USD conversions use numeric rates.

select
    upper(btrim(currency)) as currency,
    rate_date::date as rate_date,
    rate_to_usd::numeric(18, 8) as rate_to_usd
from {{ source('proxy', 'fx_rates_proxy') }}
