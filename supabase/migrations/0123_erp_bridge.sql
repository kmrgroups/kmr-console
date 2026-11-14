-- 0123: the universal ERP bridge. One hidden program on the ERP PC sends the ERP's tables; the server converts them and calls the same
-- import functions the apps already use. Every one of them skips what is already loaded, so sending the same data again never duplicates it.
-- The bridge identifies a plant by its sync key (the same key the Sales Flow despatch sync uses).
-- Run after 0122. Safe to run again.
create table if not exists console.bridge_runs (
  id bigserial primary key, customer_id uuid not null references console.customers(id) on delete cascade,
  kind text not null, at timestamptz not null default now(), ok boolean not null, rows integer not null default 0, summary jsonb not null default '{}');
create index if not exists bridge_runs_cust on console.bridge_runs (customer_id, kind, at desc);
alter table console.bridge_runs enable row level security;
drop policy if exists bridge_runs_staff on console.bridge_runs;
create policy bridge_runs_staff on console.bridge_runs for select to authenticated using (console.is_staff());

-- which plant does this key belong to
create or replace function public.kmr_bridge_whoami(p_key text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid; sl text; nm text;
begin
  select k.customer_id into cid from console.sf_erp_keys k where k.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex') and k.active;
  if cid is null then raise exception 'Unknown sync key.' using errcode = 'KM403'; end if;
  select slug, name into sl, nm from console.customers where id = cid;
  return jsonb_build_object('slug', sl, 'name', nm);
end $$;
revoke all on function public.kmr_bridge_whoami(text) from public, anon, authenticated;
grant execute on function public.kmr_bridge_whoami(text) to service_role;

-- run one of the import functions for the plant of this key (acting as the developer login, so the usual access checks pass)
create or replace function public.kmr_bridge_run(p_key text, p_fn text, p_args jsonb, p_kind text, p_rows integer default 0) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; sl text; uid uuid; res jsonb;
begin
  if p_fn not in ('kmr_inv_import', 'kmr_mmd_hist_import', 'kmr_dcg_import', 'kmr_cal_import_erp', 'kmr_ops_bulk') then raise exception 'Not allowed.' using errcode = 'KM403'; end if;
  select k.customer_id into cid from console.sf_erp_keys k where k.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex') and k.active;
  if cid is null then raise exception 'Unknown sync key.' using errcode = 'KM403'; end if;
  select slug into sl from console.customers where id = cid;
  select u.id into uid from auth.users u join console.staff s on s.user_id = u.id and s.active where lower(u.email) = 'info@kmr-groups.com' limit 1;
  if uid is null then raise exception 'The developer login is not set up as KMR staff.' using errcode = 'KM403'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', uid, 'email', 'info@kmr-groups.com')::text, true);
  perform pg_advisory_xact_lock(hashtextextended('bridge:' || cid::text || ':' || p_kind, 0));
  begin
    execute format('select to_jsonb(public.%I($1, $2))', p_fn) into res using sl, p_args;
    insert into console.bridge_runs (customer_id, kind, ok, rows, summary) values (cid, p_kind, true, coalesce(p_rows, 0), coalesce(res, '{}'));
  exception when others then
    insert into console.bridge_runs (customer_id, kind, ok, rows, summary) values (cid, p_kind, false, coalesce(p_rows, 0), jsonb_build_object('error', sqlerrm));
    raise;
  end;
  return coalesce(res, '{}'::jsonb);
end $$;
revoke all on function public.kmr_bridge_run(text, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.kmr_bridge_run(text, text, jsonb, text, integer) to service_role;

-- last result of each kind for a plant (developer only)
create or replace function public.kmr_bridge_status(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when not coalesce(console.is_developer(), false) then '[]'::jsonb else coalesce((
    select jsonb_agg(to_jsonb(x) order by x.kind) from (
      select distinct on (b.kind) b.kind, b.at, b.ok, b.rows, b.summary from console.bridge_runs b join console.customers c on c.id = b.customer_id
       where c.slug = lower(p_slug) order by b.kind, b.at desc) x), '[]'::jsonb) end $$;
revoke all on function public.kmr_bridge_status(text) from public, anon;
grant execute on function public.kmr_bridge_status(text) to authenticated;
