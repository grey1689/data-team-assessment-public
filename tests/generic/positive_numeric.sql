{#
  Fails when the column is null or <= 0.

  Applied to earn/redeem amounts and FX rates, which must be positive
  after the clean layer's numeric casts.
#}
{% test positive_numeric(model, column_name) %}
    select *
    from {{ model }}
    where {{ column_name }} is null
       or {{ column_name }} <= 0
{% endtest %}
