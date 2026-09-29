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
