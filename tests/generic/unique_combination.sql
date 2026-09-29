{#
  Fails when `combination_of_columns` is not unique on the relation.

  Used for fx_rates, whose grain is (currency, rate_date) rather than a
  single-column primary key.
#}
{% test unique_combination(model, combination_of_columns) %}
    select
        {{ combination_of_columns | join(', ') }}
    from {{ model }}
    group by {{ combination_of_columns | join(', ') }}
    having count(*) > 1
{% endtest %}
