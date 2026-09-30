-- =====================================================================
-- Operations Master cards: per list — Load sample · Flush sample · Load data (JSON) · Flush data (your own records;
-- the portal downloads a JSON backup first). Plus a "Sample drawing" card that puts a ready-made drawing into the
-- company's Balloon Inspector. Needs 0026. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_data_overview(text)') is null then raise exception 'Run 0026_data_master.sql first.'; end if;
end $$;

-- counts: in use per list; sample and own (your) records per list; sample drawings in Balloon Inspector
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; bi uuid; nd bigint := null;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) from public.bi_reports where org_id = $1 and file_path like ''static:%''' into nd using bi;
  end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || coalesce((select jsonb_object_agg('_sample_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and sample group by kind) y), '{}')
      || coalesce((select jsonb_object_agg('_own_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and not sample group by kind) z), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample),
                            '_has_balloon', bi is not null, '_drawings', coalesce(nd, 0));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- your own (non-sample) records of one list; the portal downloads them as JSON before calling this
create or replace function public.kmr_ops_flush_data(p_slug text, p_kind text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); n int;
begin
  delete from console.ops_records where customer_id = cid and kind = p_kind and not sample;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kmr_ops_flush_data(text, text) from public, anon;
grant execute on function public.kmr_ops_flush_data(text, text) to authenticated;

-- Sample drawing for Balloon Inspector: a report that points at a drawing kept on the website ("static:" path);
-- Balloon Inspector balloons it automatically when it is opened.
create or replace function public.kmr_ops_sample_drawing(p_slug text, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); bi uuid; n int := 0; cols text[]; vals jsonb; r jsonb;
begin
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is null then raise exception 'Balloon Inspector is not in your company''s plan.'; end if;
  if to_regclass('public.bi_reports') is null then raise exception 'Balloon Inspector is not set up in this database.'; end if;
  if p_action = 'flush' then
    execute 'delete from public.bi_reports where org_id = $1 and file_path like ''static:%''' using bi;
    get diagnostics n = row_count; return n;
  end if;
  if p_action <> 'load' then raise exception 'Unknown action.'; end if;
  for r in select * from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('title', 'Sample drawing — Mounting Plate', 'part_no', 'EX-2040', 'rev', 'B', 'drawing_no', 'EX-2040-DRG', 'customer', 'Sample customer',
                         'file_path', 'static:/it/balloon/samples/EX-2040_sample.dxf', 'file_name', 'EX-2040_sample.dxf'))) loop
    execute 'select count(*) from public.bi_reports where org_id = $1 and file_path = $2' into n using bi, r ->> 'file_path';
    continue when n > 0;
    -- only the columns this project's table has (the Balloon schema may differ slightly between projects)
    vals := r || jsonb_build_object('org_id', bi, 'data', '{}'::jsonb, 'created_by', auth.uid(), 'updated_by', auth.uid());
    select array_agg(a.attname::text order by a.attnum) into cols from pg_attribute a
     where a.attrelid = 'public.bi_reports'::regclass and a.attnum > 0 and not a.attisdropped and vals ? a.attname and vals -> a.attname <> 'null'::jsonb;
    execute format('insert into public.bi_reports (%s) select %s from jsonb_populate_record(null::public.bi_reports, $1)',
                   (select string_agg(quote_ident(c), ', ') from unnest(cols) c), (select string_agg(quote_ident(c), ', ') from unnest(cols) c)) using vals;
  end loop;
  execute 'select count(*) from public.bi_reports where org_id = $1 and file_path like ''static:%''' into n using bi;
  return n;
end $$;
revoke all on function public.kmr_ops_sample_drawing(text, text) from public, anon;
grant execute on function public.kmr_ops_sample_drawing(text, text) to authenticated;
