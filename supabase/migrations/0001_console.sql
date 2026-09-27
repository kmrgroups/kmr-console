-- =====================================================================
-- KMR Console — the back office for KMR's software products.
-- Schema "console": KMR staff, customers, products, licences, releases.
-- Only KMR staff (console.staff) can read or change anything here; the products
-- themselves read their licence through console.licence_status() with the service key.
-- =====================================================================
create schema if not exists console;
grant usage on schema console to authenticated, service_role;
alter default privileges in schema console grant all on tables to authenticated, service_role;
alter default privileges in schema console grant all on sequences to authenticated, service_role;
alter default privileges in schema console grant execute on functions to authenticated, service_role;

-- ---------------------------------------------------------------------
-- KMR staff who can use the Console
-- ---------------------------------------------------------------------
create table console.staff (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  email       text not null,
  role        text not null default 'support' check (role in ('owner','admin','sales','support')),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create or replace function console.staff_role() returns text
language sql stable security definer set search_path = console, public as $$
  select role from console.staff where user_id = auth.uid() and active
$$;
create or replace function console.is_staff() returns boolean
language sql stable as $$ select console.staff_role() is not null $$;
create or replace function console.is_manager() returns boolean
language sql stable as $$ select console.staff_role() in ('owner','admin') $$;

-- ---------------------------------------------------------------------
-- Products KMR sells
-- ---------------------------------------------------------------------
create table console.products (
  code             text primary key check (code ~ '^[a-z][a-z0-9-]{1,20}$'),
  name             text not null,
  description      text,
  app_path         text,                                  -- where customers open it, e.g. /it/hrm
  seat_label       text not null default 'users',         -- what the licence limit counts
  current_version  text,
  active           boolean not null default true,
  sort_order       integer not null default 100
);
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('hrm',     'HRM Suite',          'Employees, onboarding, ID cards, attendance and leave', '/it/hrm',          'employees', '2.0.0', 10),
  ('balloon', 'Balloon Inspector',  'Ballooned drawings and inspection reports',             '/it/balloon.html', 'users',     '1.0.0', 20),
  ('pd',      'Process Documents',  'PFD, PFMEA, Control Plan, SOP, SPC, MSA and reports',   '/it/pd.html',      'users',     '1.0.0', 30)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- Customers (companies that use KMR products)
-- ---------------------------------------------------------------------
create sequence console.customer_no;
create table console.customers (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique default ('C' || lpad(nextval('console.customer_no')::text, 4, '0')),
  name           text not null check (length(name) between 2 and 120),
  legal_name     text,
  country        text not null default 'IN' check (country ~ '^[A-Z]{2}$'),
  currency       text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  tax_id         text,                                   -- GSTIN in India, VAT / EIN elsewhere
  address        text,
  city           text,
  state          text,
  postal_code    text,
  time_zone      text not null default 'Asia/Kolkata',
  contact_name   text,
  contact_email  text,
  contact_phone  text,
  status         text not null default 'lead' check (status in ('lead','pilot','active','inactive')),
  source         text,                                   -- website form, referral, exhibition …
  notes          text,
  created_by     uuid references auth.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on console.customers (status);
create index on console.customers (lower(name));

-- ---------------------------------------------------------------------
-- Licences: which customer may use which product, until when, for how many
-- ---------------------------------------------------------------------
create table console.licences (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references console.customers(id) on delete cascade,
  product_code  text not null references console.products(code),
  status        text not null default 'trial' check (status in ('trial','pilot','active','suspended','expired','cancelled')),
  starts_on     date not null default current_date,
  valid_until   date,                                    -- null = no end date
  seats         integer check (seats is null or seats > 0),   -- employees (HRM) or users; null = unlimited
  product_ref   uuid,                                    -- the customer's company inside the product (HRM tenant id …)
  product_slug  text,                                    -- its short name there
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (customer_id, product_code),
  unique (product_code, product_ref),
  check (valid_until is null or valid_until >= starts_on)
);
create index on console.licences (product_code, status);

-- Every change to a licence is kept
create table console.licence_events (
  id           bigserial primary key,
  licence_id   uuid not null references console.licences(id) on delete cascade,
  action       text not null,
  detail       jsonb,
  actor_id     uuid,
  created_at   timestamptz not null default now()
);
create index on console.licence_events (licence_id, created_at desc);

create or replace function console.log_licence() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if tg_op = 'INSERT' then
    insert into console.licence_events (licence_id, action, detail, actor_id)
    values (new.id, 'created', jsonb_build_object('status', new.status, 'valid_until', new.valid_until, 'seats', new.seats), auth.uid());
  elsif (new.status, new.valid_until, new.seats) is distinct from (old.status, old.valid_until, old.seats) then
    insert into console.licence_events (licence_id, action, detail, actor_id)
    values (new.id, 'changed', jsonb_build_object(
      'status', jsonb_build_array(old.status, new.status),
      'valid_until', jsonb_build_array(old.valid_until, new.valid_until),
      'seats', jsonb_build_array(old.seats, new.seats)), auth.uid());
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger licences_log_insert after insert on console.licences for each row execute function console.log_licence();
create trigger licences_log_update before update on console.licences for each row execute function console.log_licence();

-- ---------------------------------------------------------------------
-- Releases (version history per product)
-- ---------------------------------------------------------------------
create table console.releases (
  id            uuid primary key default gen_random_uuid(),
  product_code  text not null references console.products(code),
  version       text not null check (version ~ '^\d+\.\d+\.\d+$'),
  released_on   date not null default current_date,
  notes         text,
  created_at    timestamptz not null default now(),
  unique (product_code, version)
);
insert into console.releases (product_code, version, notes) values
  ('hrm', '2.0.0', 'Attendance (biometric devices, shifts), leave, approvals; runs on the KMR platform with Console licences'),
  ('balloon', '1.0.0', 'Balloon Inspector — first release'),
  ('pd', '1.0.0', 'Process Documents — first release, with Fanuc CNC program generator')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Functions used by the products (service key only)
-- ---------------------------------------------------------------------
create or replace function console.licence_status(p_product text, p_ref uuid)
returns table (status text, valid_until date, seats integer)
language sql stable security definer set search_path = console, public as $$
  select l.status, l.valid_until, l.seats from console.licences l
   where l.product_code = p_product and l.product_ref = p_ref
$$;
create or replace function console.user_id_by_email(p_email text) returns uuid
language sql stable security definer set search_path = auth, public as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1
$$;
revoke all on function console.licence_status(text, uuid) from public, anon, authenticated;
revoke all on function console.user_id_by_email(text) from public, anon, authenticated;
grant execute on function console.licence_status(text, uuid) to service_role;
grant execute on function console.user_id_by_email(text) to service_role;

-- ---------------------------------------------------------------------
-- Row-level security: KMR staff only
-- ---------------------------------------------------------------------
alter table console.staff          enable row level security;
alter table console.products       enable row level security;
alter table console.customers      enable row level security;
alter table console.licences       enable row level security;
alter table console.licence_events enable row level security;
alter table console.releases       enable row level security;

create policy staff_read   on console.staff for select to authenticated using (console.is_staff());
create policy staff_owner  on console.staff for all to authenticated using (console.staff_role() = 'owner') with check (console.staff_role() = 'owner');

do $$
declare t text;
begin
  foreach t in array array['products','customers','licences','licence_events','releases'] loop
    execute format('create policy %I on console.%I for select to authenticated using (console.is_staff())', t || '_read', t);
  end loop;
  -- sales and support may add / edit customers; owners and admins manage licences, products and releases
  execute 'create policy customers_write on console.customers for all to authenticated using (console.is_staff()) with check (console.is_staff())';
  foreach t in array array['products','licences','releases'] loop
    execute format('create policy %I on console.%I for all to authenticated using (console.is_manager()) with check (console.is_manager())', t || '_write', t);
  end loop;
end $$;
revoke all on all tables in schema console from anon;
