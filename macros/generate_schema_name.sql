{#
  Use the custom schema name as-is instead of prefixing with target.schema.

  Default dbt would prefix custom schemas with target.schema. We want
  dedicated `clean` and `canonical` schemas next to `proxy`. Macros that
  omit +schema still land in target.schema (proxy).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
