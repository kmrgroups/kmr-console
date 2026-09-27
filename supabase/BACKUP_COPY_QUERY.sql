-- KMR data copy: one row per table (public schema) with all its rows as JSON.
select table_name as "table",
       (select count(*) from jsonb_array_elements(d)) as rows,
       d::text as data
from (
  select table_name,
         (xpath('/row/c/text()', query_to_xml(format('select coalesce(jsonb_agg(t), ''[]'')::text as c from public.%I t', table_name), false, true, '')))[1]::text::jsonb as d
  from information_schema.tables
  where table_schema = 'public' and table_type = 'BASE TABLE'
) x
order by 1;
