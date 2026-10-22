-- =====================================================================
-- 0081 — QMS Learning Guide (a new KMR App, for any company)
--  • A self-learning manual for ISO 9001, IATF 16949, VDA 6.3, AIAG Control Plan and the core tools (APQP, PPAP, FMEA, MSA, SPC):
--    every clause with its requirement in plain words, what it means, how to implement, documents and records, a sample example,
--    and where the clause comes from. Every page carries the watermark "Educational Purpose Only".
--  • Coverage analysis: which KMR app covers which clause, and what is still missing.
--  • The content is in the website; this migration only adds the product so it can be licensed and switched on per company.
-- Needs 0080. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.d8_sample(uuid, text)') is null then raise exception 'Run 0080_d8_problem_solving.sql first.'; end if;
end $$;
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('qms', 'QMS Learning Guide', 'Self-learning manual of ISO 9001, IATF 16949, VDA 6.3, Control Plan and the core tools, clause by clause, with examples and a coverage analysis of the KMR apps', '/it/qms.html', 'users', '1.0.0', 16)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values
  ('qms', '1.0.0', 'QMS Learning Guide: ISO 9001 and IATF 16949 clause by clause, coverage analysis') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 3, true, 'Starting price list (0081) — per user, change in Console › Billing'
  from (values ('qms', 'month', 40), ('qms', 'year', 400)) v(code, period, amt)
 where not exists (select 1 from console.prices x where x.product_code = v.code and x.currency = 'INR' and x.period = v.period)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('qms', 'QMS Learning Guide', 'Learn ISO 9001, IATF 16949 and the core tools clause by clause, in plain words, with examples.',
   E'Every clause: the requirement, what it means, how to implement, documents and records, a sample\nSearch, filters and a learning path for beginners\nCoverage analysis: what the KMR apps already cover and what is left', 16, true)
on conflict (code) do update set name = excluded.name, tagline = excluded.tagline, features = excluded.features, is_active = true;
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('qms', 'Standards manual', 'ISO 9001 and IATF 16949 clause by clause with explanations, implementation steps, documents and records, and samples', true, 15, 0, 0, 10),
  ('qms', 'Coverage analysis', 'Which KMR app covers which clause, and the clauses still without an app', false, 5, 0, 0, 20)
on conflict (product_code, name) do nothing;
delete from console.app_features f where f.product_code = 'qms' and f.name = 'Core platform' and not exists (select 1 from console.invoice_lines il where il.feature_id = f.id);
update console.app_features set price_year = price_month * 10 where product_code = 'qms' and price_year = 0;
select console.sync_app_price('qms');

-- the app has no data of its own: access is by the company's licence and member roles, like the other company-level apps
create or replace function public.kmr_qms_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'qms') is not null;
end $$;
revoke all on function public.kmr_qms_enabled(text) from public; grant execute on function public.kmr_qms_enabled(text) to authenticated;

--@@REGENERATED@@
