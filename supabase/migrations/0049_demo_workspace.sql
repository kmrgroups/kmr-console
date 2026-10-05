-- =====================================================================
-- 0049 — Sample data lives ONLY in demo workspaces, never in a real company.
--
--  • console.customers.kind: 'customer' (default) | 'demo' | 'internal'. The Console's demo customers (source "KMR demo data")
--    are marked 'demo' automatically.
--  • Guards: a row marked sample (Operations Master, Sales Flow, Calibration Hub, APQP, PPAP), a demo HRM employee
--    (@demo.kmr.test) or the Balloon Inspector sample drawing can only be created inside a demo workspace. Every entry point —
--    Grand Master, Operations Master, the HRM loaders — is therefore refused for a real company, with a plain message.
--  • kmr_sample_report(): READ-ONLY count of the sample rows still sitting in each company (KMR staff).
--  • kmr_sample_purge(slug, confirm) / kmr_sample_purge_all(confirm): removes them after saving a copy of exactly those rows
--    in console.sample_purge_log (KMR staff). Demo workspaces are never purged.
--  • console.demo_refresh(): switches on the company-level apps in the demo workspace and reloads its sample data — run nightly.
--  • kmr_workspace_info(slug): lets the apps know whether they are in a demo workspace (to show / hide the sample buttons).
-- Needs 0048. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.apqp_projects') is null then raise exception 'Run 0048_apqp_ppap.sql first.'; end if;
end $$;

-- ---------- 1. what kind of company is it? ----------
alter table console.customers add column if not exists kind text not null default 'customer' check (kind in ('customer', 'demo', 'internal'));
update console.customers set kind = 'demo' where source = 'KMR demo data' and kind <> 'demo';
create or replace function console.customers_kind_fill() returns trigger language plpgsql as $$
begin if new.source = 'KMR demo data' then new.kind := 'demo'; end if; return new; end $$;
drop trigger if exists customers_kind on console.customers;
create trigger customers_kind before insert or update of source on console.customers for each row execute function console.customers_kind_fill();

create or replace function console.is_demo(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select coalesce((select kind = 'demo' from console.customers where id = p_cid), false) $$;
-- is this app workspace (HRM tenant, Balloon / Process Documents / Capacity workspace) a demo company's?
create or replace function console.is_demo_ref(p_code text, p_ref uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.licences l join console.customers c on c.id = l.customer_id where l.product_code = p_code and l.product_ref = p_ref and c.kind = 'demo') $$;
revoke all on function console.is_demo(uuid), console.is_demo_ref(text, uuid) from public, anon;

-- ---------- 2. guards: no sample data in a real company ----------
create or replace function console.guard_sample() returns trigger language plpgsql as $$
begin
  if coalesce(new.sample, false) and not console.is_demo(new.customer_id) then
    raise exception 'Sample data is only for the KMR demo workspace, not for a real company. Use the demo workspace to explore, or import your own data.' using errcode = 'P0001';
  end if;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['ops_records', 'sf_lines', 'sf_actions', 'cal_instruments', 'apqp_projects', 'ppap_submissions'] loop
    if to_regclass('console.' || t) is null then continue; end if;
    execute format('drop trigger if exists %I on console.%I', t || '_sample_guard', t);
    execute format('create trigger %I before insert or update of sample on console.%I for each row execute function console.guard_sample()', t || '_sample_guard', t);
  end loop;
end $$;

-- HRM demo staff and the Balloon sample drawing are identified by convention, not by a flag
do $$ begin
  if to_regclass('hrm.employees') is not null then
    create or replace function hrm.guard_demo_employee() returns trigger language plpgsql security definer set search_path = hrm, console, public as $f$
    begin
      if new.email ilike '%@demo.kmr.test' and not console.is_demo_ref('hrm', new.tenant_id) then
        raise exception 'Sample data is only for the KMR demo workspace, not for a real company.' using errcode = 'P0001';
      end if;
      return new;
    end $f$;
    drop trigger if exists employees_demo_guard on hrm.employees;
    create trigger employees_demo_guard before insert on hrm.employees for each row execute function hrm.guard_demo_employee();
  end if;
  if to_regclass('public.bi_reports') is not null then
    create or replace function public.guard_demo_report() returns trigger language plpgsql security definer set search_path = public, console as $f$
    begin
      if new.file_path like 'static:%' and not console.is_demo_ref('balloon', new.org_id) then
        raise exception 'Sample data is only for the KMR demo workspace, not for a real company.' using errcode = 'P0001';
      end if;
      return new;
    end $f$;
    drop trigger if exists bi_reports_demo_guard on public.bi_reports;
    create trigger bi_reports_demo_guard before insert on public.bi_reports for each row execute function public.guard_demo_report();
  end if;
end $$;

-- ---------- 3. what is there? (read-only) ----------
create or replace function console.sample_counts(p_cid uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare c jsonb; ref uuid; n int;
begin
  c := jsonb_build_object(
    'Operations Master', (select count(*) from console.ops_records where customer_id = p_cid and sample),
    'Sales Flow', (select count(*) from console.sf_lines where customer_id = p_cid and sample),
    'Calibration Hub', (select count(*) from console.cal_instruments where customer_id = p_cid and sample),
    'APQP', (select count(*) from console.apqp_projects where customer_id = p_cid and sample),
    'PPAP', (select count(*) from console.ppap_submissions where customer_id = p_cid and sample));
  ref := console.grand_ref(p_cid, 'hrm');
  if ref is not null and to_regclass('hrm.employees') is not null then
    execute 'select count(*) from hrm.employees where tenant_id = $1 and email ilike ''%@demo.kmr.test''' into n using ref; c := c || jsonb_build_object('HRM staff', n);
  end if;
  ref := console.grand_ref(p_cid, 'balloon');
  if ref is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) from public.bi_reports where org_id = $1 and file_path like ''static:%''' into n using ref; c := c || jsonb_build_object('Balloon drawings', n);
  end if;
  return c;
end $$;
revoke all on function console.sample_counts(uuid) from public, anon, authenticated;

create or replace function public.kmr_sample_report() returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare r record; c jsonb; out jsonb := '[]';
begin
  if not console.is_staff() then raise exception 'KMR staff only.'; end if;
  for r in select id, name, slug, kind, code from console.customers order by (kind = 'demo'), name loop
    c := console.sample_counts(r.id);
    out := out || jsonb_build_object('id', r.id, 'code', r.code, 'name', r.name, 'slug', r.slug, 'kind', r.kind, 'counts', c,
                                     'total', (select coalesce(sum(v::int), 0) from jsonb_each_text(c) x(k, v)));
  end loop;
  return out;
end $$;

-- ---------- 4. remove it from real companies — with a copy kept ----------
create table if not exists console.sample_purge_log (
  id uuid primary key default gen_random_uuid(), customer_id uuid, customer_name text, slug text,
  purged_at timestamptz not null default now(), purged_by text, counts jsonb not null default '{}', snapshot jsonb not null default '{}');
alter table console.sample_purge_log enable row level security;
drop policy if exists sample_purge_log_staff on console.sample_purge_log;
create policy sample_purge_log_staff on console.sample_purge_log for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function console.sample_purge(p_cid uuid, p_by text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cu console.customers%rowtype; snap jsonb; counts jsonb; ref uuid;
begin
  select * into cu from console.customers where id = p_cid;
  if not found then raise exception 'Company not found.'; end if;
  if cu.kind = 'demo' then raise exception 'This is a demo workspace — its sample data stays. Use “Reset demo” instead.'; end if;
  counts := console.sample_counts(p_cid);
  if (select coalesce(sum(v::int), 0) from jsonb_each_text(counts) x(k, v)) = 0 then return jsonb_build_object('counts', counts, 'removed', 0); end if;
  -- a copy of exactly the rows that will go
  snap := jsonb_build_object(
    'ops_records', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.ops_records x where x.customer_id = p_cid and x.sample),
    'sf_lines', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.sf_lines x where x.customer_id = p_cid and x.sample),
    'sf_despatch', (select coalesce(jsonb_agg(to_jsonb(d)), '[]') from console.sf_despatch d join console.sf_lines l on l.id = d.line_id where l.customer_id = p_cid and l.sample),
    'sf_actions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.sf_actions x where x.customer_id = p_cid and x.sample),
    'cal_instruments', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.cal_instruments x where x.customer_id = p_cid and x.sample),
    'cal_records', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from console.cal_records r join console.cal_instruments i on i.id = r.instrument_id where i.customer_id = p_cid and i.sample),
    'apqp_projects', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.apqp_projects x where x.customer_id = p_cid and x.sample),
    'apqp_items', (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from console.apqp_items i join console.apqp_projects p on p.id = i.project_id where p.customer_id = p_cid and p.sample),
    'ppap_submissions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from console.ppap_submissions x where x.customer_id = p_cid and x.sample));
  ref := console.grand_ref(p_cid, 'hrm');
  if ref is not null and to_regclass('hrm.employees') is not null then
    snap := snap || jsonb_build_object('hrm_employees', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from hrm.employees e where e.tenant_id = ref and e.email ilike '%@demo.kmr.test'));
  end if;
  insert into console.sample_purge_log (customer_id, customer_name, slug, purged_by, counts, snapshot) values (p_cid, cu.name, cu.slug, p_by, counts, snap);
  -- now remove (the same order the apps' own "flush sample" uses; children follow their parent)
  delete from console.sf_actions where customer_id = p_cid and sample;
  delete from console.sf_lines where customer_id = p_cid and sample;
  delete from console.cal_instruments where customer_id = p_cid and sample;
  delete from console.ppap_submissions where customer_id = p_cid and sample;
  delete from console.apqp_projects where customer_id = p_cid and sample;
  delete from console.ops_records where customer_id = p_cid and sample;
  if ref is not null and to_regprocedure('hrm.demo_flush(uuid)') is not null then perform hrm.demo_flush(ref); end if;
  ref := console.grand_ref(p_cid, 'balloon');
  if ref is not null and to_regclass('public.bi_reports') is not null then execute 'delete from public.bi_reports where org_id = $1 and file_path like ''static:%''' using ref; end if;
  return jsonb_build_object('counts', counts, 'removed', (select coalesce(sum(v::int), 0) from jsonb_each_text(counts) x(k, v)));
end $$;
revoke all on function console.sample_purge(uuid, text) from public, anon, authenticated;

create or replace function public.kmr_sample_purge(p_slug text, p_confirm text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  if not console.is_staff() then raise exception 'KMR staff only.'; end if;
  if coalesce(trim(p_confirm), '') <> 'PURGE SAMPLE DATA' then raise exception 'Type PURGE SAMPLE DATA to confirm.'; end if;
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null then raise exception 'Company not found.'; end if;
  return console.sample_purge(cid, lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
create or replace function public.kmr_sample_purge_all(p_confirm text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare r record; out jsonb := '[]'; res jsonb; who text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not console.is_staff() then raise exception 'KMR staff only.'; end if;
  if coalesce(trim(p_confirm), '') <> 'PURGE SAMPLE DATA' then raise exception 'Type PURGE SAMPLE DATA to confirm.'; end if;
  for r in select id, name, slug from console.customers where kind <> 'demo' order by name loop
    res := console.sample_purge(r.id, who);
    if (res ->> 'removed')::int > 0 then out := out || jsonb_build_object('name', r.name, 'slug', r.slug, 'removed', res -> 'removed', 'counts', res -> 'counts'); end if;
  end loop;
  return out;
end $$;

-- ---------- 5. the demo workspace ----------
-- company-level apps are always on in the demo; the sample is then reloaded (acting as the demo administrator)
drop function if exists console.demo_refresh(uuid);
create or replace function console.demo_refresh(p_cid uuid, p_full boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cu console.customers%rowtype; pcode text; out jsonb;
begin
  select * into cu from console.customers where id = p_cid and kind = 'demo';
  if not found then raise exception 'This is not a demo workspace.'; end if;
  foreach pcode in array array['sales', 'calib', 'apqp', 'ppap'] loop
    insert into console.licences (customer_id, product_code, status, valid_until, seats, notes, product_ref, product_slug)
    select p_cid, pcode, 'active', null, 25, 'KMR demo data', p_cid, cu.slug where exists (select 1 from console.products pr where pr.code = pcode)
    on conflict (customer_id, product_code) do nothing;
  end loop;
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'email', lower(coalesce(cu.contact_email, ''))) ::text, true);
  if p_full then perform public.kmr_grand_sample(cu.slug, 'flush'); end if;   -- the nightly reset starts clean; the first load only adds what is missing
  out := public.kmr_grand_sample(cu.slug, 'load');
  return out;
end $$;
create or replace function console.demo_refresh_all() returns jsonb language plpgsql security definer set search_path = console, public as $$
declare r record; out jsonb := '[]';
begin
  for r in select id, slug from console.customers where kind = 'demo' and slug = 'kmr-demo' loop
    out := out || jsonb_build_object('slug', r.slug, 'loaded', console.demo_refresh(r.id));
  end loop;
  return out;
end $$;
revoke all on function console.demo_refresh(uuid, boolean), console.demo_refresh_all() from public, anon, authenticated;
grant execute on function console.demo_refresh(uuid, boolean), console.demo_refresh_all() to service_role;

-- ---------- 6. what the apps ask ----------
create or replace function public.kmr_workspace_info(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('kind', c.kind) from console.customers c where c.slug = lower(p_slug) $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('kmr_sample_report', 'kmr_sample_purge', 'kmr_sample_purge_all', 'kmr_workspace_info') loop
    execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
