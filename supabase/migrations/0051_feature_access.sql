-- =====================================================================
-- 0051 — (1) A customer gets ONLY the features it bought. (2) Set-up fees at Indian market rates. (3) Hosting (Vercel + Supabase) items.
--   • console.app_features.key — a stable code per feature (e.g. pd.spc-studies) that the apps use to show or hide a module.
--   • console.licences.features — the feature keys the customer may use. NULL = no restriction (existing customers keep working until you set it).
--   • A PAID invoice sets it: the core features plus every feature on the invoice (added to what the customer already has).
--     You can also set it by hand on the customer's page.
--   • public.kmr_access_features(product): what each app asks — "which features does my workspace have?"
-- Needs 0050. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.app_features') is null then raise exception 'Run 0050_app_features.sql first.'; end if;
end $$;

-- ---------- 1. feature keys ----------
alter table console.app_features add column if not exists key text;
create or replace function console.app_feature_key() returns trigger language plpgsql as $$
begin
  if new.key is null or new.key = '' then
    new.key := new.product_code || '.' || left(trim(both '-' from regexp_replace(lower(new.name), '[^a-z0-9]+', '-', 'g')), 40);
  end if;
  return new;
end $$;
drop trigger if exists app_features_key on console.app_features;
create trigger app_features_key before insert on console.app_features for each row execute function console.app_feature_key();
update console.app_features set key = product_code || '.' || left(trim(both '-' from regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g')), 40) where key is null;
create unique index if not exists app_features_key_uq on console.app_features (key);

-- ---------- 2. which features a licence has ----------
alter table console.licences add column if not exists features text[];

-- Paid invoice: licences renewed (as before) and the features on the invoice switched on
create or replace function console.apply_paid_invoice(p_invoice uuid, p_paid_at timestamptz) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; ln record; bought text[];
begin
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.status <> 'issued' then return; end if;
  update console.invoices set status = 'paid', paid_at = p_paid_at, updated_at = now() where id = p_invoice;
  for ln in select product_code, max(period_to) period_to, max(qty) qty from console.invoice_lines
             where invoice_id = p_invoice and product_code is not null and period_to is not null group by product_code loop
    update console.licences l set status = 'active',
      valid_until = case when l.valid_until is null and l.status = 'active' then null else greatest(coalesce(l.valid_until, ln.period_to), ln.period_to) end,
      seats = ceil(ln.qty)::int, updated_at = now()
     where l.customer_id = inv.customer_id and l.product_code = ln.product_code;
    -- the features this invoice was for (core ones always); added to what the customer already has
    select coalesce(array_agg(distinct f.key), '{}') into bought
      from console.invoice_lines il join console.app_features f on f.id = il.feature_id
     where il.invoice_id = p_invoice and il.product_code = ln.product_code;
    if array_length(bought, 1) > 0 then
      update console.licences l set features = (
          select coalesce(array_agg(distinct k), '{}') from unnest(
            coalesce(l.features, '{}') || bought || coalesce((select array_agg(key) from console.app_features where product_code = ln.product_code and is_core and active), '{}')) k)
       where l.customer_id = inv.customer_id and l.product_code = ln.product_code;
    end if;
  end loop;
  update console.customers set status = 'active', updated_at = now() where id = inv.customer_id and status in ('lead','pilot');
end $$;
revoke all on function console.apply_paid_invoice(uuid, timestamptz) from public, anon, authenticated;

-- ---------- what the apps ask ----------
-- restricted = false  → the workspace has every feature (no list set)
create or replace function public.kmr_access_features(p_product text)
returns table (org_id uuid, restricted boolean, features text[])
language sql stable security definer set search_path = console, public as $$
  select a.org_id, l.features is not null, coalesce(l.features, '{}')
    from public.kmr_access(p_product) a
    left join console.licences l on l.product_code = p_product and l.product_ref = a.org_id
$$;
revoke all on function public.kmr_access_features(text) from public, anon;
grant execute on function public.kmr_access_features(text) to authenticated;

-- the customer portal: what the company bought
create or replace function public.kmr_portal_features(p_slug text)
returns table (product_code text, restricted boolean, features jsonb)
language plpgsql stable security definer set search_path = console, public as $$
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return; end if;
  return query
    select l.product_code, l.features is not null,
           coalesce((select jsonb_agg(jsonb_build_object('key', f.key, 'name', f.name, 'detail', f.detail) order by f.sort_order, f.name)
                       from console.app_features f
                      where f.product_code = l.product_code and f.active and (l.features is null or f.key = any(l.features))), '[]'::jsonb)
      from console.licences l join console.customers c on c.id = l.customer_id where c.slug = lower(p_slug);
end $$;
revoke all on function public.kmr_portal_features(text) from public, anon;
grant execute on function public.kmr_portal_features(text) to authenticated;

-- ---------- 3. one-time set-up fees (₹ per feature, before GST) — typical Indian SaaS onboarding rates for a small manufacturer ----------
-- only fills fees still at 0, so anything you have already changed is kept
with s(key, fee) as (values
 ('hrm.employee-records-id-cards',15000), ('hrm.attendance-shifts-leave',12000), ('hrm.payroll-statutory-reports',20000), ('hrm.recruitment-onboarding',8000), ('hrm.skill-matrix-training-safety',10000),
 ('balloon.drawing-ballooning',10000), ('balloon.inspection-first-article-reports',8000), ('balloon.cad-formats-dxf-dwg-step',5000), ('balloon.data-flow-to-process-documents',5000),
 ('pd.process-flow-diagram',15000), ('pd.pfmea-aiag-vda-and-4th-edition',20000), ('pd.control-plan-sop',15000), ('pd.setup-patrol-pdi-sheets',10000), ('pd.spc-studies',12000), ('pd.msa-gauge-r-r-studies',10000),
 ('capacity.monthly-plan-machine-loading',20000), ('capacity.takt-time-levelling',8000), ('capacity.alternate-machines-what-if',8000),
 ('sales.monthly-plan-from-operations-master',15000), ('sales.daily-despatch-abc-analysis',8000), ('sales.loss-reasons-action-plans',6000),
 ('calib.instrument-register-qr-labels',15000), ('calib.due-alerts-certificates',6000), ('calib.out-of-tolerance-cases',5000), ('calib.gauge-r-r-msa',8000),
 ('apqp.programmes-five-phases',12000), ('apqp.deliverable-tracker-gate-sign-offs',8000), ('apqp.evidence-from-other-kmr-apps',6000),
 ('ppap.submissions-the-18-elements',12000), ('ppap.part-submission-warrant',8000), ('ppap.evidence-assembly-from-kmr-apps',8000))
update console.app_features f set setup_fee = s.fee from s where f.key = s.key and f.setup_fee = 0;
-- any other feature still without a set-up fee: core ₹10,000, optional ₹5,000
update console.app_features set setup_fee = case when is_core then 10000 else 5000 end where setup_fee = 0;

-- the generic ₹50,000 "implementation" line would now double the per-feature set-up: stop adding it automatically (still in the catalogue)
update console.cost_items set include_by_default = false, detail = 'Extra implementation work beyond the set-up of the chosen features'
 where product_code is null and name = 'Implementation & configuration' and amount = 50000 and include_by_default;

-- ---------- 4. hosting: Vercel (app hosting) + Supabase (database, storage, backups) ----------
-- Shared infrastructure (Vercel Pro + Supabase Pro ≈ ₹4,000 a month) is spread over the customers; these are optional lines on a quotation or invoice
insert into console.cost_items (product_code, name, detail, basis, amount, default_qty, include_by_default, sort_order)
select v.* from (values
  (null::text, 'Cloud hosting & database (Vercel + Supabase)', 'Managed application hosting, database, daily backups, monitoring and security updates for the customer''s workspace', 'per_month', 1500::numeric, 1::numeric, false, 100),
  (null, 'Dedicated database & hosting (own Supabase / Vercel project)', 'The customer''s data in its own database and hosting project, with higher limits and its own backup schedule', 'per_month', 6000, 1, false, 110),
  (null, 'Extra storage (per 10 GB)', 'Additional file / drawing storage beyond the included allowance', 'per_month', 500, 1, false, 120),
  (null, 'Custom domain & SSL', 'The customer''s own web address (e.g. erp.theircompany.com) with SSL certificate', 'per_year', 3000, 1, false, 130)
) v(product_code, name, detail, basis, amount, default_qty, include_by_default, sort_order)
where not exists (select 1 from console.cost_items c where c.name = v.name);
