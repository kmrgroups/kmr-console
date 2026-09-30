-- =====================================================================
-- Operations Master › Balloon Inspector card: Load data · Flush data for the company's OWN ballooned drawings
-- (every report except the sample drawing). Flush data downloads a JSON backup first (done by the portal);
-- Load data adds the reports from that file back. Drawing files stay in storage, so reports come back complete.
-- The file is the same format as the Data Master's Balloon backup. Needs 0027. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_ops_sample_drawing(text,text)') is null then raise exception 'Run 0027_ops_card_actions.sql first.'; end if;
end $$;

-- the company's Balloon Inspector workspace (company administrators only)
create or replace function console.balloon_ref(p_slug text) returns uuid
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); bi uuid;
begin
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is null then raise exception 'Balloon Inspector is not in your company''s plan.'; end if;
  if to_regclass('public.bi_reports') is null then raise exception 'Balloon Inspector is not set up in this database.'; end if;
  return bi;
end $$;
revoke all on function console.balloon_ref(text) from public, anon, authenticated;

-- counts: as 0027, plus _own_drawings (the company's own Balloon reports)
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; bi uuid; nd bigint := null; no_ bigint := null;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) filter (where file_path like ''static:%''), count(*) filter (where coalesce(file_path, '''') not like ''static:%'')
               from public.bi_reports where org_id = $1' into nd, no_ using bi;
  end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || coalesce((select jsonb_object_agg('_sample_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and sample group by kind) y), '{}')
      || coalesce((select jsonb_object_agg('_own_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and not sample group by kind) z), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample),
                            '_has_balloon', bi is not null, '_drawings', coalesce(nd, 0), '_own_drawings', coalesce(no_, 0));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- JSON of the company's own Balloon reports (the sample drawing is left out)
create or replace function public.kmr_balloon_own_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare bi uuid := console.balloon_ref(p_slug); rows jsonb;
begin
  execute 'select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), ''[]'') from public.bi_reports x
            where x.org_id = $1 and coalesce(x.file_path, '''') not like ''static:%''' into rows using bi;
  return jsonb_build_object('format', 'kmr-app-data', 'version', 1, 'app', 'balloon', 'scope', 'own', 'company', lower(p_slug),
                            'exported_at', now(), 'tables', jsonb_build_object('bi_reports', rows));
end $$;
revoke all on function public.kmr_balloon_own_export(text) from public, anon;
grant execute on function public.kmr_balloon_own_export(text) to authenticated;

-- remove the company's own Balloon reports (the sample drawing stays); drawing files are kept in storage
create or replace function public.kmr_balloon_own_flush(p_slug text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare bi uuid := console.balloon_ref(p_slug); n int;
begin
  if to_regclass('public.pd_projects') is not null
     and exists (select 1 from pg_attribute where attrelid = 'public.pd_projects'::regclass and attname = 'bi_report_id' and not attisdropped) then
    execute 'update public.pd_projects set bi_report_id = null where bi_report_id in
               (select id from public.bi_reports where org_id = $1 and coalesce(file_path, '''') not like ''static:%'')' using bi;
  end if;
  perform console.app_triggers('bi', false);
  execute 'delete from public.bi_reports where org_id = $1 and coalesce(file_path, '''') not like ''static:%''' using bi;
  get diagnostics n = row_count;
  perform console.app_triggers('bi', true);
  return n;
end $$;
revoke all on function public.kmr_balloon_own_flush(text) from public, anon;
grant execute on function public.kmr_balloon_own_flush(text) to authenticated;

-- add reports from a JSON file (from Flush data, or a Data Master Balloon backup). A report already there is replaced
-- by the file's copy; everything goes into THIS company's workspace, whatever the file says.
create or replace function public.kmr_balloon_own_load(p_slug text, p_data jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare bi uuid := console.balloon_ref(p_slug); rows jsonb; n int;
begin
  if p_data ->> 'format' is distinct from 'kmr-app-data' or p_data ->> 'app' is distinct from 'balloon' then
    raise exception 'This is not a Balloon Inspector data file.';
  end if;
  rows := (select coalesce(jsonb_agg(r || jsonb_build_object('org_id', bi,
                     'id', coalesce(nullif(r ->> 'id', ''), gen_random_uuid()::text),
                     'created_at', coalesce(r -> 'created_at', to_jsonb(now())), 'updated_at', coalesce(r -> 'updated_at', to_jsonb(now())),
                     'data', coalesce(r -> 'data', '{}'::jsonb), 'status', coalesce(r -> 'status', '"draft"'::jsonb))), '[]')
             from jsonb_array_elements(coalesce(p_data -> 'tables' -> 'bi_reports', '[]')) r
            where coalesce(r ->> 'file_path', '') not like 'static:%');
  if jsonb_array_length(rows) = 0 then raise exception 'No reports found in the file.'; end if;
  perform console.app_triggers('bi', false);
  -- a report id already used by ANOTHER company is never overwritten
  if exists (select 1 from jsonb_array_elements(rows) r join public.bi_reports b on b.id = (r ->> 'id')::uuid and b.org_id <> bi) then
    perform console.app_triggers('bi', true);
    raise exception 'This file belongs to another company''s Balloon Inspector.';
  end if;
  delete from public.bi_reports b using jsonb_array_elements(rows) r where b.org_id = bi and b.id = (r ->> 'id')::uuid;
  insert into public.bi_reports select * from jsonb_populate_recordset(null::public.bi_reports, rows) on conflict do nothing;
  get diagnostics n = row_count;
  perform console.app_triggers('bi', true);
  return n;
end $$;
revoke all on function public.kmr_balloon_own_load(text, jsonb) from public, anon;
grant execute on function public.kmr_balloon_own_load(text, jsonb) to authenticated;
