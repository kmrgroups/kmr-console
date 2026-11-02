-- =====================================================================
-- 0091 — Daily Work Management (DWM) — a new KMR app, company level like Sales Flow
--  • the Plant Head's monthly DWM sheet (plan O / completed C / missed X / concession E / off –), the Review standards
--    and the Executive Director reporting register, saved per company
--  • sign-in and licence through console.qp_role (same as every other app); viewers read, editors and admins change
--  • one saved document per company and key:  'plan:YYYY-MM'  (the month's sheet)  and  'edr'  (reporting + directions register)
-- Needs 0048 (qp_* functions). Safe to re-run.
-- =====================================================================

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('dwm', 'Daily Work Management', 'Plant Head monthly DWM sheet: every review planned by day, marked completed / missed / concession, adherence against the 98% target, review standards and Executive Director reporting', '/it/dwm.html', 'users', '1.0.0', 140)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;

insert into console.releases (product_code, version, notes) values
  ('dwm', '1.0.0', 'Daily Work Management: monthly Plant Head sheet with O/C/X/E status and adherence, review standards, Executive Director reporting and directions register, standards alignment, presentation')
on conflict do nothing;

insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0091) — change in Console • Billing'
  from (values ('dwm', 'month', 1500), ('dwm', 'year', 15000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;

insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('dwm', 'Daily Work Management', 'The plant head''s daily, weekly and monthly reviews planned, ticked off and measured against a 98% adherence target.',
   E'Monthly sheet with plan, completed, missed and concession status\nAdherence per activity, per day and for the month\nReview standards and Executive Director reporting', 140, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);

insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('dwm', 'Monthly DWM sheet and adherence', 'Plan by day from each activity''s frequency, O/C/X/E status, adherence per activity, per day and for the month, missed and concession record', true, 1500, 0, 5000, 10)
on conflict (product_code, name) do nothing;

-- the licence for every active customer, like the other apps of the suite
insert into console.licences (customer_id, product_code, status, valid_until, seats, notes)
select id, 'dwm', 'active', null, 25, 'KMR Apps Suite licence'
  from console.customers where status = 'active'
on conflict (customer_id, product_code) do nothing;

-- ---------- the saved documents ----------
create table if not exists console.dwm_docs (
  customer_id uuid not null references console.customers(id) on delete cascade,
  doc_key     text not null check (doc_key ~ '^(plan:[0-9]{4}-[0-9]{2}|edr)$'),
  doc         jsonb not null,
  updated_by  text,
  updated_at  timestamptz not null default now(),
  primary key (customer_id, doc_key)
);
alter table console.dwm_docs enable row level security;
drop policy if exists dwm_docs_staff on console.dwm_docs;
create policy dwm_docs_staff on console.dwm_docs for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_dwm_get(p_slug text, p_key text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'dwm');
begin
  return (select doc from console.dwm_docs where customer_id = cid and doc_key = p_key);
end $$;

create or replace function public.kmr_dwm_save(p_slug text, p_key text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dwm'); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_key !~ '^(plan:[0-9]{4}-[0-9]{2}|edr)$' then raise exception 'Unknown document.'; end if;
  if p_doc is null or jsonb_typeof(p_doc) <> 'object' then raise exception 'Nothing to save.'; end if;
  if length(p_doc::text) > 2000000 then raise exception 'The sheet is too large.'; end if;
  insert into console.dwm_docs (customer_id, doc_key, doc, updated_by) values (cid, p_key, p_doc, me)
  on conflict (customer_id, doc_key) do update set doc = excluded.doc, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('ok', true, 'saved_at', now());
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_dwm_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- ---------- platform functions: Data Master, clear-data, apps list in the portal ----------
do $wrap$ begin
  if to_regprocedure('console.app2_tables_dwm_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_dwm_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''dwm'' then array[''dwm_docs''] else console.app2_tables_dwm_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_dwm_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_dwm_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint;
    begin
      if p_app = 'dwm' then
        if p_real_only then return 0; end if;          -- there is no sample data for DWM: only a full clear removes the sheets
        delete from console.dwm_docs where customer_id = p_cid; get diagnostics n = row_count; return n;
      end if;
      return console.app2_clear_dwm_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_dwm_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;

-- text patches: the apps a person may open (portal), as done for the other apps. A function that already has the change is left alone.
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join')
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('dwm' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*when 'layout'\s+then console\.qp_member\(([a-z_.]+), em, 'layout'\))$re$, E'\\1\n     when ''dwm'' then console.qp_member(\\2, em, ''dwm'')', 'g');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'DWM: % portal functions updated', n;
end $patch$;
