{{ config(
    alias="redeem_events_clean",
    materialized="table"
) }}

-- Clean redemption status-log records (clean.redeem_events_clean).
-- Grain remains log_id (multiple statuses per redemption_id). Trims keys,
-- lowercases channel/status, uppercases currency, and casts amount/timestamps.

select
    btrim(log_id) as log_id,
    btrim(redemption_id) as redemption_id,
    btrim(player_id) as player_id,
    lower(btrim(channel)) as channel,
    lower(btrim(status)) as status,
    amount::numeric(18, 4) as amount,
    upper(btrim(currency)) as currency,
    status_changed_at::timestamp as status_changed_at
from {{ source('proxy', 'redeem_events_proxy') }}
