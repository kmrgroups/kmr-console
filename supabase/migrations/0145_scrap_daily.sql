-- Applied via the Supabase connector 2026-11-17. Daily internal scrap records (Esbee INTERNAL REJECTION 2026 sheets).
create table if not exists console.scrap_daily(
  id bigint generated always as identity primary key, customer_id uuid not null, source_file text not null, part_label text not null,
  part_cell text, part_desc text, scrap_date date not null, section text, defect text not null, qty numeric not null check (qty >= 0),
  created_at timestamptz not null default now(), customer_name text);
create index if not exists scrap_daily_cust_date on console.scrap_daily(customer_id, scrap_date);
create index if not exists scrap_daily_cust_part on console.scrap_daily(customer_id, part_label);
alter table console.scrap_daily enable row level security;
