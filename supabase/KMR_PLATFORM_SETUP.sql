-- =====================================================================
-- KMR PLATFORM SETUP — run ONCE in the KMR Supabase project (dehlcusptkzfhqvpfyjh).
-- Adds two new sections next to the website's and the quality tools' tables:
--   console  KMR Console: staff, customers, products, licences, releases
--            + licences for Balloon Inspector / Process Documents (existing workspaces adopted as pilots)
--   hrm      HRM Suite for all customer companies
-- Nothing existing is changed or deleted (website tables, bi_* and pd_* tool tables, the "media" bucket).
--
-- BEFORE RUNNING
--   1. Take a backup: Database -> Backups (or Project Settings -> Database -> download a backup).
--   2. Set YOUR KMR CONSOLE OWNER below to your existing login email (e.g. the website admin login).
--   3. SQL Editor -> New query -> paste this whole file -> Run.  It ends with: KMR PLATFORM READY
-- AFTER RUNNING
--   4. Project Settings -> Data API -> Exposed schemas: add  hrm  and  console  -> Save.
-- =====================================================================

-- ------------------- YOUR KMR CONSOLE OWNER --------------------------
create temp table kmr_setup as select
  'info@kmr-groups.com'   ::text as owner_email,   -- an EXISTING login (Authentication -> Users)
  'Rajavelu R'            ::text as owner_name;
-- ---------------------------------------------------------------------

do $$
declare s record;
begin
  select * into s from kmr_setup;
  if to_regclass('console.staff') is not null or to_regclass('hrm.tenants') is not null then
    raise exception 'The KMR platform is already set up in this project. Nothing was changed.';
  end if;
  if not exists (select 1 from auth.users where lower(email) = lower(s.owner_email)) then
    raise exception 'No login found for %. Put an existing login email in owner_email (Authentication -> Users), then run again.', s.owner_email;
  end if;
end $$;

-- =====================================================================
-- migrations/0001_console.sql
-- =====================================================================
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


-- =====================================================================
-- products/hrm/0001_foundation.sql
-- =====================================================================
-- The HRM lives in its own schema "hrm" so it can share one Supabase project with other
-- KMR products (and the KMR website) without any table-name clashes.
create schema if not exists hrm;
grant usage on schema hrm to anon, authenticated, service_role;
alter default privileges in schema hrm grant all on tables to anon, authenticated, service_role;
alter default privileges in schema hrm grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema hrm grant execute on functions to anon, authenticated, service_role;

-- =====================================================================
-- HRM Suite — Phase 1: Foundation + Core HR
-- Multi-tenant schema with row-level security on every tenant table.
-- Run in the Supabase SQL editor (or `supabase db push`).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tenants (companies) and their domains
-- ---------------------------------------------------------------------
create table hrm.tenants (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,40}$'),
  name            text not null,                 -- short display name
  legal_name      text,
  logo_path       text,                          -- path in the public "branding" bucket
  primary_color   text not null default '#1F3A5F',
  accent_color    text not null default '#E07A1F',
  address         text,
  phone           text,
  email           text,
  website         text,
  emp_code_prefix text not null default 'EMP',
  emp_code_seq    integer not null default 0,
  settings        jsonb not null default '{}'::jsonb,   -- email_from, whatsapp numbers, id card options...
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);

create table hrm.tenant_domains (
  domain      text primary key check (domain = lower(domain)),
  tenant_id   uuid not null references hrm.tenants(id) on delete cascade,
  is_primary  boolean not null default false,
  verified    boolean not null default false,
  created_at  timestamptz not null default now()
);
create index on hrm.tenant_domains(tenant_id);

-- ---------------------------------------------------------------------
-- Organisation masters
-- ---------------------------------------------------------------------
create table hrm.plants (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references hrm.tenants(id) on delete cascade,
  code       text not null,
  name       text not null,
  address    text,
  state      text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table hrm.departments (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references hrm.tenants(id) on delete cascade,
  name       text not null,
  code       text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create table hrm.designations (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references hrm.tenants(id) on delete cascade,
  name       text not null,
  grade      text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, name)
);

-- ---------------------------------------------------------------------
-- Users (one row per Supabase auth user) and roles
-- ---------------------------------------------------------------------
create table hrm.app_users (
  id                   uuid primary key references auth.users(id) on delete cascade,
  tenant_id            uuid not null references hrm.tenants(id) on delete cascade,
  role                 text not null check (role in (
                         'platform_admin','company_admin','hr_manager','hr_executive',
                         'payroll','manager','interviewer','employee')),
  full_name            text not null,
  email                text not null,
  phone                text,
  employee_id          uuid,                     -- FK added after employees table
  must_change_password boolean not null default false,
  active               boolean not null default true,
  created_at           timestamptz not null default now()
);
create index on hrm.app_users(tenant_id);

-- ---------------------------------------------------------------------
-- Employees
-- ---------------------------------------------------------------------
create table hrm.employees (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references hrm.tenants(id) on delete cascade,
  employee_code           text,
  status                  text not null default 'invited' check (status in (
                            'invited','onboarding','submitted','sent_back','active','inactive','exited')),
  first_name              text not null,
  last_name               text,
  email                   text,
  mobile                  text,
  plant_id                uuid references hrm.plants(id),
  department_id           uuid references hrm.departments(id),
  designation_id          uuid references hrm.designations(id),
  reporting_manager_id    uuid references hrm.employees(id),
  employment_type         text not null default 'permanent' check (employment_type in (
                            'permanent','probation','fixed_term','trainee','apprentice','contract')),
  category                text not null default 'staff' check (category in ('staff','workman','management')),
  date_of_joining         date,
  date_of_birth           date,
  gender                  text,
  blood_group             text check (blood_group is null or blood_group in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  photo_path              text,                  -- selfie in the private employee-docs bucket
  emergency_contact_name  text,
  emergency_contact_phone text,
  profile                 jsonb not null default '{}'::jsonb,   -- onboarding sections (personal, family, academic, professional)
  verify_token            text not null unique default encode(gen_random_bytes(16), 'hex'),  -- used by the ID card QR
  created_by              uuid references auth.users(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (tenant_id, employee_code)
);
create index on hrm.employees(tenant_id, status);

alter table hrm.app_users
  add constraint app_users_employee_fk foreign key (employee_id) references hrm.employees(id) on delete set null;

-- Statutory and bank details are kept apart so that managers who can see
-- an employee's profile cannot see these fields.
create table hrm.employee_private (
  employee_id     uuid primary key references hrm.employees(id) on delete cascade,
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  pan             text,
  aadhaar_last4   text check (aadhaar_last4 is null or aadhaar_last4 ~ '^[0-9]{4}$'),  -- full Aadhaar is never stored
  uan             text,
  previous_pf_no  text,
  esi_ip_no       text,
  bank_name       text,
  bank_branch     text,
  account_holder  text,
  account_number  text,
  ifsc            text,
  tax_regime      text check (tax_regime is null or tax_regime in ('new','old')),
  updated_at      timestamptz not null default now()
);

create table hrm.onboarding_invites (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  employee_id         uuid not null references hrm.employees(id) on delete cascade,
  token_hash          text not null unique,      -- sha256 of the link token; the raw token is only in the link
  status              text not null default 'sent' check (status in (
                        'sent','in_progress','submitted','sent_back','approved','expired','revoked')),
  current_step        integer not null default 0,
  sent_back_sections  text[] not null default '{}',
  hr_comment          text,
  consent_at          timestamptz,
  consent_ip          text,
  reminders_sent      integer not null default 0,
  last_reminder_at    timestamptz,
  expires_at          timestamptz not null default now() + interval '7 days',
  submitted_at        timestamptz,
  reviewed_at         timestamptz,
  reviewed_by         uuid references auth.users(id),
  created_by          uuid references auth.users(id),
  created_at          timestamptz not null default now()
);
create index on hrm.onboarding_invites(tenant_id, status);
create index on hrm.onboarding_invites(employee_id);

create table hrm.employee_documents (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  employee_id  uuid not null references hrm.employees(id) on delete cascade,
  doc_type     text not null,                    -- aadhaar, pan, cheque, qualification, relieving, payslip, experience, photo, selfie, other
  file_path    text not null,                    -- employee-docs/<tenant>/<employee>/<uuid>.<ext>
  file_name    text,
  mime_type    text,
  size_bytes   integer,
  status       text not null default 'uploaded' check (status in ('uploaded','approved','rejected')),
  comment      text,
  uploaded_at  timestamptz not null default now()
);
create index on hrm.employee_documents(employee_id);

create table hrm.id_cards (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  employee_id  uuid not null references hrm.employees(id) on delete cascade,
  version      integer not null default 1,
  status       text not null default 'active' check (status in ('active','replaced','revoked')),
  issued_at    timestamptz not null default now(),
  valid_until  date,
  issued_by    uuid references auth.users(id),
  reason       text                               -- new, lost, damaged, data change
);
create index on hrm.id_cards(employee_id);

-- ---------------------------------------------------------------------
-- Passkeys (Face ID / fingerprint / Windows Hello login)
-- ---------------------------------------------------------------------
create table hrm.passkeys (
  id            text primary key,                 -- base64url credential id
  user_id       uuid not null references auth.users(id) on delete cascade,
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  public_key    text not null,                    -- base64url COSE public key
  counter       bigint not null default 0,
  transports    text[] not null default '{}',
  device_name   text,
  backed_up     boolean not null default false,
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);
create index on hrm.passkeys(user_id);

-- ---------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------
create table hrm.notification_templates (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  event           text not null,
  channel         text not null check (channel in ('email','whatsapp')),
  subject         text,
  body            text not null,
  wa_template     text,                           -- approved Meta template name
  wa_language     text default 'en',
  wa_params       text[] not null default '{}',   -- variable names mapped to {{1}}, {{2}}...
  active          boolean not null default true,
  updated_at      timestamptz not null default now(),
  unique (tenant_id, event, channel)
);

create table hrm.notifications (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  event         text not null,
  channel       text not null check (channel in ('email','whatsapp','sms')),
  recipient     text not null,
  subject       text,
  body          text,
  status        text not null default 'queued' check (status in ('queued','sent','delivered','read','failed','skipped')),
  provider_id   text,
  error         text,
  related_type  text,
  related_id    uuid,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);
create index on hrm.notifications(tenant_id, created_at desc);
create index on hrm.notifications(provider_id);

-- ---------------------------------------------------------------------
-- Audit log (append-only)
-- ---------------------------------------------------------------------
create table hrm.audit_log (
  id          bigserial primary key,
  tenant_id   uuid references hrm.tenants(id) on delete cascade,
  actor_id    uuid,
  action      text not null,                     -- insert / update / delete / semantic e.g. onboarding.approved
  entity      text not null,
  entity_id   text,
  old_data    jsonb,
  new_data    jsonb,
  created_at  timestamptz not null default now()
);
create index on hrm.audit_log(tenant_id, created_at desc);
create index on hrm.audit_log(entity, entity_id);

-- =====================================================================
-- Helper functions
-- =====================================================================

-- Tenant of the signed-in user (null for anonymous / service role)
create or replace function hrm.current_tenant_id() returns uuid
language sql stable security definer set search_path = hrm, public as $$
  select tenant_id from hrm.app_users where id = auth.uid() and active
$$;

create or replace function hrm.current_role_name() returns text
language sql stable security definer set search_path = hrm, public as $$
  select role from hrm.app_users where id = auth.uid() and active
$$;

create or replace function hrm.current_employee_id() returns uuid
language sql stable security definer set search_path = hrm, public as $$
  select employee_id from hrm.app_users where id = auth.uid() and active
$$;

-- True when the signed-in user holds any of the given roles.
-- company_admin and platform_admin pass every HR check.
create or replace function hrm.has_role(variadic roles text[]) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (
    select 1 from hrm.app_users
    where id = auth.uid() and active
      and (role = any(roles) or role in ('company_admin','platform_admin'))
  )
$$;

create or replace function hrm.is_hr() returns boolean
language sql stable as $$ select hrm.has_role('hr_manager','hr_executive') $$;

-- Employees in the signed-in manager's reporting line (direct + indirect)
create or replace function hrm.is_in_my_team(emp uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  with recursive team as (
    select id from hrm.employees where reporting_manager_id = hrm.current_employee_id()
    union
    select e.id from hrm.employees e join team t on e.reporting_manager_id = t.id
  )
  select exists (select 1 from team where id = emp)
$$;

-- Atomically allocate the next employee code, e.g. DEN-PL1-0042
create or replace function hrm.next_employee_code(p_tenant uuid, p_plant uuid default null) returns text
language plpgsql security definer set search_path = hrm, public as $$
declare
  v_prefix text;
  v_seq    integer;
  v_plant  text;
begin
  update hrm.tenants set emp_code_seq = emp_code_seq + 1
   where id = p_tenant
   returning emp_code_prefix, emp_code_seq into v_prefix, v_seq;
  if v_seq is null then
    raise exception 'tenant % not found', p_tenant;
  end if;
  if p_plant is not null then
    select code into v_plant from hrm.plants where id = p_plant and tenant_id = p_tenant;
  end if;
  return v_prefix || coalesce('-' || v_plant, '') || '-' || lpad(v_seq::text, 4, '0');
end $$;

-- Generic audit trigger
create or replace function hrm.audit_row() returns trigger
language plpgsql security definer set search_path = hrm, public as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
begin
  if tg_op = 'UPDATE' and v_old = v_new then
    return new;
  end if;
  insert into hrm.audit_log(tenant_id, actor_id, action, entity, entity_id, old_data, new_data)
  values (
    case when tg_table_name = 'tenants' then (v_row->>'id')::uuid else (v_row->>'tenant_id')::uuid end,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    coalesce(v_row->>'id', v_row->>'employee_id'),
    v_old,
    v_new
  );
  return coalesce(new, old);
end $$;

create or replace function hrm.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

create trigger employees_touch before update on hrm.employees
  for each row execute function hrm.touch_updated_at();
create trigger employee_private_touch before update on hrm.employee_private
  for each row execute function hrm.touch_updated_at();

do $$
declare t text;
begin
  foreach t in array array['tenants','tenant_domains','plants','departments','designations','app_users',
                           'employees','employee_private','onboarding_invites','employee_documents','id_cards',
                           'notification_templates']
  loop
    execute format('create trigger %I after insert or update or delete on hrm.%I
                    for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- Default masters for a new tenant
create or replace function hrm.seed_tenant_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $$
begin
  insert into hrm.departments(tenant_id, name, code) values
    (p_tenant,'Production','PRD'),(p_tenant,'Quality','QA'),(p_tenant,'Maintenance','MNT'),
    (p_tenant,'Stores','STR'),(p_tenant,'Production Planning & Control','PPC'),
    (p_tenant,'Human Resources','HR'),(p_tenant,'Accounts & Finance','FIN'),
    (p_tenant,'Purchase','PUR'),(p_tenant,'Engineering','ENG'),(p_tenant,'EHS','EHS')
  on conflict do nothing;
  insert into hrm.designations(tenant_id, name, grade) values
    (p_tenant,'Operator','W1'),(p_tenant,'Senior Operator','W2'),(p_tenant,'Technician','W3'),
    (p_tenant,'Supervisor','S1'),(p_tenant,'Engineer','S2'),(p_tenant,'Senior Engineer','S3'),
    (p_tenant,'Assistant Manager','M1'),(p_tenant,'Manager','M2'),(p_tenant,'Senior Manager','M3'),
    (p_tenant,'Head of Department','M4')
  on conflict do nothing;
end $$;

-- =====================================================================
-- Row-level security
-- =====================================================================
alter table hrm.tenants                enable row level security;
alter table hrm.tenant_domains         enable row level security;
alter table hrm.plants                 enable row level security;
alter table hrm.departments            enable row level security;
alter table hrm.designations           enable row level security;
alter table hrm.app_users              enable row level security;
alter table hrm.employees              enable row level security;
alter table hrm.employee_private       enable row level security;
alter table hrm.onboarding_invites     enable row level security;
alter table hrm.employee_documents     enable row level security;
alter table hrm.id_cards               enable row level security;
alter table hrm.passkeys               enable row level security;
alter table hrm.notification_templates enable row level security;
alter table hrm.notifications          enable row level security;
alter table hrm.audit_log              enable row level security;

-- Tenants: members read their own company; company admins edit branding.
create policy tenants_read on hrm.tenants for select to authenticated
  using (id = hrm.current_tenant_id());
create policy tenants_update on hrm.tenants for update to authenticated
  using (id = hrm.current_tenant_id() and hrm.has_role('company_admin'))
  with check (id = hrm.current_tenant_id());

create policy domains_read on hrm.tenant_domains for select to authenticated
  using (tenant_id = hrm.current_tenant_id());

-- Masters: everyone in the tenant reads; HR writes.
do $$
declare t text;
begin
  foreach t in array array['plants','departments','designations'] loop
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id())', t || '_read', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_write', t);
  end loop;
end $$;

-- Users: everyone sees their own row; HR sees all users of the tenant; company admin manages.
create policy app_users_self on hrm.app_users for select to authenticated
  using (id = auth.uid());
create policy app_users_hr_read on hrm.app_users for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
create policy app_users_admin_write on hrm.app_users for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('company_admin'))
  with check (tenant_id = hrm.current_tenant_id());

-- Employees: HR full access; managers read their team; employees read themselves.
create policy employees_hr on hrm.employees for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
create policy employees_self on hrm.employees for select to authenticated
  using (id = hrm.current_employee_id());
create policy employees_team on hrm.employees for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(id));
create policy employees_payroll on hrm.employees for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll'));

-- Private (bank / statutory): HR and payroll, plus the employee themselves (read only).
create policy private_hr on hrm.employee_private for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('hr_manager','hr_executive','payroll'))
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('hr_manager','hr_executive','payroll'));
create policy private_self on hrm.employee_private for select to authenticated
  using (employee_id = hrm.current_employee_id());

create policy invites_hr on hrm.onboarding_invites for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());

create policy docs_hr on hrm.employee_documents for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
create policy docs_self on hrm.employee_documents for select to authenticated
  using (employee_id = hrm.current_employee_id());

create policy id_cards_hr on hrm.id_cards for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
create policy id_cards_self on hrm.id_cards for select to authenticated
  using (employee_id = hrm.current_employee_id());

create policy passkeys_self_read on hrm.passkeys for select to authenticated
  using (user_id = auth.uid());
create policy passkeys_self_delete on hrm.passkeys for delete to authenticated
  using (user_id = auth.uid());

create policy templates_read on hrm.notification_templates for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
create policy templates_write on hrm.notification_templates for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('hr_manager'))
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('hr_manager'));

create policy notifications_hr on hrm.notifications for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());

create policy audit_admin on hrm.audit_log for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('hr_manager'));

-- =====================================================================
-- Storage buckets
--   branding       public  — logos shown on login page, emails and ID cards
--   employee-docs  private — Aadhaar, PAN, cheques, certificates, selfies.
--                            No client policies: the app issues short-lived
--                            signed URLs only after checking the user's role.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('hrm-branding', 'hrm-branding', true, 2097152, array['image/png','image/jpeg','image/webp','image/svg+xml']),
  ('hrm-docs', 'hrm-docs', false, 10485760, array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict (id) do nothing;


-- =====================================================================
-- products/hrm/0002_attendance_leave.sql
-- =====================================================================
-- =====================================================================
-- HRM Suite — Phase 2: Attendance + Leave
-- Run after 0001_foundation.sql (Supabase SQL editor or `supabase db push`).
-- Safe to run once on a database that already holds Phase 1 data.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Shifts and holidays
-- ---------------------------------------------------------------------
create table hrm.shifts (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references hrm.tenants(id) on delete cascade,
  code               text not null,                  -- G, A, B, C ...
  name               text not null,
  start_time         time not null,
  end_time           time not null,                  -- earlier than start_time = ends next day (night shift)
  break_minutes      integer not null default 30 check (break_minutes between 0 and 240),
  grace_in_minutes   integer not null default 10 check (grace_in_minutes between 0 and 120),
  grace_out_minutes  integer not null default 10 check (grace_out_minutes between 0 and 120),
  half_day_minutes   integer not null default 240 check (half_day_minutes between 60 and 900),
  full_day_minutes   integer not null default 450 check (full_day_minutes between 60 and 1200),
  active             boolean not null default true,
  created_at         timestamptz not null default now(),
  unique (tenant_id, code),
  check (half_day_minutes < full_day_minutes)
);

create table hrm.holidays (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  plant_id      uuid references hrm.plants(id) on delete cascade,   -- null = every plant
  holiday_date  date not null,
  name          text not null,
  created_at    timestamptz not null default now(),
  unique nulls not distinct (tenant_id, plant_id, holiday_date)
);
create index on hrm.holidays(tenant_id, holiday_date);

-- Attendance settings on the employee record
alter table hrm.employees
  add column shift_id      uuid references hrm.shifts(id) on delete set null,   -- null = detect from the first punch
  add column weekly_offs   smallint[] not null default '{0}',                      -- 0 = Sunday ... 6 = Saturday
  add column attendance_id text;                                                   -- user / enrol number on the biometric device
alter table hrm.employees
  add constraint employees_attendance_id_unique unique (tenant_id, attendance_id),
  add constraint employees_weekly_offs_valid check (weekly_offs <@ array[0,1,2,3,4,5,6]::smallint[]);

-- ---------------------------------------------------------------------
-- Biometric devices and raw punches
-- ---------------------------------------------------------------------
create table hrm.attendance_devices (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  plant_id      uuid references hrm.plants(id) on delete set null,
  name          text not null,
  kind          text not null default 'api' check (kind in ('api','adms')),
  serial_no     text unique,                     -- ADMS (eSSL / ZKTeco push) devices identify themselves by serial
  key_hash      text unique,                     -- sha256 of the API key; the key itself is shown once
  last_seen_at  timestamptz,
  last_ip       text,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  check (kind <> 'adms' or serial_no is not null),
  check (kind <> 'api' or key_hash is not null)
);
create index on hrm.attendance_devices(tenant_id);

create table hrm.attendance_punches (
  id             bigserial primary key,
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid references hrm.employees(id) on delete cascade,   -- null until the device user is matched
  attendance_id  text not null,                   -- as sent by the device (or the employee code for manual punches)
  punched_at     timestamptz not null,
  device_id      uuid references hrm.attendance_devices(id) on delete set null,
  source         text not null check (source in ('device','csv','manual','regularisation')),
  direction      text check (direction is null or direction in ('in','out')),
  created_by     uuid references auth.users(id),
  created_at     timestamptz not null default now(),
  unique (tenant_id, attendance_id, punched_at)
);
create index on hrm.attendance_punches(tenant_id, employee_id, punched_at);
create index on hrm.attendance_punches(tenant_id, punched_at) where employee_id is null;

-- One processed row per employee per day
create table hrm.attendance_days (
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  work_date        date not null,
  shift_id         uuid references hrm.shifts(id) on delete set null,
  first_in         timestamptz,
  last_out         timestamptz,
  punch_count      integer not null default 0,
  worked_minutes   integer not null default 0,
  late_minutes     integer not null default 0,
  early_minutes    integer not null default 0,
  ot_minutes       integer not null default 0,
  status           text not null check (status in (
                     'present','half_day','absent','missed_punch','weekly_off','holiday','leave','half_leave')),
  present_days     numeric(3,1) not null default 0,   -- what payroll counts
  leave_days       numeric(3,1) not null default 0,
  absent_days      numeric(3,1) not null default 0,
  leave_type_code  text,
  remarks          text,
  computed_at      timestamptz not null default now(),
  primary key (employee_id, work_date)
);
create index on hrm.attendance_days(tenant_id, work_date);

create table hrm.regularisation_requests (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references hrm.tenants(id) on delete cascade,
  employee_id       uuid not null references hrm.employees(id) on delete cascade,
  work_date         date not null,
  in_time           time,
  out_time          time,                          -- earlier than in_time = next day
  reason            text not null check (length(reason) between 3 and 500),
  status            text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  decided_by        uuid references auth.users(id),
  decided_at        timestamptz,
  decision_comment  text,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  check (in_time is not null or out_time is not null)
);
create index on hrm.regularisation_requests(tenant_id, status);
create index on hrm.regularisation_requests(employee_id, work_date);

-- ---------------------------------------------------------------------
-- Leave
-- ---------------------------------------------------------------------
create table hrm.leave_types (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references hrm.tenants(id) on delete cascade,
  code                  text not null check (code ~ '^[A-Z0-9]{1,6}$'),
  name                  text not null,
  annual_quota          numeric(5,1) not null default 0 check (annual_quota >= 0),
  accrual               text not null default 'yearly' check (accrual in ('yearly','monthly','none')),
  carry_forward_max     numeric(5,1) not null default 0 check (carry_forward_max >= 0),
  requires_balance      boolean not null default true,    -- false for loss of pay
  paid                  boolean not null default true,
  allow_half_day        boolean not null default true,
  count_non_working     boolean not null default false,   -- true = weekly offs / holidays inside the range are counted
  min_notice_days       integer not null default 0 check (min_notice_days between 0 and 90),
  max_days_per_request  numeric(5,1) check (max_days_per_request is null or max_days_per_request > 0),
  color                 text not null default '#2563EB',
  sort_order            integer not null default 100,
  active                boolean not null default true,
  created_at            timestamptz not null default now(),
  unique (tenant_id, code)
);

create table hrm.leave_requests (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references hrm.tenants(id) on delete cascade,
  employee_id       uuid not null references hrm.employees(id) on delete cascade,
  leave_type_id     uuid not null references hrm.leave_types(id),
  from_date         date not null,
  to_date           date not null,
  half_day          text not null default 'none' check (half_day in ('none','first_half','second_half')),
  days              numeric(5,1) not null check (days > 0),
  reason            text,
  status            text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  decided_by        uuid references auth.users(id),
  decided_at        timestamptz,
  decision_comment  text,
  cancelled_at      timestamptz,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  check (to_date >= from_date),
  check (half_day = 'none' or from_date = to_date)
);
create index on hrm.leave_requests(tenant_id, status);
create index on hrm.leave_requests(employee_id, from_date);

-- Every change to a balance is a ledger row, so balances can always be explained.
create table hrm.leave_ledger (
  id             bigserial primary key,
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid not null references hrm.employees(id) on delete cascade,
  leave_type_id  uuid not null references hrm.leave_types(id) on delete cascade,
  leave_year     integer not null,               -- year in which the leave year starts
  entry_date     date not null default current_date,
  kind           text not null check (kind in ('opening','accrual','carry_forward','availed','reversal','adjustment','lapse')),
  days           numeric(6,2) not null,          -- + credit, - debit
  period         text,                           -- accrual period ('2026' or '2026-10'); makes grants idempotent
  request_id     uuid references hrm.leave_requests(id) on delete set null,
  note           text,
  created_by     uuid references auth.users(id),
  created_at     timestamptz not null default now()
);
create index on hrm.leave_ledger(employee_id, leave_year);
create unique index leave_ledger_once_per_period on hrm.leave_ledger(employee_id, leave_type_id, kind, period)
  where period is not null;

create view hrm.leave_balances with (security_invoker = true) as
  select tenant_id, employee_id, leave_type_id, leave_year,
         sum(days) filter (where kind in ('opening','accrual','carry_forward','adjustment','lapse')) as credited,
         -sum(days) filter (where kind in ('availed','reversal'))                                    as availed,
         sum(days)                                                                                 as balance
    from hrm.leave_ledger
   group by tenant_id, employee_id, leave_type_id, leave_year;

-- =====================================================================
-- Functions
-- =====================================================================

-- Stores punches from a device / CSV / manual entry. Matches the device user to an employee
-- by attendance_id, falling back to the employee code. Duplicates are ignored.
-- Returns the punches that were new, so the app can recompute those days.
create or replace function hrm.ingest_punches(p_tenant uuid, p_device uuid, p_source text, p_rows jsonb, p_actor uuid default null)
returns table (employee_id uuid, punched_at timestamptz)
language plpgsql security definer set search_path = hrm, public as $$
#variable_conflict use_column
begin
  return query
  with rows as (
    select trim(r->>'attendance_id') as att, (r->>'punched_at')::timestamptz as ts, nullif(r->>'direction','') as dir
      from jsonb_array_elements(p_rows) r
     where coalesce(trim(r->>'attendance_id'),'') <> '' and r->>'punched_at' is not null
  ), matched as (
    select r.*, coalesce(
             (select e.id from hrm.employees e where e.tenant_id = p_tenant and e.attendance_id = r.att),
             (select e.id from hrm.employees e where e.tenant_id = p_tenant and e.attendance_id is null and e.employee_code = r.att)
           ) as emp
      from rows r
  ), ins as (
    insert into hrm.attendance_punches as ap (tenant_id, employee_id, attendance_id, punched_at, device_id, source, direction, created_by)
    select p_tenant, m.emp, m.att, m.ts, p_device, p_source, m.dir, p_actor from matched m
    on conflict (tenant_id, attendance_id, punched_at) do nothing
    returning ap.employee_id, ap.punched_at
  )
  select ins.employee_id, ins.punched_at from ins;
end $$;
revoke all on function hrm.ingest_punches(uuid, uuid, text, jsonb, uuid) from public, anon, authenticated;

-- When HR sets or changes an employee's attendance ID, earlier unmatched punches are linked.
create or replace function hrm.link_unmatched_punches() returns trigger
language plpgsql security definer set search_path = hrm, public as $$
begin
  if new.attendance_id is distinct from old.attendance_id or new.employee_code is distinct from old.employee_code then
    update hrm.attendance_punches set employee_id = new.id
     where tenant_id = new.tenant_id and employee_id is null
       and attendance_id in (new.attendance_id, case when new.attendance_id is null then new.employee_code end);
  end if;
  return new;
end $$;
create trigger employees_link_punches after update of attendance_id, employee_code on hrm.employees
  for each row execute function hrm.link_unmatched_punches();

-- Manager or HR may decide on this employee's requests.
create or replace function hrm.can_approve_for(emp uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.employees e where e.id = emp and e.tenant_id = hrm.current_tenant_id())
     and emp is distinct from hrm.current_employee_id()
     and (hrm.is_hr() or (hrm.has_role('manager') and hrm.is_in_my_team(emp)))
$$;

-- Default shifts and leave types, added to the Phase 1 defaults for new companies.
create or replace function hrm.seed_tenant_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $$
begin
  insert into hrm.departments(tenant_id, name, code) values
    (p_tenant,'Production','PRD'),(p_tenant,'Quality','QA'),(p_tenant,'Maintenance','MNT'),
    (p_tenant,'Stores','STR'),(p_tenant,'Production Planning & Control','PPC'),
    (p_tenant,'Human Resources','HR'),(p_tenant,'Accounts & Finance','FIN'),
    (p_tenant,'Purchase','PUR'),(p_tenant,'Engineering','ENG'),(p_tenant,'EHS','EHS')
  on conflict do nothing;
  insert into hrm.designations(tenant_id, name, grade) values
    (p_tenant,'Operator','W1'),(p_tenant,'Senior Operator','W2'),(p_tenant,'Technician','W3'),
    (p_tenant,'Supervisor','S1'),(p_tenant,'Engineer','S2'),(p_tenant,'Senior Engineer','S3'),
    (p_tenant,'Assistant Manager','M1'),(p_tenant,'Manager','M2'),(p_tenant,'Senior Manager','M3'),
    (p_tenant,'Head of Department','M4')
  on conflict do nothing;
  insert into hrm.shifts(tenant_id, code, name, start_time, end_time, break_minutes, half_day_minutes, full_day_minutes) values
    (p_tenant,'G','General shift','09:00','17:30',30,240,450),
    (p_tenant,'A','First shift','06:00','14:30',30,240,450),
    (p_tenant,'B','Second shift','14:30','23:00',30,240,450),
    (p_tenant,'C','Night shift','23:00','06:00',30,210,390)
  on conflict do nothing;
  insert into hrm.leave_types(tenant_id, code, name, annual_quota, accrual, carry_forward_max, requires_balance, paid, allow_half_day, min_notice_days, color, sort_order) values
    (p_tenant,'CL','Casual leave',12,'yearly',0,true,true,true,0,'#2563EB',10),
    (p_tenant,'SL','Sick leave',12,'yearly',0,true,true,true,0,'#DC2626',20),
    (p_tenant,'EL','Earned leave',15,'monthly',45,true,true,false,7,'#059669',30),
    (p_tenant,'CO','Compensatory off',0,'none',0,true,true,true,0,'#7C3AED',40),
    (p_tenant,'LOP','Loss of pay',0,'none',0,false,false,true,0,'#6B7280',90)
  on conflict do nothing;
end $$;

-- Existing companies get the new defaults too
select hrm.seed_tenant_defaults(id) from hrm.tenants;

-- Audit trail for configuration and requests (punches and daily rows are high-volume and have their own history)
do $$
declare t text;
begin
  foreach t in array array['shifts','holidays','attendance_devices','leave_types','leave_requests','regularisation_requests'] loop
    execute format('create trigger %I after insert or update or delete on hrm.%I
                    for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- =====================================================================
-- Row-level security
-- =====================================================================
alter table hrm.shifts                  enable row level security;
alter table hrm.holidays                enable row level security;
alter table hrm.attendance_devices      enable row level security;
alter table hrm.attendance_punches      enable row level security;
alter table hrm.attendance_days         enable row level security;
alter table hrm.regularisation_requests enable row level security;
alter table hrm.leave_types             enable row level security;
alter table hrm.leave_requests          enable row level security;
alter table hrm.leave_ledger            enable row level security;

-- Setup lists: everyone in the company reads, HR writes.
do $$
declare t text;
begin
  foreach t in array array['shifts','holidays','leave_types'] loop
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id())', t || '_read', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_write', t);
  end loop;
end $$;

create policy devices_hr on hrm.attendance_devices for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());

-- Attendance data: HR full; payroll reads; managers read their team; employees read their own.
do $$
declare t text;
begin
  foreach t in array array['attendance_punches','attendance_days','leave_ledger'] loop
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''payroll''))', t || '_payroll', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (employee_id = hrm.current_employee_id())', t || '_self', t);
  end loop;
end $$;

-- Requests: employees create their own (pending only); decisions go through the app,
-- which checks can_approve_for() and writes with the service role.
do $$
declare t text;
begin
  foreach t in array array['leave_requests','regularisation_requests'] loop
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''payroll''))', t || '_payroll', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (employee_id = hrm.current_employee_id())', t || '_self', t);
    execute format('create policy %I on hrm.%I for insert to authenticated with check (employee_id = hrm.current_employee_id() and tenant_id = hrm.current_tenant_id() and status = ''pending'')', t || '_self_insert', t);
  end loop;
end $$;


-- =====================================================================
-- products/hrm/0003_data_tools.sql
-- =====================================================================
-- =====================================================================
-- HRM Suite — data tools: sample data, JSON export / import (restore), nightly backups.
-- Server-only functions (service key): the app checks the person is a company administrator first.
-- Safe to re-run.
-- =====================================================================

-- ---------- sample data (tagged: employees @demo.kmr.test, plants DP1 / DP2) ----------
create or replace function hrm.demo_load(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid; pfx text; p1 uuid; p2 uuid; d0 date := current_date - 30;
  fn text[] := array['Arun','Priya','Karthik','Divya','Suresh','Lakshmi','Rahul','Meena','Vijay','Anitha','Manoj','Kavya','Ravi','Deepa','Ganesh','Sowmya','Prakash','Nandini','Harish','Revathi','Naveen','Pooja','Senthil','Bhavya'];
  ln text[] := array['Kumar','Sharma','Raj','Nair','Reddy','Iyer','Verma','Pillai','Rao','Menon','Gowda','Das','Shetty','Patel','Murthy','Joshi','Babu','Krishnan','Hegde','Naidu','Prasad','Singh','Mani','Rangan'];
  dept text[] := array['Human Resources','Production','Production','Production','Quality','Quality','Maintenance','Stores','Production Planning & Control','Production','Production','Production','Quality','Maintenance','Production','Production','Engineering','Accounts & Finance','Purchase','Production','Production','EHS','Production','Production'];
  desig text[] := array['Manager','Supervisor','Operator','Operator','Engineer','Technician','Technician','Senior Operator','Engineer','Operator','Senior Operator','Operator','Technician','Operator','Operator','Operator','Senior Engineer','Assistant Manager','Engineer','Operator','Operator','Engineer','Operator','Operator'];
  shiftc text[] := array['G','G','A','A','G','A','B','G','G','A','B','B','C','C','A','B','G','G','G',null,null,'G',null,'C'];
  i int; e uuid; mgr uuid; sid uuid; att text; d date; st int; en int; late int; emp record;
begin
  t := p_tenant;
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if pfx is null then raise exception 'Company not found.'; end if;
  if exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then
    raise exception 'Sample data is already loaded. Flush it first to load it again.';
  end if;

  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';
  if p1 is null then insert into hrm.plants (tenant_id, code, name, state) values (t, 'DP1', 'Plant 1 — Bommasandra', 'Karnataka') returning id into p1; end if;
  select id into p2 from hrm.plants where tenant_id = t and code = 'DP2';
  if p2 is null then insert into hrm.plants (tenant_id, code, name, state) values (t, 'DP2', 'Plant 2 — Hosur', 'Tamil Nadu') returning id into p2; end if;

  for i in 1..24 loop
    select id into sid from hrm.shifts where tenant_id = t and code = shiftc[i];
    att := (1000 + i)::text;
    insert into hrm.employees (tenant_id, employee_code, status, first_name, last_name, email, mobile, plant_id,
        department_id, designation_id, reporting_manager_id, employment_type, category, date_of_joining, gender,
        shift_id, weekly_offs, attendance_id)
    values (t, pfx || '-D' || lpad(i::text, 3, '0'), 'active', fn[i], ln[i],
        lower(fn[i] || '.' || ln[i]) || '@demo.kmr.test', '98450' || lpad((10000 + i * 37)::text, 5, '0'),
        case when i % 3 = 0 then p2 else p1 end,
        (select id from hrm.departments where tenant_id = t and name = dept[i]),
        (select id from hrm.designations where tenant_id = t and name = desig[i]),
        case when i = 1 then null else mgr end,
        case when i in (20, 21, 23) then 'contract' else 'permanent' end,
        case when desig[i] in ('Operator','Senior Operator','Technician') then 'workman' when desig[i] = 'Manager' then 'management' else 'staff' end,
        current_date - (200 + i * 37), case when i % 2 = 0 then 'female' else 'male' end,
        sid, case when i % 5 = 0 then '{0,6}'::smallint[] else '{0}'::smallint[] end, att)
    returning id into e;
    if i in (1, 2) then mgr := e; end if;
  end loop;

  -- 30 days of punches: ~93% presence, realistic lateness, a few missed out-punches, night shifts
  for emp in select e.id, e.attendance_id, e.weekly_offs, s.start_time, s.end_time, s.code
               from hrm.employees e left join hrm.shifts s on s.id = e.shift_id
              where e.tenant_id = t and e.email like '%@demo.kmr.test' loop
    for d in select generate_series(d0, current_date - 1, '1 day')::date loop
      if extract(dow from d)::int = any(emp.weekly_offs) then continue; end if;
      if random() < 0.07 then continue; end if;                                         -- absent
      if emp.code is null then                                                           -- rotating shift: pick by week
        st := (array[360, 870, 1380])[1 + (extract(week from d)::int % 3)];
        en := st + 510;
      else
        st := extract(hour from emp.start_time)::int * 60 + extract(minute from emp.start_time)::int;
        en := extract(hour from emp.end_time)::int * 60 + extract(minute from emp.end_time)::int;
        if en <= st then en := en + 1440; end if;
      end if;
      late := case when random() < 0.12 then 12 + (random() * 35)::int else (random() * 16)::int - 12 end;
      insert into hrm.attendance_punches (tenant_id, employee_id, attendance_id, punched_at, source)
      values (t, emp.id, emp.attendance_id, (d + make_interval(mins => st + late)) at time zone 'Asia/Kolkata', 'device')
      on conflict do nothing;
      if random() > 0.03 then
        insert into hrm.attendance_punches (tenant_id, employee_id, attendance_id, punched_at, source)
        values (t, emp.id, emp.attendance_id, (d + make_interval(mins => en + (random() * 50)::int - 8)) at time zone 'Asia/Kolkata', 'device')
        on conflict do nothing;
      end if;
    end loop;
  end loop;

  -- leave: opening balances for this leave year
  insert into hrm.leave_ledger (tenant_id, employee_id, leave_type_id, leave_year, kind, days, period, note)
  select t, e.id, lt.id, extract(year from current_date)::int, 'opening',
         case lt.code when 'CL' then 6 when 'SL' then 5 when 'EL' then 12 else 2 end,
         'opening-' || extract(year from current_date)::int, 'Demo opening balance'
    from hrm.employees e cross join hrm.leave_types lt
   where e.tenant_id = t and e.email like '%@demo.kmr.test' and lt.tenant_id = t and lt.code in ('CL','SL','EL','CO');

  -- pending requests for the approvals demo
  insert into hrm.leave_requests (tenant_id, employee_id, leave_type_id, from_date, to_date, days, reason)
  select t, e.id, (select id from hrm.leave_types where tenant_id = t and code = x.code), current_date + x.off, current_date + x.off + x.len - 1, x.len, x.reason
    from (values (3, 'CL', 5, 1, 'Family function'), (5, 'EL', 12, 3, 'Native place visit'), (9, 'SL', 2, 1, 'Medical appointment')) x(n, code, off, len, reason)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || '-D' || lpad(x.n::text, 3, '0');
  insert into hrm.regularisation_requests (tenant_id, employee_id, work_date, in_time, out_time, reason)
  select t, e.id, current_date - x.back, x.tin::time, x.tout::time, x.reason
    from (values (4, 3, '06:00', '14:40', 'Forgot to punch out'), (10, 6, '06:05', '14:35', 'Biometric device was down at gate 2')) x(n, back, tin, tout, reason)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || '-D' || lpad(x.n::text, 3, '0');

  -- holidays (real Indian holidays for the year; they stay after a flush)
  insert into hrm.holidays (tenant_id, holiday_date, name)
  select t, make_date(extract(year from current_date)::int, m, dd), nm
    from (values (1, 26, 'Republic Day'), (5, 1, 'May Day'), (8, 15, 'Independence Day'), (10, 2, 'Gandhi Jayanti'), (11, 1, 'Kannada Rajyotsava'), (12, 25, 'Christmas')) h(m, dd, nm)
  on conflict do nothing;

  return (select count(*) from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
end $fn$;

create or replace function hrm.demo_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n integer;
begin
  update hrm.employees set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  delete from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test';
  get diagnostics n = row_count;
  delete from hrm.plants p where p.tenant_id = p_tenant and p.code in ('DP1','DP2') and not exists (select 1 from hrm.employees e where e.plant_id = p.id);
  return n;
end $fn$;

-- ---------- JSON export: everything that belongs to one company (logins and message logs excluded) ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger'] loop
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 1, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

-- ---------- JSON import: restores a backup of the SAME company (replaces its data; logins are kept) ----------
create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  -- remember which login belongs to which employee
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  -- clear the company's data (children first)
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.attendance_devices where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  delete from hrm.notification_templates where tenant_id = p_tenant;
  delete from hrm.leave_types where tenant_id = p_tenant;
  delete from hrm.holidays where tenant_id = p_tenant;
  delete from hrm.shifts where tenant_id = p_tenant;
  delete from hrm.designations where tenant_id = p_tenant;
  delete from hrm.departments where tenant_id = p_tenant;
  delete from hrm.plants where tenant_id = p_tenant;
  -- put the backup back (parents first)
  foreach t in array ins loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    execute format('insert into hrm.%I select * from jsonb_populate_recordset(null::hrm.%I, $1)', t, t) using p_data->'tables'->t;
    get diagnostics n = row_count; counts := counts || jsonb_build_object(t, n);
  end loop;
  -- re-link logins to their employee records, and restore company settings
  update hrm.app_users u set employee_id = (l->>'employee_id')::uuid
    from jsonb_array_elements(links) l
   where u.id = (l->>'id')::uuid and (l->>'employee_id') is not null and exists (select 1 from hrm.employees e where e.id = (l->>'employee_id')::uuid);
  update hrm.tenants set settings = coalesce(p_data->'company'->'settings', settings),
         legal_name = coalesce(p_data->'company'->>'legal_name', legal_name),
         address = coalesce(p_data->'company'->>'address', address)
   where id = p_tenant;
  return counts;
end $fn$;

revoke all on function hrm.demo_load(uuid), hrm.demo_flush(uuid), hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.demo_load(uuid), hrm.demo_flush(uuid), hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- private bucket for nightly backups (kept 7 days) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('hrm-backups', 'hrm-backups', false, 52428800)
on conflict (id) do nothing;


-- =====================================================================
-- products/hrm/0004_company_email.sql
-- =====================================================================
-- =====================================================================
-- HRM — each customer company sends its HR emails from ITS OWN mailbox (Gmail / Google Workspace,
-- Microsoft 365 / Outlook, Zoho Mail, GoDaddy, Hostinger or any mail server). No KMR address is used.
-- Until a company connects its mailbox, HRM emails are not sent (WhatsApp and in-app still work).
-- The mailbox password is stored encrypted by the server; this table is never readable from the browser.
-- Safe to re-run.
-- =====================================================================
create table if not exists hrm.tenant_mail (
  tenant_id     uuid primary key references hrm.tenants(id) on delete cascade,
  from_email    text not null,
  from_name     text,
  host          text not null,
  port          integer not null default 587 check (port between 1 and 65535),
  secure        boolean not null default false,      -- true = SSL on connect (port 465); false = STARTTLS (587)
  username      text not null,
  password_enc  text not null,                        -- AES-256-GCM, encrypted by the HRM server
  verified_at   timestamptz,
  last_error    text,
  updated_at    timestamptz not null default now(),
  updated_by    uuid
);
alter table hrm.tenant_mail enable row level security;
-- no policies: only the server (service role) reads or writes it
revoke all on hrm.tenant_mail from anon, authenticated;


-- =====================================================================
-- products/hrm/0005_payroll.sql
-- =====================================================================
-- =====================================================================
-- HRM Phase 3 — Payroll. Needs 0001–0004. Safe to re-run.
--  • Payroll settings per company (pay days basis, PF / ESI / Professional Tax, overtime, Labour Code wages)
--  • Salary components (Basic, DA, HRA, Conveyance, Special allowance …) and each employee's salary (with revisions)
--  • Loans and salary advances, recovered in monthly instalments
--  • Monthly payroll runs: draft → finalised; one line (payslip) per employee
-- Who sees what: HR managers and Payroll staff (and company admins) see and run payroll;
-- each employee sees only their own payslips, and only after the month is finalised.
-- =====================================================================

-- ---------- settings ----------
create table if not exists hrm.pay_settings (
  tenant_id          uuid primary key references hrm.tenants(id) on delete cascade,
  pay_basis          text not null default 'calendar' check (pay_basis in ('calendar','fixed_26','fixed_30')),
  lop_source         text not null default 'attendance' check (lop_source in ('attendance','manual')),
  labour_code_wages  boolean not null default true,        -- PF wages at least 50% of pay (Code on Wages, from 21 Nov 2025)
  pf_enabled         boolean not null default true,
  pf_ceiling         numeric(10,2) not null default 15000,  -- change here when the government's ceiling changes
  pf_restrict        boolean not null default true,         -- contribute on wages up to the ceiling only
  eps_ceiling        numeric(10,2) not null default 15000,
  pf_admin_rate      numeric(5,2) not null default 0.5,
  edli_rate          numeric(5,2) not null default 0.5,
  esi_enabled        boolean not null default true,
  esi_threshold      numeric(10,2) not null default 21000,
  esi_ee_rate        numeric(5,2) not null default 0.75,
  esi_er_rate        numeric(5,2) not null default 3.25,
  pt_enabled         boolean not null default true,
  pt_state           text not null default 'Karnataka',
  pt_slabs           jsonb not null default '[{"from":0,"amount":0,"feb":0},{"from":25000,"amount":200,"feb":300}]',
  ot_enabled         boolean not null default true,
  ot_multiplier      numeric(4,2) not null default 2,       -- Factories Act: twice the ordinary rate
  hours_per_day      numeric(4,2) not null default 8,
  payslip_note       text,
  updated_at         timestamptz not null default now()
);

create table if not exists hrm.pay_components (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references hrm.tenants(id) on delete cascade,
  code        text not null check (code ~ '^[A-Z0-9_]{2,12}$'),
  name        text not null check (length(name) between 2 and 60),
  calc        text not null check (calc in ('percent_gross','percent_basic','fixed','balance')),
  value       numeric(12,2) not null default 0,
  is_wages    boolean not null default false,   -- Basic, DA, retaining allowance: "wages" for PF
  in_ot_base  boolean not null default false,   -- counts for the overtime rate
  prorate     boolean not null default true,    -- reduced for loss-of-pay days
  sort_order  integer not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (tenant_id, code)
);

-- ---------- salaries ----------
create table if not exists hrm.salary_structures (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  employee_id     uuid not null references hrm.employees(id) on delete cascade,
  effective_from  date not null,
  monthly_gross   numeric(12,2) not null check (monthly_gross > 0),
  components      jsonb not null default '[]',          -- [{code, name, amount}] fixed monthly earnings
  pf_applicable   boolean not null default true,
  esi_applicable  boolean,                                -- null = automatic by the ESI threshold
  pt_applicable   boolean not null default true,
  vpf_percent     numeric(5,2) not null default 0,
  monthly_tds     numeric(12,2) not null default 0,
  notes           text,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  unique (employee_id, effective_from)
);
create index if not exists salary_structures_emp on hrm.salary_structures (employee_id, effective_from desc);

create table if not exists hrm.loans (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  employee_id  uuid not null references hrm.employees(id) on delete cascade,
  kind         text not null default 'loan' check (kind in ('loan','advance')),
  amount       numeric(12,2) not null check (amount > 0),
  emi          numeric(12,2) not null check (emi > 0),
  start_month  text not null check (start_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  balance      numeric(12,2) not null,
  status       text not null default 'active' check (status in ('active','closed')),
  notes        text,
  created_by   uuid,
  created_at   timestamptz not null default now()
);
create index if not exists loans_emp on hrm.loans (tenant_id, employee_id, status);

-- ---------- payroll runs ----------
create table if not exists hrm.payroll_runs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  month         text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  status        text not null default 'draft' check (status in ('draft','finalised')),
  totals        jsonb not null default '{}',
  settings      jsonb not null default '{}',     -- the rules used, kept with the run
  created_by    uuid,
  created_at    timestamptz not null default now(),
  computed_at   timestamptz,
  finalised_at  timestamptz,
  finalised_by  uuid,
  emailed_at    timestamptz,
  unique (tenant_id, month)
);

create table if not exists hrm.payroll_lines (
  run_id        uuid not null references hrm.payroll_runs(id) on delete cascade,
  employee_id   uuid not null references hrm.employees(id) on delete cascade,
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  days_in_month numeric(5,2) not null default 0,
  paid_days     numeric(5,2) not null default 0,
  lop_days      numeric(5,2) not null default 0,
  lop_override  numeric(5,2),                     -- set by HR on the run; null = from attendance
  ot_hours      numeric(7,2) not null default 0,
  earnings      jsonb not null default '[]',      -- [{code, name, full, amount}]
  deductions    jsonb not null default '[]',      -- [{code, name, amount}]
  employer      jsonb not null default '[]',      -- [{code, name, amount}]
  adjustments   jsonb not null default '[]',      -- [{label, kind: earning|deduction, amount}] added by HR
  tds_override  numeric(12,2),
  gross         numeric(12,2) not null default 0,
  total_deductions numeric(12,2) not null default 0,
  net_pay       numeric(12,2) not null default 0,
  pf_wage       numeric(12,2) not null default 0,
  esi_wage      numeric(12,2) not null default 0,
  info          jsonb not null default '{}',      -- name, code, designation, department, bank, PAN, UAN, ESI no. at the time
  notes         text,
  updated_at    timestamptz not null default now(),
  primary key (run_id, employee_id)
);
create index if not exists payroll_lines_emp on hrm.payroll_lines (employee_id);

create table if not exists hrm.loan_recoveries (
  loan_id  uuid not null references hrm.loans(id) on delete cascade,
  run_id   uuid not null references hrm.payroll_runs(id) on delete cascade,
  tenant_id uuid not null references hrm.tenants(id) on delete cascade,
  amount   numeric(12,2) not null,
  primary key (loan_id, run_id)
);

-- ---------- access ----------
do $$
declare t text;
begin
  foreach t in array array['pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_payroll', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''hr_manager'',''payroll'')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role(''hr_manager'',''payroll''))', t || '_payroll', t);
  end loop;
end $$;
-- employees: their own payslips once the month is finalised, and the run header for those months
-- (helpers read past row-level security, so the two policies do not call each other in a loop)
create or replace function hrm.payroll_run_final(p_run uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.payroll_runs where id = p_run and status = 'finalised')
$$;
create or replace function hrm.payroll_run_mine(p_run uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.payroll_lines where run_id = p_run and employee_id = hrm.current_employee_id())
$$;
drop policy if exists payroll_lines_self on hrm.payroll_lines;
create policy payroll_lines_self on hrm.payroll_lines for select to authenticated
  using (employee_id = hrm.current_employee_id() and hrm.payroll_run_final(run_id));
drop policy if exists payroll_runs_self on hrm.payroll_runs;
create policy payroll_runs_self on hrm.payroll_runs for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status = 'finalised' and hrm.payroll_run_mine(id));
drop policy if exists salary_structures_self on hrm.salary_structures;
create policy salary_structures_self on hrm.salary_structures for select to authenticated
  using (employee_id = hrm.current_employee_id());
drop policy if exists loans_self on hrm.loans;
create policy loans_self on hrm.loans for select to authenticated using (employee_id = hrm.current_employee_id());
-- the company's payroll rules are not secret (employees see them on payslips)
drop policy if exists pay_settings_read on hrm.pay_settings;
create policy pay_settings_read on hrm.pay_settings for select to authenticated using (tenant_id = hrm.current_tenant_id());

-- ---------- defaults for a company ----------
create or replace function hrm.seed_payroll_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.pay_settings (tenant_id) values (p_tenant) on conflict do nothing;
  if not exists (select 1 from hrm.pay_components where tenant_id = p_tenant) then
    insert into hrm.pay_components (tenant_id, code, name, calc, value, is_wages, in_ot_base, prorate, sort_order) values
      (p_tenant, 'BASIC', 'Basic salary',          'percent_gross', 50, true,  true,  true, 1),
      (p_tenant, 'DA',    'Dearness allowance',    'fixed',          0, true,  true,  true, 2),
      (p_tenant, 'HRA',   'House rent allowance',  'percent_basic', 40, false, false, true, 3),
      (p_tenant, 'CONV',  'Conveyance allowance',  'fixed',       1600, false, false, true, 4),
      (p_tenant, 'SPL',   'Special allowance',     'balance',        0, false, true,  true, 5);
  end if;
end $fn$;

-- sample salaries for the sample employees (used by "Load sample data")
create or replace function hrm.demo_payroll(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n integer;
begin
  perform hrm.seed_payroll_defaults(p_tenant);
  -- components are left empty: the payroll splits them with the company's components when it works out the month
  insert into hrm.salary_structures (tenant_id, employee_id, effective_from, monthly_gross, pf_applicable, notes)
  select e.tenant_id, e.id, coalesce(e.date_of_joining, current_date - 365),
         case when d.name ilike '%manager%' then 85000 when d.name ilike '%senior engineer%' then 60000
              when d.name ilike '%engineer%' then 42000 when d.name ilike '%supervisor%' then 32000
              when d.name ilike '%senior%' then 24000 when d.name ilike '%technician%' then 20000 else 17500 end,
         true, 'Sample salary'
    from hrm.employees e left join hrm.designations d on d.id = e.designation_id
   where e.tenant_id = p_tenant and e.email like '%@demo.kmr.test'
     and not exists (select 1 from hrm.salary_structures s where s.employee_id = e.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  insert into hrm.loans (tenant_id, employee_id, kind, amount, emi, start_month, balance, notes)
  select e.tenant_id, e.id, 'loan', 30000, 3000, to_char(current_date - 31, 'YYYY-MM'), 30000, 'Sample loan'
    from hrm.employees e where e.tenant_id = p_tenant and e.email like '%@demo.kmr.test'
     and not exists (select 1 from hrm.loans l where l.employee_id = e.id)
   order by e.employee_code limit 2;
  return n;
end $fn$;

revoke all on function hrm.seed_payroll_defaults(uuid), hrm.demo_payroll(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_payroll_defaults(uuid), hrm.demo_payroll(uuid) to service_role;

-- every existing company gets the defaults
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_payroll_defaults(t); end loop; end $$;

-- ---------- backups include payroll ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries'] loop
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 2, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  delete from hrm.loan_recoveries where tenant_id = p_tenant;
  delete from hrm.payroll_lines where tenant_id = p_tenant;
  delete from hrm.payroll_runs where tenant_id = p_tenant;
  delete from hrm.loans where tenant_id = p_tenant;
  delete from hrm.salary_structures where tenant_id = p_tenant;
  delete from hrm.pay_components where tenant_id = p_tenant;
  delete from hrm.pay_settings where tenant_id = p_tenant;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.attendance_devices where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  delete from hrm.notification_templates where tenant_id = p_tenant;
  delete from hrm.leave_types where tenant_id = p_tenant;
  delete from hrm.holidays where tenant_id = p_tenant;
  delete from hrm.shifts where tenant_id = p_tenant;
  delete from hrm.designations where tenant_id = p_tenant;
  delete from hrm.departments where tenant_id = p_tenant;
  delete from hrm.plants where tenant_id = p_tenant;
  foreach t in array ins loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    execute format('insert into hrm.%I select * from jsonb_populate_recordset(null::hrm.%I, $1)', t, t) using p_data->'tables'->t;
    get diagnostics n = row_count; counts := counts || jsonb_build_object(t, n);
  end loop;
  update hrm.app_users u set employee_id = (l->>'employee_id')::uuid
    from jsonb_array_elements(links) l
   where u.id = (l->>'id')::uuid and (l->>'employee_id') is not null and exists (select 1 from hrm.employees e where e.id = (l->>'employee_id')::uuid);
  update hrm.tenants set settings = coalesce(p_data->'company'->'settings', settings),
         legal_name = coalesce(p_data->'company'->>'legal_name', legal_name),
         address = coalesce(p_data->'company'->>'address', address)
   where id = p_tenant;
  perform hrm.seed_payroll_defaults(p_tenant);
  return counts;
end $fn$;

insert into storage.buckets (id, name, public, file_size_limit) values ('hrm-backups', 'hrm-backups', false, 52428800) on conflict (id) do nothing;


-- =====================================================================
-- products/hrm/0006_recruitment.sql
-- =====================================================================
-- =====================================================================
-- HRM Phase 4 — Recruitment + Offer. Needs 0001–0005. Safe to re-run.
--  • Manpower requisitions (raised by HR or a department manager, approved by HR)
--  • Job descriptions (written from the requisition, edited and approved by HR, reused for the next opening)
--  • Candidates and their applications to a requisition, with the match score, its evidence and HR's decision
--  • Interviews with a panel, the candidate's confirm / reschedule link, and each panellist's scorecard
--  • Offers with the CTC breakup, the candidate's accept / decline link; accepting creates the employee
-- Who sees what: HR (and company admins) see everything; a manager sees the requisitions they raised;
-- an interviewer sees only the interviews they sit on (with that candidate) and writes only their own scorecard.
-- Everything runs without any paid AI service.
-- =====================================================================

-- ---------- settings ----------
create table if not exists hrm.recruit_settings (
  tenant_id          uuid primary key references hrm.tenants(id) on delete cascade,
  careers_enabled    boolean not null default true,       -- public careers page with the open roles
  careers_intro      text check (length(careers_intro) <= 2000),
  req_approval       boolean not null default true,       -- a manager's requisition waits for HR approval
  suitable_score     integer not null default 70 check (suitable_score between 1 and 100),
  hold_score         integer not null default 50 check (hold_score between 0 and 99),
  regret_auto        boolean not null default true,       -- courteous regret message to declined candidates
  regret_delay_days  integer not null default 3 check (regret_delay_days between 0 and 30),
  offer_valid_days   integer not null default 7 check (offer_valid_days between 1 and 60),
  gratuity_in_ctc    boolean not null default true,       -- show gratuity (4.81% of basic) as part of CTC
  offer_signatory    text check (length(offer_signatory) <= 120),
  offer_terms        text check (length(offer_terms) <= 6000),
  updated_at         timestamptz not null default now()
);

-- ---------- job descriptions (reusable per designation, version-controlled) ----------
create table if not exists hrm.job_descriptions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid references hrm.designations(id) on delete set null,
  title            text not null check (length(title) between 2 and 120),
  family           text,                                  -- quality, production, maintenance … (drives the template)
  purpose          text check (length(purpose) <= 2000),
  responsibilities text[] not null default '{}',
  kpis             text[] not null default '{}',
  must_have        jsonb not null default '[]',          -- [{name, weight 1–3}] competencies the role cannot do without
  good_to_have     jsonb not null default '[]',
  qualifications   text check (length(qualifications) <= 1000),
  experience       text check (length(experience) <= 300),
  reporting_to     text check (length(reporting_to) <= 120),
  context          text check (length(context) <= 600),  -- operating context: industry, plant type, standards
  outcomes         text[] not null default '{}',          -- results the role must deliver
  version          integer not null default 1,
  status           text not null default 'draft' check (status in ('draft','approved','archived')),
  approved_by      uuid,
  approved_at      timestamptz,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists job_descriptions_desig on hrm.job_descriptions (tenant_id, designation_id, version desc);

-- ---------- requisitions ----------
create table if not exists hrm.requisitions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  ref_no           text not null,
  title            text not null check (length(title) between 2 and 120),
  designation_id   uuid references hrm.designations(id) on delete set null,
  department_id    uuid references hrm.departments(id) on delete set null,
  plant_id         uuid references hrm.plants(id) on delete set null,
  headcount        integer not null default 1 check (headcount between 1 and 500),
  grade            text check (length(grade) <= 40),
  ctc_min          numeric(12,2) check (ctc_min >= 0),     -- yearly, rupees
  ctc_max          numeric(12,2) check (ctc_max >= 0),
  exp_min          numeric(4,1) check (exp_min >= 0),
  exp_max          numeric(4,1) check (exp_max >= 0),
  reason           text not null default 'new' check (reason in ('new','replacement','project')),
  replacement_for  text check (length(replacement_for) <= 120),
  required_by      date,
  location         text check (length(location) <= 120),
  notice_max_days  integer check (notice_max_days between 0 and 365),
  jd_id            uuid references hrm.job_descriptions(id) on delete set null,
  status           text not null default 'draft' check (status in ('draft','pending','approved','open','on_hold','closed','cancelled')),
  published        boolean not null default false,        -- shown on the careers page while open
  raised_by        uuid,
  raised_by_name   text,
  approved_by      uuid,
  approved_at      timestamptz,
  closed_at        timestamptz,
  notes            text check (length(notes) <= 2000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (tenant_id, ref_no)
);
create index if not exists requisitions_status on hrm.requisitions (tenant_id, status, created_at desc);

-- ---------- candidates (one per person per company; duplicates merged by e-mail / mobile) ----------
create table if not exists hrm.candidates (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  full_name           text not null check (length(full_name) between 1 and 120),
  email               text check (email = lower(email)),
  phone               text,
  location            text,
  current_company     text,
  current_designation text,
  total_exp           numeric(4,1),
  current_ctc         numeric(12,2),                     -- yearly, rupees
  expected_ctc        numeric(12,2),
  notice_days         integer,
  education           text,
  skills              text[] not null default '{}',
  resume_path         text,
  resume_name         text,
  resume_text         text,
  parse_status        text not null default 'manual' check (parse_status in ('parsed','scanned','failed','manual')),
  source              text not null default 'upload' check (source in ('upload','careers','referral','manual','import')),
  consent_at          timestamptz,                         -- careers page: consent to process the resume (DPDP Act)
  created_by          uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index if not exists candidates_email on hrm.candidates (tenant_id, email) where email is not null;
create unique index if not exists candidates_phone on hrm.candidates (tenant_id, phone) where phone is not null;

-- ---------- applications: a candidate for a requisition ----------
create table if not exists hrm.applications (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  requisition_id   uuid not null references hrm.requisitions(id) on delete cascade,
  candidate_id     uuid not null references hrm.candidates(id) on delete cascade,
  score            integer check (score between 0 and 100),
  breakdown        jsonb not null default '[]',          -- [{key, label, points, max, note}]
  evidence         jsonb not null default '[]',          -- [{competency, line}]
  flags            text[] not null default '{}',          -- hard constraints not met (notice, CTC, location …)
  recommendation   text check (recommendation in ('suitable','hold','not_suitable')),
  status           text not null default 'new' check (status in ('new','shortlisted','on_hold','declined','interview','selected','offered','joined','withdrawn')),
  decision_by      uuid,
  decision_at      timestamptz,
  decision_reason  text check (length(decision_reason) <= 500),
  overridden       boolean not null default false,        -- HR's decision differs from the recommendation
  regret_due       date,
  regret_sent_at   timestamptz,
  source           text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (requisition_id, candidate_id)
);
create index if not exists applications_req on hrm.applications (requisition_id, score desc nulls last);
create index if not exists applications_cand on hrm.applications (candidate_id);

-- ---------- interviews and scorecards ----------
create table if not exists hrm.interviews (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references hrm.tenants(id) on delete cascade,
  application_id     uuid not null references hrm.applications(id) on delete cascade,
  round              integer not null default 1 check (round between 1 and 9),
  title              text not null default 'Interview' check (length(title) <= 80),
  mode               text not null default 'in_person' check (mode in ('in_person','video','phone')),
  starts_at          timestamptz not null,
  duration_min       integer not null default 45 check (duration_min between 10 and 480),
  venue              text check (length(venue) <= 300),
  video_link         text check (length(video_link) <= 500),
  bring              text check (length(bring) <= 500),   -- documents to bring
  panel              uuid[] not null default '{}',        -- app_users ids
  panel_names        text[] not null default '{}',
  status             text not null default 'scheduled' check (status in ('scheduled','confirmed','reschedule_requested','done','cancelled','no_show')),
  token_hash         text,                                 -- candidate's confirm / reschedule link
  candidate_note     text check (length(candidate_note) <= 500),
  reminded_day_before boolean not null default false,
  reminded_same_day  boolean not null default false,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists interviews_when on hrm.interviews (tenant_id, starts_at);
create index if not exists interviews_app on hrm.interviews (application_id);
create index if not exists interviews_token on hrm.interviews (token_hash) where token_hash is not null;

create table if not exists hrm.interview_feedback (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  interview_id    uuid not null references hrm.interviews(id) on delete cascade,
  panelist_id     uuid not null,
  panelist_name   text,
  scores          jsonb not null default '{}',            -- {competency: 1–5}
  overall         integer check (overall between 1 and 5),
  recommendation  text check (recommendation in ('strong_hire','hire','hold','no_hire')),
  strengths       text check (length(strengths) <= 1500),
  concerns        text check (length(concerns) <= 1500),
  submitted_at    timestamptz not null default now(),
  unique (interview_id, panelist_id)
);

-- ---------- offers ----------
create table if not exists hrm.offers (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references hrm.tenants(id) on delete cascade,
  application_id        uuid not null references hrm.applications(id) on delete cascade,
  ref_no                text not null,
  designation_id        uuid references hrm.designations(id) on delete set null,
  department_id         uuid references hrm.departments(id) on delete set null,
  plant_id              uuid references hrm.plants(id) on delete set null,
  reporting_manager_id  uuid references hrm.employees(id) on delete set null,
  employment_type       text not null default 'probation' check (employment_type in ('permanent','probation','fixed_term','trainee','apprentice','contract')),
  category              text not null default 'staff' check (category in ('staff','workman','management')),
  date_of_joining       date not null,
  annual_ctc            numeric(12,2) not null check (annual_ctc > 0),
  monthly_gross         numeric(12,2) not null check (monthly_gross > 0),
  breakup               jsonb not null default '{}',     -- earnings, employer contributions, deductions, net, ctc
  pf_applicable         boolean not null default true,
  include_gratuity      boolean not null default true,
  valid_until           date not null,
  status                text not null default 'draft' check (status in ('draft','sent','accepted','declined','expired','withdrawn')),
  token_hash            text,
  sent_at               timestamptz,
  viewed_at             timestamptz,
  responded_at          timestamptz,
  accepted_name         text check (length(accepted_name) <= 120),   -- typed name as the candidate's signature
  decline_reason        text check (length(decline_reason) <= 500),
  employee_id           uuid references hrm.employees(id) on delete set null,
  terms                 text check (length(terms) <= 6000),
  created_by            uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (tenant_id, ref_no)
);
create index if not exists offers_app on hrm.offers (application_id);
create index if not exists offers_token on hrm.offers (token_hash) where token_hash is not null;

-- ---------- updated_at ----------
do $$ declare t text; begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','offers'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
end $$;

-- ---------- access ----------
-- helpers read past row-level security, so the policies below do not call each other in a loop
create or replace function hrm.on_panel(p_application uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i where i.application_id = p_application and auth.uid() = any(i.panel))
$$;
create or replace function hrm.on_panel_for_candidate(p_candidate uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i join hrm.applications a on a.id = i.application_id
                  where a.candidate_id = p_candidate and auth.uid() = any(i.panel))
$$;
create or replace function hrm.on_panel_for_requisition(p_req uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.interviews i join hrm.applications a on a.id = i.application_id
                  where a.requisition_id = p_req and auth.uid() = any(i.panel))
$$;
create or replace function hrm.raised_by_me(p_req uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $$
  select exists (select 1 from hrm.requisitions r where r.id = p_req and r.raised_by = auth.uid())
$$;

do $$
declare t text;
begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;

-- staff read the company's recruitment rules and approved job descriptions
drop policy if exists recruit_settings_read on hrm.recruit_settings;
create policy recruit_settings_read on hrm.recruit_settings for select to authenticated using (tenant_id = hrm.current_tenant_id());
drop policy if exists job_descriptions_staff on hrm.job_descriptions;
create policy job_descriptions_staff on hrm.job_descriptions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager','interviewer'));

-- a manager raises requisitions and follows the ones they raised
drop policy if exists requisitions_manager_read on hrm.requisitions;
create policy requisitions_manager_read on hrm.requisitions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (raised_by = auth.uid() or hrm.on_panel_for_requisition(id)));
drop policy if exists requisitions_manager_add on hrm.requisitions;
create policy requisitions_manager_add on hrm.requisitions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and raised_by = auth.uid() and status in ('draft','pending'));
drop policy if exists requisitions_manager_edit on hrm.requisitions;
create policy requisitions_manager_edit on hrm.requisitions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and raised_by = auth.uid() and status in ('draft','pending'))
  with check (tenant_id = hrm.current_tenant_id() and raised_by = auth.uid() and status in ('draft','pending'));
-- the manager who raised it sees who applied
drop policy if exists applications_manager on hrm.applications;
create policy applications_manager on hrm.applications for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (hrm.raised_by_me(requisition_id) or hrm.on_panel(id)));

-- interviewers: the interviews they sit on, that candidate, and their own scorecard
drop policy if exists interviews_panel on hrm.interviews;
create policy interviews_panel on hrm.interviews for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and auth.uid() = any(panel));
drop policy if exists candidates_panel on hrm.candidates;
create policy candidates_panel on hrm.candidates for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.on_panel_for_candidate(id));
drop policy if exists feedback_own on hrm.interview_feedback;
create policy feedback_own on hrm.interview_feedback for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and panelist_id = auth.uid())
  with check (tenant_id = hrm.current_tenant_id() and panelist_id = auth.uid()
              and exists (select 1 from hrm.interviews i where i.id = interview_id and auth.uid() = any(i.panel)));

-- ---------- audit trail ----------
do $$ declare t text; begin
  foreach t in array array['recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;
-- recruit_settings has no id column: the audit entry uses tenant_id (audit_row falls back to employee_id, which is null here)

-- ---------- resumes: private bucket, reached only through short-lived signed links ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('hrm-resumes', 'hrm-resumes', false, 5242880,
   array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword','text/plain','image/png','image/jpeg'])
on conflict (id) do nothing;

-- ---------- defaults for a company ----------
create or replace function hrm.seed_recruit_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.recruit_settings (tenant_id, offer_terms) values (p_tenant,
'1. This offer is subject to satisfactory verification of your documents, background and references, and to your being medically fit.
2. You will be on probation for six months from the date of joining; on successful completion you will be confirmed in writing.
3. Your salary details are confidential. Statutory deductions (PF, ESI, Professional Tax, Income Tax) are made as per law.
4. Either party may end the employment with the notice period stated in the company''s service rules, or salary in lieu of notice.
5. You will follow the company''s policies, standing orders, safety rules and code of conduct as amended from time to time.')
  on conflict do nothing;
end $fn$;
revoke all on function hrm.seed_recruit_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_recruit_defaults(uuid) to service_role;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_recruit_defaults(t); end loop; end $$;

-- ---------- backups include recruitment ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 3, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  delete from hrm.offers where tenant_id = p_tenant;
  delete from hrm.interview_feedback where tenant_id = p_tenant;
  delete from hrm.interviews where tenant_id = p_tenant;
  delete from hrm.applications where tenant_id = p_tenant;
  delete from hrm.candidates where tenant_id = p_tenant;
  delete from hrm.requisitions where tenant_id = p_tenant;
  delete from hrm.job_descriptions where tenant_id = p_tenant;
  delete from hrm.recruit_settings where tenant_id = p_tenant;
  delete from hrm.loan_recoveries where tenant_id = p_tenant;
  delete from hrm.payroll_lines where tenant_id = p_tenant;
  delete from hrm.payroll_runs where tenant_id = p_tenant;
  delete from hrm.loans where tenant_id = p_tenant;
  delete from hrm.salary_structures where tenant_id = p_tenant;
  delete from hrm.pay_components where tenant_id = p_tenant;
  delete from hrm.pay_settings where tenant_id = p_tenant;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.attendance_devices where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  delete from hrm.notification_templates where tenant_id = p_tenant;
  delete from hrm.leave_types where tenant_id = p_tenant;
  delete from hrm.holidays where tenant_id = p_tenant;
  delete from hrm.shifts where tenant_id = p_tenant;
  delete from hrm.designations where tenant_id = p_tenant;
  delete from hrm.departments where tenant_id = p_tenant;
  delete from hrm.plants where tenant_id = p_tenant;
  foreach t in array ins loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    execute format('insert into hrm.%I select * from jsonb_populate_recordset(null::hrm.%I, $1)', t, t) using p_data->'tables'->t;
    get diagnostics n = row_count; counts := counts || jsonb_build_object(t, n);
  end loop;
  update hrm.app_users u set employee_id = (l->>'employee_id')::uuid
    from jsonb_array_elements(links) l
   where u.id = (l->>'id')::uuid and (l->>'employee_id') is not null and exists (select 1 from hrm.employees e where e.id = (l->>'employee_id')::uuid);
  update hrm.tenants set settings = coalesce(p_data->'company'->'settings', settings),
         legal_name = coalesce(p_data->'company'->>'legal_name', legal_name),
         address = coalesce(p_data->'company'->>'address', address)
   where id = p_tenant;
  perform hrm.seed_payroll_defaults(p_tenant);
  perform hrm.seed_recruit_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;


-- =====================================================================
-- migrations/0002_quality_suite.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Milestone 2: Balloon Inspector + Process Documents under Console licences.
-- Run after 0001_console.sql, in the project where the tools' bi_* and pd_* tables already exist.
-- Safe to re-run. It only ADDS rules; it never loosens the tools' existing security.
--
--  • A workspace (bi_orgs / pd_orgs) is usable while its licence is trial / pilot / active and not past its end date.
--    Platform admins of the tool are never blocked.
--  • Enforced in the database with RESTRICTIVE row-level-security policies on the tools' data tables,
--    so it cannot be bypassed from the browser.
--  • Every workspace that exists today is adopted: a Console customer + an active pilot licence.
--  • Workspaces created later inside the tools (Admin → Companies) get a 30-day trial licence automatically.
--  • The licence's user limit caps the number of workspace members.
-- =====================================================================

do $$ begin
  if to_regclass('console.licences') is null then raise exception 'Run 0001_console.sql (KMR platform setup) first.'; end if;
  if to_regclass('public.bi_orgs') is null or to_regclass('public.pd_orgs') is null then
    raise exception 'Balloon Inspector / Process Documents tables (bi_orgs, pd_orgs) were not found in this project.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Licence state for a product + workspace (shared by policies, the tools and the HRM)
-- ---------------------------------------------------------------------
create or replace function console.access_state(p_product text, p_ref uuid)
returns table (ok boolean, status text, message text)
language sql stable security definer set search_path = console, public as $$
  select
    coalesce(l.status in ('trial','pilot','active') and (l.valid_until is null or l.valid_until >= current_date), false),
    case when l.id is null then 'none'
         when l.status in ('trial','pilot','active') and l.valid_until < current_date then 'expired'
         else l.status end,
    case when l.id is null then 'This workspace does not have a licence.'
         when l.status in ('trial','pilot','active') and l.valid_until < current_date
           then format('Your company''s %s %s ended on %s.', p.name, case when l.status = 'trial' then 'trial' else 'licence' end, to_char(l.valid_until, 'DD Mon YYYY'))
         when l.status = 'suspended' then format('Your company''s %s access is suspended.', p.name)
         when l.status in ('trial','pilot','active') then null
         else format('Your company''s %s licence is %s.', p.name, l.status) end
  from (select 1) one
  left join console.licences l on l.product_code = p_product and l.product_ref = p_ref
  left join console.products p on p.code = p_product
$$;

create or replace function console.tool_admin(p_product text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if p_product = 'balloon' then return exists (select 1 from public.bi_platform_admins where user_id = auth.uid()); end if;
  if p_product = 'pd'      then return exists (select 1 from public.pd_platform_admins where user_id = auth.uid()); end if;
  return false;
end $$;

-- True when the signed-in person may use this workspace's data right now
create or replace function console.product_ok(p_product text, p_ref uuid) returns boolean
language sql stable security definer set search_path = console, public as $$
  select console.tool_admin(p_product) or coalesce((select ok from console.access_state(p_product, p_ref)), false)
$$;
grant execute on function console.product_ok(text, uuid) to authenticated;
grant execute on function console.access_state(text, uuid) to authenticated, service_role;

-- For the tools' screens: licence state of every workspace the signed-in person belongs to
create or replace function public.kmr_access(p_product text)
returns table (org_id uuid, ok boolean, status text, message text)
language plpgsql stable security definer set search_path = public, console as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if console.tool_admin(p_product) then
    if p_product = 'balloon' then return query select o.id, true, 'admin'::text, null::text from public.bi_orgs o; end if;
    if p_product = 'pd'      then return query select o.id, true, 'admin'::text, null::text from public.pd_orgs o; end if;
    return;
  end if;
  if p_product = 'balloon' then
    return query select m.org_id, a.ok, a.status, a.message from public.bi_members m cross join lateral console.access_state('balloon', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'pd' then
    return query select m.org_id, a.ok, a.status, a.message from public.pd_members m cross join lateral console.access_state('pd', m.org_id) a where lower(m.email) = em;
  end if;
end $$;
revoke all on function public.kmr_access(text) from public, anon;
grant execute on function public.kmr_access(text) to authenticated;

-- ---------------------------------------------------------------------
-- Adopt existing workspaces (one Console customer per company name across both tools)
-- ---------------------------------------------------------------------
do $$
declare o record; cid uuid;
begin
  for o in select 'balloon' as product, id, name from public.bi_orgs
           union all select 'pd', id, name from public.pd_orgs loop
    if exists (select 1 from console.licences where product_code = o.product and product_ref = o.id) then continue; end if;
    select id into cid from console.customers where lower(name) = lower(o.name) limit 1;
    if cid is null then
      insert into console.customers (name, status, source, notes)
      values (o.name, 'pilot', 'Existing workspace', 'Adopted from the tools when the Console was connected')
      returning id into cid;
    end if;
    if not exists (select 1 from console.licences where customer_id = cid and product_code = o.product) then
      insert into console.licences (customer_id, product_code, status, product_ref, product_slug, notes)
      values (cid, o.product, 'pilot', o.id, o.name, 'Existing workspace, adopted');
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- New workspaces created inside the tools get a 30-day trial automatically
-- (the Console creates its own licence first, so its workspaces are skipped here)
-- ---------------------------------------------------------------------
create or replace function console.auto_trial() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_orgs' then 'balloon' else 'pd' end; cid uuid;
begin
  if exists (select 1 from console.licences where product_code = product and product_ref = new.id) then return new; end if;
  select id into cid from console.customers where lower(name) = lower(new.name) limit 1;
  if cid is null then
    insert into console.customers (name, status, source) values (new.name, 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  if exists (select 1 from console.licences where customer_id = cid and product_code = product) then
    -- the customer already has this product for another workspace: record this one as its own customer
    insert into console.customers (name, status, source) values (new.name || ' (' || left(new.id::text, 8) || ')', 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  insert into console.licences (customer_id, product_code, status, valid_until, product_ref, product_slug, notes)
  values (cid, product, 'trial', current_date + 30, new.id, new.name, 'Created inside the tool — 30-day trial');
  return new;
end $$;
drop trigger if exists kmr_auto_trial on public.bi_orgs;
drop trigger if exists kmr_auto_trial on public.pd_orgs;
create trigger kmr_auto_trial after insert on public.bi_orgs for each row execute function console.auto_trial();
create trigger kmr_auto_trial after insert on public.pd_orgs for each row execute function console.auto_trial();

-- ---------------------------------------------------------------------
-- User limit: a workspace cannot have more members than its licence allows
-- ---------------------------------------------------------------------
create or replace function console.member_limit() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_members' then 'balloon' else 'pd' end; lim int; n int;
begin
  select seats into lim from console.licences where product_code = product and product_ref = new.org_id;
  if lim is null then return new; end if;
  if tg_table_name = 'bi_members' then
    select count(*) into n from public.bi_members where org_id = new.org_id and lower(email) <> lower(new.email);
  else
    select count(*) into n from public.pd_members where org_id = new.org_id and lower(email) <> lower(new.email);
  end if;
  if n >= lim then raise exception 'Your licence covers % users for this workspace, and that limit is reached. Contact KMR to raise it.', lim; end if;
  return new;
end $$;
drop trigger if exists kmr_member_limit on public.bi_members;
drop trigger if exists kmr_member_limit on public.pd_members;
create trigger kmr_member_limit before insert on public.bi_members for each row execute function console.member_limit();
create trigger kmr_member_limit before insert on public.pd_members for each row execute function console.member_limit();

-- ---------------------------------------------------------------------
-- Enforcement: restrictive policies on the tools' data (added only where row-level security is on)
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select * from (values ('bi_reports','balloon'), ('pd_projects','pd'), ('pd_masters','pd')) v(tbl, product) loop
    if to_regclass('public.' || t.tbl) is null then raise notice 'Table % not found — skipped.', t.tbl; continue; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || t.tbl)::regclass) then
      raise notice 'Row-level security is OFF on % — licence not enforced there. Turn it on in the tool''s own setup.', t.tbl; continue;
    end if;
    execute format('drop policy if exists kmr_licence on public.%I', t.tbl);
    execute format('create policy kmr_licence on public.%I as restrictive for all to authenticated using (console.product_ok(%L, org_id)) with check (console.product_ok(%L, org_id))', t.tbl, t.product, t.product);
  end loop;
end $$;


-- =====================================================================
-- migrations/0003_service.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Milestone 3: service layer.
--   tickets + ticket_messages  support requests raised from inside the products, answered in the Console
--   leads                      pilot / demo requests from the website
-- Products write through the service key (after checking their own user); nothing here is open to the public.
-- Safe to re-run.
-- =====================================================================
create sequence if not exists console.ticket_no;
create table if not exists console.tickets (
  id              uuid primary key default gen_random_uuid(),
  number          text not null unique default ('T-' || lpad(nextval('console.ticket_no')::text, 5, '0')),
  customer_id     uuid references console.customers(id) on delete set null,
  product_code    text not null references console.products(code),
  product_ref     uuid,                       -- the customer's company / workspace inside the product
  raised_by_email text not null,
  raised_by_name  text not null,
  subject         text not null check (length(subject) between 3 and 150),
  priority        text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status          text not null default 'open' check (status in ('open','in_progress','waiting_on_customer','resolved','closed')),
  page_url        text,
  app_version     text,
  assigned_to     uuid references console.staff(user_id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  first_reply_at  timestamptz,
  resolved_at     timestamptz
);
create index if not exists tickets_status on console.tickets (status, created_at desc);
create index if not exists tickets_ref on console.tickets (product_code, product_ref, created_at desc);

create table if not exists console.ticket_messages (
  id           bigserial primary key,
  ticket_id    uuid not null references console.tickets(id) on delete cascade,
  author_kind  text not null check (author_kind in ('customer','kmr')),
  author_name  text not null,
  body         text not null check (length(body) between 1 and 5000),
  created_at   timestamptz not null default now()
);
create index if not exists ticket_messages_ticket on console.ticket_messages (ticket_id, created_at);

-- first KMR reply and resolution times feed the Console's response-time figures
create or replace function console.ticket_touch() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  update console.tickets set updated_at = now(),
         first_reply_at = case when new.author_kind = 'kmr' and first_reply_at is null then now() else first_reply_at end,
         status = case when new.author_kind = 'customer' and status in ('waiting_on_customer','resolved') then 'open' else status end
   where id = new.ticket_id;
  return new;
end $$;
drop trigger if exists ticket_messages_touch on console.ticket_messages;
create trigger ticket_messages_touch after insert on console.ticket_messages for each row execute function console.ticket_touch();

create table if not exists console.leads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(name) between 2 and 100),
  company     text not null check (length(company) between 2 and 150),
  email       text not null,
  phone       text,
  country     text,
  products    text[] not null default '{}',
  message     text,
  status      text not null default 'new' check (status in ('new','contacted','converted','dropped')),
  customer_id uuid references console.customers(id) on delete set null,
  source      text not null default 'website',
  created_at  timestamptz not null default now()
);
create index if not exists leads_status on console.leads (status, created_at desc);

-- Link a ticket to its Console customer automatically (from the product's licence)
create or replace function console.ticket_customer() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.customer_id is null and new.product_ref is not null then
    select customer_id into new.customer_id from console.licences where product_code = new.product_code and product_ref = new.product_ref;
  end if;
  return new;
end $$;
drop trigger if exists tickets_customer on console.tickets;
create trigger tickets_customer before insert on console.tickets for each row execute function console.ticket_customer();

alter table console.tickets         enable row level security;
alter table console.ticket_messages enable row level security;
alter table console.leads           enable row level security;
do $$
declare t text;
begin
  foreach t in array array['tickets','ticket_messages','leads'] loop
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;
revoke all on console.tickets, console.ticket_messages, console.leads from anon;


-- =====================================================================
-- migrations/0004_portal.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Customer portal ("My KMR Apps").
-- Each customer gets ONE link: www.kmr-groups.com/it/app/<slug>. After signing in, the portal shows the
-- products the customer has bought (from Console licences); the rest can be tried with sample data only.
-- Safe to re-run.
-- =====================================================================
alter table console.customers add column if not exists slug text;
alter table console.customers add column if not exists logo_url text;
update console.customers
   set slug = trim(both '-' from left(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), 40)) || '-' || lower(code)
 where slug is null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_slug_key') then
    alter table console.customers add constraint customers_slug_key unique (slug);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_slug_format') then
    alter table console.customers add constraint customers_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,60}$');
  end if;
end $$;

create or replace function console.customer_slug() returns trigger
language plpgsql set search_path = console, public as $$
begin
  if new.slug is null or new.slug = '' then
    new.slug := trim(both '-' from left(regexp_replace(lower(new.name), '[^a-z0-9]+', '-', 'g'), 40)) || '-' || lower(new.code);
  end if;
  return new;
end $$;
drop trigger if exists customers_slug on console.customers;
create trigger customers_slug before insert on console.customers for each row execute function console.customer_slug();

-- Public logo bucket for customer logos shown on their portal
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('kmr-public', 'kmr-public', true, 1048576, array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict (id) do nothing;

-- Before sign-in: the customer's name and logo for their portal page (nothing else is revealed)
create or replace function public.kmr_portal_brand(p_slug text)
returns table (name text, logo_url text)
language sql stable security definer set search_path = console, public as $$
  select c.name, c.logo_url from console.customers c where c.slug = lower(p_slug) and c.status <> 'inactive'
$$;
revoke all on function public.kmr_portal_brand(text) from public;
grant execute on function public.kmr_portal_brand(text) to anon, authenticated;

-- After sign-in: which products this person's company has (the full version is in 0007_portal_access.sql).
-- Created here only when no version exists yet, so this file is safe to re-run after 0006 / 0007.
do $guard$ begin
  if to_regprocedure('public.kmr_portal(text)') is null then
    execute $fn$create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon' and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'      and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'hrm'     and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;$fn$;
    revoke all on function public.kmr_portal(text) from public, anon;
    grant execute on function public.kmr_portal(text) to authenticated;
  end if;
end $guard$;


-- =====================================================================
-- migrations/0005_data_tools.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — data tools: sample data (Load / Flush), JSON export, nightly backups (kept 7 days).
-- Server-only (service key); the Console checks the person is an owner / administrator first. Safe to re-run.
-- =====================================================================
create or replace function console.demo_load() returns integer
language plpgsql security definer set search_path = console, public as $fn$
begin
  if exists (select 1 from console.customers where source = 'KMR demo data') then raise exception 'Sample data is already loaded. Flush it first to load it again.'; end if;
insert into console.customers (name, legal_name, country, currency, tax_id, city, state, contact_name, contact_email, contact_phone, status, source, notes) values
  ('Sri Balaji Auto Components', 'Sri Balaji Auto Components Pvt Ltd', 'IN', 'INR', '29AABCS1234F1Z5', 'Bengaluru', 'Karnataka', 'Ramesh Babu', 'ramesh@sribalaji.demo.kmr.test', '+91 98450 11111', 'active', 'KMR demo data', 'Tier-2 machining supplier'),
  ('Hosur Precision Forgings', 'Hosur Precision Forgings LLP', 'IN', 'INR', '33AAHFH5678K1Z2', 'Hosur', 'Tamil Nadu', 'Kavitha S', 'kavitha@hosurforge.demo.kmr.test', '+91 94430 22222', 'pilot', 'KMR demo data', 'Pilot of Balloon Inspector for PPAP'),
  ('Pune Gear Works', 'Pune Gear Works Pvt Ltd', 'IN', 'INR', '27AACCP4321L1Z9', 'Pune', 'Maharashtra', 'Amit Deshpande', 'amit@punegear.demo.kmr.test', '+91 98220 33333', 'lead', 'KMR demo data', 'Met at IMTEX'),
  ('Müller Präzisionsteile GmbH', 'Müller Präzisionsteile GmbH', 'DE', 'EUR', 'DE812345678', 'Stuttgart', 'Baden-Württemberg', 'Jonas Müller', 'jonas@mueller.demo.kmr.test', '+49 711 555 0100', 'pilot', 'KMR demo data', 'Export customer — Quality Suite'),
  ('Great Lakes Stamping Inc', 'Great Lakes Stamping Inc', 'US', 'USD', '38-1234567', 'Detroit', 'Michigan', 'Sarah Collins', 'sarah@glstamping.demo.kmr.test', '+1 313 555 0142', 'lead', 'KMR demo data', 'Asked for a demo of HRM + attendance'),
  ('Gulf Fabrication LLC', 'Gulf Fabrication LLC', 'AE', 'AED', '100234567800003', 'Sharjah', 'Sharjah', 'Imran Qureshi', 'imran@gulffab.demo.kmr.test', '+971 6 555 0199', 'inactive', 'KMR demo data', 'Trial ended — follow up next quarter');

insert into console.licences (customer_id, product_code, status, starts_on, valid_until, seats, notes)
select c.id, x.product, x.status, current_date - x.started, current_date + x.ends, x.seats, 'Demo licence (not connected to a workspace)'
  from (values ('Sri Balaji Auto Components', 'hrm', 'active', 120, 245, 150),
               ('Sri Balaji Auto Components', 'balloon', 'active', 120, 245, 10),
               ('Hosur Precision Forgings', 'balloon', 'pilot', 20, 10, 5),
               ('Müller Präzisionsteile GmbH', 'pd', 'trial', 10, 20, 5),
               ('Gulf Fabrication LLC', 'hrm', 'expired', 60, -5, 40)) x(cust, product, status, started, ends, seats)
  join console.customers c on c.name = x.cust and c.source = 'KMR demo data';

insert into console.leads (name, company, email, phone, country, products, message, source) values
  ('Mahesh Gowda', 'Tumkur Castings', 'mahesh@tumkurcast.demo.kmr.test', '+91 99000 44444', 'India', '{hrm}', '180 workmen across 2 shifts, using eSSL devices', 'website'),
  ('Elena Rossi', 'Rossi Meccanica Srl', 'elena@rossimec.demo.kmr.test', '+39 011 555 0177', 'Italy', '{balloon,pd}', 'PPAP documents for an Indian OEM customer', 'website');
  return (select count(*) from console.customers where source = 'KMR demo data');
end $fn$;

create or replace function console.demo_flush() returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare n integer;
begin
  delete from console.tickets where raised_by_email like '%demo.kmr.test';
  delete from console.leads where email like '%demo.kmr.test';
  delete from console.customers where source = 'KMR demo data';
  get diagnostics n = row_count;
  return n;
end $fn$;

create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['products','customers','licences','licence_events','releases','tickets','ticket_messages','leads','staff'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from console.%I x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;

revoke all on function console.demo_load(), console.demo_flush(), console.console_export() from public, anon, authenticated;
grant execute on function console.demo_load(), console.demo_flush(), console.console_export() to service_role;

insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-backups', 'kmr-backups', false, 52428800) on conflict (id) do nothing;


-- =====================================================================
-- migrations/0006_portal_dashboards.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — portal dashboards: live figures per tool for the customer's KMR Apps screen.
-- Only for people who belong to the customer (same rule as kmr_portal). Safe to re-run.
-- Every new tool adds its figures here.
-- =====================================================================
-- kmr_portal now also returns each product's workspace short name (the HRM uses it to admit only this customer)
drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);
create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon' and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'      and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'hrm'     and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;


-- =====================================================================
-- migrations/0007_portal_access.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — portal access: one login for every bought tool.
--  • kmr_portal tells the portal whether THIS person already has access inside each tool.
--  • kmr_portal_join lets the customer's contact person (the email KMR staff recorded for the customer)
--    get access to a bought tool on first use — no second sign-in, no separate invitation.
--  • larger customer logos (up to 5 MB).
-- Safe to re-run.
-- =====================================================================
update storage.buckets set file_size_limit = 5242880 where id = 'kmr-public';

drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);

create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text,
               has_access boolean, is_contact boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon' and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'      and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'hrm'     and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon' then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'      then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'hrm'     then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           lower(coalesce(c.contact_email, '')) = em
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

-- First use of a bought tool by the customer's contact person: add them to that tool as its administrator.
create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype; l console.licences%rowtype; nm text;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' or lower(coalesce(c.contact_email, '')) <> em then
    raise exception 'Only your company''s administrator can give you access to this app. Please ask them to add you.';
  end if;
  select * into l from console.licences where customer_id = c.id and product_code = p_product;
  if l.id is null or l.product_ref is null then raise exception 'This app is not set up for your company yet. Please contact KMR.'; end if;
  if not (select ok from console.access_state(p_product, l.product_ref)) then raise exception 'Your subscription for this app is not active.'; end if;
  nm := coalesce(nullif(c.contact_name, ''), split_part(em, '@', 1));
  if p_product = 'balloon' then
    insert into public.bi_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'pd' then
    insert into public.pd_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'hrm' then
    if exists (select 1 from hrm.app_users where id = uid and tenant_id <> l.product_ref) then
      raise exception 'This login is already used for another company''s HRM. Please use a different email.';
    end if;
    insert into hrm.app_users (id, tenant_id, role, full_name, email, must_change_password)
    values (uid, l.product_ref, 'company_admin', nm, em, false) on conflict (id) do update set active = true;
  else
    raise exception 'Unknown app.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

-- (portal figures, unchanged — recreated because kmr_portal changed)
create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;


-- =====================================================================
-- migrations/0008_my_portals.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — which customer portal(s) the signed-in person belongs to.
-- Lets anyone sign in at www.kmr-groups.com/it/apps.html (or be sent there by a tool) and land on their
-- own company's KMR Apps page. Safe to re-run.
-- =====================================================================
create or replace function public.kmr_my_portals()
returns table (slug text, name text)
language sql stable security definer set search_path = console, public as $$
  select distinct c.slug, c.name
    from console.customers c
   where c.slug is not null and c.status <> 'inactive'
     and exists (select 1 from public.kmr_portal(c.slug))
   order by c.name
$$;
revoke all on function public.kmr_my_portals() from public, anon;
grant execute on function public.kmr_my_portals() to authenticated;


-- =====================================================================
-- migrations/0009_portal_workspace.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — tools opened from a customer's KMR Apps page show ONLY that customer's workspace.
-- (An email that also belongs to other workspaces — e.g. KMR's own — does not see them there.)
-- Safe to re-run.
-- =====================================================================
create or replace function public.kmr_portal_workspace(p_slug text, p_product text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select l.product_ref
    from console.customers c
    join console.licences l on l.customer_id = c.id and l.product_code = p_product
   where c.slug = lower(p_slug)
     and exists (select 1 from public.kmr_portal(p_slug))      -- the caller belongs to this customer
$$;
revoke all on function public.kmr_portal_workspace(text, text) from public, anon;
grant execute on function public.kmr_portal_workspace(text, text) to authenticated;


-- =====================================================================
-- migrations/0010_capacity.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Capacity Planner (capacity plan, takt time, machine loading) as a KMR product.
-- One workspace per customer company (cp_orgs); the whole plan is one JSON document per workspace;
-- roles admin / editor / viewer per workspace; every save kept in cp_history (last 300).
-- Access follows the customer's Console licence (product "capacity"). Safe to re-run.
-- =====================================================================
create table if not exists public.cp_orgs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(name) between 2 and 120),
  settings   jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create table if not exists public.cp_members (
  org_id       uuid not null references public.cp_orgs(id) on delete cascade,
  email        text not null check (email = lower(email)),
  role         text not null default 'viewer' check (role in ('admin','editor','viewer')),
  display_name text,
  login_owned  boolean not null default false,     -- the login was created by this workspace (its admin may reset the password)
  created_by   text,
  created_at   timestamptz not null default now(),
  primary key (org_id, email)
);
create index if not exists cp_members_email on public.cp_members (email);
create table if not exists public.cp_plans (
  org_id     uuid primary key references public.cp_orgs(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists public.cp_history (
  id       bigserial primary key,
  org_id   uuid not null references public.cp_orgs(id) on delete cascade,
  data     jsonb,
  saved_at timestamptz not null default now(),
  saved_by text
);
create index if not exists cp_history_org on public.cp_history (org_id, id desc);

-- ---------- helpers ----------
create or replace function public.cp_my_role(p_org uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.cp_members where org_id = p_org and email = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;
grant execute on function public.cp_my_role(uuid) to authenticated;

create or replace function public.cp_my_workspaces() returns table (id uuid, name text, role text)
language sql stable security definer set search_path = public as $$
  select o.id, o.name, m.role from public.cp_members m join public.cp_orgs o on o.id = m.org_id
   where m.email = lower(coalesce(auth.jwt() ->> 'email', '')) order by o.name
$$;
grant execute on function public.cp_my_workspaces() to authenticated;

create or replace function public.cp_touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists cp_touch on public.cp_plans;
create trigger cp_touch before insert or update on public.cp_plans for each row execute function public.cp_touch();

create or replace function public.cp_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.cp_history (org_id, data, saved_by) values (old.org_id, old.data, old.updated_by);
  delete from public.cp_history where org_id = old.org_id
     and id not in (select id from public.cp_history where org_id = old.org_id order by id desc limit 300);
  return new;
end $$;
drop trigger if exists cp_history on public.cp_plans;
create trigger cp_history before update on public.cp_plans for each row execute function public.cp_keep_history();

create or replace function public.cp_protect_last_admin() returns trigger language plpgsql as $$
begin
  if (tg_op = 'DELETE' and old.role = 'admin') or (tg_op = 'UPDATE' and old.role = 'admin' and new.role <> 'admin') then
    if (select count(*) from public.cp_members where org_id = old.org_id and role = 'admin' and email <> old.email) = 0 then
      raise exception 'At least one admin must remain.';
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists cp_last_admin on public.cp_members;
create trigger cp_last_admin before update or delete on public.cp_members for each row execute function public.cp_protect_last_admin();

-- ---------- user management inside the planner (replaces the old "admin-users" Edge Function) ----------
-- Creating a brand-new login needs a password; an existing KMR login is simply added (it keeps its own password).
-- A workspace admin may reset only passwords of logins that this workspace created.
create or replace function public.cp_admin(p_org uuid, p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  me text := lower(coalesce(auth.jwt() ->> 'email', ''));
  em text := lower(trim(coalesce(p_payload ->> 'email', '')));
  rl text := coalesce(p_payload ->> 'role', 'viewer');
  pw text := coalesce(p_payload ->> 'password', '');
  nm text := nullif(trim(coalesce(p_payload ->> 'name', '')), '');
  uid uuid; owned boolean;
begin
  if public.cp_my_role(p_org) is distinct from 'admin' then raise exception 'Only an admin can manage users.'; end if;
  if p_action = 'list' then
    return jsonb_build_object('users', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'role', m.role, 'name', m.display_name,
      'createdAt', m.created_at, 'createdBy', m.created_by, 'hasLogin', u.id is not null, 'lastSignIn', u.last_sign_in_at) order by m.email)
      from public.cp_members m left join auth.users u on lower(u.email) = m.email where m.org_id = p_org), '[]'::jsonb));
  end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  if rl not in ('admin','editor','viewer') then raise exception 'Unknown role.'; end if;
  select id into uid from auth.users where lower(email) = em limit 1;

  if p_action = 'create' then
    owned := false;
    if uid is null then
      if length(pw) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                              raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                              confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em, crypt(pw, gen_salt('bf')), now(),
              '{"provider":"email","providers":["email"]}', jsonb_build_object('name', coalesce(nm, '')), now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
      owned := true;
    end if;
    insert into public.cp_members (org_id, email, role, display_name, login_owned, created_by)
    values (p_org, em, rl, nm, owned, me)
    on conflict (org_id, email) do update set role = excluded.role, display_name = coalesce(excluded.display_name, cp_members.display_name);
    return jsonb_build_object('ok', true, 'newLogin', owned);
  elsif p_action = 'setRole' then
    update public.cp_members set role = rl, display_name = coalesce(nm, display_name) where org_id = p_org and email = em;
    return jsonb_build_object('ok', true);
  elsif p_action = 'resetPassword' then
    if length(pw) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
    if not exists (select 1 from public.cp_members where org_id = p_org and email = em and login_owned) then
      raise exception 'This person uses their own KMR login. They can change the password themselves, or ask KMR support.';
    end if;
    update auth.users set encrypted_password = crypt(pw, gen_salt('bf')), updated_at = now() where id = uid;
    return jsonb_build_object('ok', true);
  elsif p_action = 'remove' then
    if em = me then raise exception 'You cannot remove yourself.'; end if;
    delete from public.cp_members where org_id = p_org and email = em;     -- the login stays (it may be used in other KMR apps)
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown action.';
end $$;
revoke all on function public.cp_admin(uuid, text, jsonb) from public, anon;
grant execute on function public.cp_admin(uuid, text, jsonb) to authenticated;

-- ---------- row-level security ----------
alter table public.cp_orgs    enable row level security;
alter table public.cp_members enable row level security;
alter table public.cp_plans   enable row level security;
alter table public.cp_history enable row level security;
drop policy if exists cp_orgs_read on public.cp_orgs;
create policy cp_orgs_read on public.cp_orgs for select to authenticated using (public.cp_my_role(id) is not null);
drop policy if exists cp_members_read on public.cp_members;
create policy cp_members_read on public.cp_members for select to authenticated
  using (email = lower(coalesce(auth.jwt() ->> 'email', '')) or public.cp_my_role(org_id) = 'admin');
drop policy if exists cp_plans_read on public.cp_plans;
create policy cp_plans_read on public.cp_plans for select to authenticated using (public.cp_my_role(org_id) is not null);
drop policy if exists cp_plans_insert on public.cp_plans;
create policy cp_plans_insert on public.cp_plans for insert to authenticated with check (public.cp_my_role(org_id) in ('admin','editor'));
drop policy if exists cp_plans_update on public.cp_plans;
create policy cp_plans_update on public.cp_plans for update to authenticated
  using (public.cp_my_role(org_id) in ('admin','editor')) with check (public.cp_my_role(org_id) in ('admin','editor'));
drop policy if exists cp_history_read on public.cp_history;
create policy cp_history_read on public.cp_history for select to authenticated using (public.cp_my_role(org_id) = 'admin');
-- the Console licence: restrictive, on top of the rules above
drop policy if exists kmr_licence on public.cp_plans;
create policy kmr_licence on public.cp_plans as restrictive for all to authenticated
  using (console.product_ok('capacity', org_id)) with check (console.product_ok('capacity', org_id));
drop policy if exists kmr_licence on public.cp_history;
create policy kmr_licence on public.cp_history as restrictive for all to authenticated using (console.product_ok('capacity', org_id));

-- ---------- product in the Console ----------
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('capacity', 'Capacity Planner', 'Capacity plan, takt time and machine loading', '/it/capacity.html', 'users', '4.1.0', 40)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes)
values ('capacity', '4.1.0', 'Capacity Planner on the KMR platform: one workspace per customer, KMR Apps sign-in, Console licences')
on conflict do nothing;

-- workspaces created without the Console get a 30-day trial; the user limit counts members
create or replace function console.auto_trial() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_orgs' then 'balloon' when 'cp_orgs' then 'capacity' else 'pd' end; cid uuid;
begin
  if exists (select 1 from console.licences where product_code = product and product_ref = new.id) then return new; end if;
  select id into cid from console.customers where lower(name) = lower(new.name) limit 1;
  if cid is null then insert into console.customers (name, status, source) values (new.name, 'pilot', 'Created inside the tool') returning id into cid; end if;
  if exists (select 1 from console.licences where customer_id = cid and product_code = product) then
    insert into console.customers (name, status, source) values (new.name || ' (' || left(new.id::text, 8) || ')', 'pilot', 'Created inside the tool') returning id into cid;
  end if;
  insert into console.licences (customer_id, product_code, status, valid_until, product_ref, product_slug, notes)
  values (cid, product, 'trial', current_date + 30, new.id, new.name, 'Created inside the tool — 30-day trial');
  return new;
end $$;
drop trigger if exists kmr_auto_trial on public.cp_orgs;
create trigger kmr_auto_trial after insert on public.cp_orgs for each row execute function console.auto_trial();

create or replace function console.member_limit() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text := case tg_table_name when 'bi_members' then 'balloon' when 'cp_members' then 'capacity' else 'pd' end; lim int; n int;
begin
  select seats into lim from console.licences where product_code = product and product_ref = new.org_id;
  if lim is null then return new; end if;
  if tg_table_name = 'bi_members' then select count(*) into n from public.bi_members where org_id = new.org_id and lower(email) <> lower(new.email);
  elsif tg_table_name = 'cp_members' then select count(*) into n from public.cp_members where org_id = new.org_id and email <> lower(new.email);
  else select count(*) into n from public.pd_members where org_id = new.org_id and lower(email) <> lower(new.email); end if;
  if n >= lim then raise exception 'Your licence covers % users for this workspace, and that limit is reached. Contact KMR to raise it.', lim; end if;
  return new;
end $$;
drop trigger if exists kmr_member_limit on public.cp_members;
create trigger kmr_member_limit before insert on public.cp_members for each row execute function console.member_limit();

-- ---------- portal: access, first use, figures (now including the Capacity Planner) ----------
create or replace function public.kmr_access(p_product text)
returns table (org_id uuid, ok boolean, status text, message text)
language plpgsql stable security definer set search_path = public, console as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if console.tool_admin(p_product) then
    if p_product = 'balloon' then return query select o.id, true, 'admin'::text, null::text from public.bi_orgs o; end if;
    if p_product = 'pd'      then return query select o.id, true, 'admin'::text, null::text from public.pd_orgs o; end if;
    return;
  end if;
  if p_product = 'balloon' then
    return query select m.org_id, a.ok, a.status, a.message from public.bi_members m cross join lateral console.access_state('balloon', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'pd' then
    return query select m.org_id, a.ok, a.status, a.message from public.pd_members m cross join lateral console.access_state('pd', m.org_id) a where lower(m.email) = em;
  elsif p_product = 'capacity' then
    return query select m.org_id, a.ok, a.status, a.message from public.cp_members m cross join lateral console.access_state('capacity', m.org_id) a where m.email = em;
  end if;
end $$;

drop function if exists public.kmr_portal_stats(text);
drop function if exists public.kmr_portal(text);
create or replace function public.kmr_portal(p_slug text)
returns table (product_code text, product_name text, app_path text, purchased boolean, ok boolean, status text,
               valid_until date, message text, customer_name text, logo_url text, product_slug text,
               has_access boolean, is_contact boolean)
language plpgsql stable security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype;
  member boolean := false;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' then return; end if;
  select true into member from console.licences l
   where l.customer_id = c.id and (
         (l.product_code = 'balloon'  and exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'pd'       and exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em))
      or (l.product_code = 'capacity' and exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em))
      or (l.product_code = 'hrm'      and exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)))
   limit 1;
  if not coalesce(member, false) and lower(coalesce(c.contact_email, '')) <> em then return; end if;
  return query
    select p.code, p.name, p.app_path, (l.id is not null), coalesce(a.ok, false), coalesce(a.status, 'not_purchased'),
           l.valid_until, a.message, c.name, c.logo_url, l.product_slug,
           case p.code
             when 'balloon'  then exists (select 1 from public.bi_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'pd'       then exists (select 1 from public.pd_members m where m.org_id = l.product_ref and lower(m.email) = em)
             when 'capacity' then exists (select 1 from public.cp_members m where m.org_id = l.product_ref and m.email = em)
             when 'hrm'      then exists (select 1 from hrm.app_users u where u.tenant_id = l.product_ref and u.id = uid and u.active)
             else false end,
           lower(coalesce(c.contact_email, '')) = em
      from console.products p
      left join console.licences l on l.product_code = p.code and l.customer_id = c.id
      left join lateral console.access_state(p.code, l.product_ref) a on l.id is not null
     where p.active
     order by p.sort_order;
end $$;
revoke all on function public.kmr_portal(text) from public, anon;
grant execute on function public.kmr_portal(text) to authenticated;

create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare
  em text := lower(coalesce(auth.jwt() ->> 'email', ''));
  uid uuid := auth.uid();
  c console.customers%rowtype; l console.licences%rowtype; nm text;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or em = '' or lower(coalesce(c.contact_email, '')) <> em then
    raise exception 'Only your company''s administrator can give you access to this app. Please ask them to add you.';
  end if;
  select * into l from console.licences where customer_id = c.id and product_code = p_product;
  if l.id is null or l.product_ref is null then raise exception 'This app is not set up for your company yet. Please contact KMR.'; end if;
  if not (select ok from console.access_state(p_product, l.product_ref)) then raise exception 'Your subscription for this app is not active.'; end if;
  nm := coalesce(nullif(c.contact_name, ''), split_part(em, '@', 1));
  if p_product = 'balloon' then
    insert into public.bi_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'pd' then
    insert into public.pd_members (org_id, email, role) values (l.product_ref, em, 'admin') on conflict do nothing;
  elsif p_product = 'capacity' then
    insert into public.cp_members (org_id, email, role, display_name, created_by) values (l.product_ref, em, 'admin', nm, 'KMR Apps') on conflict do nothing;
  elsif p_product = 'hrm' then
    if exists (select 1 from hrm.app_users where id = uid and tenant_id <> l.product_ref) then
      raise exception 'This login is already used for another company''s HRM. Please use a different email.';
    end if;
    insert into hrm.app_users (id, tenant_id, role, full_name, email, must_change_password)
    values (uid, l.product_ref, 'company_admin', nm, em, false) on conflict (id) do update set active = true;
  else
    raise exception 'Unknown app.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

-- (portal figures, now with the Capacity Planner)
create or replace function public.kmr_portal_stats(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c uuid; out jsonb := '{}'; ref uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from public.kmr_portal(p_slug)) then return out; end if;
  select id into c from console.customers where slug = lower(p_slug);
  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrm';
  if ref is not null then
    out := out || jsonb_build_object('hrm', jsonb_build_object(
      'Employees', (select count(*) from hrm.employees where tenant_id = ref and status = 'active'),
      'In today', (select count(*) from hrm.attendance_days where tenant_id = ref and work_date = today and status in ('present','half_day','missed_punch')),
      'Awaiting approval', (select count(*) from hrm.leave_requests where tenant_id = ref and status = 'pending')
                          + (select count(*) from hrm.regularisation_requests where tenant_id = ref and status = 'pending')));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'balloon';
  if ref is not null then
    out := out || jsonb_build_object('balloon', jsonb_build_object(
      'Reports', (select count(*) from public.bi_reports where org_id = ref),
      'Users', (select count(*) from public.bi_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'pd';
  if ref is not null then
    out := out || jsonb_build_object('pd', jsonb_build_object(
      'Projects', (select count(*) from public.pd_projects where org_id = ref),
      'Users', (select count(*) from public.pd_members where org_id = ref)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'capacity';
  if ref is not null then
    out := out || jsonb_build_object('capacity', jsonb_build_object(
      'Users', (select count(*) from public.cp_members where org_id = ref),
      'Saved versions', (select count(*) from public.cp_history where org_id = ref) + (select count(*) from public.cp_plans where org_id = ref)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;


-- =====================================================================
-- migrations/0011_customer_admin.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Customer Administration (Administration Master).
--  • ONE user list per customer (console.customer_members) with a role per tool; saving a person gives or
--    removes their access inside every tool automatically. Tools no longer manage users themselves.
--  • Company name, details and logo live on the customer (Console or the customer's Administration page) and
--    are pushed to every tool of that customer. Tools no longer keep their own company settings.
--  • HRM employees' own self-service logins stay with HR onboarding; HR staff roles are managed here.
-- Safe to re-run.
-- =====================================================================
create table if not exists console.customer_members (
  customer_id  uuid not null references console.customers(id) on delete cascade,
  email        text not null check (email = lower(email)),
  full_name    text,
  is_admin     boolean not null default false,          -- company administrator: Administration page, users, company details
  roles        jsonb not null default '{}',              -- {"hrm":"hr_manager","balloon":"editor","pd":"viewer","capacity":"admin"}
  login_owned  boolean not null default false,          -- login created here (admins may reset its password)
  created_by   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (customer_id, email)
);
alter table console.customer_members enable row level security;
drop policy if exists customer_members_staff on console.customer_members;
create policy customer_members_staff on console.customer_members for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- Is the signed-in person an administrator of this customer? (the recorded contact person always is)
create or replace function console.is_customer_admin(p_customer uuid) returns boolean
language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.is_admin and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
      or exists (select 1 from console.customers c where c.id = p_customer and lower(coalesce(c.contact_email, '')) = lower(coalesce(auth.jwt() ->> 'email', '')) and coalesce(c.contact_email, '') <> '')
      or console.is_staff()
$$;
grant execute on function console.is_customer_admin(uuid) to authenticated;

-- A KMR login (created when missing; returns the user id and whether it was created now)
create or replace function console.ensure_login(p_email text, p_password text, p_name text, out uid uuid, out created boolean)
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  created := false;
  if uid is not null then return; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'A new login needs a password of at least 8 characters.'; end if;
  uid := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(p_email), crypt(p_password, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('name', coalesce(p_name, '')), now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', lower(p_email), 'email_verified', true), 'email', now(), now(), now());
  created := true;
end $$;
revoke all on function console.ensure_login(text, text, text) from public, anon, authenticated;

-- Give / remove one person's access inside every tool of the customer, from their roles
create or replace function console.sync_member(p_customer uuid, p_email text) returns void
language plpgsql security definer set search_path = console, public, auth as $$
declare m console.customer_members%rowtype; l record; r text; uid uuid;
begin
  select * into m from console.customer_members where customer_id = p_customer and email = lower(p_email);
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  for l in select product_code, product_ref from console.licences where customer_id = p_customer and product_ref is not null loop
    r := case when m.email is null then null else nullif(m.roles ->> l.product_code, '') end;
    if l.product_code = 'balloon' then
      if r is null then delete from public.bi_members where org_id = l.product_ref and lower(email) = lower(p_email);
      else insert into public.bi_members (org_id, email, role) values (l.product_ref, lower(p_email), r)
           on conflict (org_id, email) do update set role = excluded.role; end if;
    elsif l.product_code = 'pd' then
      if r is null then delete from public.pd_members where org_id = l.product_ref and lower(email) = lower(p_email);
      else insert into public.pd_members (org_id, email, role) values (l.product_ref, lower(p_email), r)
           on conflict (org_id, email) do update set role = excluded.role; end if;
    elsif l.product_code = 'capacity' then
      if r is null then delete from public.cp_members where org_id = l.product_ref and email = lower(p_email);
      else insert into public.cp_members (org_id, email, role, display_name, created_by) values (l.product_ref, lower(p_email), r, m.full_name, 'KMR Apps')
           on conflict (org_id, email) do update set role = excluded.role, display_name = coalesce(excluded.display_name, cp_members.display_name); end if;
    elsif l.product_code = 'hrm' and uid is not null then
      if r is null then
        update hrm.app_users set active = false where id = uid and tenant_id = l.product_ref and role <> 'employee';
      else
        if exists (select 1 from hrm.app_users where id = uid and tenant_id <> l.product_ref) then
          raise exception '% already uses the HRM of another company, so it cannot get HRM access here.', p_email;
        end if;
        insert into hrm.app_users (id, tenant_id, role, full_name, email, must_change_password, active)
        values (uid, l.product_ref, r, coalesce(m.full_name, split_part(p_email, '@', 1)), lower(p_email), false, true)
        on conflict (id) do update set role = excluded.role, full_name = excluded.full_name, active = true;
      end if;
    end if;
  end loop;
end $$;
revoke all on function console.sync_member(uuid, text) from public, anon, authenticated;

-- Existing access becomes the starting user list (tool members, HRM staff, the contact person)
insert into console.customer_members (customer_id, email, full_name, is_admin, roles, created_by)
select x.customer_id, x.email, max(x.name), bool_or(x.adm), jsonb_object_agg(x.product_code, x.role), 'Imported'
  from (
    select l.customer_id, lower(m.email) email, null::text name, m.role = 'admin' adm, 'balloon' product_code, m.role from console.licences l join public.bi_members m on m.org_id = l.product_ref where l.product_code = 'balloon'
    union all select l.customer_id, lower(m.email), null, m.role = 'admin', 'pd', m.role from console.licences l join public.pd_members m on m.org_id = l.product_ref where l.product_code = 'pd'
    union all select l.customer_id, m.email, m.display_name, m.role = 'admin', 'capacity', m.role from console.licences l join public.cp_members m on m.org_id = l.product_ref where l.product_code = 'capacity'
    union all select l.customer_id, lower(u.email), u.full_name, u.role = 'company_admin', 'hrm', u.role from console.licences l join hrm.app_users u on u.tenant_id = l.product_ref
      where l.product_code = 'hrm' and u.role <> 'employee' and u.active
  ) x
 group by x.customer_id, x.email
on conflict (customer_id, email) do nothing;
insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
select id, lower(contact_email), contact_name, true, 'Contact person' from console.customers where coalesce(contact_email, '') <> ''
on conflict (customer_id, email) do update set is_admin = true;

-- ---------- the customer's Administration page (company administrators) ----------
create or replace function public.kmr_admin_role(p_slug text) returns text
language sql stable security definer set search_path = console, public as $$
  select case when console.is_customer_admin(c.id) then 'admin' when exists (select 1 from public.kmr_portal(p_slug)) then 'member' end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_admin_role(text) to authenticated;

create or replace function public.kmr_admin_company(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare c console.customers%rowtype;
begin
  select * into c from console.customers where slug = lower(p_slug);
  if c.id is null or not console.is_customer_admin(c.id) then raise exception 'Only your company''s administrators can open Administration.'; end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'legal_name', c.legal_name, 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
    'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email,
    'contact_phone', c.contact_phone, 'logo_url', c.logo_url,
    'tools', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name) order by p.sort_order), '[]')
                from console.licences l join console.products p on p.code = l.product_code where l.customer_id = c.id and l.product_ref is not null));
end $$;
grant execute on function public.kmr_admin_company(text) to authenticated;

create or replace function public.kmr_admin_save_company(p_slug text, p jsonb) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can change company details.'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'Company name is required.'; end if;
  update console.customers set
    name = trim(p ->> 'name'), legal_name = nullif(trim(coalesce(p ->> 'legal_name', '')), ''), tax_id = nullif(trim(coalesce(p ->> 'tax_id', '')), ''),
    address = nullif(trim(coalesce(p ->> 'address', '')), ''), city = nullif(trim(coalesce(p ->> 'city', '')), ''), state = nullif(trim(coalesce(p ->> 'state', '')), ''),
    postal_code = nullif(trim(coalesce(p ->> 'postal_code', '')), ''), contact_phone = nullif(trim(coalesce(p ->> 'contact_phone', '')), ''),
    logo_url = case when p ? 'logo_url' then nullif(p ->> 'logo_url', '') else logo_url end, updated_at = now()
   where id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_admin_save_company(text, jsonb) to authenticated;

create or replace function public.kmr_admin_users(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public, auth as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'name', m.full_name, 'is_admin', m.is_admin, 'roles', m.roles,
      'login_owned', m.login_owned, 'has_login', u.id is not null, 'last_sign_in', u.last_sign_in_at) order by m.is_admin desc, m.email)
    from console.customer_members m left join auth.users u on lower(u.email) = m.email where m.customer_id = cid), '[]'::jsonb);
end $$;
grant execute on function public.kmr_admin_users(text) to authenticated;

-- Add or change a person: {email, name, is_admin, roles:{tool:role}, password (only for a brand-new login)}
create or replace function public.kmr_admin_save_user(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid; em text := lower(trim(coalesce(p ->> 'email', ''))); lg record; rl jsonb := '{}'; k text; v text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p -> 'roles', '{}')) loop
    if v = '' then continue; end if;
    if k = 'hrm' and v not in ('company_admin','hr_manager','hr_executive','manager','payroll') then raise exception 'Unknown HRM role %.', v; end if;
    if k <> 'hrm' and v not in ('admin','editor','viewer') then raise exception 'Unknown role % for %.', v, k; end if;
    rl := rl || jsonb_build_object(k, v);
  end loop;
  if em = me and coalesce((p ->> 'is_admin')::boolean, false) = false and console.is_customer_admin(cid) and not console.is_staff() then
    raise exception 'You cannot remove your own administrator rights.';
  end if;
  select * into lg from console.ensure_login(em, p ->> 'password', p ->> 'name');
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
  values (cid, em, nullif(trim(coalesce(p ->> 'name', '')), ''), coalesce((p ->> 'is_admin')::boolean, false), rl, lg.created, me)
  on conflict (customer_id, email) do update set full_name = coalesce(excluded.full_name, customer_members.full_name), is_admin = excluded.is_admin,
    roles = excluded.roles, updated_at = now();
  perform console.sync_member(cid, em);
  return jsonb_build_object('ok', true, 'new_login', lg.created);
end $$;
grant execute on function public.kmr_admin_save_user(text, jsonb) to authenticated;

create or replace function public.kmr_admin_reset_password(p_slug text, p_email text, p_password text) returns text
language plpgsql security definer set search_path = console, public, auth, extensions as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can reset passwords.'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'The password must have at least 8 characters.'; end if;
  if not exists (select 1 from console.customer_members where customer_id = cid and email = lower(p_email) and login_owned) then
    raise exception 'This person uses their own KMR login. They can change it themselves, or ask KMR support.';
  end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where lower(email) = lower(p_email);
  return 'ok';
end $$;
grant execute on function public.kmr_admin_reset_password(text, text, text) to authenticated;

create or replace function public.kmr_admin_remove_user(p_slug text, p_email text) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if lower(p_email) = lower(coalesce(auth.jwt() ->> 'email', '')) then raise exception 'You cannot remove yourself.'; end if;
  if exists (select 1 from console.customers where id = cid and lower(coalesce(contact_email, '')) = lower(p_email)) then
    raise exception 'This is your company''s main contact. Ask KMR to change the contact person first.';
  end if;
  delete from console.customer_members where customer_id = cid and email = lower(p_email);
  perform console.sync_member(cid, p_email);      -- removes their access in every tool (the login itself stays)
  return 'ok';
end $$;
grant execute on function public.kmr_admin_remove_user(text, text) to authenticated;

-- ---------- company name, details and logo pushed to every tool of the customer ----------
create or replace function console.push_branding() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare l record;
begin
  for l in select product_code, product_ref from console.licences where customer_id = new.id and product_ref is not null loop
    if l.product_code = 'balloon' then update public.bi_orgs set name = new.name, logo = coalesce(new.logo_url, logo) where id = l.product_ref;
    elsif l.product_code = 'pd' then update public.pd_orgs set name = new.name, logo = coalesce(new.logo_url, logo),
           settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('companyName', new.name) where id = l.product_ref;
    elsif l.product_code = 'capacity' then update public.cp_orgs set name = new.name,
           settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('companyName', new.name, 'logo', coalesce(new.logo_url, '')) where id = l.product_ref;
    elsif l.product_code = 'hrm' then update hrm.tenants set name = new.name, legal_name = coalesce(new.legal_name, legal_name),
           address = coalesce(nullif(concat_ws(', ', new.address, new.city, new.state, new.postal_code), ''), address),
           phone = coalesce(new.contact_phone, phone), logo_path = coalesce(new.logo_url, logo_path) where id = l.product_ref;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists customers_push_branding on console.customers;
create trigger customers_push_branding after update of name, legal_name, logo_url, address, city, state, postal_code, contact_phone on console.customers
  for each row execute function console.push_branding();

-- Branding for tools that read it directly (the Capacity Planner): the customer's name and logo for a workspace
create or replace function public.kmr_workspace_brand(p_product text, p_org uuid) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('name', c.name, 'logo', c.logo_url) from console.licences l join console.customers c on c.id = l.customer_id
   where l.product_code = p_product and l.product_ref = p_org and console.product_ok(p_product, p_org)
$$;
grant execute on function public.kmr_workspace_brand(text, uuid) to authenticated;

-- Customer administrators may upload their company logo (kmr-public/customers/<customer id>/...)
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_customer_logo_insert on storage.objects';
    execute $p$create policy kmr_customer_logo_insert on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-public' and (storage.foldername(name))[1] = 'customers'
      and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$' and console.is_customer_admin(((storage.foldername(name))[2])::uuid))$p$;
  end if;
end $$;

-- ---------- keep the one user list in step, however access is given (Console switch-on, first use, tools) ----------
create or replace function console.track_member() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare product text; j jsonb; org uuid; em text; rl text; cid uuid; nm text;
begin
  product := case tg_table_name when 'bi_members' then 'balloon' when 'pd_members' then 'pd' when 'cp_members' then 'capacity' else 'hrm' end;
  j := to_jsonb(case when tg_op = 'DELETE' then old else new end);    -- the row as JSON: works for all four tables
  org := coalesce(j ->> 'org_id', j ->> 'tenant_id')::uuid; em := lower(j ->> 'email');
  select customer_id into cid from console.licences where product_code = product and product_ref = org;
  if cid is null or em is null then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    update console.customer_members set roles = roles - product, updated_at = now() where customer_id = cid and email = em;
    return old;
  end if;
  rl := j ->> 'role'; nm := coalesce(j ->> 'full_name', j ->> 'display_name');
  if tg_table_name = 'app_users' then
    if rl = 'employee' then return new; end if;                      -- employees' self-service logins stay with HR onboarding
    if not coalesce((j ->> 'active')::boolean, true) then rl := null; end if;
  end if;
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, created_by)
  values (cid, em, nm, false, case when rl is null then '{}'::jsonb else jsonb_build_object(product, rl) end, 'Tool')
  on conflict (customer_id, email) do update
    set roles = case when rl is null then customer_members.roles - product else customer_members.roles || jsonb_build_object(product, rl) end,
        full_name = coalesce(customer_members.full_name, excluded.full_name), updated_at = now();
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['public.bi_members','public.pd_members','public.cp_members','hrm.app_users'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('drop trigger if exists kmr_track_member on %s', t);
    execute format('create trigger kmr_track_member after insert or update or delete on %s for each row execute function console.track_member()', t);
  end loop;
end $$;


-- =====================================================================
-- migrations/0012_platform_brand.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — KMR's own branding (logo), shown on the Console sign-in, its main screen and favicon,
-- and on the general KMR Apps page. Customers' logos stay on each customer. Safe to re-run.
-- =====================================================================
create table if not exists console.platform_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table console.platform_settings enable row level security;
drop policy if exists platform_settings_staff on console.platform_settings;
create policy platform_settings_staff on console.platform_settings for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_platform_brand() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce((select value from console.platform_settings where key = 'brand'), '{}'::jsonb)
$$;
grant execute on function public.kmr_platform_brand() to anon, authenticated;


-- =====================================================================
-- migrations/0013_admin_everywhere.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — company administrators (and the main contact) are admins in EVERY tool the customer has,
-- including tools switched on later. Fixes "Can't open this app" for the main contact. Safe to re-run.
-- =====================================================================
create or replace function console.grant_admins(p_customer uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare m record; l record; r jsonb;
begin
  -- the main contact is always a company administrator
  insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
  select c.id, lower(c.contact_email), c.contact_name, true, 'Contact person' from console.customers c
   where c.id = p_customer and coalesce(c.contact_email, '') <> ''
  on conflict (customer_id, email) do update set is_admin = true;
  for m in select * from console.customer_members where customer_id = p_customer and is_admin loop
    r := m.roles;
    for l in select product_code from console.licences where customer_id = p_customer and product_ref is not null loop
      if coalesce(r ->> l.product_code, '') = '' then
        r := r || jsonb_build_object(l.product_code, case when l.product_code = 'hrm' then 'company_admin' else 'admin' end);
      end if;
    end loop;
    if r <> m.roles then
      update console.customer_members set roles = r, updated_at = now() where customer_id = p_customer and email = m.email;
    end if;
    begin
      perform console.sync_member(p_customer, m.email);
    exception when others then
      raise notice 'Could not give % access in every tool: %', m.email, sqlerrm;   -- e.g. the email already uses another company's HRM
    end;
  end loop;
end $$;

create or replace function console.licence_grant_admins() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.product_ref is not null then perform console.grant_admins(new.customer_id); end if;
  return new;
end $$;
drop trigger if exists licences_grant_admins on console.licences;
create trigger licences_grant_admins after insert or update of product_ref, customer_id on console.licences
  for each row execute function console.licence_grant_admins();

-- apply to every existing customer now
do $$ declare c uuid; begin
  for c in select id from console.customers loop perform console.grant_admins(c); end loop;
end $$;


-- =====================================================================
-- migrations/0014_access_repair.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — ACCESS REPAIR (safe to run any time, as often as needed).
-- Brings access up to date for every customer and ends with a report of who can use which tool.
--  • the main contact and every company administrator are admin in every tool the customer has
--  • any administrator (not only the main contact) gets access automatically when opening a bought tool
--  • tools switched on later give administrators access straight away
-- Needs 0011_customer_admin.sql (the one user list). If that is missing this file says so and stops.
-- =====================================================================
do $$ begin
  if to_regclass('console.customer_members') is null or to_regprocedure('console.sync_member(uuid,text)') is null then
    raise exception 'Run 0011_customer_admin.sql first (it creates the one user list), then run this file again.';
  end if;
end $$;

create or replace function console.grant_admins(p_customer uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare m record; l record; r jsonb;
begin
  -- the main contact is always a company administrator
  insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
  select c.id, lower(c.contact_email), c.contact_name, true, 'Contact person' from console.customers c
   where c.id = p_customer and coalesce(c.contact_email, '') <> ''
  on conflict (customer_id, email) do update set is_admin = true;
  for m in select * from console.customer_members where customer_id = p_customer and is_admin loop
    r := m.roles;
    for l in select product_code from console.licences where customer_id = p_customer and product_ref is not null loop
      if coalesce(r ->> l.product_code, '') = '' then
        r := r || jsonb_build_object(l.product_code, case when l.product_code = 'hrm' then 'company_admin' else 'admin' end);
      end if;
    end loop;
    if r <> m.roles then
      update console.customer_members set roles = r, updated_at = now() where customer_id = p_customer and email = m.email;
    end if;
    begin
      perform console.sync_member(p_customer, m.email);
    exception when others then
      raise notice 'Could not give % access in every tool: %', m.email, sqlerrm;   -- e.g. the email already uses another company's HRM
    end;
  end loop;
end $$;

create or replace function console.licence_grant_admins() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.product_ref is not null then perform console.grant_admins(new.customer_id); end if;
  return new;
end $$;
drop trigger if exists licences_grant_admins on console.licences;
create trigger licences_grant_admins after insert or update of product_ref, customer_id on console.licences
  for each row execute function console.licence_grant_admins();


-- First open of a bought tool: give access to the main contact and to company administrators
create or replace function public.kmr_portal_join(p_slug text, p_product text) returns text
language plpgsql security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); cid uuid; ok boolean;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or em = '' then raise exception 'Unknown company link.'; end if;
  if not exists (select 1 from console.licences where customer_id = cid and product_code = p_product and product_ref is not null) then
    raise exception 'This app is not set up for your company yet. Please contact KMR.';
  end if;
  if console.is_customer_admin(cid) then
    perform console.grant_admins(cid);          -- administrators: admin in every bought tool
  end if;
  perform console.sync_member(cid, em);         -- everyone: whatever Administration › Users & access says
  ok := case p_product
    when 'balloon'  then exists (select 1 from public.bi_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'balloon' where l.customer_id = cid and lower(m.email) = em)
    when 'pd'       then exists (select 1 from public.pd_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'pd' where l.customer_id = cid and lower(m.email) = em)
    when 'capacity' then exists (select 1 from public.cp_members m join console.licences l on l.product_ref = m.org_id and l.product_code = 'capacity' where l.customer_id = cid and m.email = em)
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

-- KMR staff: "Repair access" button on the Console customer page
create or replace function public.kmr_console_repair_access(p_customer uuid) returns text
language plpgsql security definer set search_path = console, public as $$
begin
  if not console.is_staff() then raise exception 'KMR staff only.'; end if;
  perform console.grant_admins(p_customer);
  return 'ok';
end $$;
revoke all on function public.kmr_console_repair_access(uuid) from public, anon;
grant execute on function public.kmr_console_repair_access(uuid) to authenticated;

-- apply to every customer now
do $$ declare c uuid; begin for c in select id from console.customers loop perform console.grant_admins(c); end loop; end $$;

-- REPORT: who can use which tool (check this after running)
select c.name as customer, p.name as tool, l.status as licence,
       coalesce((select string_agg(m.email || ' (' || (m.roles ->> l.product_code) || ')', ', ' order by m.email)
                   from console.customer_members m where m.customer_id = c.id and coalesce(m.roles ->> l.product_code, '') <> ''), '— nobody —') as people_with_access,
       lower(coalesce(c.contact_email, '')) as main_contact
  from console.licences l join console.customers c on c.id = l.customer_id join console.products p on p.code = l.product_code
 where l.product_ref is not null
 order by c.name, p.sort_order;


-- =====================================================================
-- migrations/0015_operations_master.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Operations Master (M7): one set of master data per customer, shared by all tools.
-- Lists: parts, customers, suppliers, machines, gauges, tools, consumables, raw_materials, rate_contracts,
--        cycle_times, cft (CFT team & key contacts), documents (policies, procedures, manuals, records… with a file).
-- Access through KMR Apps › Administration › Users & access: role "ops" = admin / editor / viewer;
-- company administrators always have full access. Needs 0011. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.customer_members') is null then raise exception 'Run 0011_customer_admin.sql first.'; end if;
end $$;

create table if not exists console.ops_records (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  kind        text not null check (kind in ('parts','customers','suppliers','machines','gauges','tools','consumables',
                                             'raw_materials','rate_contracts','cycle_times','cft','documents')),
  code        text not null check (length(trim(code)) between 1 and 80),
  name        text not null default '' check (length(name) <= 200),
  data        jsonb not null default '{}',
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  unique (customer_id, kind, code)
);
create index if not exists ops_records_list on console.ops_records (customer_id, kind, code);
alter table console.ops_records enable row level security;
drop policy if exists ops_records_staff on console.ops_records;
create policy ops_records_staff on console.ops_records for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- The signed-in person's Operations Master role for a customer: admin / editor / viewer / null
create or replace function console.ops_role(p_customer uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select case
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'ops', '') from console.customer_members m
           where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
  end
$$;
grant execute on function console.ops_role(uuid) to authenticated;

create or replace function public.kmr_ops_role(p_slug text) returns text
language sql stable security definer set search_path = console, public as $$
  select console.ops_role(id) from console.customers where slug = lower(p_slug)
$$;
grant execute on function public.kmr_ops_role(text) to authenticated;

create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}');
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

create or replace function public.kmr_ops_list(p_slug text, p_kind text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'data', data, 'active', active,
            'updated_at', updated_at, 'updated_by', updated_by) order by code)
          from console.ops_records where customer_id = cid and kind = p_kind), '[]');
end $$;
grant execute on function public.kmr_ops_list(text, text) to authenticated;

-- Save one record ({id?, code, name, data, active}) or many (p_rows = array; import from CSV: matched by code)
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true), updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid and kind = p_kind;
    else
      insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = console.ops_records.data || excluded.data,
         active = excluded.active, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;

create or replace function public.kmr_ops_delete(p_slug text, p_kind text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change the Operations Master.'; end if;
  delete from console.ops_records where id = p_id and customer_id = cid and kind = p_kind;
  return 'ok';
end $$;
grant execute on function public.kmr_ops_delete(text, text, uuid) to authenticated;

-- User management: "ops" is a role like a tool's (admin / editor / viewer)
create or replace function public.kmr_admin_save_user(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid; em text := lower(trim(coalesce(p ->> 'email', ''))); lg record; rl jsonb := '{}'; k text; v text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p -> 'roles', '{}')) loop
    if v = '' then continue; end if;
    if k = 'hrm' and v not in ('company_admin','hr_manager','hr_executive','manager','payroll') then raise exception 'Unknown HRM role %.', v; end if;
    if k <> 'hrm' and v not in ('admin','editor','viewer') then raise exception 'Unknown role % for %.', v, k; end if;
    rl := rl || jsonb_build_object(k, v);
  end loop;
  if em = me and coalesce((p ->> 'is_admin')::boolean, false) = false and console.is_customer_admin(cid) and not console.is_staff() then
    raise exception 'You cannot remove your own administrator rights.';
  end if;
  select * into lg from console.ensure_login(em, p ->> 'password', p ->> 'name');
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
  values (cid, em, nullif(trim(coalesce(p ->> 'name', '')), ''), coalesce((p ->> 'is_admin')::boolean, false), rl, lg.created, me)
  on conflict (customer_id, email) do update set full_name = coalesce(excluded.full_name, customer_members.full_name), is_admin = excluded.is_admin,
    roles = excluded.roles, updated_at = now();
  perform console.sync_member(cid, em);
  return jsonb_build_object('ok', true, 'new_login', lg.created);
end $$;
grant execute on function public.kmr_admin_save_user(text, jsonb) to authenticated;

-- Documents (policies, procedures, manuals, records…): private files, customers/<customer id>/documents/...
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-docs', 'kmr-docs', false, 26214400) on conflict (id) do nothing;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_docs_read on storage.objects';
    execute $p$create policy kmr_docs_read on storage.objects for select to authenticated using (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) is not null)$p$;
    execute 'drop policy if exists kmr_docs_write on storage.objects';
    execute $p$create policy kmr_docs_write on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
    execute 'drop policy if exists kmr_docs_delete on storage.objects';
    execute $p$create policy kmr_docs_delete on storage.objects for delete to authenticated using (
      bucket_id = 'kmr-docs' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.ops_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
  end if;
end $$;

-- The signed-in person's Operations Master context (role + the customer reference used for document files)
create or replace function public.kmr_ops_context(p_slug text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select case when console.ops_role(c.id) is null then null
              else jsonb_build_object('role', console.ops_role(c.id), 'customer_id', c.id) end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_ops_context(text) to authenticated;


-- =====================================================================
-- migrations/0016_capacity_masters.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — the Capacity Planner uses the Operations Master (M7b). Needs 0010, 0011, 0015. Safe to re-run.
--  Machines → Operations Master › Machines · Parts & routings → › Parts + › Cycle times
--  Plant standards → Operations Master › Plant standards (new) · Working days: weekly off (Plant standards)
--  and the customer's HRM holiday calendar. The planner keeps only its monthly plans.
-- =====================================================================
alter table console.ops_records drop constraint if exists ops_records_kind_check;
alter table console.ops_records add constraint ops_records_kind_check check (kind in ('parts','customers','suppliers','machines','gauges','tools',
  'consumables','raw_materials','rate_contracts','cycle_times','cft','documents','plant_standards'));

-- The planner's masters, in the planner's own format, for one workspace (people with access to that planner)
create or replace function public.kmr_capacity_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; hrm_ref uuid; std jsonb; hol jsonb; names jsonb;
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select data into std from console.ops_records where customer_id = cid and kind = 'plant_standards' and active order by updated_at desc limit 1;
  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrm' and product_ref is not null;
  if hrm_ref is not null then
    select coalesce(jsonb_agg(to_char(holiday_date, 'YYYY-MM-DD') order by holiday_date), '[]'), coalesce(jsonb_object_agg(to_char(holiday_date, 'YYYY-MM-DD'), name), '{}')
      into hol, names from hrm.holidays where tenant_id = hrm_ref;
  end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'cell', coalesce(r.data ->> 'cell', r.data ->> 'type', ''),
        'availDays', nullif(r.data ->> 'available_days', '')::numeric, 'hoursPerDay', nullif(r.data ->> 'hours_per_day', '')::numeric,
        'remarks', coalesce(r.data ->> 'remarks', ''), 'active', r.active) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines'), '[]'),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', row_number, 'partNo', x.part_no, 'partName', coalesce(p.name, x.part_no),
        'process', x.name, 'machine', x.machine, 'cycleTime', x.ct, 'alternates',
        coalesce((select jsonb_agg(trim(a)) from unnest(string_to_array(coalesce(x.alts, ''), ',')) a where trim(a) <> ''), '[]')) order by x.part_no, x.code)
      from (select row_number() over (order by r.data ->> 'part_no', r.code) row_number, r.code, r.name, r.data ->> 'part_no' part_no, r.data ->> 'machine' machine,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct, r.data ->> 'alternates' alts
              from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active) x
      left join console.ops_records p on p.customer_id = cid and p.kind = 'parts' and p.code = x.part_no), '[]'),
    'standards', coalesce(std, '{}'), 'holidays', coalesce(hol, '[]'), 'holidayNames', coalesce(names, '{}'),
    'has_hrm', hrm_ref is not null);
end $$;
revoke all on function public.kmr_capacity_masters(uuid) from public, anon;
grant execute on function public.kmr_capacity_masters(uuid) to authenticated;

-- One-time move: masters typed into the planner go to the Operations Master (planner admins; only fills what is missing)
create or replace function public.kmr_capacity_push_masters(p_org uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); m jsonb; o jsonb; nm int := 0; np int := 0; nc int := 0;
begin
  if public.cp_my_role(p_org) is distinct from 'admin' then raise exception 'Only a planner administrator can move the masters.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  for m in select * from jsonb_array_elements(coalesce(p -> 'machines', '[]')) loop
    insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
    values (cid, 'machines', m ->> 'code', m ->> 'code', jsonb_strip_nulls(jsonb_build_object('cell', m ->> 'cell', 'available_days', m ->> 'availDays',
            'hours_per_day', m ->> 'hoursPerDay', 'remarks', nullif(m ->> 'remarks', ''))), coalesce((m ->> 'active')::boolean, true), me)
    on conflict (customer_id, kind, code) do nothing;
    nm := nm + 1;
  end loop;
  for o in select * from jsonb_array_elements(coalesce(p -> 'operations', '[]')) loop
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'parts', o ->> 'partNo', coalesce(o ->> 'partName', ''), '{}', me) on conflict (customer_id, kind, code) do nothing;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'cycle_times', left((o ->> 'partNo') || ' · ' || (o ->> 'process'), 80), coalesce(o ->> 'process', ''),
            jsonb_strip_nulls(jsonb_build_object('part_no', o ->> 'partNo', 'machine', o ->> 'machine', 'cycle_time_sec', o ->> 'cycleTime',
              'alternates', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(o -> 'alternates', '[]'))), ', '), ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    nc := nc + 1;
  end loop;
  select count(distinct o2 ->> 'partNo') into np from jsonb_array_elements(coalesce(p -> 'operations', '[]')) o2;
  if p ? 'standards' then
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'plant_standards', 'PLANT', 'Plant standards', p -> 'standards', me) on conflict (customer_id, kind, code) do nothing;
  end if;
  return jsonb_build_object('machines', nm, 'parts', np, 'cycle_times', nc);
end $$;
revoke all on function public.kmr_capacity_push_masters(uuid, jsonb) from public, anon;
grant execute on function public.kmr_capacity_push_masters(uuid, jsonb) to authenticated;


-- =====================================================================
-- migrations/0017_ops_sample_data.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Operations Master sample data (M7c). Needs 0015 and 0016. Safe to re-run.
--  One consistent sample plant for all 13 lists (163 records): the Capacity Planner's 12 machines, 16 parts and
--  43 cycle times and its plant standards, plus customers, suppliers, raw materials, rate contracts, gauges, tools,
--  consumables, CFT team and IATF 16949 documents that refer to each other.
--  • KMR Apps › Operations Master › Load sample data / Flush sample data (Operations Master administrators).
--  • Every sample record is tagged (ops_records.sample). Flush deletes only tagged records.
--  • Load never overwrites: a code that already exists is skipped, and sample plant standards are skipped when
--    the company already has its own.
--  • Editing or importing over a sample record makes it the company's own record; Flush then leaves it alone.
--  • Dates (calibration, contracts, document reviews) are set relative to the day the sample is loaded.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_capacity_masters(uuid)') is null then raise exception 'Run 0016_capacity_masters.sql first.'; end if;
end $$;

alter table console.ops_records add column if not exists sample boolean not null default false;
create index if not exists ops_records_sample on console.ops_records (customer_id) where sample;

-- The sample plant. Dates are "@<days from today>".
create or replace function console.ops_sample() returns jsonb
language sql immutable set search_path = console, public as $fn$
  select $sample$[
{"kind":"customers","code":"CUS-001","name":"Orion Motors Pvt Ltd","data":{"gstin":"29AAACO1234F1Z5","city":"Hosur","country":"India","contact":"Purchase — S. Ramesh","email":"purchase@orion-motors.example","phone":"+91 80000 10001","payment_terms":"60 days"}},
{"kind":"customers","code":"CUS-002","name":"Sunrise Tractors Ltd","data":{"gstin":"33AABCS5678K1Z2","city":"Chennai","country":"India","contact":"SQA — P. Latha","email":"sqa@sunrise-tractors.example","phone":"+91 80000 10002","payment_terms":"45 days"}},
{"kind":"customers","code":"CUS-003","name":"Vega Commercial Vehicles Ltd","data":{"gstin":"27AACCV9012M1Z8","city":"Pune","country":"India","contact":"Buyer — A. Kulkarni","email":"buyer@vega-cv.example","phone":"+91 80000 10003","payment_terms":"60 days"}},
{"kind":"customers","code":"CUS-004","name":"Nordhaus Hydraulics GmbH","data":{"city":"Stuttgart","country":"Germany","contact":"Supply chain — K. Weber","email":"scm@nordhaus.example","phone":"+49 711 000 0004","payment_terms":"90 days, EXW"}},
{"kind":"suppliers","code":"SUP-001","name":"Deccan Steel Bars Pvt Ltd","data":{"category":"Raw material","gstin":"29AACS4100Q1Z1","city":"Bengaluru","contact":"Sales desk","email":"sales1@supplier.example","phone":"+91 80000 20001","approved":"Yes","rating":92}},
{"kind":"suppliers","code":"SUP-002","name":"Kaveri Forgings Ltd","data":{"category":"Raw material","gstin":"29AACD4101Q1Z2","city":"Hosur","contact":"Key account","email":"sales2@supplier.example","phone":"+91 80000 20002","approved":"Yes","rating":88}},
{"kind":"suppliers","code":"SUP-003","name":"Trident Castings Pvt Ltd","data":{"category":"Raw material","gstin":"29AACK4102Q1Z3","city":"Coimbatore","contact":"Marketing","email":"sales3@supplier.example","phone":"+91 80000 20003","approved":"Conditional","rating":74}},
{"kind":"suppliers","code":"SUP-004","name":"Precise Heat Treaters","data":{"category":"Outsourced process","gstin":"29AACT4103Q1Z4","city":"Bengaluru","contact":"Plant head","email":"sales4@supplier.example","phone":"+91 80000 20004","approved":"Yes","rating":90}},
{"kind":"suppliers","code":"SUP-005","name":"Surface Finish Platers","data":{"category":"Outsourced process","gstin":"29AACP4104Q1Z5","city":"Bengaluru","contact":"Owner","email":"sales5@supplier.example","phone":"+91 80000 20005","approved":"Yes","rating":85}},
{"kind":"suppliers","code":"SUP-006","name":"Carbide Tooling Solutions","data":{"category":"Tooling","gstin":"29AACM4105Q1Z6","city":"Bengaluru","contact":"Sales engineer","email":"sales6@supplier.example","phone":"+91 80000 20006","approved":"Yes","rating":94}},
{"kind":"suppliers","code":"SUP-007","name":"Metrology Calibration Labs (NABL)","data":{"category":"Gauges & calibration","gstin":"29AACC4106Q1Z7","city":"Bengaluru","contact":"Lab manager","email":"sales7@supplier.example","phone":"+91 80000 20007","approved":"Yes","rating":96}},
{"kind":"suppliers","code":"SUP-008","name":"Coolant & Lubes Traders","data":{"category":"Consumables","gstin":"29AACL4107Q1Z8","city":"Bengaluru","contact":"Sales","email":"sales8@supplier.example","phone":"+91 80000 20008","approved":"Yes","rating":82}},
{"kind":"raw_materials","code":"RM-EN8-40","name":"EN8 bright bar Ø40","data":{"grade":"EN8 (080M40)","specification":"IS 1570 / BS 970","form":"Bar","size":"Ø40 × 3 m","supplier":"SUP-001","rate_per_kg":68}},
{"kind":"raw_materials","code":"RM-EN8-65","name":"EN8 bright bar Ø65","data":{"grade":"EN8 (080M40)","specification":"IS 1570 / BS 970","form":"Bar","size":"Ø65 × 3 m","supplier":"SUP-001","rate_per_kg":67}},
{"kind":"raw_materials","code":"RM-EN19-45","name":"EN19 bar Ø45","data":{"grade":"EN19 (42CrMo4)","specification":"BS 970 709M40","form":"Bar","size":"Ø45 × 3 m","supplier":"SUP-001","rate_per_kg":92}},
{"kind":"raw_materials","code":"RM-20MNCR5-F","name":"20MnCr5 gear blank forging","data":{"grade":"20MnCr5","specification":"DIN 17210","form":"Forging","size":"Ø110 × 38","supplier":"SUP-002","rate_per_kg":105}},
{"kind":"raw_materials","code":"RM-EN353-F","name":"EN353 shaft forging","data":{"grade":"EN353 (15NiCr1)","specification":"BS 970","form":"Forging","size":"Ø55 × 260","supplier":"SUP-002","rate_per_kg":112}},
{"kind":"raw_materials","code":"RM-FG260-C","name":"Grey iron casting FG260","data":{"grade":"FG260","specification":"IS 210","form":"Casting","size":"As per drawing","supplier":"SUP-003","rate_per_kg":78}},
{"kind":"raw_materials","code":"RM-SG500-C","name":"SG iron casting SG500/7","data":{"grade":"SG500/7","specification":"IS 1865","form":"Casting","size":"As per drawing","supplier":"SUP-003","rate_per_kg":96}},
{"kind":"parts","code":"DP-1101","name":"Drive Flange","data":{"customer":"CUS-001","drawing_no":"DRG-1101-A","revision":"C","material":"RM-EN8-65","weight_kg":1.8,"annual_volume":99600,"status":"Production"}},
{"kind":"parts","code":"DP-1102","name":"Wheel Hub","data":{"customer":"CUS-001","drawing_no":"DRG-1102-A","revision":"B","material":"RM-SG500-C","weight_kg":3.4,"annual_volume":67200,"status":"Production"}},
{"kind":"parts","code":"DP-1103","name":"Input Shaft","data":{"customer":"CUS-002","drawing_no":"DRG-1103-A","revision":"B","material":"RM-EN353-F","weight_kg":2.1,"annual_volume":116400,"status":"Production"}},
{"kind":"parts","code":"DP-1104","name":"Gear Blank 42T","data":{"customer":"CUS-002","drawing_no":"DRG-1104-A","revision":"C","material":"RM-20MNCR5-F","weight_kg":1.2,"annual_volume":15600,"status":"Production"}},
{"kind":"parts","code":"DP-1105","name":"Pump Housing","data":{"customer":"CUS-004","drawing_no":"DRG-1105-A","revision":"B","material":"RM-FG260-C","weight_kg":4.6,"annual_volume":54000,"status":"Production"}},
{"kind":"parts","code":"DP-1106","name":"Steering Knuckle Bush","data":{"customer":"CUS-001","drawing_no":"DRG-1106-A","revision":"B","material":"RM-EN8-40","weight_kg":0.4,"annual_volume":15600,"status":"Production"}},
{"kind":"parts","code":"DP-1107","name":"Brake Caliper Bracket","data":{"customer":"CUS-003","drawing_no":"DRG-1107-A","revision":"C","material":"RM-SG500-C","weight_kg":2.7,"annual_volume":33600,"status":"Production"}},
{"kind":"parts","code":"DP-1108","name":"Output Shaft","data":{"customer":"CUS-002","drawing_no":"DRG-1108-A","revision":"B","material":"RM-EN353-F","weight_kg":2.4,"annual_volume":38400,"status":"Production"}},
{"kind":"parts","code":"DP-1109","name":"Timing Pulley","data":{"customer":"CUS-003","drawing_no":"DRG-1109-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":0.9,"annual_volume":42000,"status":"Production"}},
{"kind":"parts","code":"DP-1110","name":"Valve Body","data":{"customer":"CUS-004","drawing_no":"DRG-1110-A","revision":"C","material":"RM-FG260-C","weight_kg":3.1,"annual_volume":26400,"status":"Production"}},
{"kind":"parts","code":"DP-1111","name":"Spline Coupling","data":{"customer":"CUS-003","drawing_no":"DRG-1111-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":1.1,"annual_volume":18000,"status":"Production"}},
{"kind":"parts","code":"DP-1112","name":"Bearing Cap","data":{"customer":"CUS-001","drawing_no":"DRG-1112-A","revision":"B","material":"RM-EN8-65","weight_kg":0.8,"annual_volume":99600,"status":"Production"}},
{"kind":"parts","code":"DP-1113","name":"Planet Carrier","data":{"customer":"CUS-002","drawing_no":"DRG-1113-A","revision":"C","material":"RM-SG500-C","weight_kg":3.8,"annual_volume":38400,"status":"Production"}},
{"kind":"parts","code":"DP-1114","name":"Axle Spacer","data":{"customer":"CUS-003","drawing_no":"DRG-1114-A","revision":"B","material":"RM-EN8-40","weight_kg":0.3,"annual_volume":28800,"status":"Production"}},
{"kind":"parts","code":"DP-1115","name":"Clutch Hub","data":{"customer":"CUS-002","drawing_no":"DRG-1115-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":1.0,"annual_volume":32400,"status":"Production"}},
{"kind":"parts","code":"DP-1116","name":"Rocker Arm Pivot","data":{"customer":"CUS-004","drawing_no":"DRG-1116-A","revision":"C","material":"RM-EN19-45","weight_kg":0.5,"annual_volume":37200,"status":"PPAP"}},
{"kind":"machines","code":"CNC-T01","name":"CNC turning centre 01","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T02","name":"CNC turning centre 02","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T03","name":"CNC turning centre 03","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T04","name":"CNC turning centre 04","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"VMC-M01","name":"Vertical machining centre 01","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"VMC-M02","name":"Vertical machining centre 02","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"VMC-M03","name":"Vertical machining centre 03","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"HMC-H01","name":"Horizontal machining centre 01","data":{"type":"HMC","make":"Makino","model":"a51nx","cell":"HMC Machining","status":"Running"}},
{"kind":"machines","code":"GRD-G01","name":"Cylindrical grinder 01","data":{"type":"Grinding","make":"Micromatic Grinding","model":"Cylindrical 300","cell":"Grinding","status":"Running"}},
{"kind":"machines","code":"GRD-G02","name":"Cylindrical grinder 02","data":{"type":"Grinding","make":"Micromatic Grinding","model":"Cylindrical 300","cell":"Grinding","status":"Running","remarks":"Spindle overhaul due"}},
{"kind":"machines","code":"HOB-01","name":"Gear hobbing machine 01","data":{"type":"Gear Hobbing","make":"Liebherr","model":"LC 180","cell":"Gear Hobbing","status":"Running"}},
{"kind":"machines","code":"BRO-01","name":"Broaching machine 01","data":{"type":"Broaching","make":"Arkay","model":"HB 10T","cell":"Broaching","status":"Running"}},
{"kind":"cycle_times","code":"DP-1101 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1101","machine":"CNC-T01","cycle_time_sec":34.0,"alternates":"CNC-T02","setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1101 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1101","machine":"CNC-T04","cycle_time_sec":58.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1101 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1101","machine":"VMC-M01","cycle_time_sec":145.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1102","machine":"CNC-T02","cycle_time_sec":113.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1102","machine":"CNC-T04","cycle_time_sec":71.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1102","machine":"VMC-M03","cycle_time_sec":78.0,"alternates":"VMC-M01","setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1103","machine":"CNC-T02","cycle_time_sec":72.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1103","machine":"CNC-T03","cycle_time_sec":23.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Spline Hobbing","name":"Spline Hobbing","data":{"part_no":"DP-1103","machine":"HOB-01","cycle_time_sec":83.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Cylindrical Grinding","name":"Cylindrical Grinding","data":{"part_no":"DP-1103","machine":"GRD-G01","cycle_time_sec":58.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1104","machine":"CNC-T04","cycle_time_sec":27.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1104","machine":"HOB-01","cycle_time_sec":53.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1104","machine":"BRO-01","cycle_time_sec":188.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1105 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1105","machine":"HMC-H01","cycle_time_sec":158.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1105 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1105","machine":"VMC-M03","cycle_time_sec":78.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1106 · Turning","name":"Turning","data":{"part_no":"DP-1106","machine":"CNC-T01","cycle_time_sec":100.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1106 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1106","machine":"GRD-G02","cycle_time_sec":113.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1107 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1107","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1107 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1107","machine":"VMC-M02","cycle_time_sec":129.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1108","machine":"CNC-T01","cycle_time_sec":47.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1108","machine":"CNC-T04","cycle_time_sec":71.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Spline Hobbing","name":"Spline Hobbing","data":{"part_no":"DP-1108","machine":"HOB-01","cycle_time_sec":31.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Cylindrical Grinding","name":"Cylindrical Grinding","data":{"part_no":"DP-1108","machine":"GRD-G02","cycle_time_sec":203.0,"alternates":"GRD-G01","setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1109","machine":"CNC-T04","cycle_time_sec":41.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1109","machine":"HOB-01","cycle_time_sec":71.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1109","machine":"BRO-01","cycle_time_sec":121.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1110 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1110","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1110 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1110","machine":"VMC-M03","cycle_time_sec":139.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1111","machine":"CNC-T03","cycle_time_sec":169.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1111","machine":"HOB-01","cycle_time_sec":83.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1111","machine":"BRO-01","cycle_time_sec":31.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1112","machine":"CNC-T01","cycle_time_sec":100.0,"alternates":"CNC-T02","setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1112","machine":"CNC-T03","cycle_time_sec":116.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1112","machine":"VMC-M02","cycle_time_sec":84.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1113 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1113","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1113 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1113","machine":"VMC-M02","cycle_time_sec":84.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1114 · Turning","name":"Turning","data":{"part_no":"DP-1114","machine":"CNC-T02","cycle_time_sec":59.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1114 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1114","machine":"GRD-G01","cycle_time_sec":288.0,"alternates":"GRD-G02","setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1115","machine":"CNC-T03","cycle_time_sec":79.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1115","machine":"HOB-01","cycle_time_sec":61.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1115","machine":"BRO-01","cycle_time_sec":99.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1116 · Turning","name":"Turning","data":{"part_no":"DP-1116","machine":"CNC-T03","cycle_time_sec":37.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1116 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1116","machine":"GRD-G02","cycle_time_sec":203.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"plant_standards","code":"PLANT-1","name":"Plant 1 — machining","data":{"oee":80,"hoursPerDay":22,"daysPerMonth":25,"weeklyOff":"Sunday","warnPct":90,"transferLagHours":2,"lotSize":100,"levelTargetPct":100}},
{"kind":"rate_contracts","code":"RC-S-001","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN8-40","rate":68,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-002","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN8-65","rate":67,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-003","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN19-45","rate":92,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-004","name":"Kaveri Forgings Ltd","data":{"party_type":"Supplier","item":"RM-20MNCR5-F","rate":105,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-005","name":"Kaveri Forgings Ltd","data":{"party_type":"Supplier","item":"RM-EN353-F","rate":112,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-006","name":"Trident Castings Pvt Ltd","data":{"party_type":"Supplier","item":"RM-FG260-C","rate":78,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Fixed for 12 months, freight extra"}},
{"kind":"rate_contracts","code":"RC-S-007","name":"Trident Castings Pvt Ltd","data":{"party_type":"Supplier","item":"RM-SG500-C","rate":96,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Fixed for 12 months, freight extra"}},
{"kind":"rate_contracts","code":"RC-S-008","name":"Precise Heat Treaters","data":{"party_type":"Supplier","item":"Case carburising & hardening","rate":38,"currency":"INR","uom":"kg","valid_from":"@-60","valid_to":"@305","terms":"Minimum lot 200 kg, 5-day turnaround"}},
{"kind":"rate_contracts","code":"RC-C-001","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1101","rate":412,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-002","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1102","rate":685,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-003","name":"Sunrise Tractors Ltd","data":{"party_type":"Customer","item":"DP-1103","rate":598,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-004","name":"Sunrise Tractors Ltd","data":{"party_type":"Customer","item":"DP-1104","rate":356,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-005","name":"Nordhaus Hydraulics GmbH","data":{"party_type":"Customer","item":"DP-1105","rate":18.4,"currency":"EUR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-006","name":"Vega Commercial Vehicles Ltd","data":{"party_type":"Customer","item":"DP-1107","rate":540,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-007","name":"Nordhaus Hydraulics GmbH","data":{"party_type":"Customer","item":"DP-1110","rate":12.9,"currency":"EUR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-008","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1112","rate":238,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"gauges","code":"GA-VC-001","name":"Digital vernier caliper 0–150","data":{"type":"Vernier","range":"0–150 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-40","next_due":"@140","location":"CNC Turning"}},
{"kind":"gauges","code":"GA-VC-002","name":"Digital vernier caliper 0–300","data":{"type":"Vernier","range":"0–300 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-150","next_due":"@30","location":"Quality lab"}},
{"kind":"gauges","code":"GA-MC-001","name":"Outside micrometer 25–50","data":{"type":"Micrometer","range":"25–50 mm","least_count":"0.001 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-20","next_due":"@160","location":"Grinding"}},
{"kind":"gauges","code":"GA-MC-002","name":"Outside micrometer 50–75","data":{"type":"Micrometer","range":"50–75 mm","least_count":"0.001 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-100","next_due":"@80","location":"Grinding"}},
{"kind":"gauges","code":"GA-BG-001","name":"Bore gauge 35–60","data":{"type":"Bore gauge","range":"35–60 mm","least_count":"0.001 mm","make":"Baker","cal_freq_months":6,"last_calibrated":"@-60","next_due":"@120","location":"VMC Milling"}},
{"kind":"gauges","code":"GA-PG-001","name":"Plug gauge Ø25H7 GO/NOGO","data":{"type":"Plug gauge","range":"Ø25 H7","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-200","next_due":"@160","location":"VMC Milling"}},
{"kind":"gauges","code":"GA-PG-002","name":"Thread plug gauge M10×1.5 6H","data":{"type":"Plug gauge","range":"M10×1.5","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-340","next_due":"@20","location":"HMC Machining"}},
{"kind":"gauges","code":"GA-RG-001","name":"Ring gauge Ø30h6 GO/NOGO","data":{"type":"Ring gauge","range":"Ø30 h6","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-90","next_due":"@270","location":"Grinding"}},
{"kind":"gauges","code":"GA-HG-001","name":"Digital height gauge 0–300","data":{"type":"Height gauge","range":"0–300 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":12,"last_calibrated":"@-30","next_due":"@330","location":"Quality lab"}},
{"kind":"gauges","code":"GA-DI-001","name":"Dial indicator 0–10","data":{"type":"Dial","range":"0–10 mm","least_count":"0.01 mm","make":"Baker","cal_freq_months":6,"last_calibrated":"@-175","next_due":"@5","location":"Gear Hobbing"}},
{"kind":"gauges","code":"GA-SG-001","name":"Spline plug gauge 21T","data":{"type":"Plug gauge","range":"21T module 1.25","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-120","next_due":"@240","location":"Gear Hobbing"}},
{"kind":"gauges","code":"GA-CMM-001","name":"CMM bridge type 700×1000×600","data":{"type":"CMM","range":"700×1000×600 mm","least_count":"0.0015 mm","make":"Zeiss","cal_freq_months":12,"last_calibrated":"@-45","next_due":"@315","location":"Quality lab"}},
{"kind":"tools","code":"TL-INS-001","name":"Turning insert CNMG 120408","data":{"type":"Insert","size":"CNMG 120408 · P25","make":"Sandvik","tool_life":350,"cost":620,"stock":120}},
{"kind":"tools","code":"TL-INS-002","name":"Finishing insert VNMG 160404","data":{"type":"Insert","size":"VNMG 160404 · P15","make":"Sandvik","tool_life":450,"cost":680,"stock":80}},
{"kind":"tools","code":"TL-INS-003","name":"Grooving insert 3 mm","data":{"type":"Insert","size":"3 mm · P30","make":"Iscar","tool_life":600,"cost":540,"stock":40}},
{"kind":"tools","code":"TL-DRL-001","name":"Solid carbide drill Ø8.5","data":{"type":"Drill","size":"Ø8.5 × 5D","make":"Guhring","tool_life":2500,"cost":3400,"stock":12}},
{"kind":"tools","code":"TL-DRL-002","name":"Solid carbide drill Ø10.2","data":{"type":"Drill","size":"Ø10.2 × 5D","make":"Guhring","tool_life":2200,"cost":3900,"stock":10}},
{"kind":"tools","code":"TL-TAP-001","name":"Spiral flute tap M10×1.5","data":{"type":"Tap","size":"M10×1.5 6H","make":"Yamawa","tool_life":1500,"cost":1850,"stock":15}},
{"kind":"tools","code":"TL-RMR-001","name":"Carbide reamer Ø25H7","data":{"type":"Reamer","size":"Ø25 H7","make":"Guhring","tool_life":4000,"cost":6200,"stock":4}},
{"kind":"tools","code":"TL-EM-001","name":"End mill Ø16 4-flute","data":{"type":"End mill","size":"Ø16 · AlTiN","make":"Kennametal","tool_life":3000,"cost":4800,"stock":8}},
{"kind":"tools","code":"TL-BB-001","name":"Boring bar Ø20 min bore","data":{"type":"Boring bar","size":"Ø20 × 150","make":"Sandvik","tool_life":20000,"cost":14500,"stock":3}},
{"kind":"tools","code":"TL-HOB-001","name":"Gear hob module 2 AA","data":{"type":"Other","size":"m2 · class AA · TiN","make":"Liebherr","tool_life":12000,"cost":68000,"stock":2}},
{"kind":"tools","code":"TL-BRO-001","name":"Keyway broach 8 mm","data":{"type":"Other","size":"8 mm keyway","make":"Arkay","tool_life":15000,"cost":42000,"stock":2}},
{"kind":"tools","code":"TL-FIX-001","name":"Hydraulic fixture — Pump Housing","data":{"type":"Fixture","size":"DP-1105 OP10","make":"In-house","cost":185000,"stock":1}},
{"kind":"consumables","code":"CN-001","name":"Soluble cutting coolant","data":{"uom":"litre","min_stock":400,"rate":185,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-002","name":"Hydraulic oil ISO VG 68","data":{"uom":"litre","min_stock":200,"rate":160,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-003","name":"Slideway oil ISO VG 68","data":{"uom":"litre","min_stock":100,"rate":175,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-004","name":"Grinding wheel 400×50×127 A60","data":{"uom":"pcs","min_stock":4,"rate":9800,"supplier":"SUP-006"}},
{"kind":"consumables","code":"CN-005","name":"Cotton waste","data":{"uom":"kg","min_stock":50,"rate":90,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-006","name":"Rust preventive oil","data":{"uom":"litre","min_stock":150,"rate":140,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-007","name":"VCI poly bags 300×400","data":{"uom":"pcs","min_stock":2000,"rate":6,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-008","name":"Nitrile gloves","data":{"uom":"pair","min_stock":500,"rate":12,"supplier":"SUP-008"}},
{"kind":"cft","code":"CFT-001","name":"R. Venkatesh","data":{"function":"Management","cft_role":"CFT leader","email":"plant.head@sample-plant.example","phone":"+91 90000 30001"}},
{"kind":"cft","code":"CFT-002","name":"S. Priya","data":{"function":"Quality","cft_role":"CFT member","email":"quality@sample-plant.example","phone":"+91 90000 30002"}},
{"kind":"cft","code":"CFT-003","name":"K. Arun","data":{"function":"Production","cft_role":"CFT member","email":"production@sample-plant.example","phone":"+91 90000 30003"}},
{"kind":"cft","code":"CFT-004","name":"M. Divya","data":{"function":"Engineering","cft_role":"CFT member","email":"engineering@sample-plant.example","phone":"+91 90000 30004"}},
{"kind":"cft","code":"CFT-005","name":"N. Suresh","data":{"function":"Maintenance","cft_role":"CFT member","email":"maintenance@sample-plant.example","phone":"+91 90000 30005"}},
{"kind":"cft","code":"CFT-006","name":"L. Meena","data":{"function":"Purchase","cft_role":"CFT member","email":"purchase@sample-plant.example","phone":"+91 90000 30006"}},
{"kind":"cft","code":"CFT-007","name":"H. Ganesh","data":{"function":"Stores","cft_role":"Key contact","email":"stores@sample-plant.example","phone":"+91 90000 30007"}},
{"kind":"cft","code":"CFT-008","name":"P. Latha","data":{"function":"Customer contact","cft_role":"Key contact","email":"sqa@sunrise-tractors.example","phone":"+91 90000 30008","organisation":"Sunrise Tractors Ltd"}},
{"kind":"cft","code":"CFT-009","name":"S. Ramesh","data":{"function":"Customer contact","cft_role":"Escalation","email":"purchase@orion-motors.example","phone":"+91 90000 30009","organisation":"Orion Motors Pvt Ltd"}},
{"kind":"cft","code":"CFT-010","name":"Key account — Deccan Steel","data":{"function":"Supplier contact","cft_role":"Key contact","email":"sales1@supplier.example","phone":"+91 90000 30010","organisation":"Deccan Steel Bars Pvt Ltd"}},
{"kind":"documents","code":"QM-01","name":"Quality manual","data":{"doc_type":"Quality manual","iatf_clause":"4.3, 4.4","revision":"05","effective_date":"@-200","owner":"Management representative","review_due":"@165"}},
{"kind":"documents","code":"QP-01","name":"Quality policy and objectives","data":{"doc_type":"Policy","iatf_clause":"5.2, 6.2","revision":"03","effective_date":"@-200","owner":"Plant head","review_due":"@165"}},
{"kind":"documents","code":"PR-01","name":"Control of documented information","data":{"doc_type":"Procedure","iatf_clause":"7.5","revision":"04","effective_date":"@-150","owner":"Quality","review_due":"@215"}},
{"kind":"documents","code":"PR-02","name":"Risk analysis and contingency planning","data":{"doc_type":"Procedure","iatf_clause":"6.1.2.1, 6.1.2.3","revision":"02","effective_date":"@-120","owner":"Plant head","review_due":"@245"}},
{"kind":"documents","code":"PR-03","name":"Calibration and measurement system analysis","data":{"doc_type":"Procedure","iatf_clause":"7.1.5.1.1, 7.1.5.2","revision":"03","effective_date":"@-100","owner":"Quality","review_due":"@265"}},
{"kind":"documents","code":"PR-04","name":"Supplier selection and monitoring","data":{"doc_type":"Procedure","iatf_clause":"8.4.1.2, 8.4.2.4","revision":"03","effective_date":"@-180","owner":"Purchase","review_due":"@185"}},
{"kind":"documents","code":"PR-05","name":"Product and process design (APQP)","data":{"doc_type":"Procedure","iatf_clause":"8.3","revision":"02","effective_date":"@-240","owner":"Engineering","review_due":"@125"}},
{"kind":"documents","code":"PR-06","name":"Control of nonconforming output","data":{"doc_type":"Procedure","iatf_clause":"8.7","revision":"04","effective_date":"@-90","owner":"Quality","review_due":"@275"}},
{"kind":"documents","code":"PR-07","name":"Problem solving — 8D and corrective action","data":{"doc_type":"Procedure","iatf_clause":"10.2.3, 10.2.4","revision":"03","effective_date":"@-60","owner":"Quality","review_due":"@305"}},
{"kind":"documents","code":"PR-08","name":"Total productive maintenance","data":{"doc_type":"Procedure","iatf_clause":"8.5.1.5","revision":"02","effective_date":"@-130","owner":"Maintenance","review_due":"@235"}},
{"kind":"documents","code":"WI-CNC-01","name":"CNC turning — set-up and first-off approval","data":{"doc_type":"Work instruction","iatf_clause":"8.5.1.3","revision":"02","effective_date":"@-70","owner":"Production","review_due":"@295"}},
{"kind":"documents","code":"FM-QA-12","name":"Layout inspection report format","data":{"doc_type":"Form / format","iatf_clause":"8.6.2","revision":"01","effective_date":"@-160","owner":"Quality","review_due":"@205"}},
{"kind":"documents","code":"CSR-001","name":"Orion Motors customer-specific requirements","data":{"doc_type":"Customer-specific requirement","iatf_clause":"4.3.2","revision":"2026","effective_date":"@-30","owner":"Quality","review_due":"@335"}},
{"kind":"documents","code":"EXT-01","name":"IATF 16949:2016 standard","data":{"doc_type":"External standard","iatf_clause":"—","revision":"2016","effective_date":"@-400","owner":"Management representative","review_due":"@-35"}}
]$sample$::jsonb
$fn$;

create or replace function console.ops_sample_dates(d jsonb) returns jsonb
language sql stable set search_path = console, public as $$
  select coalesce(jsonb_object_agg(k, case when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^@-?[0-9]+$'
                                           then to_jsonb(to_char(current_date + substr(v #>> '{}', 2)::int, 'YYYY-MM-DD')) else v end), '{}')
    from jsonb_each(coalesce(d, '{}')) e(k, v)
$$;

create or replace function public.kmr_ops_sample_load(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); r jsonb; added int := 0; skipped int := 0; n int;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  for r in select * from jsonb_array_elements(console.ops_sample()) loop
    if r ->> 'kind' = 'plant_standards'
       and exists (select 1 from console.ops_records where customer_id = cid and kind = 'plant_standards' and not sample) then
      skipped := skipped + 1; continue;
    end if;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (cid, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), console.ops_sample_dates(r -> 'data'), true, true, me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics n = row_count;
    if n = 1 then added := added + 1; else skipped := skipped + 1; end if;
  end loop;
  return jsonb_build_object('added', added, 'skipped', skipped);
end $$;
revoke all on function public.kmr_ops_sample_load(text) from public, anon;
grant execute on function public.kmr_ops_sample_load(text) to authenticated;

create or replace function public.kmr_ops_sample_flush(p_slug text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; n int;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  delete from console.ops_records where customer_id = cid and sample;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kmr_ops_sample_flush(text) from public, anon;
grant execute on function public.kmr_ops_sample_flush(text) to authenticated;

-- Counts now also report how many sample records are loaded ("_sample")
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- Lists now say which records are sample data
create or replace function public.kmr_ops_list(p_slug text, p_kind text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'data', data, 'active', active, 'sample', sample,
            'updated_at', updated_at, 'updated_by', updated_by) order by code)
          from console.ops_records where customer_id = cid and kind = p_kind), '[]');
end $$;
grant execute on function public.kmr_ops_list(text, text) to authenticated;

-- Saving (form or CSV import) makes a record the company's own: it is no longer sample data
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true), sample = false, updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid and kind = p_kind;
    else
      insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = console.ops_records.data || excluded.data,
         active = excluded.active, sample = false, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;

-- The planner prefers the company's own plant standards over the sample ones
create or replace function public.kmr_capacity_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; hrm_ref uuid; std jsonb; hol jsonb; names jsonb;
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select data into std from console.ops_records where customer_id = cid and kind = 'plant_standards' and active order by sample, updated_at desc limit 1;
  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrm' and product_ref is not null;
  if hrm_ref is not null then
    select coalesce(jsonb_agg(to_char(holiday_date, 'YYYY-MM-DD') order by holiday_date), '[]'), coalesce(jsonb_object_agg(to_char(holiday_date, 'YYYY-MM-DD'), name), '{}')
      into hol, names from hrm.holidays where tenant_id = hrm_ref;
  end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'cell', coalesce(r.data ->> 'cell', r.data ->> 'type', ''),
        'availDays', nullif(r.data ->> 'available_days', '')::numeric, 'hoursPerDay', nullif(r.data ->> 'hours_per_day', '')::numeric,
        'remarks', coalesce(r.data ->> 'remarks', ''), 'active', r.active) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines'), '[]'),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', row_number, 'partNo', x.part_no, 'partName', coalesce(p.name, x.part_no),
        'process', x.name, 'machine', x.machine, 'cycleTime', x.ct, 'alternates',
        coalesce((select jsonb_agg(trim(a)) from unnest(string_to_array(coalesce(x.alts, ''), ',')) a where trim(a) <> ''), '[]')) order by x.part_no, x.code)
      from (select row_number() over (order by r.data ->> 'part_no', r.code) row_number, r.code, r.name, r.data ->> 'part_no' part_no, r.data ->> 'machine' machine,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct, r.data ->> 'alternates' alts
              from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active) x
      left join console.ops_records p on p.customer_id = cid and p.kind = 'parts' and p.code = x.part_no), '[]'),
    'standards', coalesce(std, '{}'), 'holidays', coalesce(hol, '[]'), 'holidayNames', coalesce(names, '{}'),
    'has_hrm', hrm_ref is not null);
end $$;
revoke all on function public.kmr_capacity_masters(uuid) from public, anon;
grant execute on function public.kmr_capacity_masters(uuid) to authenticated;


-- =====================================================================
-- migrations/0018_billing.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Milestone 4: prices, invoices and (test) payments. Needs 0001–0005. Safe to re-run.
--  • Price list: per product, per billing period (month / year) and currency — a price per user / employee
--    and a minimum number billed.
--  • Seller details (GSTIN, state, SAC, bank / UPI, invoice prefix) in console.billing_settings.
--  • Invoices: drafted from the price list, GST worked out automatically (CGST + SGST in the same state, IGST
--    across states, zero-rated export under LUT abroad, none when no GSTIN is set), numbered without gaps per
--    financial year when issued (KMR/26-27/0001). Issued invoices are never deleted — only cancelled.
--  • Payments: Razorpay Checkout through each invoice's pay link (test or live keys) or recorded by hand
--    (bank transfer, cheque…). A paid invoice renews the customer's licences: active, end date = end of the
--    paid period, limit = users / employees paid for.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.console_export()') is null then raise exception 'Run 0005_data_tools.sql first.'; end if;
end $$;
create extension if not exists pgcrypto;

-- ---------- tables ----------
create table if not exists console.prices (
  id           uuid primary key default gen_random_uuid(),
  product_code text not null references console.products(code) on delete cascade,
  period       text not null check (period in ('month','year')),
  currency     text not null check (currency ~ '^[A-Z]{3}$'),
  unit_amount  numeric(12,2) not null check (unit_amount >= 0),
  min_seats    integer not null default 1 check (min_seats between 1 and 100000),
  active       boolean not null default true,
  note         text check (length(note) <= 300),
  updated_at   timestamptz not null default now(),
  unique (product_code, period, currency)
);

create table if not exists console.billing_settings (
  id             boolean primary key default true check (id),
  legal_name     text not null default 'KMR Group of Companies',
  gstin          text check (gstin is null or gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  pan            text,
  address        text,
  city           text,
  state          text,
  state_code     text check (state_code is null or state_code ~ '^[0-9]{2}$'),
  postal_code    text,
  email          text,
  phone          text,
  invoice_prefix text not null default 'KMR' check (invoice_prefix ~ '^[A-Z0-9-]{1,10}$'),
  sac_code       text not null default '998314',
  gst_rate       numeric(5,2) not null default 18 check (gst_rate between 0 and 40),
  lut_no         text,
  bank_details   text,
  upi_id         text,
  payment_days   integer not null default 15 check (payment_days between 0 and 120),
  terms          text,
  updated_at     timestamptz not null default now()
);
insert into console.billing_settings (id) values (true) on conflict (id) do nothing;

create table if not exists console.invoice_counters (fy text primary key, last_no integer not null default 0);

create table if not exists console.invoices (
  id               uuid primary key default gen_random_uuid(),
  number           text unique,
  customer_id      uuid not null references console.customers(id) on delete restrict,
  status           text not null default 'draft' check (status in ('draft','issued','paid','cancelled')),
  period           text check (period in ('month','year')),
  currency         text not null check (currency ~ '^[A-Z]{3}$'),
  issue_date       date,
  due_date         date,
  tax_type         text not null default 'none' check (tax_type in ('cgst_sgst','igst','export','none')),
  gst_rate         numeric(5,2) not null default 0,
  subtotal         numeric(12,2) not null default 0,
  cgst             numeric(12,2) not null default 0,
  sgst             numeric(12,2) not null default 0,
  igst             numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0,
  seller           jsonb not null default '{}',
  buyer            jsonb not null default '{}',
  notes            text check (length(notes) <= 2000),
  pay_token        text not null unique default replace(gen_random_uuid()::text, '-', '') || substr(md5(random()::text), 1, 4),
  paid_at          timestamptz,
  cancelled_reason text,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists invoices_customer on console.invoices (customer_id, created_at desc);

create table if not exists console.invoice_lines (
  id           bigserial primary key,
  invoice_id   uuid not null references console.invoices(id) on delete cascade,
  sort         integer not null default 0,
  product_code text references console.products(code),
  description  text not null check (length(description) between 1 and 300),
  period_from  date,
  period_to    date,
  qty          numeric(12,2) not null check (qty > 0),
  unit_amount  numeric(12,2) not null check (unit_amount >= 0),
  amount       numeric(12,2) not null
);
create index if not exists invoice_lines_invoice on console.invoice_lines (invoice_id, sort);

create table if not exists console.payments (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references console.invoices(id) on delete restrict,
  provider    text not null check (provider in ('razorpay','manual')),
  mode        text not null default 'test' check (mode in ('test','live')),
  order_id    text unique,
  payment_id  text unique,
  amount      numeric(12,2) not null,
  currency    text not null,
  status      text not null default 'created' check (status in ('created','paid','failed')),
  reference   text,
  detail      jsonb,
  recorded_by uuid,
  created_at  timestamptz not null default now(),
  paid_at     timestamptz
);
create index if not exists payments_invoice on console.payments (invoice_id, created_at desc);

-- ---------- security: staff read everything; managers edit prices and seller details; all invoice and
-- payment changes go through the functions below ----------
alter table console.prices enable row level security;
alter table console.billing_settings enable row level security;
alter table console.invoice_counters enable row level security;
alter table console.invoices enable row level security;
alter table console.invoice_lines enable row level security;
alter table console.payments enable row level security;
do $$ declare t text; begin
  foreach t in array array['prices','billing_settings','invoices','invoice_lines','payments'] loop
    execute format('drop policy if exists %I on console.%I', t || '_read', t);
    execute format('create policy %I on console.%I for select to authenticated using (console.is_staff())', t || '_read', t);
  end loop;
  foreach t in array array['prices','billing_settings'] loop
    execute format('drop policy if exists %I on console.%I', t || '_write', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_manager()) with check (console.is_manager())', t || '_write', t);
  end loop;
end $$;
revoke all on console.prices, console.billing_settings, console.invoice_counters, console.invoices, console.invoice_lines, console.payments from anon;

-- ---------- helpers ----------
-- Indian financial year of a date: 2026-09-30 → '26-27', 2027-02-01 → '26-27'
create or replace function console.fin_year(d date) returns text language sql immutable as $$
  select case when extract(month from d) >= 4
    then to_char(d, 'YY') || '-' || to_char(d + interval '1 year', 'YY')
    else to_char(d - interval '1 year', 'YY') || '-' || to_char(d, 'YY') end
$$;

create or replace function console.require_manager() returns void language plpgsql stable security definer set search_path = console, public as $$
begin
  if not console.is_manager() then raise exception 'Only an owner or administrator can do this.'; end if;
end $$;

-- Recalculate a draft's tax and totals from its lines, the customer and the seller details
create or replace function console.invoice_recalc(p_id uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; sub numeric; tt text; buyer_code text; rate numeric;
begin
  select * into inv from console.invoices where id = p_id for update;
  if inv.status <> 'draft' then return; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  sub := coalesce((select sum(amount) from console.invoice_lines where invoice_id = p_id), 0);
  buyer_code := case when coalesce(c.tax_id, '') ~ '^[0-9]{2}[A-Z0-9]{13}$' then left(c.tax_id, 2) end;
  tt := case
    when c.country <> 'IN' then 'export'
    when s.gstin is null or s.gst_rate = 0 then 'none'
    when buyer_code is not null then case when buyer_code = coalesce(s.state_code, left(s.gstin, 2)) then 'cgst_sgst' else 'igst' end
    when nullif(trim(c.state), '') is not null and nullif(trim(s.state), '') is not null then
         case when lower(trim(c.state)) = lower(trim(s.state)) then 'cgst_sgst' else 'igst' end
    else 'cgst_sgst' end;
  rate := case when tt in ('cgst_sgst','igst') then s.gst_rate else 0 end;
  update console.invoices set subtotal = sub, tax_type = tt, gst_rate = rate,
    cgst = case when tt = 'cgst_sgst' then round(sub * rate / 200, 2) else 0 end,
    sgst = case when tt = 'cgst_sgst' then round(sub * rate / 200, 2) else 0 end,
    igst = case when tt = 'igst' then round(sub * rate / 100, 2) else 0 end,
    updated_at = now()
   where id = p_id;
  update console.invoices set total = subtotal + cgst + sgst + igst where id = p_id;
end $$;

-- ---------- invoices (owners / administrators) ----------
-- New draft from the price list. p_items = [{"product_code":"hrm","seats":40}, …]
create or replace function console.create_invoice(p_customer uuid, p_period text, p_from date, p_items jsonb, p_notes text default null) returns uuid
language plpgsql security definer set search_path = console, public as $$
declare c console.customers; it jsonb; pr console.prices; prod console.products; q numeric; inv uuid; n int := 0; pto date;
begin
  perform console.require_manager();
  select * into c from console.customers where id = p_customer;
  if c.id is null then raise exception 'Customer not found.'; end if;
  if p_period not in ('month','year') then raise exception 'Choose monthly or yearly billing.'; end if;
  if p_from is null then raise exception 'Choose the date the billed period starts.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Pick at least one product to bill.'; end if;
  pto := (p_from + case when p_period = 'year' then interval '1 year' else interval '1 month' end - interval '1 day')::date;
  insert into console.invoices (customer_id, period, currency, notes, created_by)
  values (c.id, p_period, c.currency, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()) returning id into inv;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into prod from console.products where code = it ->> 'product_code';
    if prod.code is null then raise exception 'Unknown product %.', it ->> 'product_code'; end if;
    select * into pr from console.prices where product_code = prod.code and period = p_period and currency = c.currency and active;
    if pr.id is null then
      raise exception 'There is no % price in % for %. Add it under Prices & invoices first.', case when p_period = 'year' then 'yearly' else 'monthly' end, c.currency, prod.name;
    end if;
    q := greatest(coalesce(nullif(it ->> 'seats', '')::numeric, 0), pr.min_seats);
    n := n + 1;
    insert into console.invoice_lines (invoice_id, sort, product_code, description, period_from, period_to, qty, unit_amount, amount)
    values (inv, n, prod.code, prod.name || ' — ' || case when p_period = 'year' then 'yearly' else 'monthly' end || ' subscription, ' || q::int || ' ' || prod.seat_label,
            p_from, pto, q, pr.unit_amount, round(q * pr.unit_amount, 2));
  end loop;
  perform console.invoice_recalc(inv);
  return inv;
end $$;

-- An extra line on a draft (set-up, training, discount as a negative amount is not allowed — lower the price instead)
create or replace function console.add_invoice_line(p_invoice uuid, p_description text, p_qty numeric, p_unit_amount numeric) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then raise exception 'Only a draft invoice can be changed.'; end if;
  if length(trim(coalesce(p_description, ''))) = 0 then raise exception 'Describe the line.'; end if;
  if coalesce(p_qty, 0) <= 0 or coalesce(p_unit_amount, -1) < 0 then raise exception 'Quantity must be above 0 and the rate 0 or more.'; end if;
  insert into console.invoice_lines (invoice_id, sort, description, qty, unit_amount, amount)
  values (p_invoice, coalesce((select max(sort) from console.invoice_lines where invoice_id = p_invoice), 0) + 1, trim(p_description), p_qty, p_unit_amount, round(p_qty * p_unit_amount, 2));
  perform console.invoice_recalc(p_invoice);
end $$;

create or replace function console.remove_invoice_line(p_invoice uuid, p_line bigint) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then raise exception 'Only a draft invoice can be changed.'; end if;
  delete from console.invoice_lines where id = p_line and invoice_id = p_invoice;
  perform console.invoice_recalc(p_invoice);
end $$;

create or replace function console.discard_invoice(p_invoice uuid) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then
    raise exception 'Only a draft can be discarded. Cancel an issued invoice instead — its number stays in the series.';
  end if;
  delete from console.invoices where id = p_invoice;
end $$;

-- Issue: next number in the financial year, seller and buyer details frozen on the invoice
create or replace function console.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; v_fy text; n int; num text;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'draft' then raise exception 'This invoice is already %.', inv.status; end if;
  if not exists (select 1 from console.invoice_lines where invoice_id = p_invoice) then raise exception 'The invoice has no lines.'; end if;
  perform console.invoice_recalc(p_invoice);
  select * into inv from console.invoices where id = p_invoice;
  if inv.total <= 0 then raise exception 'The invoice total must be above zero.'; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  if nullif(trim(coalesce(s.address, '')), '') is null then raise exception 'Fill in your seller details (address) under Prices & invoices before issuing.'; end if;
  v_fy := console.fin_year(current_date);
  insert into console.invoice_counters (fy, last_no) values (v_fy, 1)
  on conflict (fy) do update set last_no = console.invoice_counters.last_no + 1 returning last_no into n;
  num := s.invoice_prefix || '/' || v_fy || '/' || lpad(n::text, 4, '0');
  update console.invoices set number = num, status = 'issued', issue_date = current_date, due_date = current_date + s.payment_days,
    seller = jsonb_build_object('legal_name', s.legal_name, 'gstin', s.gstin, 'pan', s.pan, 'address', s.address, 'city', s.city, 'state', s.state,
      'state_code', coalesce(s.state_code, left(s.gstin, 2)), 'postal_code', s.postal_code, 'email', s.email, 'phone', s.phone, 'sac_code', s.sac_code,
      'lut_no', s.lut_no, 'bank_details', s.bank_details, 'upi_id', s.upi_id, 'terms', s.terms),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;

create or replace function console.cancel_invoice(p_invoice uuid, p_reason text) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be cancelled.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for cancelling.'; end if;
  update console.invoices set status = 'cancelled', cancelled_reason = trim(p_reason), updated_at = now() where id = p_invoice;
end $$;

-- Paid: invoice closed, licences renewed for the paid period and users / employees
create or replace function console.apply_paid_invoice(p_invoice uuid, p_paid_at timestamptz) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; ln record;
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
  end loop;
  update console.customers set status = 'active', updated_at = now() where id = inv.customer_id and status in ('lead','pilot');
end $$;
revoke all on function console.apply_paid_invoice(uuid, timestamptz), console.invoice_recalc(uuid) from public, anon, authenticated;

-- Payment received outside Razorpay (bank transfer, cheque, UPI to the bank account…)
create or replace function console.mark_invoice_paid(p_invoice uuid, p_reference text, p_date date default current_date) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice;
  if inv.status is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be marked paid.'; end if;
  if length(trim(coalesce(p_reference, ''))) < 3 then raise exception 'Enter the payment reference (UTR, cheque no. …).'; end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, recorded_by, paid_at)
  values (p_invoice, 'manual', 'live', inv.total, inv.currency, 'paid', trim(p_reference), auth.uid(), coalesce(p_date, current_date)::timestamptz);
  perform console.apply_paid_invoice(p_invoice, coalesce(p_date, current_date)::timestamptz);
end $$;

-- ---------- the public pay link (called by the Console server with the service key only) ----------
create or replace function console.invoice_for_token(p_token text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('invoice', to_jsonb(i) - 'created_by', 'lines',
           coalesce((select jsonb_agg(to_jsonb(l) order by l.sort, l.id) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
           'paid_by', (select jsonb_build_object('provider', p.provider, 'mode', p.mode, 'payment_id', p.payment_id, 'reference', p.reference, 'paid_at', p.paid_at)
                         from console.payments p where p.invoice_id = i.id and p.status = 'paid' order by p.paid_at desc limit 1))
    from console.invoices i where i.pay_token = p_token and i.status in ('issued','paid','cancelled') and length(p_token) >= 20
$$;

create or replace function console.razorpay_order_started(p_token text, p_order_id text, p_mode text, p_amount numeric, p_currency text) returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices;
begin
  select * into inv from console.invoices where pay_token = p_token;
  if inv.status is distinct from 'issued' then raise exception 'This invoice cannot be paid (it is %).', coalesce(inv.status, 'not found'); end if;
  if p_amount <> inv.total or p_currency <> inv.currency then raise exception 'Amount does not match the invoice.'; end if;
  insert into console.payments (invoice_id, provider, mode, order_id, amount, currency)
  values (inv.id, 'razorpay', case when p_mode = 'live' then 'live' else 'test' end, p_order_id, p_amount, p_currency);
end $$;

-- A Razorpay payment whose signature the server has verified. Safe to call twice (checkout + webhook).
create or replace function console.razorpay_payment_verified(p_order_id text, p_payment_id text, p_detail jsonb default null) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare pay console.payments;
begin
  select * into pay from console.payments where order_id = p_order_id and provider = 'razorpay' for update;
  if pay.id is null then raise exception 'Unknown Razorpay order.'; end if;
  if pay.status <> 'paid' then
    update console.payments set status = 'paid', payment_id = p_payment_id, detail = p_detail, paid_at = now() where id = pay.id;
    perform console.apply_paid_invoice(pay.invoice_id, now());
  end if;
  return jsonb_build_object('invoice_id', pay.invoice_id, 'status', (select status from console.invoices where id = pay.invoice_id));
end $$;

revoke all on function console.invoice_for_token(text), console.razorpay_order_started(text, text, text, numeric, text),
  console.razorpay_payment_verified(text, text, jsonb) from public, anon, authenticated;
grant execute on function console.invoice_for_token(text), console.razorpay_order_started(text, text, text, numeric, text),
  console.razorpay_payment_verified(text, text, jsonb) to service_role;

-- ---------- customer portal: a company's invoices, for its administrators ----------
create or replace function public.kmr_portal_invoices(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can see invoices.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('number', number, 'issue_date', issue_date, 'due_date', due_date, 'total', total, 'currency', currency,
            'status', status, 'pay_token', pay_token) order by issue_date desc, number desc)
          from console.invoices where customer_id = cid and status in ('issued','paid','cancelled')), '[]');
end $$;
revoke all on function public.kmr_portal_invoices(text) from public, anon;
grant execute on function public.kmr_portal_invoices(text) to authenticated;

-- ---------- backups include billing ----------
create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['products','customers','licences','licence_events','releases','tickets','ticket_messages','leads','staff',
                           'prices','billing_settings','invoice_counters','invoices','invoice_lines','payments'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from console.%I x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;
revoke all on function console.console_export() from public, anon, authenticated;
grant execute on function console.console_export() to service_role;

-- ---------- Console sample data: flushing the demo customers also removes their invoices and payments ----------
create or replace function console.demo_flush() returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare n integer;
begin
  delete from console.payments where invoice_id in (select i.id from console.invoices i join console.customers c on c.id = i.customer_id where c.source = 'KMR demo data');
  delete from console.invoices where customer_id in (select id from console.customers where source = 'KMR demo data');
  delete from console.tickets where raised_by_email like '%demo.kmr.test';
  delete from console.leads where email like '%demo.kmr.test';
  delete from console.customers where source = 'KMR demo data';
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function console.demo_flush() from public, anon, authenticated;
grant execute on function console.demo_flush() to service_role;


-- =====================================================================
-- migrations/0019_bank_payments.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — payments straight to KMR's bank account (replaces Razorpay). Needs 0018. Safe to re-run.
--  • Seller details get the bank account as separate fields (account name, number, IFSC, bank, branch, type,
--    SWIFT for customers abroad) and a UPI ID; they are frozen on each invoice when it is issued.
--  • The customer pays by NEFT / RTGS / IMPS / UPI / cheque using the details on the invoice's pay link, then
--    reports it there ("I've paid": method, UTR / reference, date, amount).
--  • KMR checks the bank statement and Confirms (invoice paid, licences renewed) or Rejects (with a reason).
--    Payments can still be recorded directly with Mark as paid.
-- =====================================================================
do $$ begin
  if to_regclass('console.invoices') is null then raise exception 'Run 0018_billing.sql first.'; end if;
end $$;

-- ---------- bank account in the seller details ----------
alter table console.billing_settings
  add column if not exists bank_account_name text,
  add column if not exists bank_account_no   text check (bank_account_no is null or bank_account_no ~ '^[0-9]{6,20}$'),
  add column if not exists bank_ifsc         text check (bank_ifsc is null or bank_ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  add column if not exists bank_name         text,
  add column if not exists bank_branch       text,
  add column if not exists bank_account_type text,
  add column if not exists bank_swift        text check (bank_swift is null or bank_swift ~ '^[A-Z0-9]{8}([A-Z0-9]{3})?$');

-- ---------- payments: reported by the customer, confirmed or rejected by KMR ----------
alter table console.payments drop constraint if exists payments_provider_check;
alter table console.payments add constraint payments_provider_check check (provider in ('manual','bank_transfer','upi','cheque','razorpay'));
alter table console.payments drop constraint if exists payments_status_check;
alter table console.payments add constraint payments_status_check check (status in ('created','reported','paid','failed','rejected'));
alter table console.payments
  add column if not exists method        text check (method is null or method in ('neft','rtgs','imps','upi','cheque','other')),
  add column if not exists paid_on       date,
  add column if not exists payer_name    text check (payer_name is null or length(payer_name) <= 120),
  add column if not exists reject_reason text;
alter table console.payments alter column mode set default 'live';

drop function if exists console.razorpay_order_started(text, text, text, numeric, text);
drop function if exists console.razorpay_payment_verified(text, text, jsonb);

-- Issue: the bank account is frozen on the invoice with the other seller details
create or replace function console.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; v_fy text; n int; num text;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'draft' then raise exception 'This invoice is already %.', inv.status; end if;
  if not exists (select 1 from console.invoice_lines where invoice_id = p_invoice) then raise exception 'The invoice has no lines.'; end if;
  perform console.invoice_recalc(p_invoice);
  select * into inv from console.invoices where id = p_invoice;
  if inv.total <= 0 then raise exception 'The invoice total must be above zero.'; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  if nullif(trim(coalesce(s.address, '')), '') is null then raise exception 'Fill in your seller details (address) under Prices & invoices before issuing.'; end if;
  if s.bank_account_no is null and s.upi_id is null and nullif(trim(coalesce(s.bank_details, '')), '') is null then
    raise exception 'Add your bank account (or UPI ID) under Prices & invoices › Seller details, so the customer knows where to pay.';
  end if;
  v_fy := console.fin_year(current_date);
  insert into console.invoice_counters (fy, last_no) values (v_fy, 1)
  on conflict (fy) do update set last_no = console.invoice_counters.last_no + 1 returning last_no into n;
  num := s.invoice_prefix || '/' || v_fy || '/' || lpad(n::text, 4, '0');
  update console.invoices set number = num, status = 'issued', issue_date = current_date, due_date = current_date + s.payment_days,
    seller = jsonb_build_object('legal_name', s.legal_name, 'gstin', s.gstin, 'pan', s.pan, 'address', s.address, 'city', s.city, 'state', s.state,
      'state_code', coalesce(s.state_code, left(s.gstin, 2)), 'postal_code', s.postal_code, 'email', s.email, 'phone', s.phone, 'sac_code', s.sac_code,
      'lut_no', s.lut_no, 'bank_details', s.bank_details, 'upi_id', s.upi_id, 'terms', s.terms,
      'bank_account_name', s.bank_account_name, 'bank_account_no', s.bank_account_no, 'bank_ifsc', s.bank_ifsc, 'bank_name', s.bank_name,
      'bank_branch', s.bank_branch, 'bank_account_type', s.bank_account_type, 'bank_swift', s.bank_swift),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;

-- Payment recorded directly by KMR (bank statement, cheque …)
drop function if exists console.mark_invoice_paid(uuid, text, date);
create or replace function console.mark_invoice_paid(p_invoice uuid, p_reference text, p_date date default current_date, p_method text default 'neft') returns void
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; m text := coalesce(nullif(p_method, ''), 'neft');
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice;
  if inv.status is distinct from 'issued' then raise exception 'Only an issued, unpaid invoice can be marked paid.'; end if;
  if length(trim(coalesce(p_reference, ''))) < 3 then raise exception 'Enter the payment reference (UTR, cheque no. …).'; end if;
  if m not in ('neft','rtgs','imps','upi','cheque','other') then raise exception 'Unknown payment method.'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'The payment date cannot be in the future.'; end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, method, paid_on, recorded_by, paid_at)
  values (p_invoice, case m when 'upi' then 'upi' when 'cheque' then 'cheque' else 'bank_transfer' end, 'live', inv.total, inv.currency, 'paid',
          trim(p_reference), m, coalesce(p_date, current_date), auth.uid(), coalesce(p_date, current_date)::timestamptz);
  update console.payments set status = 'rejected', reject_reason = 'Invoice paid — recorded separately' where invoice_id = p_invoice and status = 'reported';
  perform console.apply_paid_invoice(p_invoice, coalesce(p_date, current_date)::timestamptz);
end $$;

-- The customer reports a payment on the pay link (called by the Console server with the service key only)
create or replace function console.report_payment(p_token text, p_method text, p_reference text, p_paid_on date, p_amount numeric, p_payer text default null) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; ref text := upper(regexp_replace(trim(coalesce(p_reference, '')), '\s+', ' ', 'g'));
begin
  select * into inv from console.invoices where pay_token = p_token and length(p_token) >= 20;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'issued' then raise exception 'This invoice is %, so no payment can be reported.', inv.status; end if;
  if coalesce(p_method, '') not in ('neft','rtgs','imps','upi','cheque','other') then raise exception 'Choose how you paid.'; end if;
  if length(ref) not between 4 and 60 then raise exception 'Enter the UTR / transaction reference from your bank (4 to 60 characters).'; end if;
  if p_paid_on is null or p_paid_on > current_date + 1 or p_paid_on < current_date - 180 then raise exception 'Enter the date you paid.'; end if;
  if coalesce(p_amount, 0) <= 0 or p_amount > inv.total * 2 then raise exception 'Enter the amount you paid.'; end if;
  if exists (select 1 from console.payments where invoice_id = inv.id and upper(reference) = ref and status in ('reported','paid')) then
    raise exception 'This reference has already been reported for this invoice. KMR will confirm it shortly.';
  end if;
  if (select count(*) from console.payments where invoice_id = inv.id and status = 'reported') >= 5 then
    raise exception 'Several payments are already waiting for confirmation. Please contact KMR.';
  end if;
  insert into console.payments (invoice_id, provider, mode, amount, currency, status, reference, method, paid_on, payer_name)
  values (inv.id, case p_method when 'upi' then 'upi' when 'cheque' then 'cheque' else 'bank_transfer' end, 'live', round(p_amount, 2), inv.currency,
          'reported', ref, p_method, p_paid_on, nullif(left(trim(coalesce(p_payer, '')), 120), ''));
  return 'ok';
end $$;

-- KMR found the money in the bank: invoice paid, licences renewed
create or replace function console.confirm_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare pay console.payments;
begin
  perform console.require_manager();
  select * into pay from console.payments where id = p_payment for update;
  if pay.status is distinct from 'reported' then raise exception 'Only a reported payment can be confirmed.'; end if;
  if (select status from console.invoices where id = pay.invoice_id) <> 'issued' then raise exception 'The invoice is no longer waiting for payment.'; end if;
  update console.payments set status = 'paid', recorded_by = auth.uid(), paid_at = coalesce(pay.paid_on, current_date)::timestamptz where id = p_payment;
  update console.payments set status = 'rejected', reject_reason = 'Invoice paid — another payment was confirmed'
   where invoice_id = pay.invoice_id and status = 'reported' and id <> p_payment;
  perform console.apply_paid_invoice(pay.invoice_id, coalesce(pay.paid_on, current_date)::timestamptz);
end $$;

create or replace function console.reject_payment(p_payment uuid, p_reason text) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.payments where id = p_payment) is distinct from 'reported' then raise exception 'Only a reported payment can be rejected.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason, e.g. "not received in the bank".'; end if;
  update console.payments set status = 'rejected', reject_reason = trim(p_reason), recorded_by = auth.uid() where id = p_payment;
end $$;

-- The pay link now also shows payments the customer reported
create or replace function console.invoice_for_token(p_token text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('invoice', to_jsonb(i) - 'created_by', 'lines',
           coalesce((select jsonb_agg(to_jsonb(l) order by l.sort, l.id) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
           'paid_by', (select jsonb_build_object('provider', p.provider, 'method', p.method, 'reference', p.reference, 'paid_at', p.paid_at)
                         from console.payments p where p.invoice_id = i.id and p.status = 'paid' order by p.paid_at desc limit 1),
           'reported', coalesce((select jsonb_agg(jsonb_build_object('method', p.method, 'reference', p.reference, 'amount', p.amount, 'paid_on', p.paid_on,
                         'status', p.status, 'reject_reason', p.reject_reason, 'created_at', p.created_at) order by p.created_at desc)
                         from console.payments p where p.invoice_id = i.id and p.status in ('reported','rejected') and p.created_at > now() - interval '60 days'), '[]'))
    from console.invoices i where i.pay_token = p_token and i.status in ('issued','paid','cancelled') and length(p_token) >= 20
$$;

revoke all on function console.invoice_for_token(text), console.report_payment(text, text, text, date, numeric, text) from public, anon, authenticated;
grant execute on function console.invoice_for_token(text), console.report_payment(text, text, text, date, numeric, text) to service_role;

-- Customer portal: show when a payment is waiting for KMR's confirmation
create or replace function public.kmr_portal_invoices(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can see invoices.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('number', i.number, 'issue_date', i.issue_date, 'due_date', i.due_date, 'total', i.total, 'currency', i.currency,
            'status', i.status, 'pay_token', i.pay_token,
            'reported', exists (select 1 from console.payments p where p.invoice_id = i.id and p.status = 'reported')) order by i.issue_date desc, i.number desc)
          from console.invoices i where i.customer_id = cid and i.status in ('issued','paid','cancelled')), '[]');
end $$;
revoke all on function public.kmr_portal_invoices(text) from public, anon;
grant execute on function public.kmr_portal_invoices(text) to authenticated;


-- =====================================================================
-- migrations/0020_seller_identity.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — seller identity on invoices. Needs 0019. Safe to re-run.
--  • Seller details: trade name (the name invoices lead with) and legal name, constitution, Udyam (MSME)
--    number and category, website, authorised signatory, and the company seal + signature images.
--  • Seal and signature files live in a PRIVATE storage bucket (kmr-billing); invoices show them through
--    short-lived links only.
--  • MSME note on invoices (MSMED Act, 2006 — payment within the agreed period, at most 45 days), switchable.
--  • Issued invoices now freeze the complete seller details, so every field added here reaches them.
-- =====================================================================
do $$ begin
  if to_regprocedure('console.report_payment(text, text, text, date, numeric, text)') is null then raise exception 'Run 0019_bank_payments.sql first.'; end if;
end $$;

alter table console.billing_settings
  add column if not exists trade_name      text,
  add column if not exists constitution    text,
  add column if not exists udyam_no        text check (udyam_no is null or udyam_no ~ '^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$'),
  add column if not exists msme_category   text check (msme_category is null or msme_category in ('Micro','Small','Medium')),
  add column if not exists website         text,
  add column if not exists signatory_name  text,
  add column if not exists signatory_title text,
  add column if not exists seal_path       text,
  add column if not exists signature_path  text,
  add column if not exists show_seal       boolean not null default true,
  add column if not exists show_msme_note  boolean not null default true;

-- Private files: seal and signature (uploaded by the Console server after checking the staff member)
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-billing', 'kmr-billing', false, 2097152) on conflict (id) do nothing;

-- Everything an invoice needs to show about the seller, frozen when it is issued
create or replace function console.seller_snapshot() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select (to_jsonb(s) - 'id' - 'updated_at' - 'invoice_prefix' - 'payment_days' - 'gst_rate')
         || jsonb_build_object('state_code', coalesce(s.state_code, left(s.gstin, 2)))
    from console.billing_settings s where s.id
$$;
revoke all on function console.seller_snapshot() from public, anon, authenticated;

create or replace function console.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare inv console.invoices; c console.customers; s console.billing_settings; v_fy text; n int; num text;
begin
  perform console.require_manager();
  select * into inv from console.invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.status <> 'draft' then raise exception 'This invoice is already %.', inv.status; end if;
  if not exists (select 1 from console.invoice_lines where invoice_id = p_invoice) then raise exception 'The invoice has no lines.'; end if;
  perform console.invoice_recalc(p_invoice);
  select * into inv from console.invoices where id = p_invoice;
  if inv.total <= 0 then raise exception 'The invoice total must be above zero.'; end if;
  select * into c from console.customers where id = inv.customer_id;
  select * into s from console.billing_settings where id;
  if nullif(trim(coalesce(s.address, '')), '') is null then raise exception 'Fill in your seller details (address) under Prices & invoices before issuing.'; end if;
  if s.bank_account_no is null and s.upi_id is null and nullif(trim(coalesce(s.bank_details, '')), '') is null then
    raise exception 'Add your bank account (or UPI ID) under Prices & invoices › Seller details, so the customer knows where to pay.';
  end if;
  v_fy := console.fin_year(current_date);
  insert into console.invoice_counters (fy, last_no) values (v_fy, 1)
  on conflict (fy) do update set last_no = console.invoice_counters.last_no + 1 returning last_no into n;
  num := s.invoice_prefix || '/' || v_fy || '/' || lpad(n::text, 4, '0');
  update console.invoices set number = num, status = 'issued', issue_date = current_date, due_date = current_date + s.payment_days,
    seller = console.seller_snapshot(),
    buyer = jsonb_build_object('code', c.code, 'name', coalesce(nullif(c.legal_name, ''), c.name), 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
      'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email),
    updated_at = now()
   where id = p_invoice;
  return num;
end $$;


-- =====================================================================
-- migrations/0021_website.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — manages the website (replaces the website's own /admin). Needs 0020. Safe to re-run.
--  • Enquiries: the "Pilot requests" inbox now takes every enquiry from the website — software pilots, training,
--    import & export, trading, distribution and shop questions — with the business and product it is about.
--  • Software catalogue for the website: the Console's products with their INR prices (public, read-only).
-- =====================================================================
do $$ begin
  if to_regprocedure('console.seller_snapshot()') is null then raise exception 'Run 0020_seller_identity.sql first.'; end if;
end $$;

-- ---------- enquiries ----------
alter table console.leads drop constraint if exists leads_company_check;
alter table console.leads alter column company drop not null;
alter table console.leads
  add column if not exists business     text not null default 'software',
  add column if not exists product_name text,
  add column if not exists quantity     text,
  add column if not exists notes        text;
alter table console.leads drop constraint if exists leads_business_check;
alter table console.leads add constraint leads_business_check check (business in ('software','shop','training','import_export','trading','distribution','general'));
alter table console.leads drop constraint if exists leads_status_check;
alter table console.leads add constraint leads_status_check check (status in ('new','contacted','quoted','converted','dropped'));

-- ---------- software catalogue (website Software page) ----------
create or replace function public.kmr_software_catalog() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'description', p.description, 'app_path', p.app_path,
           'seat_label', p.seat_label, 'version', p.current_version,
           'prices', coalesce((select jsonb_agg(jsonb_build_object('period', x.period, 'amount', x.unit_amount, 'min', x.min_seats) order by x.period)
                                from console.prices x where x.product_code = p.code and x.active and x.currency = 'INR'), '[]'))
         order by p.sort_order), '[]')
    from console.products p where p.active
$$;
grant execute on function public.kmr_software_catalog() to anon, authenticated;

-- Customer Operations Master data is the customer's confidential data: it is never copied to the website.
drop function if exists console.publish_ops_products(uuid, text[], text);

-- ---------- private storage for compliance documents (Console › Website › Compliance) ----------
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-records', 'kmr-records', false, 10485760) on conflict (id) do nothing;


-- =====================================================================
-- migrations/0022_hardening.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Milestone 5: hardening. Needs 0021. Safe to re-run.
--  • Rate limits for logins, forms and payment reports (public.kmr_rate_ok, server only)
--  • Activity log: who changed invoices, payments, prices, staff, licences, orders and website content (triggers)
--  • Error log (with de-duplication, so one alert per error per hour) and email log
--  • Backups: the Console backup now also covers customer users, platform settings and all website data;
--    a second nightly file covers the apps' data (Operations Master, Balloon Inspector, Process Documents,
--    Capacity Planner). Both are kept 30 days.
-- =====================================================================
do $$ begin
  if to_regclass('console.leads') is null or to_regprocedure('console.console_export()') is null then
    raise exception 'Run the earlier Console migrations (up to 0021) first.';
  end if;
end $$;

-- ---------- rate limits ----------
create table if not exists console.rate_hits (
  key  text not null,
  at   timestamptz not null default now()
);
create index if not exists rate_hits_key_at on console.rate_hits (key, at desc);
create table if not exists console.rate_blocks (
  key   text primary key,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  blocked  integer not null default 1
);
alter table console.rate_hits enable row level security;
alter table console.rate_blocks enable row level security;

-- true = allowed (and counted); false = over the limit for this window
create or replace function public.kmr_rate_ok(p_key text, p_max integer, p_window_seconds integer) returns boolean
language plpgsql security definer set search_path = console, public as $$
declare n integer; k text := left(coalesce(p_key, ''), 200);
begin
  if k = '' then return true; end if;
  delete from console.rate_hits where key = k and at < now() - make_interval(secs => p_window_seconds);
  if random() < 0.02 then delete from console.rate_hits where at < now() - interval '1 day'; end if;
  select count(*) into n from console.rate_hits where key = k;
  if n >= p_max then
    insert into console.rate_blocks (key) values (k)
    on conflict (key) do update set last_at = now(), blocked = console.rate_blocks.blocked + 1;
    return false;
  end if;
  insert into console.rate_hits (key) values (k);
  return true;
end $$;
revoke all on function public.kmr_rate_ok(text, integer, integer) from public, anon, authenticated;
grant execute on function public.kmr_rate_ok(text, integer, integer) to service_role;

-- ---------- activity log ----------
create table if not exists console.audit_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  actor     text,
  tbl       text not null,
  row_id    text,
  action    text not null check (action in ('insert','update','delete')),
  changes   jsonb
);
create index if not exists audit_log_at on console.audit_log (at desc);
create index if not exists audit_log_tbl on console.audit_log (tbl, at desc);
alter table console.audit_log enable row level security;

create or replace function console.audit_row() returns trigger
language plpgsql security definer set search_path = console, public as $$
declare
  who text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email',
                       nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user);
  o jsonb; n jsonb; diff jsonb := '{}'::jsonb; k text;
  skip text[] := array['updated_at','created_at','search','fts'];
begin
  if tg_op = 'INSERT' then
    n := to_jsonb(new);
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, n ->> 'id', 'insert', n - skip);
    return new;
  elsif tg_op = 'DELETE' then
    o := to_jsonb(old);
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, o ->> 'id', 'delete', o - skip);
    return old;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  for k in select jsonb_object_keys(n) loop
    if not (k = any(skip)) and (o -> k) is distinct from (n -> k) then
      diff := diff || jsonb_build_object(k, jsonb_build_array(o -> k, n -> k));
    end if;
  end loop;
  if diff <> '{}'::jsonb then
    insert into console.audit_log (actor, tbl, row_id, action, changes)
    values (who, tg_table_schema || '.' || tg_table_name, coalesce(n ->> 'id', n ->> 'code', n ->> 'user_id'), 'update', diff);
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'console.staff','console.customers','console.licences','console.prices','console.billing_settings',
    'console.invoices','console.invoice_lines','console.payments','console.platform_settings',
    'public.orders','public.products','public.company_info','public.legal_pages','public.site_settings','public.verticals',
    'public.hero_slides','public.site_stats','public.home_points','public.product_benefits','public.job_openings',
    'public.job_applications','public.leaders','public.gallery_items','public.compliance_records'] loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists kmr_audit on %s', t);
      execute format('create trigger kmr_audit after insert or update or delete on %s for each row execute function console.audit_row()', t);
    end if;
  end loop;
end $$;

-- ---------- error log (one alert per error per hour) ----------
create table if not exists console.app_errors (
  id       bigserial primary key,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  app      text not null,
  path     text,
  message  text not null,
  digest   text,
  detail   text,
  count    integer not null default 1
);
create index if not exists app_errors_last on console.app_errors (last_at desc);
alter table console.app_errors enable row level security;

-- returns true when this is a new error (or the same error again after an hour) — the caller then sends one alert
create or replace function public.kmr_log_error(p_app text, p_path text, p_message text, p_digest text default null, p_detail text default null) returns boolean
language plpgsql security definer set search_path = console, public as $$
declare e console.app_errors; msg text := left(coalesce(p_message, 'Unknown error'), 1000);
begin
  select * into e from console.app_errors
   where app = left(p_app, 40) and message = msg and coalesce(path, '') = coalesce(left(p_path, 300), '')
   order by last_at desc limit 1;
  if e.id is not null and e.last_at > now() - interval '1 hour' then
    update console.app_errors set count = count + 1, last_at = now() where id = e.id;
    return false;
  end if;
  insert into console.app_errors (app, path, message, digest, detail)
  values (left(p_app, 40), left(p_path, 300), msg, left(p_digest, 100), left(p_detail, 4000));
  delete from console.app_errors where last_at < now() - interval '90 days';
  return true;
end $$;
revoke all on function public.kmr_log_error(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.kmr_log_error(text, text, text, text, text) to service_role;

-- ---------- email log ----------
create table if not exists console.email_log (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  app     text not null,
  kind    text not null,
  to_addr text not null,
  subject text,
  status  text not null check (status in ('sent','skipped','failed')),
  error   text,
  ref     text
);
create index if not exists email_log_at on console.email_log (at desc);
alter table console.email_log enable row level security;

-- ---------- backups ----------
create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['console.products','console.customers','console.customer_members','console.licences','console.licence_events',
                           'console.releases','console.tickets','console.ticket_messages','console.leads','console.staff',
                           'console.prices','console.billing_settings','console.invoice_counters','console.invoices','console.invoice_lines',
                           'console.payments','console.platform_settings',
                           'public.company_info','public.site_settings','public.verticals','public.hero_slides','public.site_stats',
                           'public.home_points','public.product_benefits','public.products','public.orders','public.legal_pages',
                           'public.job_openings','public.job_applications','public.leaders','public.gallery_items','public.compliance_records',
                           'public.hero_content'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 2, 'exported_at', now(), 'tables', out);
end $fn$;

-- the customers' app data (kept separate: it can be large, and it is the customers' own data)
create or replace function console.apps_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['console.ops_records','public.bi_orgs','public.bi_members','public.bi_reports','public.pd_orgs','public.pd_members',
                           'public.pd_projects','public.pd_masters','public.cp_orgs','public.cp_members','public.cp_plans'] loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-apps-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;
revoke all on function console.console_export(), console.apps_export() from public, anon, authenticated;
grant execute on function console.console_export(), console.apps_export() to service_role;
update storage.buckets set file_size_limit = 209715200 where id = 'kmr-backups';


-- =====================================================================
-- migrations/0023_test_data.sql
-- =====================================================================
-- =====================================================================
-- KMR Console — Test data tools (Console › Test data). Needs 0022. Safe to re-run.
--  • Settings backup: KMR's own settings and website content as one JSON file (download / upload to restore)
--  • Full backup: every table of every KMR app, saved to kmr-backups before any clean-out
--  • Clean out: removes customers, orders, app workspaces, HR records and logs — keeps KMR staff, products,
--    prices, seller details, platform settings and all website content
--  • Demo Operations Master for the demo customer
-- All functions are server-only (service role). The Console checks that the person is the owner first.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_rate_ok(text,integer,integer)') is null then
    raise exception 'Run 0022_hardening.sql first.';
  end if;
end $$;

-- invoice pay links: built-in random (no pgcrypto needed — it lives in another schema on Supabase)
alter table console.invoices alter column pay_token set default (replace(gen_random_uuid()::text, '-', '') || substr(md5(random()::text), 1, 4));

-- ---------- settings kept through a clean-out (restore order: parents first) ----------
create or replace function console.settings_tables() returns text[] language sql immutable as $$
  select array['console.products','console.prices','console.releases','console.billing_settings','console.platform_settings',
               'public.company_info','public.site_settings','public.verticals','public.hero_slides','public.hero_content',
               'public.site_stats','public.home_points','public.product_benefits','public.legal_pages','public.leaders',
               'public.gallery_items','public.compliance_records','public.products','public.job_openings']
$$;

create or replace function console.settings_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb; st jsonb;
begin
  foreach t in array console.settings_tables() loop
    if to_regclass(t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %s x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  -- staff for reference only (logins cannot be moved between projects, so a restore never touches staff)
  select coalesce(jsonb_agg(jsonb_build_object('email', email, 'full_name', full_name, 'role', role, 'active', active)), '[]') into st from console.staff;
  return jsonb_build_object('format', 'kmr-settings', 'version', 1, 'exported_at', now(), 'tables', out, 'staff', st);
end $fn$;

-- upsert rows into a table by its primary key, using only the columns present in the file
create or replace function console.upsert_rows(p_table text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare cols text[]; pk text[]; sets text; n integer := 0; rel regclass := to_regclass(p_table);
begin
  if rel is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return 0; end if;
  select array_agg(a.attname order by a.attnum) into cols
    from pg_attribute a
   where a.attrelid = rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     and exists (select 1 from jsonb_array_elements(p_rows) r where r ? a.attname);
  select array_agg(a.attname) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
   where i.indrelid = rel and i.indisprimary;
  if cols is null or pk is null or not (pk <@ cols) then raise exception 'Cannot restore %: the file has no id column for it.', p_table; end if;
  select string_agg(format('%I = excluded.%I', c, c), ', ') into sets from unnest(cols) c where not (c = any(pk));
  execute format('insert into %s (%s) select %s from jsonb_populate_recordset(null::%s, $1) on conflict (%s) do %s',
                 rel, (select string_agg(quote_ident(c), ', ') from unnest(cols) c), (select string_agg(quote_ident(c), ', ') from unnest(cols) c),
                 rel, (select string_agg(quote_ident(c), ', ') from unnest(pk) c),
                 case when sets is null then 'nothing' else 'update set ' || sets end)
    using p_rows;
  get diagnostics n = row_count;
  return n;
end $fn$;

create or replace function console.settings_import(p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $fn$
declare t text; n integer; out jsonb := '{}'::jsonb;
begin
  if p_data ->> 'format' is distinct from 'kmr-settings' then raise exception 'This is not a KMR settings file (Console › Test data › Download settings).'; end if;
  foreach t in array console.settings_tables() loop
    if to_regclass(t) is null or not (p_data -> 'tables' ? t) then continue; end if;
    n := console.upsert_rows(t, p_data -> 'tables' -> t);
    out := out || jsonb_build_object(t, n);
  end loop;
  return out;
end $fn$;

-- ---------- full backup: every table of every app ----------
create or replace function console.full_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; r record; rows jsonb;
begin
  for r in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where c.relkind = 'r' and n.nspname in ('console','public','hrm')
              and c.relname not in ('rate_hits','rate_blocks') order by 1, 2 loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from %I.%I x', r.nspname, r.relname) into rows;
    out := out || jsonb_build_object(r.nspname || '.' || r.relname, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-full-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;


-- pause / resume the apps' own row rules (e.g. "at least one admin must remain") during a deliberate removal
create or replace function console.app_triggers(p_prefix text, p_on boolean) returns void
language plpgsql security definer set search_path = console, public as $fn$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind = 'r' and c.relname ~ ('^(' || p_prefix || ')_')
              and exists (select 1 from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) loop
    execute format('alter table public.%I %s trigger user', r.relname, case when p_on then 'enable' else 'disable' end);
  end loop;
end $fn$;

-- ---------- clean out ----------
-- p_parts: customers | shop | catalogue | apps | logs.  p_keep_hrm: the HRM company to keep (KMR's own), by short name.
create or replace function console.platform_flush(p_parts text[], p_keep_hrm text default null) returns jsonb
language plpgsql security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; n integer; r record; keep uuid[]; w integer := 0;
begin
  if 'customers' = any(p_parts) then
    delete from console.payments;        get diagnostics n = row_count; out := out || jsonb_build_object('payments', n);
    delete from console.invoice_lines;
    delete from console.invoices;        get diagnostics n = row_count; out := out || jsonb_build_object('invoices', n);
    update console.invoice_counters set last_no = 0;
    delete from console.ticket_messages;
    delete from console.tickets;         get diagnostics n = row_count; out := out || jsonb_build_object('tickets', n);
    delete from console.leads;           get diagnostics n = row_count; out := out || jsonb_build_object('enquiries', n);
    delete from console.customers;       get diagnostics n = row_count; out := out || jsonb_build_object('customers', n);   -- + licences, users, Operations Master
  end if;

  if 'shop' = any(p_parts) then
    if to_regclass('public.orders') is not null then delete from public.orders; get diagnostics n = row_count; out := out || jsonb_build_object('orders', n); end if;
    if to_regclass('public.job_applications') is not null then delete from public.job_applications; get diagnostics n = row_count; out := out || jsonb_build_object('applications', n); end if;
  end if;

  if 'catalogue' = any(p_parts) then
    if to_regclass('public.orders') is not null then delete from public.orders; end if;
    if to_regclass('public.job_applications') is not null then delete from public.job_applications; end if;
    if to_regclass('public.products') is not null then delete from public.products; get diagnostics n = row_count; out := out || jsonb_build_object('website_products', n); end if;
    if to_regclass('public.job_openings') is not null then delete from public.job_openings; get diagnostics n = row_count; out := out || jsonb_build_object('job_openings', n); end if;
  end if;

  if 'apps' = any(p_parts) then
    perform console.app_triggers('bi|pd|cp', false);
    -- Balloon Inspector, Process Documents, Capacity Planner: everything under each workspace, then the workspaces
    for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
              where s.nspname = 'public' and c.relkind = 'r' and c.relname ~ '^(bi|pd|cp)_' and c.relname !~ '(_orgs|_platform_admins)$' loop
      execute format('delete from public.%I', r.relname);
    end loop;
    for r in select unnest(array['bi_orgs','pd_orgs','cp_orgs']) t loop
      if to_regclass('public.' || r.t) is not null then execute format('delete from public.%I', r.t); get diagnostics n = row_count; w := w + n; end if;
    end loop;
    out := out || jsonb_build_object('app_workspaces', w);
    perform console.app_triggers('bi|pd|cp', true);
    -- the HRM change-log would try to record rows of companies being deleted: pause it for this transaction only
    for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
              where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
      execute format('alter table %s disable trigger %I', r.rel, r.tgname);
    end loop;
    -- HRM: every company except KMR's own; KMR's own keeps its settings and administrators, loses employees and HR records
    select coalesce(array_agg(id), '{}') into keep from hrm.tenants
     where (p_keep_hrm is not null and slug = lower(p_keep_hrm))
        or id in (select tenant_id from hrm.app_users where role = 'platform_admin');
    delete from hrm.tenants where not (id = any(keep)); get diagnostics n = row_count; out := out || jsonb_build_object('hrm_companies', n);
    delete from hrm.app_users where tenant_id = any(keep) and employee_id is not null and role not in ('platform_admin','company_admin');
    update hrm.app_users set employee_id = null where tenant_id = any(keep);
    delete from hrm.onboarding_invites where tenant_id = any(keep);
    delete from hrm.attendance_punches where tenant_id = any(keep);
    delete from hrm.attendance_days where tenant_id = any(keep);
    delete from hrm.regularisation_requests where tenant_id = any(keep);
    delete from hrm.leave_ledger where tenant_id = any(keep);
    delete from hrm.leave_requests where tenant_id = any(keep);
    if to_regclass('hrm.payroll_runs') is not null then delete from hrm.payroll_runs where tenant_id = any(keep); end if;
    if to_regclass('hrm.loans') is not null then delete from hrm.loans where tenant_id = any(keep); end if;
    delete from hrm.employees where tenant_id = any(keep); get diagnostics n = row_count; out := out || jsonb_build_object('hrm_employees_of_kmr', n);
    delete from hrm.notifications where tenant_id = any(keep);
    delete from hrm.audit_log where tenant_id = any(keep);
    update hrm.tenants set emp_code_seq = 0 where id = any(keep);
    for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
              where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
      execute format('alter table %s enable trigger %I', r.rel, r.tgname);
    end loop;
  end if;

  if 'logs' = any(p_parts) then
    delete from console.audit_log; delete from console.email_log; delete from console.app_errors;
    delete from console.rate_hits; delete from console.rate_blocks;
    out := out || jsonb_build_object('logs', 'cleared');
  end if;
  return out;
end $fn$;

-- logins nobody uses any more (after a clean-out): the Console deletes them through the Supabase admin API
drop function if exists console.orphan_logins();
create or replace function console.orphan_logins() returns table (user_id uuid, email text)
language plpgsql stable security definer set search_path = console, public, auth as $fn$
-- builds the "still in use" list only from tables and columns that exist in this project (the apps differ slightly)
declare ids uuid[] := '{}'; mails text[] := '{}'; t text; c text; more uuid[]; m text[];
begin
  foreach t in array array['console.staff','hrm.app_users','console.customer_members','public.staff_profiles',
                           'public.bi_platform_admins','public.pd_platform_admins','public.bi_members','public.pd_members','public.cp_members'] loop
    if to_regclass(t) is null then continue; end if;
    foreach c in array array['user_id','id'] loop
      if exists (select 1 from pg_attribute where attrelid = to_regclass(t) and attname = c and not attisdropped and atttypid = 'uuid'::regtype)
         and not (c = 'id' and t in ('console.customer_members')) then
        execute format('select coalesce(array_agg(%I), ''{}'') from %s', c, t) into more;
        ids := ids || more;
      end if;
    end loop;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(t) and attname = 'email' and not attisdropped) then
      execute format('select coalesce(array_agg(lower(email::text)), ''{}'') from %s', t) into m;
      mails := mails || m;
    end if;
  end loop;
  return query select u.id, u.email::text from auth.users u
    where not (u.id = any(ids)) and not (lower(coalesce(u.email, '')) = any(mails));
end $fn$;

-- ---------- demo: Operations Master sample for one customer ----------
create or replace function console.ops_demo_load(p_customer uuid) returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare r jsonb; n integer := 0; k integer;
begin
  for r in select * from jsonb_array_elements(console.ops_sample()) loop
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (p_customer, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), console.ops_sample_dates(r -> 'data'), true, true, 'KMR demo data')
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;

revoke all on function console.settings_tables(), console.settings_export(), console.upsert_rows(text, jsonb), console.settings_import(jsonb),
  console.full_export(), console.platform_flush(text[], text), console.orphan_logins(), console.ops_demo_load(uuid) from public, anon, authenticated;
grant execute on function console.settings_tables(), console.settings_export(), console.upsert_rows(text, jsonb), console.settings_import(jsonb),
  console.full_export(), console.platform_flush(text[], text), console.orphan_logins(), console.ops_demo_load(uuid) to service_role;

-- ---------- delete one HRM company / one app workspace (used to remove the demo) ----------
create or replace function console.hrm_delete_company(p_tenant uuid) returns boolean
language plpgsql security definer set search_path = console, public as $fn$
declare r record; n integer;
begin
  for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
            where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
    execute format('alter table %s disable trigger %I', r.rel, r.tgname);
  end loop;
  delete from hrm.tenants where id = p_tenant; get diagnostics n = row_count;
  for r in select t.tgrelid::regclass::text rel, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
            where p.proname = 'audit_row' and p.pronamespace = 'hrm'::regnamespace and not t.tgisinternal loop
    execute format('alter table %s enable trigger %I', r.rel, r.tgname);
  end loop;
  return n > 0;
end $fn$;

create or replace function console.workspace_delete(p_product text, p_id uuid) returns boolean
language plpgsql security definer set search_path = console, public as $fn$
declare pre text := case p_product when 'balloon' then 'bi' when 'pd' then 'pd' when 'capacity' then 'cp' end; r record; n integer;
begin
  if pre is null then raise exception 'Unknown product %', p_product; end if;
  perform console.app_triggers(pre, false);
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid
            where s.nspname = 'public' and c.relkind = 'r' and c.relname like pre || '\_%' and c.relname <> pre || '_orgs'
              and a.attname = 'org_id' and not a.attisdropped loop
    execute format('delete from public.%I where org_id = $1', r.relname) using p_id;
  end loop;
  execute format('delete from public.%I where id = $1', pre || '_orgs') using p_id;
  get diagnostics n = row_count;
  perform console.app_triggers(pre, true);
  return n > 0;
end $fn$;
revoke all on function console.app_triggers(text, boolean), console.hrm_delete_company(uuid), console.workspace_delete(text, uuid) from public, anon, authenticated;
grant execute on function console.app_triggers(text, boolean), console.hrm_delete_company(uuid), console.workspace_delete(text, uuid) to service_role;


-- =====================================================================
-- migrations/0024_ops_links.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Process Documents uses the Operations Master. Needs 0015–0017. Safe to re-run.
--  • kmr_pd_masters(workspace): the customer's machines, gauges, customers and parts, in Process Documents' own format
--  • kmr_pd_push_masters(workspace, lists): one-time move of lists typed into Process Documents (fills only what is missing)
-- Customers' Operations Master data stays theirs: only members of that customer's own workspace can read it.
-- =====================================================================
do $$ begin
  if to_regclass('console.ops_records') is null then raise exception 'Run 0015_operations_master.sql first.'; end if;
end $$;

-- the signed-in person's role in a Process Documents workspace (null = not a member)
create or replace function public.kmr_pd_role(p_org uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select coalesce(
    (select m.role from public.pd_members m where m.org_id = p_org and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', '')) limit 1),
    (select 'admin' from public.pd_platform_admins a where a.user_id = auth.uid() limit 1))
$$;

-- Operations Master machine type → the process codes Process Documents plans with
create or replace function console.pd_keys_for(p_type text, p_processes text) returns jsonb
language sql immutable as $$
  select case
    when coalesce(trim(p_processes), '') <> '' then
      (select coalesce(jsonb_agg(upper(trim(x))), '[]') from unnest(string_to_array(p_processes, ',')) x where trim(x) <> '')
    when p_type ilike 'cnc turning%' then '["TURN1","TURN2"]'::jsonb
    when p_type in ('VMC','HMC') then '["VMC"]'::jsonb
    when p_type ilike 'grinding%' then '["CGRIND"]'::jsonb
    when p_type ilike 'gear hobbing%' then '["HOB"]'::jsonb
    when p_type ilike 'broaching%' then '["BROACH"]'::jsonb
    when p_type ilike 'inspection%' then '["FINAL"]'::jsonb
    else '[]'::jsonb end
$$;

create or replace function public.kmr_pd_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  if public.kmr_pd_role(p_org) is null then raise exception 'No access to this workspace.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then return null; end if;                       -- a workspace not linked to a customer keeps its own lists
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'make', coalesce(r.data ->> 'make', ''), 'model', coalesce(r.data ->> 'model', ''),
        'capacity', coalesce(r.data ->> 'capacity', ''), 'keys', console.pd_keys_for(r.data ->> 'type', r.data ->> 'processes'),
        'maxDia', nullif(r.data ->> 'max_size_mm', '')::numeric, 'cap', nullif(r.data ->> 'capability_mm', '')::numeric,
        'location', coalesce(nullif(r.data ->> 'cell', ''), r.data ->> 'location', ''), 'pm', coalesce(r.data ->> 'pm_frequency', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.active and coalesce(r.data ->> 'status', '') <> 'Scrapped'), '[]'),
    'gauges', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'range', coalesce(r.data ->> 'range', ''), 'lc', coalesce(r.data ->> 'least_count', ''),
        'calFreq', case when coalesce(r.data ->> 'cal_freq_months', '') <> '' then (r.data ->> 'cal_freq_months') || ' months' else '' end,
        'calDue', coalesce(r.data ->> 'next_due', ''), 'location', coalesce(r.data ->> 'location', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'gauges' and r.active), '[]'),
    'customers', coalesce((select jsonb_agg(jsonb_build_object(
        'name', r.name, 'code', coalesce(r.data ->> 'supplier_code', ''),
        'address', concat_ws(', ', nullif(r.data ->> 'address', ''), nullif(r.data ->> 'city', ''), nullif(r.data ->> 'country', '')),
        'contact', concat_ws(' / ', nullif(r.data ->> 'contact', ''), nullif(r.data ->> 'email', '')),
        'ccSym', coalesce(r.data ->> 'cc_symbol', ''), 'scSym', coalesce(r.data ->> 'sc_symbol', ''), 'approval', coalesce(r.data ->> 'approval', '')) order by r.name)
      from console.ops_records r where r.customer_id = cid and r.kind = 'customers' and r.active), '[]'),
    'parts', coalesce((select jsonb_agg(jsonb_build_object(
        'partNo', r.code, 'partName', r.name, 'drawingNo', coalesce(r.data ->> 'drawing_no', ''), 'rev', coalesce(r.data ->> 'revision', ''),
        'material', coalesce(r.data ->> 'material', ''), 'customer', coalesce(r.data ->> 'customer', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'));
end $$;
revoke all on function public.kmr_pd_masters(uuid) from public, anon;
grant execute on function public.kmr_pd_masters(uuid) to authenticated;

-- One-time move: lists typed into Process Documents go to the Operations Master (workspace admins; fills only what is missing)
create or replace function public.kmr_pd_push_masters(p_org uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); x jsonb; nm int := 0; ng int := 0; nc int := 0; k int; v_code text;
begin
  if public.kmr_pd_role(p_org) is distinct from 'admin' then raise exception 'Only a workspace administrator can move the lists.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then raise exception 'This workspace is not linked to a KMR customer.'; end if;
  for x in select * from jsonb_array_elements(coalesce(p -> 'machines', '[]')) loop
    v_code := left(coalesce(nullif(trim(x ->> 'id'), ''), nullif(trim(x ->> 'name'), '')), 80);
    continue when v_code is null;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'machines', v_code, left(coalesce(x ->> 'name', v_code), 200), jsonb_strip_nulls(jsonb_build_object(
      'make', nullif(x ->> 'make', ''), 'model', nullif(x ->> 'model', ''), 'capacity', nullif(x ->> 'capacity', ''),
      'processes', nullif(case when jsonb_typeof(x -> 'keys') = 'array' then array_to_string(array(select jsonb_array_elements_text(x -> 'keys')), ', ') else x ->> 'keys' end, ''),
      'max_size_mm', nullif(x ->> 'maxDia', ''), 'capability_mm', nullif(x ->> 'cap', ''), 'cell', nullif(x ->> 'location', ''), 'pm_frequency', nullif(x ->> 'pm', ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; nm := nm + k;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p -> 'gauges', '[]')) loop
    v_code := left(coalesce(nullif(trim(x ->> 'id'), ''), nullif(trim(x ->> 'name'), '')), 80);
    continue when v_code is null;
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'gauges', v_code, left(coalesce(x ->> 'name', v_code), 200), jsonb_strip_nulls(jsonb_build_object(
      'range', nullif(x ->> 'range', ''), 'least_count', nullif(x ->> 'lc', ''), 'location', nullif(x ->> 'location', ''),
      'next_due', case when (x ->> 'calDue') ~ '^\d{4}-\d{2}-\d{2}$' then x ->> 'calDue' end,
      'cal_freq_months', nullif(substring(coalesce(x ->> 'calFreq', '') from '(\d+)'), ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; ng := ng + k;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p -> 'customers', '[]')) loop
    v_code := left(upper(regexp_replace(coalesce(nullif(trim(x ->> 'name'), ''), ''), '[^A-Za-z0-9]+', '-', 'g')), 40);
    continue when coalesce(v_code, '') = '';
    insert into console.ops_records (customer_id, kind, code, name, data, updated_by)
    values (cid, 'customers', v_code, left(x ->> 'name', 200), jsonb_strip_nulls(jsonb_build_object(
      'supplier_code', nullif(x ->> 'code', ''), 'address', nullif(x ->> 'address', ''), 'contact', nullif(x ->> 'contact', ''),
      'cc_symbol', nullif(x ->> 'ccSym', ''), 'sc_symbol', nullif(x ->> 'scSym', ''), 'approval', nullif(x ->> 'approval', ''))), me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics k = row_count; nc := nc + k;
  end loop;
  return jsonb_build_object('machines', nm, 'gauges', ng, 'customers', nc);
end $$;
revoke all on function public.kmr_pd_push_masters(uuid, jsonb) from public, anon;
grant execute on function public.kmr_pd_push_masters(uuid, jsonb) to authenticated;
revoke all on function public.kmr_pd_role(uuid) from public, anon;
grant execute on function public.kmr_pd_role(uuid) to authenticated;


-- =====================================================================
-- migrations/0025_ops_sample_per_list.sql
-- =====================================================================
-- =====================================================================
-- Operations Master — sample data per list, and consumables by process. Needs 0024. Safe to re-run.
--  • kmr_ops_sample_load(slug, kind) / kmr_ops_sample_flush(slug, kind): load or flush ONE list's sample records
--    (the whole-master versions stay: kmr_ops_sample_load(slug) / kmr_ops_sample_flush(slug))
--  • kmr_ops_counts adds the sample count of every list ("_sample_<list>")
--  • Consumables carry "processes" (Process Documents codes such as TURN1, VMC); Process Documents lists them per process
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_pd_masters(uuid)') is null then raise exception 'Run 0024_ops_links.sql first.'; end if;
end $$;

-- which processes the sample consumables are used in
create or replace function console.ops_sample_processes(p_code text) returns text language sql immutable as $$
  select case p_code
    when 'CN-001' then 'TURN1, TURN2, VMC, DRILL, HOB, BROACH'
    when 'CN-002' then 'TURN1, TURN2, VMC, HOB'
    when 'CN-003' then 'TURN1, TURN2, VMC, CGRIND'
    when 'CN-004' then 'CGRIND, IGRIND, SGRIND'
    when 'CN-005' then 'TURN1, TURN2, VMC, DEBURR'
    when 'CN-006' then 'WASH, PACK'
    when 'CN-007' then 'PACK'
    when 'CN-008' then 'DEBURR, WASH, FINAL, PACK'
  end
$$;

create or replace function console.ops_sample_insert(p_customer uuid, p_kind text, p_by text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare r jsonb; added int := 0; skipped int := 0; n int; d jsonb;
begin
  for r in select * from jsonb_array_elements(console.ops_sample()) x where p_kind is null or x ->> 'kind' = p_kind loop
    if r ->> 'kind' = 'plant_standards'
       and exists (select 1 from console.ops_records where customer_id = p_customer and kind = 'plant_standards' and not sample) then
      skipped := skipped + 1; continue;
    end if;
    d := console.ops_sample_dates(r -> 'data');
    if r ->> 'kind' = 'consumables' and console.ops_sample_processes(r ->> 'code') is not null and not (d ? 'processes') then
      d := d || jsonb_build_object('processes', console.ops_sample_processes(r ->> 'code'));
    end if;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (p_customer, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), d, true, true, p_by)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics n = row_count;
    if n = 1 then added := added + 1; else skipped := skipped + 1; end if;
  end loop;
  return jsonb_build_object('added', added, 'skipped', skipped);
end $$;

create or replace function console.ops_admin_customer(p_slug text) returns uuid
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  return cid;
end $$;

-- whole master (unchanged behaviour, now with consumable processes)
create or replace function public.kmr_ops_sample_load(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
begin
  return console.ops_sample_insert(console.ops_admin_customer(p_slug), null, lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;

-- one list
create or replace function public.kmr_ops_sample_load(p_slug text, p_kind text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
begin
  return console.ops_sample_insert(console.ops_admin_customer(p_slug), p_kind, lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;

create or replace function public.kmr_ops_sample_flush(p_slug text, p_kind text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); n int;
begin
  delete from console.ops_records where customer_id = cid and kind = p_kind and sample;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.kmr_ops_sample_load(text), public.kmr_ops_sample_load(text, text), public.kmr_ops_sample_flush(text, text) from public, anon;
grant execute on function public.kmr_ops_sample_load(text), public.kmr_ops_sample_load(text, text), public.kmr_ops_sample_flush(text, text) to authenticated;
revoke all on function console.ops_sample_insert(uuid, text, text), console.ops_admin_customer(text) from public, anon, authenticated;

-- counts: records in use per list, sample records in total and per list
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || coalesce((select jsonb_object_agg('_sample_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and sample group by kind) y), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- Console › Test data demo loader uses the same sample (with consumable processes)
create or replace function console.ops_demo_load(p_customer uuid) returns integer
language plpgsql security definer set search_path = console, public as $$
begin
  return (console.ops_sample_insert(p_customer, null, 'KMR demo data') ->> 'added')::int;
end $$;
revoke all on function console.ops_demo_load(uuid) from public, anon, authenticated;
grant execute on function console.ops_demo_load(uuid) to service_role;

-- sample consumables already loaded get their processes too
update console.ops_records set data = data || jsonb_build_object('processes', console.ops_sample_processes(code))
 where kind = 'consumables' and sample and not (data ? 'processes') and console.ops_sample_processes(code) is not null;

-- Process Documents: consumables grouped by process (from each consumable's "processes")
create or replace function public.kmr_pd_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  if public.kmr_pd_role(p_org) is null then raise exception 'No access to this workspace.'; end if;
  select customer_id into cid from console.licences where product_code = 'pd' and product_ref = p_org;
  if cid is null then return null; end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'make', coalesce(r.data ->> 'make', ''), 'model', coalesce(r.data ->> 'model', ''),
        'capacity', coalesce(r.data ->> 'capacity', ''), 'keys', console.pd_keys_for(r.data ->> 'type', r.data ->> 'processes'),
        'maxDia', nullif(r.data ->> 'max_size_mm', '')::numeric, 'cap', nullif(r.data ->> 'capability_mm', '')::numeric,
        'location', coalesce(nullif(r.data ->> 'cell', ''), r.data ->> 'location', ''), 'pm', coalesce(r.data ->> 'pm_frequency', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.active and coalesce(r.data ->> 'status', '') <> 'Scrapped'), '[]'),
    'gauges', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.code, 'name', r.name, 'range', coalesce(r.data ->> 'range', ''), 'lc', coalesce(r.data ->> 'least_count', ''),
        'calFreq', case when coalesce(r.data ->> 'cal_freq_months', '') <> '' then (r.data ->> 'cal_freq_months') || ' months' else '' end,
        'calDue', coalesce(r.data ->> 'next_due', ''), 'location', coalesce(r.data ->> 'location', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'gauges' and r.active), '[]'),
    'customers', coalesce((select jsonb_agg(jsonb_build_object(
        'name', r.name, 'code', coalesce(r.data ->> 'supplier_code', ''),
        'address', concat_ws(', ', nullif(r.data ->> 'address', ''), nullif(r.data ->> 'city', ''), nullif(r.data ->> 'country', '')),
        'contact', concat_ws(' / ', nullif(r.data ->> 'contact', ''), nullif(r.data ->> 'email', '')),
        'ccSym', coalesce(r.data ->> 'cc_symbol', ''), 'scSym', coalesce(r.data ->> 'sc_symbol', ''), 'approval', coalesce(r.data ->> 'approval', '')) order by r.name)
      from console.ops_records r where r.customer_id = cid and r.kind = 'customers' and r.active), '[]'),
    'consumables', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'items', items) order by k) from (
        select upper(trim(p)) k, string_agg(r.name, E'\n' order by r.name) items
          from console.ops_records r, unnest(string_to_array(coalesce(r.data ->> 'processes', ''), ',')) p
         where r.customer_id = cid and r.kind = 'consumables' and r.active and trim(p) <> '' group by 1) c), '[]'),
    'parts', coalesce((select jsonb_agg(jsonb_build_object(
        'partNo', r.code, 'partName', r.name, 'drawingNo', coalesce(r.data ->> 'drawing_no', ''), 'rev', coalesce(r.data ->> 'revision', ''),
        'material', coalesce(r.data ->> 'material', ''), 'customer', coalesce(r.data ->> 'customer', '')) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'parts' and r.active), '[]'));
end $$;
revoke all on function public.kmr_pd_masters(uuid) from public, anon;
grant execute on function public.kmr_pd_masters(uuid) to authenticated;

-- Saving (form, CSV or Excel upload): a sample record stays "sample" unless something in it actually changed,
-- so uploading a downloaded workbook unchanged does not turn every sample record into your own.
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records o set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true),
             sample = o.sample and o.code = trim(r ->> 'code') and o.name = coalesce(trim(r ->> 'name'), '') and o.data = coalesce(r -> 'data', '{}')
                      and o.active = coalesce((r ->> 'active')::boolean, true),
             updated_at = now(), updated_by = me
       where o.id = (r ->> 'id')::uuid and o.customer_id = cid and o.kind = p_kind;
    else
      insert into console.ops_records as o (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = o.data || excluded.data, active = excluded.active,
         sample = o.sample and o.name = excluded.name and o.data @> excluded.data and o.active = excluded.active,
         updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;


-- =====================================================================
-- migrations/0026_data_master.sql
-- =====================================================================
-- =====================================================================
-- KMR Apps › Data Master (company administrators): per app — record counts, JSON download, JSON upload (restore),
-- and Flush all data (the portal downloads a JSON backup first). Needs 0025 (and HRM 0005). Safe to re-run.
-- Apps: hrm · balloon · pd · capacity · ops (Operations Master). Logins, users and access are never removed;
-- Balloon Inspector drawing files are kept so a restore brings reports back complete.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_ops_sample_load(text,text)') is null then raise exception 'Run 0025_ops_sample_per_list.sql first.'; end if;
end $$;

-- the customer and the app's workspace, for a company administrator only
create or replace function console.data_target(p_slug text, p_app text, out cid uuid, out ref uuid)
language plpgsql stable security definer set search_path = console, public as $$
begin
  select c.id into cid from console.customers c where c.slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  if p_app = 'ops' then ref := cid; return; end if;
  if p_app not in ('hrm','balloon','pd','capacity') then raise exception 'Unknown app %', p_app; end if;
  select l.product_ref into ref from console.licences l where l.customer_id = cid and l.product_code = p_app and l.product_ref is not null limit 1;
  if ref is null then raise exception 'Your company does not have this app yet.'; end if;
end $$;

-- data tables of a tool workspace (everything with org_id except the workspace, its users and platform admins)
create or replace function console.data_tables(p_app text) returns text[]
language sql stable security definer set search_path = console, public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r'
     and c.relname like (case p_app when 'balloon' then 'bi' when 'pd' then 'pd' when 'capacity' then 'cp' end) || '\_%'
     and c.relname !~ '_(orgs|members|platform_admins)$'
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'org_id' and not a.attisdropped)
$$;

-- ---------- HRM: remove a company's data (logins and the company itself stay) ----------
create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  select count(*) into emps from hrm.employees where tenant_id = p_tenant;
  if to_regclass('hrm.loan_recoveries') is not null then
    delete from hrm.loan_recoveries where tenant_id = p_tenant; delete from hrm.payroll_lines where tenant_id = p_tenant;
    delete from hrm.payroll_runs where tenant_id = p_tenant; delete from hrm.loans where tenant_id = p_tenant;
    delete from hrm.salary_structures where tenant_id = p_tenant;
  end if;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee';
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employee_private where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  if p_setup then
    delete from hrm.attendance_devices where tenant_id = p_tenant;
    delete from hrm.notification_templates where tenant_id = p_tenant;
    delete from hrm.leave_types where tenant_id = p_tenant;
    delete from hrm.holidays where tenant_id = p_tenant;
    delete from hrm.shifts where tenant_id = p_tenant;
    delete from hrm.designations where tenant_id = p_tenant;
    delete from hrm.departments where tenant_id = p_tenant;
    delete from hrm.plants where tenant_id = p_tenant;
    if to_regclass('hrm.pay_components') is not null then
      delete from hrm.pay_components where tenant_id = p_tenant; delete from hrm.pay_settings where tenant_id = p_tenant;
    end if;
    perform hrm.seed_tenant_defaults(p_tenant);
    if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(p_tenant); end if;
  end if;
  update hrm.tenants set emp_code_seq = 0 where id = p_tenant;
  delete from hrm.notifications where tenant_id = p_tenant;
  delete from hrm.audit_log where tenant_id = p_tenant;
  return jsonb_build_object('employees', emps, 'setup_reset', p_setup);
end $fn$;
revoke all on function hrm.company_flush(uuid, boolean) from public, anon, authenticated;

-- ---------- overview: what each app holds ----------
create or replace function public.kmr_data_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; l record; out jsonb := '[]'::jsonb; t text; n bigint; det jsonb; tot bigint;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  for l in select product_code, product_ref from console.licences where customer_id = cid and product_ref is not null
             and product_code in ('hrm','balloon','pd','capacity') order by array_position(array['hrm','balloon','pd','capacity'], product_code) loop
    det := '{}'; tot := 0;
    if l.product_code = 'hrm' then
      foreach t in array array['employees','attendance_days','leave_requests','payroll_runs','loans','id_cards','onboarding_invites'] loop
        if to_regclass('hrm.' || t) is null then continue; end if;
        execute format('select count(*) from hrm.%I where tenant_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    else
      foreach t in array console.data_tables(l.product_code) loop
        execute format('select count(*) from public.%I where org_id = $1', t) into n using l.product_ref;
        det := det || jsonb_build_object(t, n); tot := tot + n;
      end loop;
    end if;
    out := out || jsonb_build_array(jsonb_build_object('app', l.product_code, 'records', tot, 'detail', det));
  end loop;
  select count(*) into n from console.ops_records where customer_id = cid;
  out := out || jsonb_build_array(jsonb_build_object('app', 'ops', 'records', n, 'detail', jsonb_build_object('ops_records', n)));
  return out;
end $$;
grant execute on function public.kmr_data_overview(text) to authenticated;

-- ---------- JSON download ----------
create or replace function public.kmr_data_export(p_slug text, p_app text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; tabs jsonb := '{}';
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then
    tabs := jsonb_build_object('hrm', hrm.company_export(tg.ref));
  elsif p_app = 'ops' then
    select coalesce(jsonb_agg(to_jsonb(r) - 'customer_id' order by r.kind, r.code), '[]') into rows from console.ops_records r where r.customer_id = tg.cid;
    tabs := jsonb_build_object('ops_records', rows);
  else
    foreach t in array console.data_tables(p_app) loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x where x.org_id = $1', t) into rows using tg.ref;
      tabs := tabs || jsonb_build_object(t, rows);
    end loop;
  end if;
  return jsonb_build_object('format', 'kmr-app-data', 'version', 1, 'app', p_app, 'company', lower(p_slug), 'exported_at', now(), 'tables', tabs);
end $$;
grant execute on function public.kmr_data_export(text, text) to authenticated;

-- ---------- flush ----------
create or replace function console.data_clear(p_app text, p_cid uuid, p_ref uuid) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare t text; n bigint := 0; k bigint; pass int; left_ text[];
begin
  if p_app = 'ops' then
    delete from console.ops_records where customer_id = p_cid; get diagnostics n = row_count; return n;
  end if;
  if p_app = 'balloon' and to_regclass('public.pd_projects') is not null
     and exists (select 1 from pg_attribute where attrelid = 'public.pd_projects'::regclass and attname = 'bi_report_id' and not attisdropped) then
    execute 'update public.pd_projects set bi_report_id = null where bi_report_id in (select id from public.bi_reports where org_id = $1)' using p_ref;
  end if;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, false);
  left_ := console.data_tables(p_app);
  for pass in 1..4 loop                                   -- a few passes, so tables that point at each other clear in any order
    exit when cardinality(left_) = 0;
    foreach t in array left_ loop
      begin
        execute format('delete from public.%I where org_id = $1', t) using p_ref; get diagnostics k = row_count; n := n + k;
        left_ := array_remove(left_, t);
      exception when foreign_key_violation then null;
      end;
    end loop;
  end loop;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, true);
  if cardinality(left_) > 0 then raise exception 'Could not clear: % (linked records elsewhere).', array_to_string(left_, ', '); end if;
  return n;
end $$;
revoke all on function console.data_clear(text, uuid, uuid) from public, anon, authenticated;

create or replace function public.kmr_data_flush(p_slug text, p_app text, p_hrm_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record;
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then return hrm.company_flush(tg.ref, coalesce(p_hrm_setup, false)); end if;
  return jsonb_build_object('removed', console.data_clear(p_app, tg.cid, tg.ref));
end $$;
grant execute on function public.kmr_data_flush(text, text, boolean) to authenticated;

-- ---------- JSON upload (restore): replaces this app's data with the file's ----------
create or replace function public.kmr_data_import(p_slug text, p_app text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; n bigint; k bigint; tot bigint := 0; pass int; todo text[]; ok text[] := '{}';
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_data ->> 'format' is distinct from 'kmr-app-data' then raise exception 'This is not a KMR Data Master file.'; end if;
  if p_data ->> 'app' is distinct from p_app then raise exception 'This file is a backup of another app (%).', p_data ->> 'app'; end if;
  if p_app = 'hrm' then
    -- the HRM restore checks the backup belongs to this very company
    return jsonb_build_object('restored', hrm.company_import(tg.ref, p_data -> 'tables' -> 'hrm'));
  end if;
  perform console.data_clear(p_app, tg.cid, tg.ref);
  if p_app = 'ops' then
    rows := (select coalesce(jsonb_agg(r || jsonb_build_object('customer_id', tg.cid)), '[]') from jsonb_array_elements(coalesce(p_data -> 'tables' -> 'ops_records', '[]')) r);
    insert into console.ops_records select * from jsonb_populate_recordset(null::console.ops_records, rows) on conflict do nothing;
    get diagnostics n = row_count;
    return jsonb_build_object('restored', n);
  end if;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, false);
  todo := array(select x from unnest(console.data_tables(p_app)) x where (p_data -> 'tables') ? x);
  for pass in 1..4 loop
    exit when cardinality(todo) = 0;
    foreach t in array todo loop
      -- every row is put back into THIS company's workspace, whatever the file says
      rows := (select coalesce(jsonb_agg(r || jsonb_build_object('org_id', tg.ref)), '[]') from jsonb_array_elements(p_data -> 'tables' -> t) r);
      begin
        execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I, $1) on conflict do nothing', t, t) using rows;
        get diagnostics k = row_count; tot := tot + k; todo := array_remove(todo, t);
      exception when foreign_key_violation then null;
      end;
    end loop;
  end loop;
  perform console.app_triggers(case p_app when 'balloon' then 'bi' when 'pd' then 'pd' else 'cp' end, true);
  if cardinality(todo) > 0 then raise exception 'Could not restore: %.', array_to_string(todo, ', '); end if;
  return jsonb_build_object('restored', tot);
end $$;
grant execute on function public.kmr_data_import(text, text, jsonb) to authenticated;

revoke all on function console.data_target(text, text), console.data_tables(text) from public, anon, authenticated;


-- =====================================================================
-- migrations/0027_ops_card_actions.sql
-- =====================================================================
-- =====================================================================
-- Operations Master cards: per list — Load sample · Flush sample · Load data (JSON) · Flush data (your own records;
-- the portal downloads a JSON backup first). Plus a "Sample drawing" card that puts a ready-made drawing into the
-- company's Balloon Inspector. Needs 0026. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_data_overview(text)') is null then raise exception 'Run 0026_data_master.sql first.'; end if;
end $$;

-- counts: in use per list; sample and own (your) records per list; sample drawings in Balloon Inspector
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; bi uuid; nd bigint := null;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) from public.bi_reports where org_id = $1 and file_path like ''static:%''' into nd using bi;
  end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || coalesce((select jsonb_object_agg('_sample_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and sample group by kind) y), '{}')
      || coalesce((select jsonb_object_agg('_own_' || kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and not sample group by kind) z), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample),
                            '_has_balloon', bi is not null, '_drawings', coalesce(nd, 0));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- your own (non-sample) records of one list; the portal downloads them as JSON before calling this
create or replace function public.kmr_ops_flush_data(p_slug text, p_kind text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); n int;
begin
  delete from console.ops_records where customer_id = cid and kind = p_kind and not sample;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kmr_ops_flush_data(text, text) from public, anon;
grant execute on function public.kmr_ops_flush_data(text, text) to authenticated;

-- Sample drawing for Balloon Inspector: a report that points at a drawing kept on the website ("static:" path);
-- Balloon Inspector balloons it automatically when it is opened.
create or replace function public.kmr_ops_sample_drawing(p_slug text, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.ops_admin_customer(p_slug); bi uuid; n int := 0; cols text[]; vals jsonb; r jsonb;
begin
  select product_ref into bi from console.licences where customer_id = cid and product_code = 'balloon' and product_ref is not null limit 1;
  if bi is null then raise exception 'Balloon Inspector is not in your company''s plan.'; end if;
  if to_regclass('public.bi_reports') is null then raise exception 'Balloon Inspector is not set up in this database.'; end if;
  if p_action = 'flush' then
    execute 'delete from public.bi_reports where org_id = $1 and file_path like ''static:%''' using bi;
    get diagnostics n = row_count; return n;
  end if;
  if p_action <> 'load' then raise exception 'Unknown action.'; end if;
  for r in select * from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('title', 'Sample drawing — Mounting Plate', 'part_no', 'EX-2040', 'rev', 'B', 'drawing_no', 'EX-2040-DRG', 'customer', 'Sample customer',
                         'file_path', 'static:/it/balloon/samples/EX-2040_sample.dxf', 'file_name', 'EX-2040_sample.dxf'))) loop
    execute 'select count(*) from public.bi_reports where org_id = $1 and file_path = $2' into n using bi, r ->> 'file_path';
    continue when n > 0;
    -- only the columns this project's table has (the Balloon schema may differ slightly between projects)
    vals := r || jsonb_build_object('org_id', bi, 'data', '{}'::jsonb, 'created_by', auth.uid(), 'updated_by', auth.uid());
    select array_agg(a.attname::text order by a.attnum) into cols from pg_attribute a
     where a.attrelid = 'public.bi_reports'::regclass and a.attnum > 0 and not a.attisdropped and vals ? a.attname and vals -> a.attname <> 'null'::jsonb;
    execute format('insert into public.bi_reports (%s) select %s from jsonb_populate_record(null::public.bi_reports, $1)',
                   (select string_agg(quote_ident(c), ', ') from unnest(cols) c), (select string_agg(quote_ident(c), ', ') from unnest(cols) c)) using vals;
  end loop;
  execute 'select count(*) from public.bi_reports where org_id = $1 and file_path like ''static:%''' into n using bi;
  return n;
end $$;
revoke all on function public.kmr_ops_sample_drawing(text, text) from public, anon;
grant execute on function public.kmr_ops_sample_drawing(text, text) to authenticated;


-- =====================================================================
-- migrations/0028_balloon_card_data.sql
-- =====================================================================
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


-- =====================================================================
-- migrations/0029_grand_master.sql
-- =====================================================================
-- =====================================================================
-- Grand Master (KMR Apps › Masters › Grand Master, company administrators): three cards
--   1. Real Data     — every app's real data (not sample): one JSON download, upload (restore), flush (backup first)
--   2. Sample Data   — every app's sample data: load all, flush all
--   3. Administration — company details & logo, users & access, invoices & payments: download, upload, flush
-- Invoices and payments are KMR's numbered tax records: company administrators can download them; only KMR staff can
-- flush or upload them. Logins themselves are never deleted. Needs 0028 (and HRM 0005). Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_balloon_own_load(text,jsonb)') is null then raise exception 'Run 0028_balloon_card_data.sql first.'; end if;
end $$;

-- the customer, for a company administrator only
create or replace function console.grand_customer(p_slug text) returns uuid
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can use the Grand Master.'; end if;
  return cid;
end $$;
revoke all on function console.grand_customer(text) from public, anon, authenticated;

create or replace function console.grand_ref(p_cid uuid, p_app text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select product_ref from console.licences where customer_id = p_cid and product_code = p_app and product_ref is not null limit 1
$$;
revoke all on function console.grand_ref(uuid, text) from public, anon, authenticated;

-- ---------- HRM: real = every employee except the sample ones (@demo.kmr.test) ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

-- ---------- overview ----------
create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
  end if;
  r := console.grand_ref(cid, 'balloon');
  if r is not null and to_regclass('public.bi_reports') is not null then
    execute 'select count(*) filter (where coalesce(file_path, '''') not like ''static:%''), count(*) filter (where file_path like ''static:%'') from public.bi_reports where org_id = $1'
      into n, k using r;
    real_ := real_ || jsonb_build_object('balloon', n); smp := smp || jsonb_build_object('balloon', k);
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is null then continue; end if;
    n := 0;
    declare tb text; m bigint; begin
      foreach tb in array console.data_tables(t) loop
        execute format('select count(*) from public.%I where org_id = $1', tb) into m using r; n := n + m;
      end loop;
    end;
    real_ := real_ || jsonb_build_object(t, n);
  end loop;
  select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.ops_records where customer_id = cid;
  real_ := real_ || jsonb_build_object('ops', n); smp := smp || jsonb_build_object('ops', k);
  select * into c from console.customers where id = cid;
  return jsonb_build_object('real', real_, 'sample', smp, 'staff', console.is_staff(),
    'admin', jsonb_build_object(
      'company', c.name, 'logo', coalesce(c.logo_url, '') <> '',
      'details', (select count(*) from unnest(array[c.legal_name, c.tax_id, c.address, c.city, c.state, c.postal_code, c.contact_phone]) v where coalesce(v, '') <> ''),
      'users', (select count(*) from console.customer_members where customer_id = cid),
      'invoices', (select count(*) from console.invoices where customer_id = cid),
      'payments', (select count(*) from console.payments p join console.invoices i on i.id = p.invoice_id where i.customer_id = cid)));
end $$;
revoke all on function public.kmr_grand_overview(text) from public, anon;
grant execute on function public.kmr_grand_overview(text) to authenticated;

-- ---------- 1. Real data ----------
create or replace function public.kmr_grand_real_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); apps jsonb := '{}'; t text;
begin
  foreach t in array array['hrm','pd','capacity'] loop
    if console.grand_ref(cid, t) is not null then apps := apps || jsonb_build_object(t, public.kmr_data_export(p_slug, t)); end if;
  end loop;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    apps := apps || jsonb_build_object('balloon', public.kmr_balloon_own_export(p_slug));
  end if;
  apps := apps || jsonb_build_object('ops', jsonb_build_object('format', 'kmr-ops-own', 'records',
    coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'code', r.code, 'name', r.name, 'data', r.data, 'active', r.active) order by r.kind, r.code)
                from console.ops_records r where r.customer_id = cid and not r.sample), '[]')));
  return jsonb_build_object('format', 'kmr-real-data', 'version', 1, 'company', lower(p_slug), 'exported_at', now(), 'apps', apps);
end $$;
revoke all on function public.kmr_grand_real_export(text) from public, anon;
grant execute on function public.kmr_grand_real_export(text) to authenticated;

create or replace function public.kmr_grand_real_flush(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; t text; n int;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then out := out || jsonb_build_object('hrm', hrm.real_flush(r)); end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_balloon_own_flush(p_slug));
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is not null then out := out || jsonb_build_object(t, console.data_clear(t, cid, r)); end if;
  end loop;
  delete from console.ops_records where customer_id = cid and not sample; get diagnostics n = row_count;
  return out || jsonb_build_object('ops', n);
end $$;
revoke all on function public.kmr_grand_real_flush(text) from public, anon;
grant execute on function public.kmr_grand_real_flush(text) to authenticated;

-- puts every app in the file back as it was in the backup (all in one go: if one app fails, nothing changes)
create or replace function public.kmr_grand_real_import(p_slug text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; t text; a jsonb; n int; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_data ->> 'format' is distinct from 'kmr-real-data' then raise exception 'This is not a Grand Master real-data file.'; end if;
  if lower(coalesce(p_data ->> 'company', '')) <> lower(p_slug) then
    raise exception 'This file is a backup of another company (%).', p_data ->> 'company';
  end if;
  foreach t in array array['hrm','pd','capacity'] loop
    a := p_data -> 'apps' -> t;
    if a is null or console.grand_ref(cid, t) is null then continue; end if;
    out := out || jsonb_build_object(t, public.kmr_data_import(p_slug, t, a) -> 'restored');
  end loop;
  a := p_data -> 'apps' -> 'balloon';
  if a is not null and console.grand_ref(cid, 'balloon') is not null then
    perform public.kmr_balloon_own_flush(p_slug);
    if jsonb_array_length(coalesce(a -> 'tables' -> 'bi_reports', '[]')) > 0 then
      out := out || jsonb_build_object('balloon', public.kmr_balloon_own_load(p_slug, a));
    else out := out || jsonb_build_object('balloon', 0); end if;
  end if;
  a := p_data -> 'apps' -> 'ops';
  if a is not null then
    delete from console.ops_records where customer_id = cid and not sample;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    select cid, x ->> 'kind', x ->> 'code', coalesce(x ->> 'name', x ->> 'code'), coalesce(x -> 'data', '{}'), coalesce((x ->> 'active')::boolean, true), false, me
      from jsonb_array_elements(coalesce(a -> 'records', '[]')) x
     where coalesce(x ->> 'kind', '') <> '' and coalesce(x ->> 'code', '') <> ''
    on conflict (customer_id, kind, code) do update set name = excluded.name, data = excluded.data, active = excluded.active, sample = false, updated_by = me;
    get diagnostics n = row_count; out := out || jsonb_build_object('ops', n);
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_real_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_real_import(text, jsonb) to authenticated;

-- ---------- 2. Sample data ----------
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
    else n := hrm.demo_flush(r); end if;
    out := out || jsonb_build_object('hrm', n, 'hrm_tenant', r);
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_ops_sample_drawing(p_slug, p_action));
  end if;
  if p_action = 'load' then out := out || jsonb_build_object('ops', (public.kmr_ops_sample_load(p_slug) ->> 'added')::int);
  else out := out || jsonb_build_object('ops', public.kmr_ops_sample_flush(p_slug)); end if;
  return out;
end $$;
revoke all on function public.kmr_grand_sample(text, text) from public, anon;
grant execute on function public.kmr_grand_sample(text, text) to authenticated;

-- the HRM company of a customer, for the HRM app to finish the sample attendance (company administrators only)
create or replace function public.kmr_grand_hrm_tenant(p_slug text) returns uuid
language sql stable security definer set search_path = console, public as $$
  select console.grand_ref(console.grand_customer(p_slug), 'hrm')
$$;
revoke all on function public.kmr_grand_hrm_tenant(text) from public, anon;
grant execute on function public.kmr_grand_hrm_tenant(text) to authenticated;

-- ---------- 3. Administration data ----------
create or replace function public.kmr_grand_admin_export(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); c console.customers%rowtype;
begin
  select * into c from console.customers where id = cid;
  return jsonb_build_object('format', 'kmr-admin-data', 'version', 1, 'company', lower(p_slug), 'exported_at', now(),
    'company_details', jsonb_build_object('name', c.name, 'legal_name', c.legal_name, 'tax_id', c.tax_id, 'address', c.address, 'city', c.city,
        'state', c.state, 'postal_code', c.postal_code, 'country', c.country, 'contact_name', c.contact_name, 'contact_email', c.contact_email,
        'contact_phone', c.contact_phone, 'logo_url', c.logo_url),
    'users', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'full_name', m.full_name, 'is_admin', m.is_admin, 'roles', m.roles,
        'login_owned', m.login_owned) order by m.email) from console.customer_members m where m.customer_id = cid), '[]'),
    'invoices', coalesce((select jsonb_agg(to_jsonb(i) || jsonb_build_object(
        'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'id' order by l.sort) from console.invoice_lines l where l.invoice_id = i.id), '[]'),
        'payments', coalesce((select jsonb_agg(to_jsonb(p)) from console.payments p where p.invoice_id = i.id), '[]')) order by i.created_at)
      from console.invoices i where i.customer_id = cid), '[]'));
end $$;
revoke all on function public.kmr_grand_admin_export(text) from public, anon;
grant execute on function public.kmr_grand_admin_export(text) to authenticated;

-- tools show the company logo too: clear it there when the company's logo is flushed
create or replace function console.grand_clear_logos(p_cid uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare l record;
begin
  for l in select product_code, product_ref from console.licences where customer_id = p_cid and product_ref is not null loop
    if l.product_code = 'balloon' and exists (select 1 from pg_attribute where attrelid = 'public.bi_orgs'::regclass and attname = 'logo' and not attisdropped) then
      execute 'update public.bi_orgs set logo = null where id = $1' using l.product_ref;
    elsif l.product_code = 'pd' and exists (select 1 from pg_attribute where attrelid = 'public.pd_orgs'::regclass and attname = 'logo' and not attisdropped) then
      execute 'update public.pd_orgs set logo = null where id = $1' using l.product_ref;
    elsif l.product_code = 'capacity' then
      execute 'update public.cp_orgs set settings = coalesce(settings, ''{}''::jsonb) - ''logo'' where id = $1' using l.product_ref;
    elsif l.product_code = 'hrm' then update hrm.tenants set logo_path = null where id = l.product_ref;
    end if;
  end loop;
end $$;
revoke all on function console.grand_clear_logos(uuid) from public, anon, authenticated;

-- p_parts: any of 'company', 'users', 'invoices'
create or replace function public.kmr_grand_admin_flush(p_slug text, p_parts text[]) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; me text := lower(coalesce(auth.jwt() ->> 'email', '')); m record; n int := 0;
begin
  if 'invoices' = any(p_parts) and not console.is_staff() then
    raise exception 'Invoices and payments are KMR''s tax records: only KMR staff can flush them. You can download them.';
  end if;
  if 'company' = any(p_parts) then
    update console.customers set legal_name = null, tax_id = null, address = null, city = null, state = null, postal_code = null,
           contact_phone = null, logo_url = null, updated_at = now() where id = cid;
    perform console.grand_clear_logos(cid);
    out := out || jsonb_build_object('company', true);
  end if;
  if 'users' = any(p_parts) then
    -- everyone except you and the company's main contact; their access in every app goes too (logins stay)
    for m in select email from console.customer_members where customer_id = cid and email <> me
               and email <> (select lower(coalesce(contact_email, '')) from console.customers where id = cid) loop
      delete from console.customer_members where customer_id = cid and email = m.email;
      perform console.sync_member(cid, m.email);
      n := n + 1;
    end loop;
    out := out || jsonb_build_object('users', n);
  end if;
  if 'invoices' = any(p_parts) then
    delete from console.payments where invoice_id in (select id from console.invoices where customer_id = cid); get diagnostics n = row_count;
    out := out || jsonb_build_object('payments', n);
    delete from console.invoices where customer_id = cid; get diagnostics n = row_count;
    out := out || jsonb_build_object('invoices', n);
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_admin_flush(text, text[]) from public, anon;
grant execute on function public.kmr_grand_admin_flush(text, text[]) to authenticated;

create or replace function public.kmr_grand_admin_import(p_slug text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; d jsonb; u jsonb; i jsonb; n int := 0; ni int := 0; np int := 0;
  me text := lower(coalesce(auth.jwt() ->> 'email', '')); em text; skipped int := 0;
begin
  if p_data ->> 'format' is distinct from 'kmr-admin-data' then raise exception 'This is not a Grand Master administration file.'; end if;
  if lower(coalesce(p_data ->> 'company', '')) <> lower(p_slug) then raise exception 'This file is a backup of another company (%).', p_data ->> 'company'; end if;
  d := p_data -> 'company_details';
  if d is not null then
    update console.customers set
      name = coalesce(nullif(trim(d ->> 'name'), ''), name), legal_name = nullif(d ->> 'legal_name', ''), tax_id = nullif(d ->> 'tax_id', ''),
      address = nullif(d ->> 'address', ''), city = nullif(d ->> 'city', ''), state = nullif(d ->> 'state', ''),
      postal_code = nullif(d ->> 'postal_code', ''), contact_phone = nullif(d ->> 'contact_phone', ''), logo_url = nullif(d ->> 'logo_url', ''),
      updated_at = now() where id = cid;
    out := out || jsonb_build_object('company', true);
  end if;
  for u in select * from jsonb_array_elements(coalesce(p_data -> 'users', '[]')) loop
    em := lower(trim(coalesce(u ->> 'email', '')));
    continue when em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if em = me then continue; end if;                                   -- your own rights are never changed by a file
    insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
    values (cid, em, nullif(u ->> 'full_name', ''), coalesce((u ->> 'is_admin')::boolean, false), coalesce(u -> 'roles', '{}'),
            coalesce((u ->> 'login_owned')::boolean, false), me)
    on conflict (customer_id, email) do update set full_name = excluded.full_name, is_admin = excluded.is_admin, roles = excluded.roles, updated_at = now();
    begin
      perform console.sync_member(cid, em);
    exception when others then skipped := skipped + 1;                -- e.g. that login already uses another company's HRM
    end;
    n := n + 1;
  end loop;
  out := out || jsonb_build_object('users', n, 'users_partly', skipped);
  if jsonb_array_length(coalesce(p_data -> 'invoices', '[]')) > 0 then
    if not console.is_staff() then
      out := out || jsonb_build_object('invoices_skipped', true);
    else
      for i in select * from jsonb_array_elements(p_data -> 'invoices') loop
        continue when exists (select 1 from console.invoices where id = (i ->> 'id')::uuid or number = i ->> 'number');
        insert into console.invoices select * from jsonb_populate_record(null::console.invoices, (i - 'lines' - 'payments') || jsonb_build_object('customer_id', cid));
        insert into console.invoice_lines (invoice_id, sort, product_code, description, period_from, period_to, qty, unit_amount, amount)
        select (i ->> 'id')::uuid, l.sort, l.product_code, l.description, l.period_from, l.period_to, l.qty, l.unit_amount, l.amount
          from jsonb_populate_recordset(null::console.invoice_lines, coalesce(i -> 'lines', '[]')) l;
        insert into console.payments select * from jsonb_populate_recordset(null::console.payments, coalesce(i -> 'payments', '[]')) on conflict do nothing;
        get diagnostics n = row_count; np := np + n; ni := ni + 1;
      end loop;
      out := out || jsonb_build_object('invoices', ni, 'payments', np);
    end if;
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_admin_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_admin_import(text, jsonb) to authenticated;


-- =====================================================================
-- migrations/0030_hrm_recruitment.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — HRM recruitment (HRM migration 0006) on the platform. Needs 0029. Safe to re-run, before or after HRM 0006.
--  • KMR Apps › Users & access can give the HRM role "Interviewer" (sits on interview panels, fills in scorecards)
--  • Data Master / Grand Master flushes of HRM also clear recruitment: requisitions, job descriptions, candidates,
--    applications, interviews, scorecards and offers. Resume files stay in storage, so a restore brings them back.
-- =====================================================================
do $$ begin
  if to_regprocedure('hrm.real_flush(uuid)') is null then raise exception 'Run 0029_grand_master.sql first.'; end if;
end $$;

create or replace function public.kmr_admin_save_user(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public, auth as $$
declare cid uuid; em text := lower(trim(coalesce(p ->> 'email', ''))); lg record; rl jsonb := '{}'; k text; v text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can manage users.'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid e-mail address.'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p -> 'roles', '{}')) loop
    if v = '' then continue; end if;
    if k = 'hrm' and v not in ('company_admin','hr_manager','hr_executive','manager','payroll','interviewer') then raise exception 'Unknown HRM role %.', v; end if;
    if k <> 'hrm' and v not in ('admin','editor','viewer') then raise exception 'Unknown role % for %.', v, k; end if;
    rl := rl || jsonb_build_object(k, v);
  end loop;
  if em = me and coalesce((p ->> 'is_admin')::boolean, false) = false and console.is_customer_admin(cid) and not console.is_staff() then
    raise exception 'You cannot remove your own administrator rights.';
  end if;
  select * into lg from console.ensure_login(em, p ->> 'password', p ->> 'name');
  insert into console.customer_members (customer_id, email, full_name, is_admin, roles, login_owned, created_by)
  values (cid, em, nullif(trim(coalesce(p ->> 'name', '')), ''), coalesce((p ->> 'is_admin')::boolean, false), rl, lg.created, me)
  on conflict (customer_id, email) do update set full_name = coalesce(excluded.full_name, customer_members.full_name), is_admin = excluded.is_admin,
    roles = excluded.roles, updated_at = now();
  perform console.sync_member(cid, em);
  return jsonb_build_object('ok', true, 'new_login', lg.created);
end $$;
grant execute on function public.kmr_admin_save_user(text, jsonb) to authenticated;

-- recruitment data of a company (nothing when HRM 0006 is not installed yet)
create or replace function hrm.recruit_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
begin
  foreach t in array array['offers','interview_feedback','interviews','applications','candidates','requisitions','job_descriptions'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;
revoke all on function hrm.recruit_flush(uuid) from public, anon, authenticated;

-- ---------- HRM flush (Data Master) now includes recruitment ----------
create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  perform hrm.recruit_flush(p_tenant);
  select count(*) into emps from hrm.employees where tenant_id = p_tenant;
  if to_regclass('hrm.loan_recoveries') is not null then
    delete from hrm.loan_recoveries where tenant_id = p_tenant; delete from hrm.payroll_lines where tenant_id = p_tenant;
    delete from hrm.payroll_runs where tenant_id = p_tenant; delete from hrm.loans where tenant_id = p_tenant;
    delete from hrm.salary_structures where tenant_id = p_tenant;
  end if;
  delete from hrm.leave_ledger where tenant_id = p_tenant;
  delete from hrm.leave_requests where tenant_id = p_tenant;
  delete from hrm.regularisation_requests where tenant_id = p_tenant;
  delete from hrm.attendance_days where tenant_id = p_tenant;
  delete from hrm.attendance_punches where tenant_id = p_tenant;
  delete from hrm.id_cards where tenant_id = p_tenant;
  delete from hrm.employee_documents where tenant_id = p_tenant;
  delete from hrm.onboarding_invites where tenant_id = p_tenant;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee';
  update hrm.app_users set employee_id = null where tenant_id = p_tenant;
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant;
  delete from hrm.employee_private where tenant_id = p_tenant;
  delete from hrm.employees where tenant_id = p_tenant;
  if p_setup then
    delete from hrm.attendance_devices where tenant_id = p_tenant;
    delete from hrm.notification_templates where tenant_id = p_tenant;
    delete from hrm.leave_types where tenant_id = p_tenant;
    delete from hrm.holidays where tenant_id = p_tenant;
    delete from hrm.shifts where tenant_id = p_tenant;
    delete from hrm.designations where tenant_id = p_tenant;
    delete from hrm.departments where tenant_id = p_tenant;
    delete from hrm.plants where tenant_id = p_tenant;
    if to_regclass('hrm.pay_components') is not null then
      delete from hrm.pay_components where tenant_id = p_tenant; delete from hrm.pay_settings where tenant_id = p_tenant;
    end if;
    perform hrm.seed_tenant_defaults(p_tenant);
    if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(p_tenant); end if;
  end if;
  update hrm.tenants set emp_code_seq = 0 where id = p_tenant;
  delete from hrm.notifications where tenant_id = p_tenant;
  delete from hrm.audit_log where tenant_id = p_tenant;
  return jsonb_build_object('employees', emps, 'setup_reset', p_setup);
end $fn$;
revoke all on function hrm.company_flush(uuid, boolean) from public, anon, authenticated;

-- ---------- real-data flush (Grand Master) now includes recruitment ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant);                 -- recruitment (requisitions, candidates, offers) is real data
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

-- =====================================================================
-- The Console owner
-- =====================================================================
insert into console.staff (user_id, full_name, email, role)
select u.id, s.owner_name, lower(s.owner_email), 'owner'
  from kmr_setup s join auth.users u on lower(u.email) = lower(s.owner_email);
drop table kmr_setup;

select 'KMR PLATFORM READY' as result,
       (select count(*) from console.products) as products,
       (select count(*) from console.staff)    as console_staff,
       (select string_agg(id, ', ') from storage.buckets where id like 'hrm-%') as hrm_buckets;
