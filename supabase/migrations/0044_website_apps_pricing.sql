-- =====================================================================
-- 0044 — KMR Apps on the website, managed from KMR Console › Website CMS › Software › KMR Apps on the website,
-- and a starting price list for every app, programme and service. Needs 0021 (website) and 0018 (billing). Safe to re-run.
--
--  • public.app_listings: one row per KMR App — one-line benefit, key features, picture, order, show / hide.
--    New apps added under Products & versions get a row automatically; the website shows every listed app.
--  • kmr_software_catalog() returns those fields with the prices (Console › Billing › Price list stays the place for prices).
--  • Prices (INR, before GST). Only set where no price exists yet — prices already typed in are kept, EXCEPT the
--    old flat placeholders of ₹1,00,000 and above per user / employee, which are replaced.
--  • Training programmes and software services get "from" prices (still enquiry-based) where they show "price on request".
-- =====================================================================
do $$ begin
  if to_regclass('console.prices') is null then raise exception 'Run 0018_billing.sql first.'; end if;
  if to_regprocedure('public.kmr_software_catalog()') is null then raise exception 'Run 0021_website.sql first.'; end if;
end $$;

create table if not exists public.app_listings (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique references console.products(code) on delete cascade,
  name        text not null default '',
  tagline     text check (length(tagline) <= 200),
  features    text check (length(features) <= 1500),   -- one feature per line
  image_url   text,
  sort_order  integer not null default 100,
  is_active   boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table public.app_listings enable row level security;
drop policy if exists app_listings_read on public.app_listings;
create policy app_listings_read on public.app_listings for select to anon, authenticated using (is_active);
grant select on public.app_listings to anon, authenticated;

-- every product gets a listing (now and whenever a new app is added)
create or replace function console.app_listing_sync() returns trigger language plpgsql security definer set search_path = console, public as $$
begin
  insert into public.app_listings (code, name, sort_order, is_active)
  values (new.code, new.name, coalesce(new.sort_order, 100), new.code <> 'console')
  on conflict (code) do update set name = excluded.name;
  return new;
end $$;
drop trigger if exists products_listing on console.products;
create trigger products_listing after insert or update of name on console.products for each row execute function console.app_listing_sync();

insert into public.app_listings (code, name, tagline, features, sort_order, is_active)
select p.code, p.name, d.tagline, d.features, p.sort_order, p.code <> 'console'
  from console.products p
  left join (values
    ('hrm', 'Hire, onboard, track attendance and pay your people — with IATF-ready HR records.',
     E'Self-onboarding with documents, selfie and digital ID card\nBiometric attendance, shifts, leave and payroll\nRecruitment, skill matrix, training and safety records'),
    ('balloon', 'Balloon any drawing in minutes and build the inspection report automatically.',
     E'Reads PDF, DXF, DWG and STEP drawings\nNumbered balloons and characteristic table with SC / CC\nFirst-article and inspection reports; data flows to Process Documents'),
    ('pd', 'Turn a ballooned drawing into the full APQP / PPAP document set.',
     E'Process flow, PFMEA (AIAG-VDA) and control plan\nSetup, patrol and self-inspection sheets, PDI, SOP\nSPC and MSA studies, CNC set-up sheets'),
    ('capacity', 'See machine loading, takt time and bottlenecks for every month before they hit delivery.',
     E'Monthly plan and machine loading with alternates\nTakt time and levelling\nUses your Operations Master and the HRM holiday calendar'),
    ('sales', 'Plan every part every month and see despatch against plan, day by day.',
     E'Monthly plan from your Operations Master parts and rate contracts\nDaily despatch, pending and ABC analysis\nLoss reasons and action plans with owners and dates'),
    ('calib', 'Never miss a calibration — every gauge, its history and its MSA in one place.',
     E'Instrument register with QR labels and gauge history\nDue alerts, calibration certificates and out-of-tolerance cases\nGauge R&R (MSA) linked to your control plans')
  ) d(code, tagline, features) on d.code = p.code
on conflict (code) do update set name = excluded.name,
  tagline  = coalesce(public.app_listings.tagline, excluded.tagline),     -- never overwrite what was typed in the CMS
  features = coalesce(public.app_listings.features, excluded.features);

-- ---------- the catalogue the website reads ----------
create or replace function public.kmr_software_catalog() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'description', p.description, 'app_path', p.app_path,
           'seat_label', p.seat_label, 'version', p.current_version,
           'tagline', l.tagline, 'image_url', nullif(l.image_url, ''), 'listed', coalesce(l.is_active, true),
           'features', case when coalesce(l.features, '') = '' then null
                            else (select jsonb_agg(trim(f)) from unnest(string_to_array(l.features, E'\n')) f where trim(f) <> '') end,
           'prices', coalesce((select jsonb_agg(jsonb_build_object('period', x.period, 'amount', x.unit_amount, 'min', x.min_seats) order by x.period)
                                from console.prices x where x.product_code = p.code and x.active and x.currency = 'INR'), '[]'))
         order by coalesce(l.sort_order, p.sort_order), p.sort_order), '[]')
    from console.products p left join public.app_listings l on l.code = p.code
   where p.active
$$;
grant execute on function public.kmr_software_catalog() to anon, authenticated;

-- ---------- price list (INR, before GST; yearly = 10 × monthly, i.e. two months free) ----------
-- per employee (HRM) or per user (other apps); minimum seats keep small orders sensible
with plan(code, month, min_seats) as (values
  ('hrm', 60, 25), ('balloon', 1500, 1), ('pd', 2500, 1), ('capacity', 1500, 1), ('sales', 800, 2), ('calib', 1000, 1)
), want as (
  select code, 'month'::text period, month::numeric amount, min_seats from plan
  union all select code, 'year', month * 10, min_seats from plan
)
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select w.code, w.period, 'INR', w.amount, w.min_seats, true, 'Starting price list (0044) — change in Console › Billing'
  from want w join console.products p on p.code = w.code
on conflict (product_code, period, currency) do update
  set unit_amount = excluded.unit_amount, min_seats = excluded.min_seats, active = true, note = excluded.note, updated_at = now()
  where console.prices.unit_amount >= 100000          -- replace only the old flat placeholders; real prices stay
     or console.prices.unit_amount = 0;

-- ---------- training programmes and software services: "from" prices, still enquiry-based ----------
do $$ begin
  if to_regclass('public.products') is null then return; end if;
  update public.products p set price = v.price, unit = v.unit
    from (values
      ('IATF 16949:2016 Awareness & Internal Auditor', 6500, 'participant'),
      ('Core Tools: APQP, PPAP, FMEA, SPC & MSA', 7500, 'participant'),
      ('Problem Solving with 8D & Root Cause Analysis', 3500, 'participant'),
      ('Manufacturing Excellence for Supervisors', 3000, 'participant'),
      ('Custom business software', 75000, 'project'),
      ('IT consulting for MSMEs', 15000, 'day'),
      ('Business website & online store set-up', 25000, 'project')
    ) v(name, price, unit)
   where p.name = v.name and coalesce(p.price, 0) = 0;
end $$;
