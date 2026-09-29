# Canonical data model

Product asked for a **monthly view of earned value, redeemed value, and outstanding float**, broken out by **game** and **redemption channel**.

This folder is that model. The table to hand to Product is **`canonical.monthly_rewards_by_game_channel`**. The other three models in this schema are supporting transforms (they can be ephemeral if you do not want them persisted).

## Schemas and data flow

Three Postgres schemas in `zbd_development`:

| Schema | Role | Naming |
| --- | --- | --- |
| `proxy` | Landing zone. CSV extracts loaded as-is. | `*_proxy` |
| `clean` | Typed, trimmed copies of proxy. No rows dropped. | `*_clean` |
| `canonical` | USD facts and the Product monthly rollup. | Product table plus optional supports |

```mermaid
flowchart LR
    subgraph files["Source files"]
        csv["data/*.csv"]
    end

    subgraph proxy["schema: proxy"]
        gp["games_proxy"]
        pp["players_proxy"]
        ep["earn_events_proxy"]
        rp["redeem_events_proxy"]
        fp["fx_rates_proxy"]
    end

    subgraph clean["schema: clean"]
        gc["games_clean"]
        pc["players_clean"]
        ec["earn_events_clean"]
        rc["redeem_events_clean"]
        fc["fx_rates_clean"]
    end

    subgraph canonical["schema: canonical"]
        prc["player_redemption_channel"]
        evu["earn_value_usd"]
        rvu["redeem_value_usd"]
        prod["monthly_rewards_by_game_channel"]
    end

    csv -->|dbt macros + Python COPY| gp
    csv --> pp
    csv --> ep
    csv --> rp
    csv --> fp

    gp --> gc
    pp --> pc
    ep --> ec
    rp --> rc
    fp --> fc

    rc --> prc
    ec --> evu
    fc --> evu
    prc --> evu
    rc --> rvu
    pc --> rvu
    fc --> rvu
    evu --> prod
    rvu --> prod
    gc --> prod
```

**How work moves through the layers**

1. **proxy** — `create_source_tables` builds empty `*_proxy` tables. `load_source_data.py` COPY-loads each CSV. No business logic.
2. **clean** — one dbt model per proxy table. Casts, trims, normalizes case. Same grain as source.
3. **canonical** — convert to USD, attach game/channel, then roll up to month × game × channel.

## ERD: clean through Product

Relationships below are **logical** (how the SQL joins). Proxy does not enforce foreign keys; some earn `player_id` values have no player row.

```mermaid
erDiagram
    games_clean {
        text game_id PK
        text game_name
        text platform
        text primary_region
        date launch_date
    }

    players_clean {
        text player_id PK
        date signup_date
        text region
        text primary_game_id FK
        text status
        timestamp updated_at
    }

    earn_events_clean {
        text event_id PK
        text earn_id
        text player_id FK
        text game_id FK
        timestamp earned_at
        numeric amount
        text currency
        text earn_type
    }

    redeem_events_clean {
        text log_id PK
        text redemption_id
        text player_id FK
        text channel
        text status
        numeric amount
        text currency
        timestamp status_changed_at
    }

    fx_rates_clean {
        text currency PK
        date rate_date PK
        numeric rate_to_usd
    }

    player_redemption_channel {
        text player_id PK
        text primary_redemption_channel
    }

    earn_value_usd {
        text event_id PK
        text player_id
        text game_id FK
        text channel
        date report_month
        numeric amount_usd
    }

    redeem_value_usd {
        text log_id PK
        text player_id FK
        text game_id FK
        text channel
        date report_month
        text status
        numeric signed_amount_usd
    }

    monthly_rewards_by_game_channel {
        date report_month PK
        text game_id PK
        text game_name
        text channel PK
        numeric earned_value_usd
        numeric redeemed_value_usd
        numeric outstanding_float_usd
    }

    games_clean ||--o{ players_clean : "primary_game_id"
    games_clean ||--o{ earn_events_clean : "game_id"
    players_clean ||--o{ earn_events_clean : "player_id (optional)"
    players_clean ||--o{ redeem_events_clean : "player_id"
    players_clean ||--o| player_redemption_channel : "modal settled channel"
    redeem_events_clean }o--|| player_redemption_channel : "settled logs"
    earn_events_clean ||--|| earn_value_usd : "FX + channel"
    fx_rates_clean ||--o{ earn_value_usd : "month + currency"
    fx_rates_clean ||--o{ redeem_value_usd : "month + currency"
    redeem_events_clean ||--o{ redeem_value_usd : "settled / reversed"
    players_clean ||--o{ redeem_value_usd : "game via primary_game_id"
    earn_value_usd }o--o{ monthly_rewards_by_game_channel : "sum earned"
    redeem_value_usd }o--o{ monthly_rewards_by_game_channel : "sum net redeemed"
    games_clean ||--o{ monthly_rewards_by_game_channel : "game_name"
```

## Product grain

`monthly_rewards_by_game_channel` is unique on **`report_month` + `game_id` + `channel`**.

| Column | Meaning |
| --- | --- |
| `earned_value_usd` | USD earned that month |
| `redeemed_value_usd` | USD settled minus reversed that month |
| `outstanding_float_usd` | Cumulative earned minus cumulative net redeemed through month end |

```sql
select *
from canonical.monthly_rewards_by_game_channel
order by report_month, game_name, channel;
```
