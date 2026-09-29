{#
  Fails when the relation has zero rows.

  Use this on proxy sources to confirm a load landed without pinning a
  fixed CSV row count (counts will change as new files are loaded).
#}
{% test expect_at_least_one_row(model) %}
    select count(*) as actual_row_count
    from {{ model }}
    having count(*) = 0
{% endtest %}
