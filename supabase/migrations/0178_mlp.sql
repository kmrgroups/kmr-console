-- KMR 0178 — Machine loading plan (mlp): back-schedules the Production plan from the customer due date to the first operation, throughput time, machine load by week.
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('mlp', 'Machine loading plan', 'Works back from the customer due date to the first operation using cycle times, shows throughput time and the load on every machine day by day', '/it/mlp.html', 'users', '1.0.0', 177)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;
insert into console.releases (product_code, version, notes) values ('mlp', '1.0.0', 'Machine loading plan: back-scheduling, throughput time, machine load by week, publish') on conflict do nothing;
insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0178) — change in Console • Billing' from (values ('mlp', 'month', 1500), ('mlp', 'year', 15000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;
insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('mlp', 'Machine loading plan', 'See when every operation must start so the customer due date is met, how long each part takes through the plant, and which machines are overloaded.',
   E'Due date worked back to the first operation from cycle times\nThroughput time per part on the dashboard\nMachine load by week against available hours\nPublished plan feeds Capacity, manpower, overtime and budget plans', 177, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('mlp', 'Back-scheduling and machine load', 'Start and finish of every operation, throughput time, weekly machine load', true, 1500, 0, 3000, 10) on conflict (product_code, name) do nothing;
create table if not exists console.mlp_plan (id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade, month text not null, version int not null,
  rows jsonb not null default '[]', summary jsonb not null default '{}', published_by text, published_at timestamptz not null default now(), unique (customer_id, month, version));
alter table console.mlp_plan enable row level security;
drop policy if exists mlp_plan_staff on console.mlp_plan;
create policy mlp_plan_staff on console.mlp_plan for all to authenticated using (console.is_staff()) with check (console.is_staff());
-- functions kmr_mlp_context / kmr_mlp_data / kmr_mlp_save / kmr_mlp_publish / kmr_mlp_latest and the portal / year-backup patch: as applied (see database).
-- kmr_mlp_data returns console.ppl_data plus 'mlast' (last published version) and 'today'; kmr_mlp_save keeps hpd, eff, days, wait (days between processes), supd (supplier lead days) in console.ppl_cfg.
