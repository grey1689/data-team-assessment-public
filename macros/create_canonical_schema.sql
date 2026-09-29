{#
  Creates the reporting schema. Final Product-facing dbt models will live
  here (configured via models.zbd.canonical in dbt_project.yml).
  Run with: python scripts/dbt_macro_runner.py create_canonical_schema
#}
{% macro create_canonical_schema() %}
  {% if execute %}
    {% do run_query("create schema if not exists canonical") %}
  {% endif %}
{% endmacro %}
