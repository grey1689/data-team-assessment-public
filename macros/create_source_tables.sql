{#
  DDL macros for landing-zone tables in target.schema (proxy by default).

  Tables are suffixed `_proxy` so they are distinct from `*_clean` models
  in schema `clean`. These run via `dbt run-operation`, not `dbt run`.

  Column names and types follow DATA_DICTIONARY.md and the CSV headers.
  No foreign keys: extracts can reference games/players that do not join cleanly.
#}

{% macro create_proxy_schema() %}
  {# Create the landing schema once so subsequent CREATE TABLE statements succeed. #}
  {% if execute %}
    {% do run_query("create schema if not exists " ~ target.schema) %}
  {% endif %}
{% endmacro %}

{% macro create_games_proxy_table() %}
  {# Grain: one row per game_id. #}
  {% if execute %}
    {% do run_query(
      "create table if not exists " ~ target.schema ~ ".games_proxy (
        game_id text primary key,
        game_name text,
        platform text,
        primary_region text,
        launch_date date
      )"
    ) %}
  {% endif %}
{% endmacro %}

{% macro create_players_proxy_table() %}
  {# Grain: one row per player_id. updated_at is the snapshot write time. #}
  {% if execute %}
    {% do run_query(
      "create table if not exists " ~ target.schema ~ ".players_proxy (
        player_id text primary key,
        signup_date date,
        region text,
        primary_game_id text,
        status text,
        updated_at timestamp
      )"
    ) %}
  {% endif %}
{% endmacro %}

{% macro create_earn_events_proxy_table() %}
  {# Grain: one row per event_id (pipeline record), not necessarily per earn_id. #}
  {% if execute %}
    {% do run_query(
      "create table if not exists " ~ target.schema ~ ".earn_events_proxy (
        event_id text primary key,
        earn_id text,
        player_id text,
        game_id text,
        earned_at timestamp,
        amount numeric,
        currency text,
        earn_type text
      )"
    ) %}
  {% endif %}
{% endmacro %}

{% macro create_redeem_events_proxy_table() %}
  {# Grain: one row per log_id (status change). Multiple logs can share redemption_id. #}
  {% if execute %}
    {% do run_query(
      "create table if not exists " ~ target.schema ~ ".redeem_events_proxy (
        log_id text primary key,
        redemption_id text,
        player_id text,
        channel text,
        status text,
        amount numeric,
        currency text,
        status_changed_at timestamp
      )"
    ) %}
  {% endif %}
{% endmacro %}

{% macro create_fx_rates_proxy_table() %}
  {# Grain: one rate per currency and snapshot date. Composite primary key. #}
  {% if execute %}
    {% do run_query(
      "create table if not exists " ~ target.schema ~ ".fx_rates_proxy (
        currency text,
        rate_date date,
        rate_to_usd numeric,
        primary key (currency, rate_date)
      )"
    ) %}
  {% endif %}
{% endmacro %}

{% macro create_source_tables() %}
  {# Entry point: create schema plus all five `_proxy` source tables. #}
  {{ create_proxy_schema() }}
  {{ create_games_proxy_table() }}
  {{ create_players_proxy_table() }}
  {{ create_earn_events_proxy_table() }}
  {{ create_redeem_events_proxy_table() }}
  {{ create_fx_rates_proxy_table() }}
{% endmacro %}
