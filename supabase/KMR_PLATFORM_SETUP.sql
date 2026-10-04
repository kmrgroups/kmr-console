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
-- products/hrm/0007_sample_flow.sql
-- =====================================================================
-- =====================================================================
-- HRM 0007 — Sample data runs through the whole flow. Needs 0001–0006. Safe to re-run.
-- "Load sample data" (KMR Apps › Grand Master › Sample Data Master, or Console › Test data) now also fills
-- the hiring flow, joined up with the sample employees and plants:
--   • 3 job descriptions and 3 openings (Quality Engineer and CNC Operator open on the careers page,
--     Maintenance Technician waiting for HR approval)
--   • 10 sample candidates with resumes, each scored by the HRM's own match engine, at every stage:
--     new, shortlisted (one against the recommendation), on hold, declined with the regret sent,
--     interview coming up, interview done with the panel's scorecard, offer sent, offer declined,
--     and offer accepted → the new joiner is on the employee list with the salary from the offer
-- Everything is marked "sample": the sample flush removes it, real data is never touched.
-- Sample e-mails end in @demo.kmr.test and phone numbers are made up, so nothing is ever sent to a real person.
-- =====================================================================

alter table hrm.job_descriptions add column if not exists sample boolean not null default false;
alter table hrm.requisitions     add column if not exists sample boolean not null default false;
alter table hrm.candidates       add column if not exists sample boolean not null default false;
create index if not exists requisitions_sample on hrm.requisitions (tenant_id) where sample;
create index if not exists candidates_sample on hrm.candidates (tenant_id) where sample;

-- ---------- the sample hiring flow (made with the HRM's own JD writer, resume reader, match score and CTC breakup) ----------
create or replace function hrm.demo_recruit(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant;
  d jsonb := $sample${"jds": [{"key": "QE", "title": "Quality Engineer", "family": "quality", "purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant.", "responsibilities": ["Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals", "Plan and conduct internal process and product audits; close non-conformities on time", "Work with suppliers on incoming quality, supplier PPM and corrective actions", "Maintain calibration of gauges and measuring instruments", "Train operators on quality standards, poka-yoke and work instructions"], "kpis": ["Customer PPM", "Internal rejection %", "Customer complaints closed on time (8D)", "Cpk of critical characteristics ≥ 1.33", "Audit NCs closed on time", "Cost of poor quality"], "must_have": [{"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "weight": 3}, {"name": "Problem solving (8D, RCA, CAPA)", "weight": 3}, {"name": "Quality improvement", "weight": 2}, {"name": "Inspection & metrology", "weight": 2}, {"name": "IATF 16949 / ISO 9001", "weight": 2}], "good_to_have": [{"name": "Customer quality / OEM interface", "weight": 1}, {"name": "Supplier quality development", "weight": 1}, {"name": "Internal / process audits", "weight": 1}, {"name": "Six Sigma", "weight": 1}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "weight": 1}], "qualifications": "Diploma or B.E / B.Tech (Mechanical / Production)", "experience": "3–6 years", "reporting_to": "Quality Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001; location: Bengaluru", "outcomes": ["Bring customer PPM down and hold it", "Close customer complaints with effective, verified corrective action", "Keep the plant audit-ready for IATF 16949"], "designation": "Engineer", "status": "approved"}, {"key": "OP", "title": "CNC Operator", "family": "operator", "purpose": "Operate and set machines safely to produce good parts to the drawing and work instruction.", "responsibilities": ["Operate and set the machine as per the work instruction", "Do first-off and in-process checks with gauges; record them", "Report abnormalities and stop on doubt", "Maintain 5S and do autonomous maintenance checks", "Follow safety rules and wear PPE"], "kpis": ["Output per shift", "Rejection %", "Check-sheet compliance", "Safety"], "must_have": [{"name": "CNC machining", "weight": 3}, {"name": "Inspection & metrology", "weight": 2}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "weight": 1}], "good_to_have": [{"name": "Lean / continuous improvement", "weight": 1}, {"name": "TPM / maintenance excellence", "weight": 1}, {"name": "Welding / fabrication", "weight": 1}], "qualifications": "ITI / 10th / 12th", "experience": "1–4 years", "reporting_to": "Operator / technician Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001; location: Hosur", "outcomes": ["Right-first-time parts at the planned output"], "designation": "Operator", "status": "approved"}, {"key": "MT", "title": "Maintenance Technician", "family": "maintenance", "purpose": "Keep plant machines and utilities available and reliable through planned maintenance and quick, lasting breakdown repair.", "responsibilities": ["Attend breakdowns quickly and find the root cause so they do not repeat", "Plan and carry out preventive and predictive maintenance as per the PM schedule", "Maintain hydraulic, pneumatic, electrical and PLC-controlled systems", "Keep critical spares and the maintenance history up to date", "Drive TPM, autonomous maintenance and MTBF / MTTR improvement", "Follow LOTO and permit-to-work safety rules"], "kpis": ["Machine availability %", "MTBF", "MTTR", "PM adherence %", "Maintenance cost per unit", "Repeat breakdowns"], "must_have": [{"name": "TPM / maintenance excellence", "weight": 3}, {"name": "Mechanical maintenance", "weight": 2}, {"name": "Electrical maintenance", "weight": 2}, {"name": "Problem solving (8D, RCA, CAPA)", "weight": 1}], "good_to_have": [{"name": "Health, safety & environment", "weight": 1}, {"name": "CNC machining", "weight": 1}, {"name": "ERP (SAP / Oracle / Tally)", "weight": 1}, {"name": "Lean / continuous improvement", "weight": 1}], "qualifications": "Diploma or ITI (Fitter / Electrician)", "experience": "2–5 years", "reporting_to": "Maintenance Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001; location: Bengaluru", "outcomes": ["Raise machine availability and MTBF", "Cut repeat breakdowns"], "designation": "Technician", "status": "draft"}], "reqs": [{"key": "QE", "ref": "REQ-SMP-01", "title": "Quality Engineer", "designation": "Engineer", "department": "Quality", "plant": "DP1", "family": "quality", "headcount": 2, "exp_min": 3, "exp_max": 6, "ctc_min": 450000, "ctc_max": 750000, "notice_max_days": 60, "location": "Bengaluru", "status": "open", "published": true, "reason": "new", "required_in": 30, "opened_ago": 21}, {"key": "OP", "ref": "REQ-SMP-02", "title": "CNC Operator", "designation": "Operator", "department": "Production", "plant": "DP2", "family": "operator", "headcount": 4, "exp_min": 1, "exp_max": 4, "ctc_min": 220000, "ctc_max": 320000, "notice_max_days": 30, "location": "Hosur", "status": "open", "published": true, "reason": "replacement", "required_in": 14, "opened_ago": 35}, {"key": "MT", "ref": "REQ-SMP-03", "title": "Maintenance Technician", "designation": "Technician", "department": "Maintenance", "plant": "DP1", "family": "maintenance", "headcount": 1, "exp_min": 2, "exp_max": 5, "ctc_min": 260000, "ctc_max": 380000, "notice_max_days": 45, "location": "Bengaluru", "status": "pending", "published": false, "reason": "new", "required_in": 45, "opened_ago": 2}], "candidates": [{"key": "c1", "full_name": "Karthikeyan M", "email": "karthikeyan.m@demo.kmr.test", "phone": "9003120101", "location": "Bengaluru", "total_exp": 5.3, "current_ctc": 540000, "expected_ctc": 650000, "notice_days": 30, "education": "B.E / B.Tech", "current_company": null, "current_designation": null, "skills": ["IATF 16949 / ISO 9001", "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "Problem solving (8D, RCA, CAPA)", "Quality improvement", "Internal / process audits", "Inspection & metrology", "Statistical analysis (SPC, Cpk, MSA)", "CNC machining"], "resume_text": "KARTHIKEYAN M\nQuality Engineer | karthikeyan.m@demo.kmr.test | +91 90031 20101 | Bengaluru, Karnataka\n\nPROFILE\nQuality engineer with 5 years in automotive Tier-1 machining plants working to IATF 16949.\n\nEXPERIENCE\nSundaram Precision Parts Pvt Ltd, Bengaluru — Quality Engineer          Jul 2023 – Present\n• Reduced in-process rejection from 2.4% to 0.7% with poka-yoke and layered process audits on CNC turning cells\n• Closed 22 customer complaints with 8D and why-why analysis; customer PPM brought down from 160 to 40\n• Prepared PPAP, PFMEA and control plans for 11 new parts; ran Cpk and MSA (GR&R) studies on critical characteristics\nLakshmi Auto Components, Hosur — Quality Inspector                         Jun 2021 – Jun 2023\n• Incoming and final inspection with CMM, height gauge and micrometers; maintained calibration records\n\nEDUCATION\nB.E. Mechanical Engineering, Visvesvaraya Technological University           2017 – 2021\n\nCurrent CTC: 5.4 LPA | Expected CTC: 6.5 LPA | Notice period: 30 days", "source": "upload"}, {"key": "c2", "full_name": "Divya Prakash", "email": "divya.prakash@demo.kmr.test", "phone": "9003120102", "location": "Hosur", "total_exp": 5.3, "current_ctc": 480000, "expected_ctc": 600000, "notice_days": 45, "education": "B.E / B.Tech", "current_company": null, "current_designation": null, "skills": ["IATF 16949 / ISO 9001", "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "Problem solving (8D, RCA, CAPA)", "Quality improvement", "Customer quality / OEM interface", "Internal / process audits", "Inspection & metrology", "Statistical analysis (SPC, Cpk, MSA)", "Production planning & control", "CNC machining", "Logistics", "Costing & finance"], "resume_text": "DIVYA PRAKASH\ndivya.prakash@demo.kmr.test | 90031 20102 | Hosur\n\nQuality Engineer — 5 years, automotive machining and assembly (IATF 16949)\n\nWork experience\nHosur Forge & Machining Ltd — Quality Engineer (Aug 2022 – Present)\n- Led internal process audits and product audits; improved audit score from 78% to 92%\n- Customer complaint handling with 8D for two OEM customers; repeat complaints reduced to zero in FY25\n- SPC on critical dimensions and control charts on 6 CNC lines; PPAP submissions for 6 parts\nVel Engineering, Krishnagiri — QC Inspector (Jul 2021 – Jul 2022)\n- Final inspection and dispatch audit; gauge calibration\n\nEducation: B.E. Mechanical, Anna University (2021)\nCurrent CTC 4.8 lakhs, expecting 6 lakhs. Notice period 45 days.", "source": "careers"}, {"key": "c3", "full_name": "Suresh Babu R", "email": "suresh.babu@demo.kmr.test", "phone": "9003120103", "location": "Bengaluru", "total_exp": 5.3, "current_ctc": null, "expected_ctc": 450000, "notice_days": 30, "education": "Diploma", "current_company": null, "current_designation": null, "skills": ["Core tools (APQP, PPAP, FMEA, SPC, MSA)", "Quality improvement", "Supplier quality development", "Internal / process audits", "Inspection & metrology", "Communication & documentation"], "resume_text": "SURESH BABU R\nBengaluru | suresh.babu@demo.kmr.test | 9003120103\n\nQuality Inspector, Bharat Gears & Shafts, Bengaluru (Jan 2023 – Present)\n• Inspection of shafts and gears as per control plan; CMM programming basics\n• Maintained inspection reports and rejection data; supported PPAP documentation\nTrainee Inspector, Apex Fasteners (Jun 2021 – Dec 2022)\n• Incoming inspection, gauge handling\n\nDiploma in Mechanical Engineering (DME), 2021\nNotice: 30 days. Expected: 4.5 LPA", "source": "upload"}, {"key": "c4", "full_name": "Meenakshi Sundar", "email": "meenakshi.sundar@demo.kmr.test", "phone": "9003120104", "location": "Chennai", "total_exp": 11.3, "current_ctc": 950000, "expected_ctc": 1200000, "notice_days": 90, "education": "B.E / B.Tech", "current_company": null, "current_designation": null, "skills": ["IATF 16949 / ISO 9001", "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "Quality improvement", "Customer quality / OEM interface", "Supplier quality development", "Internal / process audits", "Statistical analysis (SPC, Cpk, MSA)", "CNC machining"], "resume_text": "MEENAKSHI SUNDAR\nmeenakshi.sundar@demo.kmr.test | +91 90031 20104 | Chennai, Tamil Nadu\n\nSenior Quality Engineer with 11 years in automotive sheet-metal and machining (IATF 16949, ISO 9001)\nDelphi Pressings Pvt Ltd, Chennai — Senior Quality Engineer, Apr 2017 – Present\n• Supplier quality and customer quality for 3 OEMs; reduced warranty returns by 35%\n• Core tools: APQP, PPAP, FMEA, SPC, MSA; trained 40 inspectors\nOrient Auto Parts, Chennai — Quality Engineer, Jun 2015 – Mar 2017\n\nB.Tech Mechanical Engineering, SRM University, 2015\nCurrent CTC: 9.5 LPA. Expected CTC: 12 LPA. Notice period: 90 days", "source": "upload"}, {"key": "c5", "full_name": "Rahul Verma", "email": "rahul.verma@demo.kmr.test", "phone": "9003120105", "location": "Pune", "total_exp": 3, "current_ctc": null, "expected_ctc": 500000, "notice_days": 30, "education": null, "current_company": null, "current_designation": null, "skills": ["Internal / process audits", "Customer handling / sales", "Costing & finance"], "resume_text": "RAHUL VERMA\nrahul.verma@demo.kmr.test | 9003120105 | Pune\n\nSales executive with 3 years in industrial tools distribution.\n- Achieved 110% of the yearly sales target in FY24\n- Managed 45 dealer accounts across Maharashtra\n\nBBA, Pune University, 2021\nExpected CTC 5 LPA, notice 30 days", "source": "careers"}, {"key": "c6", "full_name": "Nandini Hegde", "email": "nandini.hegde@demo.kmr.test", "phone": "9003120106", "location": "Bengaluru", "total_exp": 4.2, "current_ctc": null, "expected_ctc": 580000, "notice_days": 60, "education": "B.E / B.Tech", "current_company": null, "current_designation": null, "skills": ["Core tools (APQP, PPAP, FMEA, SPC, MSA)", "Problem solving (8D, RCA, CAPA)", "Quality improvement", "Internal / process audits", "Inspection & metrology", "Production / shop-floor management", "CNC machining"], "resume_text": "NANDINI HEGDE\nnandini.hegde@demo.kmr.test | +91 90031 20106 | Bengaluru\n\nQuality Engineer, 3 years — machined automotive components\nPrecision Turned Parts Pvt Ltd, Bengaluru — Quality Engineer (Sep 2023 – Present)\n• Process audits and layered audits on turning and grinding lines\n• 8D for internal and customer complaints; rejection reduced from 1.8% to 1.1%\nAsian Valves, Bengaluru — Graduate Engineer Trainee (Aug 2022 – Aug 2023)\n• Inspection with micrometers, bore gauges and height gauge; MSA studies\n\nB.E. Industrial & Production Engineering, 2022\nNotice period: 60 days | Expected: 5.8 LPA", "source": "careers"}, {"key": "c7", "full_name": "Manikandan P", "email": "manikandan.p@demo.kmr.test", "phone": "9003120107", "location": "Hosur", "total_exp": 4.3, "current_ctc": 228000, "expected_ctc": 276000, "notice_days": 15, "education": "ITI", "current_company": null, "current_designation": null, "skills": ["Quality improvement", "Inspection & metrology", "Lean / continuous improvement", "TPM / maintenance excellence", "Shop-floor discipline (5S, SOP, check sheets)", "CNC machining"], "resume_text": "MANIKANDAN P\nmanikandan.p@demo.kmr.test | 90031 20107 | Hosur, Tamil Nadu\n\nCNC Turning Operator — 4 years\nHosur Precision Machining — CNC Operator (Aug 2023 – Present)\n• Operating Fanuc and Siemens CNC turning centres; offset correction and tool change\n• First-piece approval and in-process inspection with vernier and micrometer; zero customer rejection in 2025\n• 5S and TPM activities; daily machine checklist\nSri Murugan Engineering — Machine Operator (Jul 2022 – Jul 2023)\n\nITI Machinist, 2022\nCurrent salary 19,000 per month; expected 23,000 per month. Notice period 15 days.", "source": "referral"}, {"key": "c8", "full_name": "Senthil Kumar A", "email": "senthil.kumar@demo.kmr.test", "phone": "9003120108", "location": "Hosur", "total_exp": 3.1, "current_ctc": null, "expected_ctc": 260000, "notice_days": 0, "education": "ITI", "current_company": null, "current_designation": null, "skills": ["Internal / process audits", "Inspection & metrology", "Shop-floor discipline (5S, SOP, check sheets)", "CNC machining", "Mechanical maintenance"], "resume_text": "SENTHIL KUMAR A\nsenthil.kumar@demo.kmr.test | 9003120108 | Krishnagiri\n\nVMC / CNC Operator, 3 years\nGlobal Auto Machining, Hosur — VMC Operator (Sep 2024 – Present)\n- Loading and unloading, program selection, offset changes on Fanuc VMC\n- In-process inspection with gauges; maintained check sheets\nTrainee Operator, Lucas Components (Sep 2023 – Aug 2024)\n\nITI Fitter, 2023\nExpected 2.6 LPA. Notice period: immediate", "source": "upload"}, {"key": "c9", "full_name": "Bhavya Reddy", "email": "bhavya.reddy@demo.kmr.test", "phone": "9003120109", "location": "Hosur", "total_exp": 1.3, "current_ctc": null, "expected_ctc": 220000, "notice_days": null, "education": "Diploma", "current_company": null, "current_designation": null, "skills": ["Internal / process audits", "Inspection & metrology", "Lean / continuous improvement", "Shop-floor discipline (5S, SOP, check sheets)", "CNC machining"], "resume_text": "BHAVYA REDDY\nbhavya.reddy@demo.kmr.test | 9003120109 | Hosur\n\nDiploma in Mechanical Engineering, 2025 — fresher\nApprentice Trainee, Ashok Components, Hosur (Jul 2025 – Present)\n• Operating CNC turning machine under supervision; learning setting and offsets\n• Daily 5S and machine cleaning; first-piece inspection support\nExpected salary: 2.2 LPA", "source": "careers"}, {"key": "c10", "full_name": "Ganesh Murthy", "email": "ganesh.murthy@demo.kmr.test", "phone": "9003120110", "location": "Hosur", "total_exp": 5.3, "current_ctc": 290000, "expected_ctc": 340000, "notice_days": 30, "education": "ITI", "current_company": null, "current_designation": null, "skills": ["Quality improvement", "Internal / process audits", "Lean / continuous improvement", "Shop-floor discipline (5S, SOP, check sheets)", "CNC machining"], "resume_text": "GANESH MURTHY\nganesh.murthy@demo.kmr.test | 9003120110 | Hosur\n\nCNC Setter cum Operator — 5 years\nTitan Auto Parts, Hosur — CNC Setter (Jun 2022 – Present)\n• Setting and operating CNC turning centres (Fanuc 0i); new part setting in under 45 minutes\n• Reduced setup time by 30% with SMED; scrap brought down from 1.5% to 0.6%\nRaja Engineering, Hosur — CNC Operator (Jun 2021 – May 2022)\n\nITI Turner, 2021\nCurrent CTC 2.9 LPA, expected 3.4 LPA. Notice 30 days.", "source": "upload"}], "apps": [{"cand": "c1", "req": "QE", "status": "offered", "score": 81, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 30.7, "max": 40, "note": "All shown in the resume"}, {"key": "good", "label": "Good-to-have", "points": 2.4, "max": 10, "note": "24% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "5.3 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 10, "max": 10, "note": "Shows: automotive, auto components, tier-1, iatf, machining"}, {"key": "results", "label": "Results in the role's areas", "points": 8, "max": 10, "note": "2 results with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "B.E / B.Tech"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 30 d ok; salary within budget; same city"}], "evidence": [{"competency": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "line": "Prepared PPAP, PFMEA and control plans for 11 new parts; ran Cpk and MSA (GR&R) studies on critical characteristics"}, {"competency": "Problem solving (8D, RCA, CAPA)", "line": "Closed 22 customer complaints with 8D and why-why analysis; customer PPM brought down from 160 to 40"}, {"competency": "Quality improvement", "line": "Reduced in-process rejection from 2.4% to 0.7% with poka-yoke and layered process audits on CNC turning cells"}, {"competency": "Inspection & metrology", "line": "Incoming and final inspection with CMM, height gauge and micrometers; maintained calibration records"}, {"competency": "IATF 16949 / ISO 9001", "line": "Quality engineer with 5 years in automotive Tier-1 machining plants working to IATF 16949."}], "flags": [], "recommendation": "suitable", "offer": {"ctc": 649992, "gross": 50990, "breakup": {"monthly_gross": 50990, "earnings": [{"code": "BASIC", "name": "Basic salary", "monthly": 25495, "annual": 305940}, {"code": "HRA", "name": "House rent allowance", "monthly": 10198, "annual": 122376}, {"code": "CONV", "name": "Conveyance allowance", "monthly": 1600, "annual": 19200}, {"code": "SPL", "name": "Special allowance", "monthly": 13697, "annual": 164364}], "employer": [{"code": "EPS", "name": "Pension (EPS 8.33%)", "monthly": 1250, "annual": 15000}, {"code": "EPF_ER", "name": "Employer PF (3.67%)", "monthly": 550, "annual": 6600}, {"code": "PF_ADMIN", "name": "PF admin charges (0.5%)", "monthly": 75, "annual": 900}, {"code": "EDLI", "name": "EDLI (0.5%)", "monthly": 75, "annual": 900}], "deductions": [{"code": "PF", "name": "Provident fund (12%)", "monthly": 1800, "annual": 21600}, {"code": "PT", "name": "Professional tax (Karnataka)", "monthly": 200, "annual": 2400}], "gratuity": {"monthly": 1226, "annual": 14712}, "net_monthly": 48990, "ctc_monthly": 54166, "ctc_annual": 649992, "pf_applicable": true}, "status": "sent"}}, {"cand": "c2", "req": "QE", "status": "interview", "score": 83, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 30.7, "max": 40, "note": "All shown in the resume"}, {"key": "good", "label": "Good-to-have", "points": 5.2, "max": 10, "note": "52% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "5.3 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 10, "max": 10, "note": "Shows: automotive, oem, iatf, machining, engineering"}, {"key": "results", "label": "Results in the role's areas", "points": 8, "max": 10, "note": "2 results with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "B.E / B.Tech"}, {"key": "limits", "label": "Notice, salary, location", "points": 9, "max": 10, "note": "notice 45 d ok; salary within budget; in Hosur"}], "evidence": [{"competency": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "line": "SPC on critical dimensions and control charts on 6 CNC lines;"}, {"competency": "Problem solving (8D, RCA, CAPA)", "line": "Customer complaint handling with 8D for two OEM customers; repeat complaints reduced to zero in FY25"}, {"competency": "Quality improvement", "line": "Customer complaint handling with 8D for two OEM customers; repeat complaints reduced to zero in FY25"}, {"competency": "Inspection & metrology", "line": "Final inspection and dispatch audit; gauge calibration"}, {"competency": "IATF 16949 / ISO 9001", "line": "Quality Engineer — 5 years, automotive machining and assembly (IATF 16949)"}, {"competency": "Customer quality / OEM interface", "line": "Customer complaint handling with 8D for two OEM customers; repeat complaints reduced to zero in FY25"}, {"competency": "Internal / process audits", "line": "Led internal process audits and product audits; improved audit score from 78% to 92%"}], "flags": [], "recommendation": "suitable", "offer": null}, {"cand": "c3", "req": "QE", "status": "shortlisted", "score": 49, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 14, "max": 40, "note": "Not shown: Problem solving (8D, RCA, CAPA), IATF 16949 / ISO 9001"}, {"key": "good", "label": "Good-to-have", "points": 2.4, "max": 10, "note": "24% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "5.3 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 2.5, "max": 10, "note": "Shows: engineering"}, {"key": "results", "label": "Results in the role's areas", "points": 0, "max": 10, "note": "No measurable results found"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "Diploma"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 30 d ok; salary within budget; same city"}], "evidence": [{"competency": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "line": "Maintained inspection reports and rejection data; supported PPAP documentation"}, {"competency": "Quality improvement", "line": "Maintained inspection reports and rejection data; supported PPAP documentation"}, {"competency": "Inspection & metrology", "line": "Maintained inspection reports and rejection data; supported PPAP documentation"}], "flags": [], "recommendation": "not_suitable", "offer": null}, {"cand": "c4", "req": "QE", "status": "on_hold", "score": 53, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 16.7, "max": 40, "note": "Not shown: Problem solving (8D, RCA, CAPA), Inspection & metrology"}, {"key": "good", "label": "Good-to-have", "points": 6.4, "max": 10, "note": "64% shown"}, {"key": "exp", "label": "Experience", "points": 9, "max": 15, "note": "11.3 years — above the band (may be over-qualified)"}, {"key": "context", "label": "Industry & plant context", "points": 10, "max": 10, "note": "Shows: automotive, iatf, machining, engineering, iso 9001"}, {"key": "results", "label": "Results in the role's areas", "points": 5, "max": 10, "note": "1 result with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "B.E / B.Tech"}, {"key": "limits", "label": "Notice, salary, location", "points": 1, "max": 10, "note": "notice 90 d too long; salary above budget; in Chennai"}], "evidence": [{"competency": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "line": "Core tools: APQP, PPAP, FMEA, SPC, MSA; trained 40 inspectors"}, {"competency": "Quality improvement", "line": "Supplier quality and customer quality for 3 OEMs; reduced warranty returns by 35%"}, {"competency": "IATF 16949 / ISO 9001", "line": "Senior Quality Engineer with 11 years in automotive sheet-metal and machining (IATF 16949, ISO 9001)"}, {"competency": "Customer quality / OEM interface", "line": "Supplier quality and customer quality for 3 OEMs; reduced warranty returns by 35%"}, {"competency": "Supplier quality development", "line": "Supplier quality and customer quality for 3 OEMs; reduced warranty returns by 35%"}], "flags": ["Notice 90 days is over the 60-day limit", "Expected salary ₹12.0 L is above the ₹7.5 L budget"], "recommendation": "hold", "offer": null}, {"cand": "c5", "req": "QE", "status": "declined", "score": 27, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 0, "max": 40, "note": "Not shown: Core tools (APQP, PPAP, FMEA, SPC, MSA), Problem solving (8D, RCA, CAPA), Quality improvement, Inspection & metrology, IATF 16949 / ISO 9001"}, {"key": "good", "label": "Good-to-have", "points": 1.2, "max": 10, "note": "12% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "3 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 0, "max": 10, "note": "No matching industry context"}, {"key": "results", "label": "Results in the role's areas", "points": 0, "max": 10, "note": "No measurable results found"}, {"key": "edu", "label": "Qualification", "points": 2, "max": 5, "note": "Not found"}, {"key": "limits", "label": "Notice, salary, location", "points": 9, "max": 10, "note": "notice 30 d ok; salary within budget; in Pune"}], "evidence": [], "flags": [], "recommendation": "not_suitable", "offer": null}, {"cand": "c6", "req": "QE", "status": "new", "score": 70, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 26.7, "max": 40, "note": "Not shown: IATF 16949 / ISO 9001"}, {"key": "good", "label": "Good-to-have", "points": 1.2, "max": 10, "note": "12% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "4.2 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 7.5, "max": 10, "note": "Shows: automotive, engineering, precision"}, {"key": "results", "label": "Results in the role's areas", "points": 5, "max": 10, "note": "1 result with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "B.E / B.Tech"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 60 d ok; salary within budget; same city"}], "evidence": [{"competency": "Problem solving (8D, RCA, CAPA)", "line": "8D for internal and customer complaints; rejection reduced from 1.8% to 1.1%"}, {"competency": "Quality improvement", "line": "8D for internal and customer complaints; rejection reduced from 1.8% to 1.1%"}, {"competency": "Inspection & metrology", "line": "Inspection with micrometers, bore gauges and height gauge;"}], "flags": [], "recommendation": "suitable", "offer": null}, {"cand": "c7", "req": "OP", "status": "joined", "score": 76, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 32, "max": 40, "note": "All shown in the resume"}, {"key": "good", "label": "Good-to-have", "points": 4, "max": 10, "note": "40% shown"}, {"key": "exp", "label": "Experience", "points": 12, "max": 15, "note": "4.3 years — above the band"}, {"key": "context", "label": "Industry & plant context", "points": 7.5, "max": 10, "note": "Shows: machining, engineering, precision"}, {"key": "results", "label": "Results in the role's areas", "points": 5, "max": 10, "note": "1 result with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "ITI"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 15 d ok; salary within budget; same city"}], "evidence": [{"competency": "CNC machining", "line": "Operating Fanuc and Siemens CNC turning centres; offset correction and tool change"}, {"competency": "Inspection & metrology", "line": "First-piece approval and in-process inspection with vernier and micrometer; zero customer rejection in 2025"}, {"competency": "Shop-floor discipline (5S, SOP, check sheets)", "line": "First-piece approval and in-process inspection with vernier and micrometer; zero customer rejection in 2025"}], "flags": [], "recommendation": "suitable", "offer": {"ctc": 300000, "gross": 22957, "breakup": {"monthly_gross": 22957, "earnings": [{"code": "BASIC", "name": "Basic salary", "monthly": 11479, "annual": 137748}, {"code": "HRA", "name": "House rent allowance", "monthly": 4592, "annual": 55104}, {"code": "CONV", "name": "Conveyance allowance", "monthly": 1600, "annual": 19200}, {"code": "SPL", "name": "Special allowance", "monthly": 5286, "annual": 63432}], "employer": [{"code": "EPS", "name": "Pension (EPS 8.33%)", "monthly": 956, "annual": 11472}, {"code": "EPF_ER", "name": "Employer PF (3.67%)", "monthly": 421, "annual": 5052}, {"code": "PF_ADMIN", "name": "PF admin charges (0.5%)", "monthly": 57, "annual": 684}, {"code": "EDLI", "name": "EDLI (0.5%)", "monthly": 57, "annual": 684}], "deductions": [{"code": "PF", "name": "Provident fund (12%)", "monthly": 1377, "annual": 16524}], "gratuity": {"monthly": 552, "annual": 6624}, "net_monthly": 21580, "ctc_monthly": 25000, "ctc_annual": 300000, "pf_applicable": true}, "status": "accepted"}}, {"cand": "c8", "req": "OP", "status": "interview", "score": 57, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 24, "max": 40, "note": "All shown in the resume"}, {"key": "good", "label": "Good-to-have", "points": 0, "max": 10, "note": "0% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "3.1 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 2.5, "max": 10, "note": "Shows: machining"}, {"key": "results", "label": "Results in the role's areas", "points": 0, "max": 10, "note": "No measurable results found"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "ITI"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 0 d ok; salary within budget; same city"}], "evidence": [{"competency": "CNC machining", "line": "Loading and unloading, program selection, offset changes on Fanuc VMC"}, {"competency": "Inspection & metrology", "line": "In-process inspection with gauges; maintained check sheets"}, {"competency": "Shop-floor discipline (5S, SOP, check sheets)", "line": "Loading and unloading, program selection, offset changes on Fanuc VMC"}], "flags": [], "recommendation": "hold", "offer": null}, {"cand": "c9", "req": "OP", "status": "new", "score": 57, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 24, "max": 40, "note": "All shown in the resume"}, {"key": "good", "label": "Good-to-have", "points": 2, "max": 10, "note": "20% shown"}, {"key": "exp", "label": "Experience", "points": 15, "max": 15, "note": "1.3 years — within the band"}, {"key": "context", "label": "Industry & plant context", "points": 2.5, "max": 10, "note": "Shows: engineering"}, {"key": "results", "label": "Results in the role's areas", "points": 0, "max": 10, "note": "No measurable results found"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "Diploma"}, {"key": "limits", "label": "Notice, salary, location", "points": 8, "max": 10, "note": "notice not stated; salary within budget; same city"}], "evidence": [{"competency": "CNC machining", "line": "Operating CNC turning machine under supervision; learning setting and offsets"}, {"competency": "Inspection & metrology", "line": "Daily 5S and machine cleaning; first-piece inspection support"}, {"competency": "Shop-floor discipline (5S, SOP, check sheets)", "line": "Operating CNC turning machine under supervision; learning setting and offsets"}], "flags": [], "recommendation": "hold", "offer": null}, {"cand": "c10", "req": "OP", "status": "offered", "score": 54, "breakdown": [{"key": "must", "label": "Must-have competencies", "points": 16, "max": 40, "note": "Not shown: Inspection & metrology"}, {"key": "good", "label": "Good-to-have", "points": 3.3, "max": 10, "note": "33% shown"}, {"key": "exp", "label": "Experience", "points": 12, "max": 15, "note": "5.3 years — above the band"}, {"key": "context", "label": "Industry & plant context", "points": 2.5, "max": 10, "note": "Shows: engineering"}, {"key": "results", "label": "Results in the role's areas", "points": 5, "max": 10, "note": "1 result with numbers"}, {"key": "edu", "label": "Qualification", "points": 5, "max": 5, "note": "ITI"}, {"key": "limits", "label": "Notice, salary, location", "points": 10, "max": 10, "note": "notice 30 d ok; salary within budget; same city"}], "evidence": [{"competency": "CNC machining", "line": "Setting and operating CNC turning centres (Fanuc 0i); new part setting in under 45 minutes"}, {"competency": "Shop-floor discipline (5S, SOP, check sheets)", "line": "Setting and operating CNC turning centres (Fanuc 0i); new part setting in under 45 minutes"}, {"competency": "Lean / continuous improvement", "line": "Reduced setup time by 30% with SMED; scrap brought down from 1.5% to 0.6%"}], "flags": [], "recommendation": "hold", "offer": {"ctc": 339996, "gross": 26016, "breakup": {"monthly_gross": 26016, "earnings": [{"code": "BASIC", "name": "Basic salary", "monthly": 13008, "annual": 156096}, {"code": "HRA", "name": "House rent allowance", "monthly": 5203, "annual": 62436}, {"code": "CONV", "name": "Conveyance allowance", "monthly": 1600, "annual": 19200}, {"code": "SPL", "name": "Special allowance", "monthly": 6205, "annual": 74460}], "employer": [{"code": "EPS", "name": "Pension (EPS 8.33%)", "monthly": 1084, "annual": 13008}, {"code": "EPF_ER", "name": "Employer PF (3.67%)", "monthly": 477, "annual": 5724}, {"code": "PF_ADMIN", "name": "PF admin charges (0.5%)", "monthly": 65, "annual": 780}, {"code": "EDLI", "name": "EDLI (0.5%)", "monthly": 65, "annual": 780}], "deductions": [{"code": "PF", "name": "Provident fund (12%)", "monthly": 1561, "annual": 18732}, {"code": "PT", "name": "Professional tax (Karnataka)", "monthly": 200, "annual": 2400}], "gratuity": {"monthly": 626, "annual": 7512}, "net_monthly": 24255, "ctc_monthly": 28333, "ctc_annual": 339996, "pf_applicable": true}, "status": "declined"}}]}$sample$::jsonb;
  x jsonb; a jsonb; o jsonb; c record; ids jsonb := '{}'; nid uuid; app uuid; iv uuid; req record; emp uuid; mgr uuid;
  panel uuid[]; names text[]; terms text; me uuid; n int := 0; k int := 0; nm text[]; ist text := 'Asia/Kolkata';
begin
  if not exists (select 1 from hrm.tenants where id = t) then raise exception 'Company not found.'; end if;
  if exists (select 1 from hrm.requisitions where tenant_id = t and sample) then return 0; end if;
  perform hrm.seed_recruit_defaults(t);
  select offer_terms into terms from hrm.recruit_settings where tenant_id = t;

  -- the company's own HR people sit on the sample panels (an interviewer first, if the company has one)
  select coalesce(array_agg(u.id), '{}'), coalesce(array_agg(u.full_name), '{}') into panel, names from (
    select id, full_name from hrm.app_users where tenant_id = t and active and role in ('interviewer','hr_manager','hr_executive','company_admin')
     order by case role when 'interviewer' then 0 when 'hr_manager' then 1 when 'hr_executive' then 2 else 3 end, created_at limit 2) u;
  me := panel[1];

  -- job descriptions
  for x in select * from jsonb_array_elements(d -> 'jds') loop
    insert into hrm.job_descriptions (tenant_id, designation_id, title, family, purpose, responsibilities, kpis, must_have, good_to_have,
        qualifications, experience, reporting_to, context, outcomes, status, approved_by, approved_at, created_by, sample, created_at)
    values (t, (select id from hrm.designations where tenant_id = t and name = x ->> 'designation'), x ->> 'title', x ->> 'family', x ->> 'purpose',
        array(select jsonb_array_elements_text(x -> 'responsibilities')), array(select jsonb_array_elements_text(x -> 'kpis')),
        x -> 'must_have', x -> 'good_to_have', x ->> 'qualifications', x ->> 'experience', x ->> 'reporting_to', x ->> 'context',
        array(select jsonb_array_elements_text(x -> 'outcomes')), x ->> 'status',
        case when x ->> 'status' = 'approved' then me end, case when x ->> 'status' = 'approved' then now() - interval '25 days' end, me, true, now() - interval '26 days')
    returning job_descriptions.id into nid;
    ids := ids || jsonb_build_object('jd_' || (x ->> 'key'), nid);
  end loop;

  -- openings
  for x in select * from jsonb_array_elements(d -> 'reqs') loop
    insert into hrm.requisitions (tenant_id, ref_no, title, designation_id, department_id, plant_id, headcount, ctc_min, ctc_max, exp_min, exp_max,
        reason, replacement_for, required_by, location, notice_max_days, jd_id, status, published, raised_by, raised_by_name, approved_by, approved_at, notes, sample, created_at)
    values (t, x ->> 'ref', x ->> 'title',
        (select id from hrm.designations where tenant_id = t and name = x ->> 'designation'),
        (select id from hrm.departments where tenant_id = t and name = x ->> 'department'),
        (select id from hrm.plants where tenant_id = t and code = x ->> 'plant'),
        (x ->> 'headcount')::int, (x ->> 'ctc_min')::numeric, (x ->> 'ctc_max')::numeric, (x ->> 'exp_min')::numeric, (x ->> 'exp_max')::numeric,
        x ->> 'reason', case when x ->> 'reason' = 'replacement' then 'Two operators moved to Plant 1' end,
        current_date + (x ->> 'required_in')::int, x ->> 'location', (x ->> 'notice_max_days')::int, (ids ->> ('jd_' || (x ->> 'key')))::uuid,
        x ->> 'status', (x ->> 'published')::boolean, me,
        case when x ->> 'status' = 'pending' then 'Maintenance head (sample)' else 'HR (sample)' end,
        case when x ->> 'status' = 'open' then me end, case when x ->> 'status' = 'open' then now() - ((x ->> 'opened_ago')::int - 1) * interval '1 day' end,
        'Sample opening', true, now() - (x ->> 'opened_ago')::int * interval '1 day')
    returning requisitions.id into nid;
    ids := ids || jsonb_build_object('req_' || (x ->> 'key'), nid);
  end loop;

  -- candidates
  for x in select * from jsonb_array_elements(d -> 'candidates') loop
    insert into hrm.candidates (tenant_id, full_name, email, phone, location, current_company, current_designation, total_exp, current_ctc, expected_ctc,
        notice_days, education, skills, resume_name, resume_text, parse_status, source, consent_at, created_by, sample, created_at)
    values (t, x ->> 'full_name', x ->> 'email', x ->> 'phone', x ->> 'location', x ->> 'current_company', x ->> 'current_designation',
        (x ->> 'total_exp')::numeric, (x ->> 'current_ctc')::numeric, (x ->> 'expected_ctc')::numeric, (x ->> 'notice_days')::int, x ->> 'education',
        array(select jsonb_array_elements_text(x -> 'skills')), replace(x ->> 'full_name', ' ', '_') || '_resume.pdf', x ->> 'resume_text', 'parsed', x ->> 'source',
        case when x ->> 'source' = 'careers' then now() - interval '12 days' end, me, true, now() - interval '14 days')
    on conflict do nothing
    returning candidates.id into nid;
    if nid is null then continue; end if;                                    -- the same e-mail is already a (real) candidate
    ids := ids || jsonb_build_object('cand_' || (x ->> 'key'), nid);
    nid := null;
  end loop;

  -- applications at every stage, with interviews, scorecards and offers
  for a in select * from jsonb_array_elements(d -> 'apps') loop
    if ids ->> ('cand_' || (a ->> 'cand')) is null then continue; end if;
    select r.* into req from hrm.requisitions r where r.id = (ids ->> ('req_' || (a ->> 'req')))::uuid;
    insert into hrm.applications (tenant_id, requisition_id, candidate_id, score, breakdown, evidence, flags, recommendation, status,
        decision_by, decision_at, decision_reason, overridden, regret_due, regret_sent_at, source, created_at)
    values (t, req.id, (ids ->> ('cand_' || (a ->> 'cand')))::uuid, (a ->> 'score')::int, a -> 'breakdown', a -> 'evidence',
        array(select jsonb_array_elements_text(a -> 'flags')), a ->> 'recommendation', a ->> 'status',
        case when a ->> 'status' <> 'new' then me end, case when a ->> 'status' <> 'new' then now() - interval '10 days' end,
        case a ->> 'cand'
          when 'c3' then 'Strong inspection base and lives nearby; check problem-solving depth in the interview'
          when 'c4' then 'Good profile, but the notice period and salary are above this opening; keep for a senior role'
          when 'c5' then 'Background is in sales, not quality'
          when 'c10' then 'Strong setter (setup time cut by 30%); inspection to be checked in the interview' end,
        a ->> 'cand' in ('c3', 'c10'),
        case when a ->> 'status' = 'declined' then current_date - 5 end, case when a ->> 'status' = 'declined' then now() - interval '5 days' end,
        (select source from hrm.candidates where id = (ids ->> ('cand_' || (a ->> 'cand')))::uuid), now() - interval '13 days')
    returning applications.id into app;
    n := n + 1;

    -- interviews: done (with the panel's scorecard) for the offered / joined ones, coming up for the interview stage
    if a ->> 'status' in ('offered', 'joined', 'interview') and cardinality(panel) > 0 then
      insert into hrm.interviews (tenant_id, application_id, round, title, mode, starts_at, duration_min, venue, video_link, bring, panel, panel_names, status, created_by)
      values (t, app, 1, case when req.title ilike '%operator%' then 'Practical test + interview' else 'Technical interview' end,
        case when a ->> 'cand' = 'c2' then 'video' else 'in_person' end,
        (case a ->> 'cand' when 'c2' then current_date + 1 when 'c8' then current_date + 2 when 'c1' then current_date - 6
                           when 'c10' then current_date - 12 else current_date - 20 end + time '11:00') at time zone ist,
        case when req.title ilike '%operator%' then 90 else 60 end,
        case when a ->> 'cand' = 'c2' then null else 'HR office, ' || coalesce((select name from hrm.plants where id = req.plant_id), 'main plant') end,
        case when a ->> 'cand' = 'c2' then 'https://meet.example.com/sample-interview' end,
        'Resume, ID proof, education certificates, last 3 payslips',
        panel, names, case a ->> 'cand' when 'c2' then 'confirmed' when 'c8' then 'scheduled' else 'done' end, me)
      returning interviews.id into iv;
      if a ->> 'status' in ('offered', 'joined') then
        insert into hrm.interview_feedback (tenant_id, interview_id, panelist_id, panelist_name, scores, overall, recommendation, strengths, concerns, submitted_at)
        select t, iv, panel[1], names[1],
          (select coalesce(jsonb_object_agg(m.v ->> 'name', case when a ->> 'cand' = 'c1' then 4 + (m.k % 2) else 4 end), '{}')
             from jsonb_array_elements((select must_have from hrm.job_descriptions where job_descriptions.id = req.jd_id)) with ordinality m(v, k)),
          case when a ->> 'cand' = 'c1' then 5 else 4 end,
          case when a ->> 'cand' = 'c1' then 'strong_hire' else 'hire' end,
          case a ->> 'cand' when 'c1' then 'Clear 8D examples with numbers; knows PPAP and MSA in depth; calm with customer escalations'
                            when 'c7' then 'Set and ran the practical job without help; good gauge handling; disciplined 5S habits'
                            else 'Fast, confident setter; understands offsets and tool wear well' end,
          case a ->> 'cand' when 'c1' then 'Limited supplier-quality exposure' when 'c7' then 'New to Siemens controls' else 'Inspection basics need coaching; salary at the top of the band' end,
          (case a ->> 'cand' when 'c1' then current_date - 6 when 'c10' then current_date - 12 else current_date - 20 end + time '13:00') at time zone ist;
      end if;
    end if;

    -- offers
    o := a -> 'offer';
    if o is not null and o <> 'null'::jsonb then
      k := k + 1;
      select e.id into mgr from hrm.employees e join hrm.designations dg on dg.id = e.designation_id
       where e.tenant_id = t and e.department_id = req.department_id and dg.name in ('Manager','Senior Engineer','Supervisor','Engineer','Assistant Manager')
       order by case dg.name when 'Manager' then 0 when 'Senior Engineer' then 1 when 'Supervisor' then 2 when 'Assistant Manager' then 3 else 4 end limit 1;
      insert into hrm.offers (tenant_id, application_id, ref_no, designation_id, department_id, plant_id, reporting_manager_id, employment_type, category,
          date_of_joining, annual_ctc, monthly_gross, breakup, pf_applicable, include_gratuity, valid_until, status, sent_at, viewed_at, responded_at,
          accepted_name, decline_reason, terms, created_by, created_at)
      values (t, app, 'OFF-SMP-' || lpad(k::text, 2, '0'), req.designation_id, req.department_id, req.plant_id, mgr, 'probation',
          case when req.title ilike '%operator%' then 'workman' else 'staff' end,
          case o ->> 'status' when 'accepted' then current_date + 5 when 'sent' then current_date + 30 else current_date + 10 end,
          (o ->> 'ctc')::numeric, (o ->> 'gross')::numeric, o -> 'breakup', true, true,
          case o ->> 'status' when 'sent' then current_date + 5 else current_date - 5 end,
          o ->> 'status',
          case o ->> 'status' when 'sent' then now() - interval '2 days' when 'accepted' then now() - interval '17 days' else now() - interval '11 days' end,
          case o ->> 'status' when 'sent' then now() - interval '1 day' when 'accepted' then now() - interval '16 days' else now() - interval '9 days' end,
          case o ->> 'status' when 'accepted' then now() - interval '15 days' when 'declined' then now() - interval '8 days' end,
          case o ->> 'status' when 'accepted' then (select full_name from hrm.candidates where id = (ids ->> ('cand_' || (a ->> 'cand')))::uuid) end,
          case o ->> 'status' when 'declined' then 'Accepted a counter-offer from my current employer' end,
          terms, me, now() - interval '12 days')
      returning offers.id into nid;
      if o ->> 'status' = 'declined' then update hrm.applications set status = 'withdrawn' where applications.id = app; end if;

      -- the accepted offer: the new joiner, with the salary from the offer, waiting to finish onboarding
      if o ->> 'status' = 'accepted' then
        select * into c from hrm.candidates where candidates.id = (ids ->> ('cand_' || (a ->> 'cand')))::uuid;
        nm := regexp_split_to_array(trim(c.full_name), '\s+');
        if not exists (select 1 from hrm.employees where tenant_id = t and email = c.email) then
          insert into hrm.employees (tenant_id, status, first_name, last_name, email, mobile, plant_id, department_id, designation_id, reporting_manager_id,
              employment_type, category, date_of_joining, created_by)
          values (t, 'invited', array_to_string(nm[1:greatest(cardinality(nm) - 1, 1)], ' '), case when cardinality(nm) > 1 then nm[cardinality(nm)] end,
              c.email, c.phone, req.plant_id, req.department_id, req.designation_id, mgr, 'probation', 'workman', current_date + 5, me)
          returning employees.id into emp;
          insert into hrm.salary_structures (tenant_id, employee_id, effective_from, monthly_gross, components, pf_applicable, notes, created_by)
          values (t, emp, current_date + 5, (o ->> 'gross')::numeric,
            (select coalesce(jsonb_agg(jsonb_build_object('code', e ->> 'code', 'name', e ->> 'name', 'amount', (e ->> 'monthly')::numeric)), '[]')
               from jsonb_array_elements(o -> 'breakup' -> 'earnings') e where e ->> 'code' not in ('OT', 'ADJ')),
            true, 'From offer OFF-SMP-' || lpad(n::text, 2, '0'), me);
        else
          select e.id into emp from hrm.employees e where e.tenant_id = t and e.email = c.email;
        end if;
        update hrm.offers set employee_id = emp where offers.id = nid;
      end if;
    end if;
  end loop;
  return n;
end $fn$;

-- remove the sample hiring flow (interviews, scorecards and offers go with their opening and candidate)
create or replace function hrm.demo_recruit_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int;
begin
  select count(*) into n from hrm.candidates where tenant_id = p_tenant and sample;
  delete from hrm.requisitions where tenant_id = p_tenant and sample;
  delete from hrm.candidates where tenant_id = p_tenant and sample;
  delete from hrm.job_descriptions j where j.tenant_id = p_tenant and j.sample
     and not exists (select 1 from hrm.requisitions r where r.jd_id = j.id);
  return n;
end $fn$;

-- ---------- one call for all the sample data that follows the sample employees (more modules join here) ----------
create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  return jsonb_build_object('recruitment', hrm.demo_recruit(p_tenant));
end $fn$;

-- the sample flush now also clears the sample hiring flow
create or replace function hrm.demo_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n integer;
begin
  perform hrm.demo_recruit_flush(p_tenant);
  update hrm.employees set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  update hrm.offers set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  delete from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test';
  get diagnostics n = row_count;
  delete from hrm.plants p where p.tenant_id = p_tenant and p.code in ('DP1','DP2') and not exists (select 1 from hrm.employees e where e.plant_id = p.id);
  return n;
end $fn$;

revoke all on function hrm.demo_recruit(uuid), hrm.demo_recruit_flush(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_recruit(uuid), hrm.demo_recruit_flush(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) to service_role;

-- companies that already hold the sample employees get the sample hiring flow now
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_flow(r); end loop;
end $$;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0008_qms.sql
-- =====================================================================
-- =====================================================================
-- HRM Phase 5A — QMS people development (IATF 16949 7.2 / 7.3, ISO 9001 5.3, 6.2, 7.2, 9.1). Needs 0001–0007.
-- Safe to re-run.
--  • Roles & responsibilities per designation, with authority, deputy and interfaces; employees acknowledge them
--  • KPIs per designation, monthly values per employee, scorecards
--  • Competency library, required level per designation, assessed level per employee → gaps
--  • Skill matrix: operations / machines × people, levels 0–4; alerts when a line is short of qualified people
--  • Training needs (TNI) from gaps, new joiners, changes, complaints, audit findings and requests
--  • Training programmes, sessions (the plan), attendance (by ID-card scan or by hand), pre/post test, sign-off
--  • Training effectiveness by the supervisor after 30/60/90 days; not effective → retraining need
--  • On-the-job training checklists (incl. customer-specific requirements and consequences of nonconformity)
--  • Internal auditor register and audits done
-- Who sees what: HR (and company admins) everything; a reporting manager his team's records, and he assesses skills,
-- enters KPI values and evaluates training effectiveness for his team; each employee his own records.
-- Everything marked "sample" (and everything of the sample people) is sample data: the sample flush removes it.
-- =====================================================================

-- ---------- settings ----------
create table if not exists hrm.qms_settings (
  tenant_id        uuid primary key references hrm.tenants(id) on delete cascade,
  quality_policy   text check (length(quality_policy) <= 3000),
  objectives       text[] not null default '{}',             -- quality objectives employees must know
  csr              text[] not null default '{}',             -- customer-specific requirements for awareness
  min_qualified    integer not null default 2 check (min_qualified between 1 and 20),   -- per operation, level 3 or 4
  eff_days         integer not null default 30 check (eff_days in (30, 60, 90)),        -- effectiveness check after
  new_joiner_days  integer not null default 30 check (new_joiner_days between 1 and 180),
  updated_at       timestamptz not null default now()
);

-- ---------- roles & responsibilities (ISO 9001 5.3) ----------
create table if not exists hrm.rr_roles (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid not null references hrm.designations(id) on delete cascade,
  department_id    uuid references hrm.departments(id) on delete set null,   -- blank = the designation in every department
  purpose          text check (length(purpose) <= 1500),
  responsibilities text[] not null default '{}',
  authorities      text[] not null default '{}',             -- e.g. "Stop the line on a quality doubt"
  deputy           text check (length(deputy) <= 120),      -- who stands in when the person is away
  interfaces       text[] not null default '{}',             -- internal / external contacts
  version          integer not null default 1,
  status           text not null default 'draft' check (status in ('draft','approved')),
  approved_by      uuid,
  approved_at      timestamptz,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists rr_roles_desig on hrm.rr_roles (tenant_id, designation_id, coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists hrm.rr_acks (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  rr_id            uuid not null references hrm.rr_roles(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  version          integer not null,
  acknowledged_at  timestamptz not null default now(),
  unique (rr_id, employee_id, version)
);

-- ---------- KPIs (ISO 9001 6.2, 9.1) ----------
create table if not exists hrm.kpis (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid references hrm.designations(id) on delete cascade,
  department_id    uuid references hrm.departments(id) on delete cascade,
  name             text not null check (length(name) between 2 and 120),
  unit             text check (length(unit) <= 20),
  target           numeric(14,3) not null,
  direction        text not null default 'higher' check (direction in ('higher','lower')),   -- higher / lower is better
  frequency        text not null default 'monthly' check (frequency in ('monthly','quarterly')),
  data_source      text check (length(data_source) <= 200),
  weight           integer not null default 1 check (weight between 1 and 5),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists kpis_desig on hrm.kpis (tenant_id, designation_id);

create table if not exists hrm.kpi_values (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  kpi_id           uuid not null references hrm.kpis(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  month            text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  actual           numeric(14,3) not null,
  note             text check (length(note) <= 300),
  entered_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (kpi_id, employee_id, month)
);

-- ---------- competencies (IATF 7.2.1, ISO 9001 7.2) ----------
create table if not exists hrm.competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  name             text not null check (length(name) between 2 and 120),
  category         text not null default 'technical' check (category in ('technical','quality','safety','behavioural','management')),
  description      text check (length(description) <= 600),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, name)
);

create table if not exists hrm.role_competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  designation_id   uuid not null references hrm.designations(id) on delete cascade,
  competency_id    uuid not null references hrm.competencies(id) on delete cascade,
  required_level   integer not null check (required_level between 1 and 4),
  sample           boolean not null default false,
  unique (designation_id, competency_id)
);

create table if not exists hrm.employee_competencies (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  competency_id    uuid not null references hrm.competencies(id) on delete cascade,
  level            integer not null check (level between 0 and 4),
  assessed_on      date not null default current_date,
  assessed_by      uuid,
  assessed_by_name text,
  method           text check (method in ('observation','test','interview','records','certificate','training')),
  note             text check (length(note) <= 300),
  updated_at       timestamptz not null default now(),
  unique (employee_id, competency_id)
);

-- ---------- skill matrix (IATF 7.2.1, 7.2.3) ----------
create table if not exists hrm.operations (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  plant_id         uuid references hrm.plants(id) on delete set null,
  line             text not null check (length(line) between 1 and 80),       -- line / cell / area
  code             text not null check (length(code) between 1 and 20),       -- e.g. OP10
  name             text not null check (length(name) between 2 and 120),
  machine          text check (length(machine) <= 80),
  critical         boolean not null default false,          -- special / safety characteristic: never without a qualified person
  min_qualified    integer check (min_qualified between 1 and 20),   -- blank = the company setting
  safety_required  boolean not null default false,          -- safety training needed before working here
  sort_order       integer not null default 0,
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, line, code)
);

create table if not exists hrm.skill_levels (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  operation_id     uuid not null references hrm.operations(id) on delete cascade,
  level            integer not null check (level between 0 and 4),
  certified_on     date,
  valid_until      date,                                    -- re-certification due
  assessed_by      uuid,
  assessed_by_name text,
  note             text check (length(note) <= 300),
  updated_at       timestamptz not null default now(),
  unique (employee_id, operation_id)
);

-- ---------- training programmes, sessions, attendance (ISO 9001 7.2, IATF 7.2.1, 7.3) ----------
create table if not exists hrm.training_programs (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  category         text not null default 'technical' check (category in ('induction','safety','quality','technical','awareness','core_tools','behavioural','ojt')),
  competency_id    uuid references hrm.competencies(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  duration_hours   numeric(5,1) not null default 2 check (duration_hours > 0 and duration_hours <= 200),
  eval_method      text not null default 'observation' check (eval_method in ('test','observation','kpi','signoff')),
  eff_days         integer check (eff_days in (30, 60, 90)),          -- blank = company setting; sign-off has none
  pass_mark        integer not null default 60 check (pass_mark between 0 and 100),
  content          text check (length(content) <= 3000),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (tenant_id, title)
);

create table if not exists hrm.training_sessions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  program_id       uuid not null references hrm.training_programs(id) on delete cascade,
  plan_month       text not null check (plan_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  starts_at        timestamptz,                             -- blank while only planned for the month
  ends_at          timestamptz,
  venue            text check (length(venue) <= 120),
  trainer          text check (length(trainer) <= 120),
  trainer_employee_id uuid references hrm.employees(id) on delete set null,
  status           text not null default 'planned' check (status in ('planned','scheduled','done','cancelled')),
  notes            text check (length(notes) <= 1000),
  invited_at       timestamptz,
  reminded_at      timestamptz,
  completed_at     timestamptz,
  sample           boolean not null default false,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists training_sessions_month on hrm.training_sessions (tenant_id, plan_month);

create table if not exists hrm.training_needs (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  program_id       uuid references hrm.training_programs(id) on delete set null,
  competency_id    uuid references hrm.competencies(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  topic            text not null check (length(topic) between 2 and 200),
  source           text not null check (source in ('competency_gap','skill_gap','new_joiner','process_change','customer_complaint','audit_finding','request','retraining','awareness','recertification')),
  reason           text check (length(reason) <= 500),
  priority         text not null default 'normal' check (priority in ('high','normal','low')),
  status           text not null default 'open' check (status in ('open','planned','trained','closed','cancelled')),
  target_month     text check (target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  session_id       uuid references hrm.training_sessions(id) on delete set null,
  raised_by        uuid,
  raised_by_name   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists training_needs_open on hrm.training_needs (tenant_id, status);
-- one open need per person for the same thing (re-running "Find training needs" adds nothing twice)
create unique index if not exists training_needs_once on hrm.training_needs (employee_id, source, coalesce(competency_id, operation_id, program_id))
  where status in ('open','planned') and coalesce(competency_id, operation_id, program_id) is not null;

create table if not exists hrm.training_attendance (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  session_id       uuid not null references hrm.training_sessions(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  need_id          uuid references hrm.training_needs(id) on delete set null,
  attended         boolean,                                 -- null = not marked yet
  method           text check (method in ('scan','manual','biometric')),
  marked_at        timestamptz,
  pre_score        integer check (pre_score between 0 and 100),
  post_score       integer check (post_score between 0 and 100),
  acknowledged_at  timestamptz,                             -- awareness sign-off by the employee
  unique (session_id, employee_id)
);

create table if not exists hrm.training_effectiveness (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  attendance_id    uuid not null unique references hrm.training_attendance(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  session_id       uuid not null references hrm.training_sessions(id) on delete cascade,
  due_on           date not null,
  evaluator_id     uuid references hrm.employees(id) on delete set null,     -- the supervisor who evaluates
  result           text check (result in ('effective','partly','not_effective')),
  rating           integer check (rating between 1 and 5),
  evidence         text check (length(evidence) <= 600),     -- what was observed / KPI change
  evaluated_by     uuid,
  evaluated_by_name text,
  evaluated_at     timestamptz,
  retrain_need_id  uuid references hrm.training_needs(id) on delete set null,
  notified_at      timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists training_eff_due on hrm.training_effectiveness (tenant_id, due_on) where result is null;

-- ---------- on-the-job training (IATF 7.2.2) ----------
create table if not exists hrm.ojt_templates (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  designation_id   uuid references hrm.designations(id) on delete set null,
  operation_id     uuid references hrm.operations(id) on delete set null,
  items            jsonb not null default '[]',             -- [{text, kind: task | csr | nc}]
  days             integer not null default 15 check (days between 1 and 180),
  active           boolean not null default true,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists hrm.ojt_records (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  template_id      uuid not null references hrm.ojt_templates(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  trainer          text check (length(trainer) <= 120),
  started_on       date not null default current_date,
  done             jsonb not null default '[]',             -- indexes of the items completed
  status           text not null default 'in_progress' check (status in ('in_progress','completed','cancelled')),
  completed_on     date,
  signed_off_by    uuid,
  signed_off_name  text,
  remarks          text check (length(remarks) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (template_id, employee_id)
);

-- ---------- internal auditors (IATF 7.2.3) ----------
create table if not exists hrm.auditors (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,
  kind             text not null default 'qms' check (kind in ('qms','process','product','supplier')),
  standards        text[] not null default '{}',             -- IATF 16949, ISO 9001, VDA 6.3, ISO 14001, ISO 45001
  qualification    text check (length(qualification) <= 200),
  trained_on       date,
  certificate_no   text check (length(certificate_no) <= 60),
  valid_until      date,
  core_tools       text[] not null default '{}',             -- APQP, PPAP, FMEA, SPC, MSA
  csr_trained      boolean not null default false,
  audits_per_year  integer not null default 2 check (audits_per_year between 0 and 50),   -- to keep the qualification
  active           boolean not null default true,
  notified_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (employee_id, kind)
);

create table if not exists hrm.auditor_audits (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  auditor_id       uuid not null references hrm.auditors(id) on delete cascade,
  audit_date       date not null,
  area             text not null check (length(area) between 2 and 160),
  audit_type       text not null default 'system' check (audit_type in ('system','process','product','supplier','layered')),
  role             text not null default 'auditor' check (role in ('lead','auditor','observer')),
  findings         integer check (findings between 0 and 500),
  created_at       timestamptz not null default now()
);

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['qms_settings','rr_roles','kpis','kpi_values','employee_competencies','skill_levels','training_sessions','training_needs','ojt_templates','ojt_records','auditors'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['qms_settings','rr_roles','rr_acks','kpis','kpi_values','competencies','role_competencies','employee_competencies','operations','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$
declare t text;
begin
  foreach t in array array['qms_settings','rr_roles','rr_acks','kpis','kpi_values','competencies','role_competencies','employee_competencies','operations','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
  -- the company's libraries: everyone in the company reads them
  foreach t in array array['qms_settings','rr_roles','kpis','competencies','role_competencies','operations','training_programs','training_sessions','ojt_templates'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_read', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id())', t || '_read', t);
  end loop;
  -- each employee: his own records
  foreach t in array array['rr_acks','kpi_values','employee_competencies','skill_levels','training_needs','training_attendance','training_effectiveness','ojt_records','auditors'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_self', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id())', t || '_self', t);
  end loop;
  -- a reporting manager: his team's records
  foreach t in array array['rr_acks','kpi_values','employee_competencies','skill_levels','training_needs','training_attendance','training_effectiveness','ojt_records'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_team', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team', t);
  end loop;
  -- … and he assesses skills and competencies, enters KPI values and asks for training for his team
  foreach t in array array['kpi_values','employee_competencies','skill_levels','ojt_records'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_team_write', t);
    execute format('create policy %I on hrm.%I for insert to authenticated with check (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id))', t || '_team_write', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_team_edit', t);
    execute format('create policy %I on hrm.%I for update to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role(''manager'') and hrm.is_in_my_team(employee_id)) with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id))', t || '_team_edit', t);
  end loop;
end $$;
drop policy if exists training_needs_team_write on hrm.training_needs;
create policy training_needs_team_write on hrm.training_needs for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id) and source = 'request' and status = 'open');
drop policy if exists training_effectiveness_team_edit on hrm.training_effectiveness;
create policy training_effectiveness_team_edit on hrm.training_effectiveness for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id))
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id));
-- the audits an auditor did
drop policy if exists auditor_audits_self on hrm.auditor_audits;
create policy auditor_audits_self on hrm.auditor_audits for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and exists (select 1 from hrm.auditors a where a.id = auditor_id and a.employee_id = hrm.current_employee_id()));

-- ---------- defaults for a company: a ready competency library and training programmes ----------
create or replace function hrm.seed_qms_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.qms_settings (tenant_id, objectives) values (p_tenant, array[
    'Customer PPM below the target agreed with each customer',
    'On-time delivery 98% or better',
    'Every person trained and qualified before working alone on an operation'])
  on conflict do nothing;
  insert into hrm.competencies (tenant_id, name, category, description)
  select p_tenant, x.n, x.c, x.d from (values
    ('Reading drawings & GD&T', 'technical', 'Reads dimensions, tolerances, fits, GD&T and notes on the drawing'),
    ('Measuring instruments', 'technical', 'Vernier, micrometer, bore gauge, height gauge, plug / snap gauges; zero setting and care'),
    ('Machine setting & first-off approval', 'technical', 'Sets the machine as per the set-up sheet and gets the first piece approved'),
    ('CNC operation', 'technical', 'Runs CNC turning / milling as per the work instruction; offsets, tool change, alarms'),
    ('Preventive & autonomous maintenance', 'technical', 'Daily checklist, lubrication, cleaning, abnormality tagging; PM as per schedule'),
    ('Control plan & work instructions', 'quality', 'Follows the control plan, reaction plan and work instruction at the station'),
    ('Core tools — APQP & PPAP', 'quality', 'Plans a new part launch and prepares the PPAP elements'),
    ('Core tools — FMEA', 'quality', 'Builds and reviews PFMEA (AIAG-VDA), action priority'),
    ('Core tools — SPC & MSA', 'quality', 'Control charts, Cp/Cpk, GR&R, bias and linearity'),
    ('Problem solving (8D, why-why)', 'quality', 'Containment, root cause, corrective and preventive action, effectiveness'),
    ('Internal auditing', 'quality', 'Plans and conducts system / process / product audits; writes findings'),
    ('Safety rules & PPE', 'safety', 'Follows the safety rules of the shop and wears the right PPE'),
    ('Fire safety & emergency', 'safety', 'Raises the alarm, uses an extinguisher, evacuates by the route'),
    ('Lock-out tag-out & machine guarding', 'safety', 'Isolates energy before maintenance; never bypasses a guard'),
    ('5S & workplace discipline', 'behavioural', 'Sort, set in order, shine, standardise, sustain at the workplace'),
    ('Communication & teamwork', 'behavioural', 'Shift handover, reporting problems, working with other departments'),
    ('Leadership & people management', 'management', 'Plans manpower, sets targets, reviews and develops the team'),
    ('Lean & Kaizen', 'management', 'Finds waste and makes small improvements that last')
  ) x(n, c, d)
  on conflict (tenant_id, name) do nothing;
  insert into hrm.training_programs (tenant_id, title, category, competency_id, duration_hours, eval_method, eff_days, pass_mark, content)
  select p_tenant, x.t, x.c, (select id from hrm.competencies where tenant_id = p_tenant and name = x.comp), x.h, x.m, x.e, x.p, x.content from (values
    ('Induction — company, HR rules and facilities', 'induction', null, 4.0, 'signoff', null::int, 60, 'Company, products and customers; standing orders; attendance and leave; canteen, transport, first aid'),
    ('Safety induction', 'safety', 'Safety rules & PPE', 3.0, 'test', 30, 70, 'Shop safety rules, PPE, hazards, near-miss reporting, emergency exits'),
    ('Quality policy, objectives & product safety', 'awareness', null, 1.0, 'signoff', null, 60, 'The quality policy and objectives, how each person contributes, product safety (IATF 7.3)'),
    ('Customer-specific requirements', 'awareness', null, 1.0, 'signoff', null, 60, 'What each customer asks for beyond the standard, and how it applies at the workplace'),
    ('Consequences of nonconformity', 'awareness', null, 1.0, 'signoff', null, 60, 'What happens to the customer and the end user when a bad part goes out'),
    ('Measuring instruments & first-off inspection', 'technical', 'Measuring instruments', 4.0, 'observation', 30, 70, 'Instruments, zero setting, recording, first-off approval'),
    ('Reading drawings & GD&T', 'technical', 'Reading drawings & GD&T', 6.0, 'test', 60, 70, 'Views, dimensions, tolerances, fits, GD&T symbols, notes'),
    ('5S & workplace discipline', 'behavioural', '5S & workplace discipline', 2.0, 'observation', 30, 60, 'The 5 steps, red tags, audits'),
    ('Core tools — FMEA', 'core_tools', 'Core tools — FMEA', 8.0, 'test', 90, 70, 'AIAG-VDA FMEA 7 steps, action priority'),
    ('Core tools — SPC & MSA', 'core_tools', 'Core tools — SPC & MSA', 8.0, 'test', 90, 70, 'Control charts, capability, GR&R'),
    ('Problem solving — 8D', 'quality', 'Problem solving (8D, why-why)', 4.0, 'kpi', 90, 60, '8 disciplines with a real case'),
    ('IATF 16949 internal auditor', 'quality', 'Internal auditing', 16.0, 'test', 90, 70, 'Process approach, turtle diagram, audit plan, findings, CSR'),
    ('Fire safety & evacuation drill', 'safety', 'Fire safety & emergency', 2.0, 'observation', 30, 60, 'Fire classes, extinguishers, evacuation and assembly point'),
    ('Lock-out tag-out', 'safety', 'Lock-out tag-out & machine guarding', 2.0, 'observation', 30, 70, 'Energy sources, isolation, locks and tags, try-out')
  ) x(t, c, comp, h, m, e, p, content)
  on conflict (tenant_id, title) do nothing;
end $fn$;
revoke all on function hrm.seed_qms_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_qms_defaults(uuid) to service_role;
-- every new company gets the payroll, recruitment and QMS defaults the moment it is created (the console's
-- "add customer", the HRM's own setup file, scripts/create-tenant.mjs) — and the companies already there get them now
create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  return new;
end $fn$;
drop trigger if exists tenants_seed_modules on hrm.tenants;
create trigger tenants_seed_modules after insert on hrm.tenants for each row execute function hrm.seed_new_tenant();
do $$ declare t uuid; begin for t in select id from hrm.tenants loop
  perform hrm.seed_payroll_defaults(t); perform hrm.seed_recruit_defaults(t); perform hrm.seed_qms_defaults(t);
end loop; end $$;

-- ---------- clearing: one function every flush calls (later modules add their tables here) ----------
-- p_mode 'all'    — everything (the Data Master's full HRM flush); the default library comes back
--        'real'   — the company's own records; sample records stay (Grand Master › Flush real data). The competency
--                   library and training programmes are company setup (like plants and designations) and stay.
--        'sample' — sample records only (Grand Master › Flush sample data)
-- Records of people go with the people (the flushes delete the employees); this clears the company-level lists.
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['training_sessions','ojt_templates','kpis','rr_roles','role_competencies','operations']
                       else array['training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backups include the QMS records ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 4, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
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
  perform hrm.seed_qms_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- =====================================================================
-- Sample data: the QMS records of the sample people, joined up with their plants, designations and the hiring flow
-- =====================================================================
create or replace function hrm.demo_qms(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant; pfx text; p1 uuid; p2 uuid; rec record; i int; n int := 0;
  op_ids uuid[]; op uuid; lvl int; sess uuid; prog uuid; att uuid; tpl uuid; aud uuid; kpi uuid; m text; k int;
  d_op uuid; d_sop uuid; d_tech uuid; d_eng uuid; d_sup uuid; d_seng uuid;
  -- skill levels: rows = sample people D003…D024 (production), columns = OP10…OP60 (0 not trained … 4 trainer)
  grid int[][] := array[
    [4,3,3,2,3,1],   -- D003 Karthik
    [3,2,3,3,1,0],   -- D004 Divya
    [3,3,2,1,2,0],   -- D010 Anitha
    [4,4,3,3,3,3],   -- D011 Manoj (senior operator, trainer)
    [2,1,3,0,3,0],   -- D012 Kavya
    [3,0,2,0,3,1],   -- D015 Ganesh
    [1,0,3,0,2,0],   -- D016 Sowmya
    [2,0,1,0,3,0],   -- D020 Revathi (contract)
    [1,0,0,0,2,0],   -- D021 Naveen (contract)
    [0,0,1,0,1,0],   -- D023 Senthil (contract)
    [3,2,2,0,3,0]];  -- D024 Bhavya
  who int[] := array[3,4,10,11,12,15,16,20,21,23,24];
  emp uuid;
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if not exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then return 0; end if;
  if exists (select 1 from hrm.operations where tenant_id = t and sample) then return 0; end if;     -- already there
  perform hrm.seed_qms_defaults(t);
  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';
  select id into p2 from hrm.plants where tenant_id = t and code = 'DP2';
  select id into d_op from hrm.designations where tenant_id = t and name = 'Operator';
  select id into d_sop from hrm.designations where tenant_id = t and name = 'Senior Operator';
  select id into d_tech from hrm.designations where tenant_id = t and name = 'Technician';
  select id into d_eng from hrm.designations where tenant_id = t and name = 'Engineer';
  select id into d_sup from hrm.designations where tenant_id = t and name = 'Supervisor';
  select id into d_seng from hrm.designations where tenant_id = t and name = 'Senior Engineer';

  update hrm.qms_settings set quality_policy = coalesce(quality_policy,
    'We make precision machined components right the first time and deliver them on time, every time. We meet our customers'' requirements and applicable statutory and regulatory requirements, train every person for the job, and improve our processes continually.'),
    csr = case when cardinality(csr) = 0 then array['Customer A: 100% inspection of the bore for the first 3 lots after any change','Customer B: PPAP level 3 for every engineering change','Customer A: retain first-off parts for one shift'] else csr end
   where tenant_id = t;

  -- ---- operations of two lines (skill matrix) ----
  insert into hrm.operations (tenant_id, plant_id, line, code, name, machine, critical, min_qualified, safety_required, sort_order, sample) values
    (t, p1, 'Turning cell 1', 'OP10', 'CNC turning — 1st setup', 'LT-01 Ace Jobber', true, null, false, 10, true),
    (t, p1, 'Turning cell 1', 'OP20', 'CNC turning — 2nd setup', 'LT-02 Ace Jobber', false, null, false, 20, true),
    (t, p1, 'Turning cell 1', 'OP30', 'VMC drilling & tapping', 'VMC-03 BFW', false, null, false, 30, true),
    (t, p1, 'Turning cell 1', 'OP40', 'Final inspection (bore & thread)', 'Inspection table', true, 3, false, 40, true),
    (t, p1, 'Assembly',       'OP50', 'Washing & packing', 'Washer WS-1', false, null, false, 50, true),
    (t, p1, 'Assembly',       'OP60', 'Bush press-fit', 'Hydraulic press HP-20T', true, null, true, 60, true);
  select array_agg(id order by sort_order) into op_ids from hrm.operations where tenant_id = t and sample;
  for i in 1..array_length(who, 1) loop
    select id into emp from hrm.employees where tenant_id = t and employee_code = pfx || '-D' || lpad(who[i]::text, 3, '0');
    if emp is null then continue; end if;
    for k in 1..6 loop
      lvl := grid[i][k];
      if lvl = 0 then continue; end if;
      insert into hrm.skill_levels (tenant_id, employee_id, operation_id, level, certified_on, valid_until, assessed_by_name, note)
      values (t, emp, op_ids[k], lvl, case when lvl >= 3 then current_date - (60 + i * 11) end,
              case when lvl >= 3 then current_date - (60 + i * 11) + 365 + case when i = 1 and k = 1 then -320 else 0 end end,
              'Priya Sharma', case when lvl = 1 then 'Under training with Manoj' end);
      n := n + 1;
    end loop;
  end loop;

  -- ---- competencies required per designation, and assessed levels ----
  insert into hrm.role_competencies (tenant_id, designation_id, competency_id, required_level, sample)
  select t, d.id, c.id, x.lvl, true
    from (values ('Operator','Measuring instruments',3), ('Operator','Control plan & work instructions',3), ('Operator','Safety rules & PPE',3), ('Operator','5S & workplace discipline',2), ('Operator','CNC operation',2),
                 ('Senior Operator','Measuring instruments',3), ('Senior Operator','Machine setting & first-off approval',3), ('Senior Operator','CNC operation',3), ('Senior Operator','Safety rules & PPE',3), ('Senior Operator','Reading drawings & GD&T',2),
                 ('Technician','Preventive & autonomous maintenance',3), ('Technician','Lock-out tag-out & machine guarding',3), ('Technician','Measuring instruments',2), ('Technician','Safety rules & PPE',3),
                 ('Engineer','Core tools — FMEA',3), ('Engineer','Core tools — SPC & MSA',3), ('Engineer','Problem solving (8D, why-why)',3), ('Engineer','Reading drawings & GD&T',3), ('Engineer','Internal auditing',2),
                 ('Supervisor','Leadership & people management',3), ('Supervisor','Control plan & work instructions',3), ('Supervisor','Problem solving (8D, why-why)',2), ('Supervisor','Safety rules & PPE',3),
                 ('Senior Engineer','Core tools — APQP & PPAP',4), ('Senior Engineer','Core tools — FMEA',3), ('Senior Engineer','Leadership & people management',2))
         x(desig, comp, lvl)
    join hrm.designations d on d.tenant_id = t and d.name = x.desig
    join hrm.competencies c on c.tenant_id = t and c.name = x.comp
  on conflict (designation_id, competency_id) do nothing;
  -- assessed: most meet the requirement, some one level short (the gaps the TNI picks up)
  insert into hrm.employee_competencies (tenant_id, employee_id, competency_id, level, assessed_on, assessed_by_name, method)
  select t, e.id, rc.competency_id,
         greatest(0, rc.required_level - case when (abs(hashtext(e.id::text || rc.competency_id::text)) % 5) = 0 then 1 when (abs(hashtext(e.id::text || rc.competency_id::text)) % 11) = 0 then 2 else 0 end
                                        + case when (abs(hashtext(rc.competency_id::text || e.id::text)) % 7) = 0 and rc.required_level < 4 then 1 else 0 end),
         current_date - (abs(hashtext(e.id::text)) % 120), 'Arun Kumar', 'observation'
    from hrm.employees e join hrm.role_competencies rc on rc.designation_id = e.designation_id and rc.sample
   where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
  on conflict (employee_id, competency_id) do nothing;

  -- ---- roles & responsibilities ----
  insert into hrm.rr_roles (tenant_id, designation_id, purpose, responsibilities, authorities, deputy, interfaces, version, status, approved_at, sample) values
    (t, d_op, 'Make good parts at the planned output, safely, as per the work instruction and control plan.',
       array['Run the machine as per the work instruction and set-up sheet','Do first-off and in-process checks and record them in the check sheet','Stop and inform the supervisor on any abnormality or doubt about quality','Keep the workplace in 5S and do the daily autonomous maintenance checks','Wear PPE and follow the safety rules'],
       array['Stop the machine on a quality or safety doubt','Segregate and red-tag suspect parts'], 'Senior Operator of the cell', array['Shift supervisor','Quality inspector','Maintenance technician'], 2, 'approved', now() - interval '120 days', true),
    (t, d_sup, 'Run the shift: people, output, quality and safety of the line.',
       array['Plan manpower for the shift using the skill matrix','Release the first-off and review check sheets','Lead the daily quality and safety meeting','Raise training needs for the team and evaluate training effectiveness','Escalate abnormalities through the escalation matrix'],
       array['Stop the line on a quality, safety or delivery risk','Move people between operations within their qualification'], 'Senior Operator nominated by the Production Manager', array['Production Manager','Quality','Maintenance','PPC','Stores'], 1, 'approved', now() - interval '200 days', true),
    (t, d_eng, 'Keep processes capable and customers satisfied; lead problem solving and audits.',
       array['Maintain PFMEA, control plan and work instructions','Run SPC and MSA studies; act on out-of-control signals','Lead 8D for customer and internal complaints','Conduct internal process audits as per the audit plan','Train operators on quality requirements and customer-specific requirements'],
       array['Hold suspect material','Approve first-off on behalf of Quality in the shift'], 'Quality Engineer of the other plant', array['Customer quality','Production','Suppliers','Maintenance'], 1, 'draft', null, true);
  insert into hrm.rr_acks (tenant_id, rr_id, employee_id, version, acknowledged_at)
  select t, r.id, e.id, r.version, now() - ((abs(hashtext(e.id::text)) % 90) || ' days')::interval
    from hrm.rr_roles r join hrm.employees e on e.designation_id = r.designation_id and e.tenant_id = t and e.email like '%@demo.kmr.test'
   where r.tenant_id = t and r.sample and r.status = 'approved' and (abs(hashtext(e.id::text)) % 4) <> 0;

  -- ---- KPIs and three months of values ----
  insert into hrm.kpis (tenant_id, designation_id, name, unit, target, direction, data_source, weight, sample) values
    (t, d_op, 'Output per shift', 'parts', 420, 'higher', 'Production report', 2, true),
    (t, d_op, 'Rejection', '%', 1.0, 'lower', 'Rejection register', 2, true),
    (t, d_op, 'Check-sheet compliance', '%', 100, 'higher', 'Layered process audit', 1, true),
    (t, d_eng, 'Customer PPM', 'PPM', 50, 'lower', 'Customer scorecard', 3, true),
    (t, d_eng, '8D closure time', 'days', 30, 'lower', 'Complaint register', 1, true),
    (t, d_sup, 'OEE of the line', '%', 75, 'higher', 'OEE sheet', 2, true),
    (t, d_sup, 'Safety incidents', 'nos', 0, 'lower', 'Incident register', 2, true);
  for k in 1..3 loop
    m := to_char(date_trunc('month', current_date) - (k || ' months')::interval, 'YYYY-MM');
    insert into hrm.kpi_values (tenant_id, kpi_id, employee_id, month, actual, entered_by)
    select t, kp.id, e.id, m,
           round((kp.target * case kp.direction when 'higher' then 0.9 + (abs(hashtext(e.id::text || m || kp.id::text)) % 20) / 100.0
                                                else 0.6 + (abs(hashtext(e.id::text || m || kp.id::text)) % 90) / 100.0 end
                  + case when kp.target = 0 then (abs(hashtext(e.id::text || m)) % 3) / 2 else 0 end)::numeric, case when kp.unit in ('%','PPM') then 1 else 0 end), null
      from hrm.kpis kp join hrm.employees e on e.designation_id = kp.designation_id and e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
     where kp.tenant_id = t and kp.sample
    on conflict do nothing;
  end loop;

  -- ---- training: three sessions done, one this week, one planned next month ----
  -- 1) quality policy awareness, 75 days ago, everybody on the production floor, signed off
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Quality policy, objectives & product safety';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 75, 'YYYY-MM'), ((current_date - 75) + time '10:00') at time zone 'Asia/Kolkata', ((current_date - 75) + time '11:00') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Suresh Reddy (Quality)', 'done', (current_date - 75)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, acknowledged_at)
  select t, sess, e.id, e.employee_code <> pfx || '-D016', 'scan', (current_date - 75)::timestamptz, case when e.employee_code <> pfx || '-D016' then (current_date - 74)::timestamptz end
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.department_id in (select id from hrm.departments where tenant_id = t and name in ('Production','Quality'));
  -- 2) measuring instruments & first-off, 40 days ago: pre/post test, effectiveness due (one effective, one not, rest due / overdue)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Measuring instruments & first-off inspection';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, trainer_employee_id, status, completed_at, sample)
  values (t, prog, to_char(current_date - 40, 'YYYY-MM'), ((current_date - 40) + time '14:00') at time zone 'Asia/Kolkata', ((current_date - 40) + time '18:00') at time zone 'Asia/Kolkata',
          'Quality lab, Plant 1', 'Manoj Gowda', (select id from hrm.employees where tenant_id = t and employee_code = pfx || '-D011'), 'done', (current_date - 40)::timestamptz, true) returning id into sess;
  i := 0;
  for rec in select id, employee_code, reporting_manager_id from hrm.employees where tenant_id = t and employee_code = any(array[pfx||'-D012', pfx||'-D015', pfx||'-D016', pfx||'-D020', pfx||'-D021', pfx||'-D023']) order by employee_code loop
    i := i + 1;
    insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
    values (t, sess, rec.id, true, 'scan', (current_date - 40)::timestamptz, 35 + i * 5, case when i = 5 then 55 else 70 + i * 4 end) returning id into att;
    insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id, result, rating, evidence, evaluated_by_name, evaluated_at)
    values (t, att, rec.id, sess, current_date - 10, rec.reporting_manager_id,
            case i when 1 then 'effective' when 5 then 'not_effective' end, case i when 1 then 4 when 5 then 2 end,
            case i when 1 then 'Did first-off on OP20 alone for two weeks; all readings correct' when 5 then 'Zero setting of the micrometer still missed twice in the layered audit' end,
            case when i in (1, 5) then 'Priya Sharma' end, case when i in (1, 5) then now() - interval '6 days' end);
    if i = 5 then
      insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, raised_by_name)
      values (t, rec.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Measuring instruments & first-off inspection (again)', 'retraining',
              'Training of ' || to_char(current_date - 40, 'DD Mon') || ' was not effective: zero setting missed', 'high', 'open', to_char(current_date + 20, 'YYYY-MM'), 'Priya Sharma');
    end if;
  end loop;
  -- 3) safety induction for the new joiners and contract workers, 20 days ago
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Safety induction';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 20, 'YYYY-MM'), ((current_date - 20) + time '09:30') at time zone 'Asia/Kolkata', ((current_date - 20) + time '12:30') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Pooja Singh (EHS)', 'done', (current_date - 20)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
  select t, sess, e.id, true, 'manual', (current_date - 20)::timestamptz, 40 + (abs(hashtext(e.id::text)) % 20), 75 + (abs(hashtext(e.id::text)) % 20)
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.employment_type = 'contract';
  insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id)
  select t, a.id, a.employee_id, sess, current_date + 10, (select reporting_manager_id from hrm.employees where id = a.employee_id)
    from hrm.training_attendance a where a.session_id = sess;
  -- 4) 8D problem solving this week (scheduled, invitations sent)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Problem solving — 8D';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, invited_at, sample)
  values (t, prog, to_char(current_date + 3, 'YYYY-MM'), ((current_date + 3) + time '10:00') at time zone 'Asia/Kolkata', ((current_date + 3) + time '14:00') at time zone 'Asia/Kolkata',
          'Conference room, Plant 1', 'Prakash Babu', 'scheduled', now() - interval '2 days', true) returning id into sess;
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, session_id, raised_by_name)
  select t, e.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Problem solving — 8D', 'customer_complaint',
         'Customer complaint: burr in the cross hole (repeat) — 8D team', 'high', 'planned', to_char(current_date + 3, 'YYYY-MM'), sess, 'Suresh Reddy'
    from hrm.employees e where e.tenant_id = t and e.employee_code = any(array[pfx||'-D005', pfx||'-D006', pfx||'-D013', pfx||'-D011', pfx||'-D002']);
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, need_id)
  select t, sess, n2.employee_id, n2.id from hrm.training_needs n2 where n2.session_id = sess;
  -- 5) planned next month: core tools FMEA for the engineers (from the competency gaps)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Core tools — FMEA';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, venue, trainer, status, sample)
  values (t, prog, to_char(current_date + 32, 'YYYY-MM'), 'Training hall, Plant 1', 'External — certified trainer', 'planned', true) returning id into sess;

  -- open needs of different kinds (the TNI list)
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, operation_id, topic, source, reason, priority, status, target_month, raised_by_name)
  select t, e.id, x.prog, x.comp, x.op, x.topic, x.src, x.reason, x.pri, 'open', to_char(current_date + x.inm, 'YYYY-MM'), x.by
    from (values
      ('-D023', null::uuid, null::uuid, op_ids[1], 'OP10 CNC turning — 1st setup', 'skill_gap', 'Needed as a backup on OP10: only one other person is qualified in the shift', 'high', 15, 'Priya Sharma'),
      ('-D016', null, null, null, 'Quality policy, objectives & product safety', 'awareness', 'Was absent for the awareness session', 'normal', 10, 'Arun Kumar'),
      ('-D009', null, null, null, 'Change of process: new washing chemical (MSDS, concentration check)', 'process_change', 'Engineering change EC-118', 'normal', 20, 'Prakash Babu'),
      ('-D019', null, null, null, 'IATF 16949 internal auditor', 'request', 'Asked to become an internal auditor', 'low', 60, 'Harish Hegde'),
      ('-D007', null, null, null, 'Lock-out tag-out', 'audit_finding', 'Internal audit finding: LOTO not applied on HP-20T during die change', 'high', 7, 'Pooja Singh')
    ) x(code, prog, comp, op, topic, src, reason, pri, inm, by)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  update hrm.training_needs nd set program_id = p.id, competency_id = p.competency_id
    from hrm.training_programs p where nd.tenant_id = t and p.tenant_id = t and nd.program_id is null and p.title = nd.topic;

  -- ---- on-the-job training ----
  insert into hrm.ojt_templates (tenant_id, title, designation_id, operation_id, items, days, sample) values
    (t, 'New operator — CNC turning cell', d_op, op_ids[1], jsonb_build_array(
       jsonb_build_object('text', 'Machine start-up, warm-up and daily checklist', 'kind', 'task'),
       jsonb_build_object('text', 'Reading the work instruction and set-up sheet', 'kind', 'task'),
       jsonb_build_object('text', 'Loading / unloading and chip handling safely', 'kind', 'task'),
       jsonb_build_object('text', 'First-off and in-process checks with the instruments; recording', 'kind', 'task'),
       jsonb_build_object('text', 'Customer A: retain first-off parts for one shift; 100% bore check after a change', 'kind', 'csr'),
       jsonb_build_object('text', 'Consequences of an oversize bore reaching the customer: line stoppage, recall, safety', 'kind', 'nc'),
       jsonb_build_object('text', 'Reaction plan: stop, segregate, red-tag, inform the supervisor', 'kind', 'task'),
       jsonb_build_object('text', 'Works independently for 3 shifts under observation', 'kind', 'task')), 15, true);
  select id into tpl from hrm.ojt_templates where tenant_id = t and sample limit 1;
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status, completed_on, signed_off_name)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 60, '[0,1,2,3,4,5,6,7]'::jsonb, 'completed', current_date - 44, 'Priya Sharma'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D020';
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 6, '[0,1,2]'::jsonb, 'in_progress'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D023';

  -- the new joiner from the sample hiring flow gets the joiner's needs and OJT
  for rec in select id from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status in ('invited','onboarding','submitted','active')
            and id in (select employee_id from hrm.offers where tenant_id = t and employee_id is not null) loop
    insert into hrm.training_needs (tenant_id, employee_id, program_id, topic, source, reason, priority, status, target_month, raised_by_name)
    select t, rec.id, p.id, p.title, 'new_joiner', 'Joining on ' || to_char(current_date + 5, 'DD Mon YYYY'), 'high', 'open', to_char(current_date + 5, 'YYYY-MM'), 'HRM (new joiner)'
      from hrm.training_programs p where p.tenant_id = t and p.title in ('Induction — company, HR rules and facilities', 'Safety induction', 'Quality policy, objectives & product safety')
    on conflict do nothing;
    insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, status) values (t, tpl, rec.id, 'Manoj Gowda', current_date + 5, 'in_progress')
    on conflict do nothing;
  end loop;

  -- ---- internal auditors ----
  insert into hrm.auditors (tenant_id, employee_id, kind, standards, qualification, trained_on, certificate_no, valid_until, core_tools, csr_trained, audits_per_year)
  select t, e.id, x.kind, x.std, x.qual, current_date - x.ago, x.cert, current_date - x.ago + x.valid, x.tools, x.csr, 2
    from (values ('-D005', 'qms', array['IATF 16949','ISO 9001'], 'IATF 16949 internal auditor (2 days, external)', 600, 'IA-2291', 1095, array['APQP','PPAP','FMEA','SPC','MSA'], true),
                 ('-D017', 'process', array['IATF 16949','VDA 6.3'], 'VDA 6.3 process auditor', 1050, 'VDA-0442', 1095, array['APQP','PPAP','FMEA'], true),
                 ('-D022', 'qms', array['ISO 45001','ISO 14001'], 'ISO 45001 internal auditor', 330, 'OHS-118', 365, array[]::text[], false))
         x(code, kind, std, qual, ago, cert, valid, tools, csr)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  insert into hrm.auditor_audits (tenant_id, auditor_id, audit_date, area, audit_type, role, findings)
  select t, a.id, current_date - x.ago, x.area, x.typ, x.role, x.f
    from hrm.auditors a join hrm.employees e on e.id = a.employee_id
    join (values ('-D005', 140, 'Production — turning cell 1', 'process', 'lead', 3), ('-D005', 40, 'Stores & dispatch', 'system', 'lead', 1),
                 ('-D017', 300, 'Assembly line', 'process', 'auditor', 2), ('-D022', 90, 'Plant 2 — EHS', 'system', 'lead', 4)) x(code, ago, area, typ, role, f)
      on e.employee_code = pfx || x.code
   where a.tenant_id = t;

  return n;
end $fn$;

-- sample data runs through every module: hiring and QMS now (more modules join here)
create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q);
end $fn$;

-- the sample flush also clears the sample QMS lists (the people's records go with the sample people)
create or replace function hrm.demo_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n integer;
begin
  perform hrm.demo_recruit_flush(p_tenant);
  update hrm.employees set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  update hrm.offers set reporting_manager_id = null
   where tenant_id = p_tenant and reporting_manager_id in (select id from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test');
  delete from hrm.employees where tenant_id = p_tenant and email like '%@demo.kmr.test';
  get diagnostics n = row_count;
  perform hrm.module_flush(p_tenant, 'sample');
  delete from hrm.plants p where p.tenant_id = p_tenant and p.code in ('DP1','DP2') and not exists (select 1 from hrm.employees e where e.plant_id = p.id)
     and not exists (select 1 from hrm.operations o where o.plant_id = p.id);
  return n;
end $fn$;

revoke all on function hrm.demo_qms(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_qms(uuid), hrm.demo_flow(uuid), hrm.demo_flush(uuid) to service_role;

-- companies that already hold the sample people get the sample QMS records now
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_qms(r); end loop;
end $$;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0009_positions.sql
-- =====================================================================
-- =====================================================================
-- HRM 0009 — Positions: the QMS runs on Position + Role + Department, never on a designation or a person.
-- Needs 0001–0008. Safe to re-run.
--   Requisition (HR enters Position, Role, Department, competencies needed)
--     → Job description of the position (drafted by the HRM, edited and approved by HR, reused for the next opening)
--       → Roles, Responsibilities, Authority, Competency & KPI sheet of the position (no names; landscape PDF with the
--         company logo and ISO 9001 / IATF 16949 clauses)
--         → Competency mapping of each person holding the position (name + designation) → training needs
--           → training calendar → attendance → effectiveness
--         → KPI sheet of each person: KPI, target, review frequency, review method, actual
-- Each employee has a Position; a new joiner gets it from the requisition he was hired for.
-- =====================================================================

-- ---------- positions ----------
create table if not exists hrm.positions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  title          text not null check (length(title) between 2 and 120),      -- Production Head, Calibration Incharge …
  role           text check (length(role) <= 160),                          -- Shopfloor handling, Manpower handling …
  department_id  uuid references hrm.departments(id) on delete set null,
  family         text,
  active         boolean not null default true,
  sample         boolean not null default false,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists positions_key on hrm.positions (tenant_id, lower(title), lower(coalesce(role, '')), coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table hrm.job_descriptions add column if not exists position_id uuid references hrm.positions(id) on delete set null;
create index if not exists job_descriptions_position on hrm.job_descriptions (position_id, version desc);
alter table hrm.requisitions add column if not exists position_id uuid references hrm.positions(id) on delete set null;
alter table hrm.employees add column if not exists position_id uuid references hrm.positions(id) on delete set null;
create index if not exists employees_position on hrm.employees (tenant_id, position_id);

-- the R&R sheet of a position (rr_roles), its competencies (role_competencies) and KPIs (kpis) hang on the position
alter table hrm.rr_roles alter column designation_id drop not null;
alter table hrm.rr_roles add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
alter table hrm.rr_roles add column if not exists roles text[] not null default '{}';
alter table hrm.rr_roles add column if not exists jd_id uuid references hrm.job_descriptions(id) on delete set null;
alter table hrm.rr_roles add column if not exists doc_no text check (length(doc_no) <= 40);
drop index if exists hrm.rr_roles_desig;
create unique index if not exists rr_roles_position on hrm.rr_roles (position_id) where position_id is not null;

alter table hrm.role_competencies alter column designation_id drop not null;
alter table hrm.role_competencies add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
create unique index if not exists role_competencies_position on hrm.role_competencies (position_id, competency_id) where position_id is not null;

alter table hrm.kpis add column if not exists position_id uuid references hrm.positions(id) on delete cascade;
alter table hrm.kpis add column if not exists review_method text check (length(review_method) <= 200);
alter table hrm.kpis add column if not exists sort_order integer not null default 0;
alter table hrm.kpis alter column target drop not null;
alter table hrm.kpis drop constraint if exists kpis_frequency_check;
alter table hrm.kpis add constraint kpis_frequency_check check (frequency in ('daily','weekly','monthly','quarterly','half_yearly','yearly'));
create index if not exists kpis_position on hrm.kpis (position_id);

drop trigger if exists positions_touch on hrm.positions;
create trigger positions_touch before update on hrm.positions for each row execute function hrm.touch_updated_at();
drop trigger if exists positions_audit on hrm.positions;
create trigger positions_audit after insert or update or delete on hrm.positions for each row execute function hrm.audit_row();
alter table hrm.positions enable row level security;
drop policy if exists positions_hr on hrm.positions;
create policy positions_hr on hrm.positions for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists positions_read on hrm.positions;
create policy positions_read on hrm.positions for select to authenticated using (tenant_id = hrm.current_tenant_id());

-- ---------- what was written per designation before becomes a position of that name ----------
do $$
declare r record; pid uuid;
begin
  for r in
    select x.tenant_id, x.designation_id, d.name, bool_and(x.sample) as sample
      from (select tenant_id, designation_id, sample from hrm.rr_roles where position_id is null and designation_id is not null
            union all select tenant_id, designation_id, sample from hrm.role_competencies where position_id is null and designation_id is not null
            union all select tenant_id, designation_id, sample from hrm.kpis where position_id is null and designation_id is not null) x
      join hrm.designations d on d.id = x.designation_id
     where not x.sample
     group by x.tenant_id, x.designation_id, d.name
  loop
    insert into hrm.positions (tenant_id, title, role) values (r.tenant_id, r.name, null)
    on conflict do nothing;
    select id into pid from hrm.positions where tenant_id = r.tenant_id and lower(title) = lower(r.name) and role is null and department_id is null;
    update hrm.rr_roles set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.role_competencies set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.kpis set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and not sample;
    update hrm.employees set position_id = pid where tenant_id = r.tenant_id and designation_id = r.designation_id and position_id is null and email not like '%@demo.kmr.test';
  end loop;
end $$;
-- several R&R versions per designation and department can now meet on one position: keep the newest
delete from hrm.rr_roles a using hrm.rr_roles b where a.position_id = b.position_id and a.position_id is not null and a.created_at < b.created_at;

-- ---------- clearing: positions join the lists ----------
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backups include the positions ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 5, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
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
  delete from hrm.positions where tenant_id = p_tenant;
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
  perform hrm.seed_qms_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- =====================================================================
-- Sample positions (written by the HRM's own job-description writer and R&R-sheet generator)
-- =====================================================================
create or replace function hrm.demo_positions(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant; pfx text; x jsonb; c jsonb; k jsonb; h text; pid uuid; jid uuid; rid uuid; cid uuid; m text; n int := 0; i int;
  spec jsonb := $spec$[{"title": "CNC Operator", "role": "Machine operation", "dept": "Production", "family": "operator", "holders": ["D003", "D004", "D010", "D011", "D012", "D015", "D016", "D020", "D021", "D023", "D024"], "status": "approved", "jd": {"purpose": "Operate and set machines safely to produce good parts to the drawing and work instruction. The role covers machine operation.", "responsibilities": ["Operate the machine as per the work instruction and set-up sheet", "Do first-off and in-process checks and record them", "Do the daily autonomous-maintenance checks", "Operate and set the machine as per the work instruction", "Do first-off and in-process checks with gauges; record them", "Report abnormalities and stop on doubt", "Maintain 5S and do autonomous maintenance checks"], "kpis": ["Output per shift", "Rejection %"], "must_have": [{"name": "CNC machining", "weight": 3}, {"name": "Inspection & metrology", "weight": 2}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "weight": 2}], "good_to_have": [{"name": "Lean / continuous improvement", "weight": 1}, {"name": "TPM / maintenance excellence", "weight": 1}, {"name": "Welding / fabrication", "weight": 1}], "qualifications": "ITI / 10th / 12th", "experience": "1–4 years", "reporting_to": "Operator / technician Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Right-first-time parts at the planned output"]}, "sheet": {"purpose": "Operate and set machines safely to produce good parts to the drawing and work instruction. The role covers machine operation.", "roles": ["Machine operation", "Operator / technician"], "responsibilities": ["Operate the machine as per the work instruction and set-up sheet", "Do first-off and in-process checks and record them", "Do the daily autonomous-maintenance checks", "Operate and set the machine as per the work instruction", "Do first-off and in-process checks with gauges; record them", "Report abnormalities and stop on doubt", "Maintain 5S and do autonomous maintenance checks"], "authorities": ["Stop the machine on a quality or safety doubt", "Stop work on a safety doubt"], "competencies": [{"name": "CNC machining", "level": 3, "category": "technical"}, {"name": "Inspection & metrology", "level": 2, "category": "quality"}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "level": 2, "category": "behavioural"}], "kpis": [{"name": "Output per shift", "unit": "parts", "target": 420, "direction": "higher", "frequency": "daily", "review_method": "Shift production report; monthly summary", "data_source": "Production report"}, {"name": "Rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Production Supervisor", "role": "Shopfloor & manpower handling", "dept": "Production", "family": "production", "holders": ["D002"], "status": "approved", "jd": {"purpose": "Deliver the daily production plan of the Production line safely, on time and right first time, with the agreed manpower and machine capacity. The role covers shopfloor handling, manpower handling.", "responsibilities": ["Run the shift / line to the production plan: output, quality, delivery and safety", "Release the set-up and first-off; review check sheets every shift", "Hold the daily start-of-shift meeting on yesterday's quality, safety and output", "Escalate abnormalities through the escalation matrix within the agreed time", "Plan manpower for each shift using the skill matrix; no one works alone on an operation he is not qualified for", "Raise training needs for the team and evaluate training effectiveness on the job", "Maintain attendance, discipline and morale; resolve grievances early", "Develop backups for key operations and people", "Run the shift or line to the daily production plan; report output, rejections and downtime", "Allocate manpower and machines; balance the line to the takt time", "Ensure work instructions, set-up approval and first-off inspection are followed", "Drive productivity, OEE and cycle-time improvement with kaizens", "Lead and develop the team; set targets, review performance and build backups for key skills"], "kpis": ["Plan vs actual output", "OEE", "Absenteeism %", "Skill matrix coverage %"], "must_have": [{"name": "Production / shop-floor management", "weight": 3}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "weight": 3}, {"name": "People leadership", "weight": 3}, {"name": "Communication & documentation", "weight": 2}, {"name": "Lean / continuous improvement", "weight": 1}], "good_to_have": [{"name": "Production planning & control", "weight": 1}, {"name": "TPM / maintenance excellence", "weight": 1}, {"name": "CNC machining", "weight": 1}, {"name": "ERP (SAP / Oracle / Tally)", "weight": 1}, {"name": "Health, safety & environment", "weight": 1}], "qualifications": "B.E / B.Tech or Diploma (Mechanical / Production)", "experience": "5–10 years", "reporting_to": "Plant Head", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Meet the daily plan with first-time-right quality", "Raise OEE and productivity on the line", "Zero safety incidents"]}, "sheet": {"purpose": "Deliver the daily production plan of the Production line safely, on time and right first time, with the agreed manpower and machine capacity. The role covers shopfloor handling, manpower handling.", "roles": ["Shopfloor handling", "Manpower handling", "Production"], "responsibilities": ["Run the shift / line to the production plan: output, quality, delivery and safety", "Release the set-up and first-off; review check sheets every shift", "Hold the daily start-of-shift meeting on yesterday's quality, safety and output", "Escalate abnormalities through the escalation matrix within the agreed time", "Plan manpower for each shift using the skill matrix; no one works alone on an operation he is not qualified for", "Raise training needs for the team and evaluate training effectiveness on the job", "Maintain attendance, discipline and morale; resolve grievances early", "Develop backups for key operations and people", "Run the shift or line to the daily production plan; report output, rejections and downtime", "Allocate manpower and machines; balance the line to the takt time", "Ensure work instructions, set-up approval and first-off inspection are followed", "Drive productivity, OEE and cycle-time improvement with kaizens", "Lead and develop the team; set targets, review performance and build backups for key skills"], "authorities": ["Stop the line on a quality, safety or delivery risk", "Hold and red-tag suspect material", "Allocate people to operations within their qualification", "Recommend leave, overtime and permission for the team", "Segregate and rework as per the reaction plan", "Stop work on a safety doubt"], "competencies": [{"name": "Production / shop-floor management", "level": 3, "category": "management"}, {"name": "Shop-floor discipline (5S, SOP, check sheets)", "level": 3, "category": "behavioural"}, {"name": "People leadership", "level": 3, "category": "management"}, {"name": "Communication & documentation", "level": 2, "category": "behavioural"}, {"name": "Lean / continuous improvement", "level": 1, "category": "technical"}], "kpis": [{"name": "Plan vs actual output", "unit": "%", "target": 98, "direction": "higher", "frequency": "daily", "review_method": "Daily production meeting; monthly summary", "data_source": "Production report"}, {"name": "OEE", "unit": "%", "target": 75, "direction": "higher", "frequency": "monthly", "review_method": "OEE sheet reviewed monthly", "data_source": "OEE sheet"}, {"name": "Absenteeism %", "unit": "%", "target": 3, "direction": "lower", "frequency": "monthly", "review_method": "Attendance report review", "data_source": "HRM attendance"}, {"name": "Skill matrix coverage %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Skill matrix review", "data_source": "HRM skill matrix"}]}}, {"title": "Quality Engineer", "role": "Customer quality & audits", "dept": "Quality", "family": "quality", "holders": ["D005", "D013"], "status": "approved", "jd": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers quality control.", "responsibilities": ["Inspect as per the control plan; record results and act on out-of-tolerance readings", "Handle complaints with 8D; verify that corrective actions work", "Run layered process audits and follow up the findings", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals"], "kpis": ["Customer PPM", "Internal rejection %"], "must_have": [{"name": "Problem solving (8D, RCA, CAPA)", "weight": 3}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "weight": 2}, {"name": "Quality improvement", "weight": 1}, {"name": "Inspection & metrology", "weight": 1}, {"name": "IATF 16949 / ISO 9001", "weight": 1}], "good_to_have": [{"name": "Customer quality / OEM interface", "weight": 1}, {"name": "Supplier quality development", "weight": 1}, {"name": "Internal / process audits", "weight": 1}, {"name": "Six Sigma", "weight": 1}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "weight": 1}], "qualifications": "Diploma or B.E / B.Tech (Mechanical / Production)", "experience": "3–6 years", "reporting_to": "Quality Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Bring customer PPM down and hold it", "Close customer complaints with effective, verified corrective action", "Keep the plant audit-ready for IATF 16949"]}, "sheet": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers quality control.", "roles": ["Quality control"], "responsibilities": ["Inspect as per the control plan; record results and act on out-of-tolerance readings", "Handle complaints with 8D; verify that corrective actions work", "Run layered process audits and follow up the findings", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals"], "authorities": ["Hold, segregate and reject non-conforming product", "Stop dispatch of suspect lots", "Accept or reject product against the specification", "Hold dispatch of suspect product", "Raise a corrective action request on any department or supplier", "Stop work on a safety doubt"], "competencies": [{"name": "Problem solving (8D, RCA, CAPA)", "level": 3, "category": "quality"}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "level": 2, "category": "quality"}, {"name": "Quality improvement", "level": 1, "category": "quality"}, {"name": "Inspection & metrology", "level": 1, "category": "quality"}, {"name": "IATF 16949 / ISO 9001", "level": 1, "category": "quality"}], "kpis": [{"name": "Customer PPM", "unit": "PPM", "target": 50, "direction": "lower", "frequency": "monthly", "review_method": "Customer scorecard reviewed in the monthly quality review", "data_source": "Customer scorecard / complaint register"}, {"name": "Internal rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Calibration Incharge", "role": "Calibration & gauge control", "dept": "Quality", "family": "quality", "holders": ["D006"], "status": "approved", "jd": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers calibration & gauge control.", "responsibilities": ["Maintain the calibration plan and history of every gauge and measuring instrument", "Calibrate in-house as per the procedure, or through an accredited (NABL / ISO 17025) laboratory", "Run MSA (GR&R, bias, linearity) for the gauges in the control plan", "Assess the effect on product when a gauge is found out of calibration, and inform Quality", "Keep gauges identified, stored and protected; withdraw damaged gauges", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals", "Lead and develop the team; set targets, review performance and build backups for key skills"], "kpis": ["Calibration plan adherence %", "Gauges overdue for calibration", "Customer PPM", "Internal rejection %"], "must_have": [{"name": "Inspection & metrology", "weight": 3}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "weight": 2}, {"name": "IATF 16949 / ISO 9001", "weight": 2}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "weight": 2}, {"name": "Problem solving (8D, RCA, CAPA)", "weight": 2}, {"name": "Quality improvement", "weight": 1}, {"name": "People leadership", "weight": 2}], "good_to_have": [{"name": "Customer quality / OEM interface", "weight": 1}, {"name": "Supplier quality development", "weight": 1}, {"name": "Internal / process audits", "weight": 1}, {"name": "Six Sigma", "weight": 1}], "qualifications": "B.E / B.Tech (Mechanical / Production / Automobile); IATF internal-auditor training preferred", "experience": "3–8 years", "reporting_to": "Plant Head", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Bring customer PPM down and hold it", "Close customer complaints with effective, verified corrective action", "Keep the plant audit-ready for IATF 16949"]}, "sheet": {"purpose": "Make sure every part the Quality team ships meets the customer's requirements, and drive down rejections and customer complaints across the plant. The role covers calibration & gauge control.", "roles": ["Calibration & gauge control", "Quality"], "responsibilities": ["Maintain the calibration plan and history of every gauge and measuring instrument", "Calibrate in-house as per the procedure, or through an accredited (NABL / ISO 17025) laboratory", "Run MSA (GR&R, bias, linearity) for the gauges in the control plan", "Assess the effect on product when a gauge is found out of calibration, and inform Quality", "Keep gauges identified, stored and protected; withdraw damaged gauges", "Run incoming, in-process and final inspection as per the control plan and inspection standards", "Handle customer complaints end to end with 8D / root-cause analysis and verify corrective actions", "Prepare and maintain PPAP, APQP, PFMEA and control-plan documents for new and changed parts", "Monitor process capability with SPC (Cp/Cpk) and MSA studies; act on out-of-control signals", "Lead and develop the team; set targets, review performance and build backups for key skills"], "authorities": ["Withdraw an out-of-calibration or damaged gauge from use", "Reject a calibration certificate that does not meet the requirement", "Accept or reject product against the specification", "Hold dispatch of suspect product", "Raise a corrective action request on any department or supplier", "Stop work on a safety doubt"], "competencies": [{"name": "Inspection & metrology", "level": 4, "category": "quality"}, {"name": "Statistical analysis (SPC, Cpk, MSA)", "level": 2, "category": "quality"}, {"name": "IATF 16949 / ISO 9001", "level": 2, "category": "quality"}, {"name": "Core tools (APQP, PPAP, FMEA, SPC, MSA)", "level": 2, "category": "quality"}, {"name": "Problem solving (8D, RCA, CAPA)", "level": 2, "category": "quality"}, {"name": "Quality improvement", "level": 1, "category": "quality"}, {"name": "People leadership", "level": 2, "category": "management"}], "kpis": [{"name": "Calibration plan adherence %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Plan vs actual reviewed monthly", "data_source": "PM / calibration plan"}, {"name": "Gauges overdue for calibration", "unit": "nos", "target": 0, "direction": "lower", "frequency": "monthly", "review_method": "Calibration status check, monthly", "data_source": "Calibration plan"}, {"name": "Customer PPM", "unit": "PPM", "target": 50, "direction": "lower", "frequency": "monthly", "review_method": "Customer scorecard reviewed in the monthly quality review", "data_source": "Customer scorecard / complaint register"}, {"name": "Internal rejection %", "unit": "%", "target": 1, "direction": "lower", "frequency": "monthly", "review_method": "Rejection register reviewed in the daily meeting and monthly review", "data_source": "Rejection register"}]}}, {"title": "Maintenance Technician", "role": "Maintenance", "dept": "Maintenance", "family": "maintenance", "holders": ["D007", "D014"], "status": "draft", "jd": {"purpose": "Keep plant machines and utilities available and reliable through planned maintenance and quick, lasting breakdown repair. The role covers maintenance.", "responsibilities": ["Attend breakdowns and find the root cause so they do not repeat", "Carry out preventive maintenance as per the PM plan", "Keep critical spares and the machine history card up to date", "Attend breakdowns quickly and find the root cause so they do not repeat", "Plan and carry out preventive and predictive maintenance as per the PM schedule", "Maintain hydraulic, pneumatic, electrical and PLC-controlled systems", "Keep critical spares and the maintenance history up to date"], "kpis": ["MTBF", "MTTR", "PM adherence %", "Machine availability %"], "must_have": [{"name": "TPM / maintenance excellence", "weight": 3}, {"name": "Mechanical maintenance", "weight": 2}, {"name": "Electrical maintenance", "weight": 2}], "good_to_have": [{"name": "Health, safety & environment", "weight": 1}, {"name": "CNC machining", "weight": 1}, {"name": "ERP (SAP / Oracle / Tally)", "weight": 1}, {"name": "Lean / continuous improvement", "weight": 1}], "qualifications": "Diploma or ITI (Fitter / Electrician)", "experience": "2–5 years", "reporting_to": "Maintenance Manager", "context": "Automotive / engineering manufacturing plant working to IATF 16949 / ISO 9001", "outcomes": ["Raise machine availability and MTBF", "Cut repeat breakdowns"]}, "sheet": {"purpose": "Keep plant machines and utilities available and reliable through planned maintenance and quick, lasting breakdown repair. The role covers maintenance.", "roles": ["Maintenance"], "responsibilities": ["Attend breakdowns and find the root cause so they do not repeat", "Carry out preventive maintenance as per the PM plan", "Keep critical spares and the machine history card up to date", "Attend breakdowns quickly and find the root cause so they do not repeat", "Plan and carry out preventive and predictive maintenance as per the PM schedule", "Maintain hydraulic, pneumatic, electrical and PLC-controlled systems", "Keep critical spares and the maintenance history up to date"], "authorities": ["Take a machine out of production for safety or repair", "Apply lock-out tag-out and permit to work", "Stop work on a safety doubt"], "competencies": [{"name": "TPM / maintenance excellence", "level": 3, "category": "behavioural"}, {"name": "Mechanical maintenance", "level": 2, "category": "technical"}, {"name": "Electrical maintenance", "level": 2, "category": "technical"}], "kpis": [{"name": "MTBF", "unit": "hours", "target": 200, "direction": "higher", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Machine history card"}, {"name": "MTTR", "unit": "hours", "target": 2, "direction": "lower", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Breakdown register"}, {"name": "PM adherence %", "unit": "%", "target": 100, "direction": "higher", "frequency": "monthly", "review_method": "Plan vs actual reviewed monthly", "data_source": "PM / calibration plan"}, {"name": "Machine availability %", "unit": "%", "target": 95, "direction": "higher", "frequency": "monthly", "review_method": "Breakdown analysis in the monthly review", "data_source": "Breakdown register"}]}}]$spec$::jsonb;
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if not exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then return 0; end if;
  if exists (select 1 from hrm.positions where tenant_id = t and sample) then return 0; end if;
  for x in select * from jsonb_array_elements(spec) loop
    insert into hrm.positions (tenant_id, title, role, department_id, family, sample)
    values (t, x->>'title', x->>'role', (select id from hrm.departments where tenant_id = t and name = x->>'dept'), x->>'family', true)
    on conflict do nothing returning id into pid;
    if pid is null then continue; end if;
    n := n + 1;
    -- the job description of the position: the sample hiring flow's JD of the same title becomes version 1 (archived),
    -- the position's JD (written with the Role) is version 2, approved
    update hrm.job_descriptions set position_id = pid, status = case when status = 'approved' then 'archived' else status end
     where tenant_id = t and sample and title = x->>'title' and position_id is null;
    insert into hrm.job_descriptions (tenant_id, position_id, title, family, purpose, responsibilities, kpis, must_have, good_to_have, qualifications, experience, reporting_to,
                                      context, outcomes, version, status, approved_at, sample)
    values (t, pid, x->>'title', x->>'family', x->'jd'->>'purpose', array(select jsonb_array_elements_text(x->'jd'->'responsibilities')),
            array(select jsonb_array_elements_text(x->'jd'->'kpis')), x->'jd'->'must_have', x->'jd'->'good_to_have', x->'jd'->>'qualifications',
            x->'jd'->>'experience', x->'jd'->>'reporting_to', x->'jd'->>'context', array(select jsonb_array_elements_text(x->'jd'->'outcomes')),
            coalesce((select max(version) from hrm.job_descriptions where position_id = pid), 0) + 1, 'approved', now() - interval '150 days', true)
    returning id into jid;
    update hrm.requisitions set position_id = pid where tenant_id = t and sample and title = x->>'title';
    -- the R&R sheet
    insert into hrm.rr_roles (tenant_id, position_id, department_id, purpose, roles, responsibilities, authorities, interfaces, version, status, approved_at, jd_id, doc_no, sample)
    values (t, pid, (select department_id from hrm.positions where id = pid), x->'sheet'->>'purpose', array(select jsonb_array_elements_text(x->'sheet'->'roles')),
            array(select jsonb_array_elements_text(x->'sheet'->'responsibilities')), array(select jsonb_array_elements_text(x->'sheet'->'authorities')),
            array['Production','Quality','Maintenance','HR'], 1, x->>'status', case when x->>'status' = 'approved' then now() - interval '140 days' end, jid,
            'HR-RR-' || lpad(n::text, 3, '0'), true)
    returning id into rid;
    i := 0;
    for c in select * from jsonb_array_elements(x->'sheet'->'competencies') loop
      insert into hrm.competencies (tenant_id, name, category, sample) values (t, c->>'name', c->>'category', true) on conflict (tenant_id, name) do nothing;
      select id into cid from hrm.competencies where tenant_id = t and name = c->>'name';
      insert into hrm.role_competencies (tenant_id, position_id, competency_id, required_level, sample) values (t, pid, cid, (c->>'level')::int, true) on conflict do nothing;
    end loop;
    for k in select * from jsonb_array_elements(x->'sheet'->'kpis') loop
      i := i + 1;
      insert into hrm.kpis (tenant_id, position_id, department_id, name, unit, target, direction, frequency, review_method, data_source, weight, sort_order, sample)
      values (t, pid, null, k->>'name', k->>'unit', (k->>'target')::numeric, k->>'direction', k->>'frequency', k->>'review_method', k->>'data_source',
              case when i <= 2 then 2 else 1 end, i, true);
    end loop;
    -- the people who hold the position
    for h in select jsonb_array_elements_text(x->'holders') loop
      update hrm.employees set position_id = pid where tenant_id = t and employee_code = pfx || '-' || h;
    end loop;
  end loop;
  -- the sample new joiner holds the position he was hired for
  update hrm.employees e set position_id = r.position_id
    from hrm.offers o join hrm.applications a on a.id = o.application_id join hrm.requisitions r on r.id = a.requisition_id
   where o.employee_id = e.id and e.tenant_id = t and e.email like '%@demo.kmr.test' and r.position_id is not null and e.position_id is null;

  -- competency mapping: most people meet the need, some are one or two levels short (the gaps the TNI picks up)
  insert into hrm.employee_competencies (tenant_id, employee_id, competency_id, level, assessed_on, assessed_by_name, method)
  select t, e.id, rc.competency_id,
         greatest(0, least(4, rc.required_level - case when (abs(hashtext(e.id::text || rc.competency_id::text)) % 5) = 0 then 1 when (abs(hashtext(e.id::text || rc.competency_id::text)) % 11) = 0 then 2 else 0 end
                                        + case when (abs(hashtext(rc.competency_id::text || e.id::text)) % 7) = 0 then 1 else 0 end)),
         current_date - (abs(hashtext(e.id::text)) % 120), 'Arun Kumar', 'observation'
    from hrm.employees e join hrm.role_competencies rc on rc.position_id = e.position_id and rc.sample
   where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.status = 'active'
  on conflict (employee_id, competency_id) do nothing;
  -- R&R acknowledged by most holders
  insert into hrm.rr_acks (tenant_id, rr_id, employee_id, version, acknowledged_at)
  select t, r.id, e.id, r.version, now() - ((abs(hashtext(e.id::text)) % 90) || ' days')::interval
    from hrm.rr_roles r join hrm.employees e on e.position_id = r.position_id and e.email like '%@demo.kmr.test' and e.status = 'active'
   where r.tenant_id = t and r.sample and r.status = 'approved' and (abs(hashtext(e.id::text)) % 4) <> 0
  on conflict do nothing;
  -- KPI sheets: three months of actuals
  for i in 1..3 loop
    m := to_char(date_trunc('month', current_date) - (i || ' months')::interval, 'YYYY-MM');
    insert into hrm.kpi_values (tenant_id, kpi_id, employee_id, month, actual)
    select t, kp.id, e.id, m,
           round((case when kp.target = 0 then (abs(hashtext(e.id::text || m || kp.id::text)) % 3) / 2.0
                       when kp.direction = 'higher' then kp.target * (0.88 + (abs(hashtext(e.id::text || m || kp.id::text)) % 20) / 100.0)
                       else kp.target * (0.6 + (abs(hashtext(e.id::text || m || kp.id::text)) % 90) / 100.0) end)::numeric,
                 case when kp.unit in ('%', 'Cpk', 'hours') then 1 else 0 end)
      from hrm.kpis kp join hrm.employees e on e.position_id = kp.position_id and e.email like '%@demo.kmr.test' and e.status = 'active'
     where kp.tenant_id = t and kp.sample and kp.target is not null
    on conflict do nothing;
  end loop;
  return n;
end $fn$;

create or replace function hrm.demo_qms(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare
  t uuid := p_tenant; pfx text; p1 uuid; p2 uuid; rec record; i int; n int := 0;
  op_ids uuid[]; op uuid; lvl int; sess uuid; prog uuid; att uuid; tpl uuid; aud uuid; kpi uuid; m text; k int;
  d_op uuid; d_sop uuid; d_tech uuid; d_eng uuid; d_sup uuid; d_seng uuid;
  -- skill levels: rows = sample people D003…D024 (production), columns = OP10…OP60 (0 not trained … 4 trainer)
  grid int[][] := array[
    [4,3,3,2,3,1],   -- D003 Karthik
    [3,2,3,3,1,0],   -- D004 Divya
    [3,3,2,1,2,0],   -- D010 Anitha
    [4,4,3,3,3,3],   -- D011 Manoj (senior operator, trainer)
    [2,1,3,0,3,0],   -- D012 Kavya
    [3,0,2,0,3,1],   -- D015 Ganesh
    [1,0,3,0,2,0],   -- D016 Sowmya
    [2,0,1,0,3,0],   -- D020 Revathi (contract)
    [1,0,0,0,2,0],   -- D021 Naveen (contract)
    [0,0,1,0,1,0],   -- D023 Senthil (contract)
    [3,2,2,0,3,0]];  -- D024 Bhavya
  who int[] := array[3,4,10,11,12,15,16,20,21,23,24];
  emp uuid;
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  if not exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then return 0; end if;
  if exists (select 1 from hrm.operations where tenant_id = t and sample) then return 0; end if;     -- already there
  perform hrm.seed_qms_defaults(t);
  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';
  select id into p2 from hrm.plants where tenant_id = t and code = 'DP2';
  select id into d_op from hrm.designations where tenant_id = t and name = 'Operator';
  select id into d_sop from hrm.designations where tenant_id = t and name = 'Senior Operator';
  select id into d_tech from hrm.designations where tenant_id = t and name = 'Technician';
  select id into d_eng from hrm.designations where tenant_id = t and name = 'Engineer';
  select id into d_sup from hrm.designations where tenant_id = t and name = 'Supervisor';
  select id into d_seng from hrm.designations where tenant_id = t and name = 'Senior Engineer';

  update hrm.qms_settings set quality_policy = coalesce(quality_policy,
    'We make precision machined components right the first time and deliver them on time, every time. We meet our customers'' requirements and applicable statutory and regulatory requirements, train every person for the job, and improve our processes continually.'),
    csr = case when cardinality(csr) = 0 then array['Customer A: 100% inspection of the bore for the first 3 lots after any change','Customer B: PPAP level 3 for every engineering change','Customer A: retain first-off parts for one shift'] else csr end
   where tenant_id = t;

  -- ---- operations of two lines (skill matrix) ----
  insert into hrm.operations (tenant_id, plant_id, line, code, name, machine, critical, min_qualified, safety_required, sort_order, sample) values
    (t, p1, 'Turning cell 1', 'OP10', 'CNC turning — 1st setup', 'LT-01 Ace Jobber', true, null, false, 10, true),
    (t, p1, 'Turning cell 1', 'OP20', 'CNC turning — 2nd setup', 'LT-02 Ace Jobber', false, null, false, 20, true),
    (t, p1, 'Turning cell 1', 'OP30', 'VMC drilling & tapping', 'VMC-03 BFW', false, null, false, 30, true),
    (t, p1, 'Turning cell 1', 'OP40', 'Final inspection (bore & thread)', 'Inspection table', true, 3, false, 40, true),
    (t, p1, 'Assembly',       'OP50', 'Washing & packing', 'Washer WS-1', false, null, false, 50, true),
    (t, p1, 'Assembly',       'OP60', 'Bush press-fit', 'Hydraulic press HP-20T', true, null, true, 60, true);
  select array_agg(id order by sort_order) into op_ids from hrm.operations where tenant_id = t and sample;
  for i in 1..array_length(who, 1) loop
    select id into emp from hrm.employees where tenant_id = t and employee_code = pfx || '-D' || lpad(who[i]::text, 3, '0');
    if emp is null then continue; end if;
    for k in 1..6 loop
      lvl := grid[i][k];
      if lvl = 0 then continue; end if;
      insert into hrm.skill_levels (tenant_id, employee_id, operation_id, level, certified_on, valid_until, assessed_by_name, note)
      values (t, emp, op_ids[k], lvl, case when lvl >= 3 then current_date - (60 + i * 11) end,
              case when lvl >= 3 then current_date - (60 + i * 11) + 365 + case when i = 1 and k = 1 then -320 else 0 end end,
              'Priya Sharma', case when lvl = 1 then 'Under training with Manoj' end);
      n := n + 1;
    end loop;
  end loop;

  -- ---- positions: job description → R&R sheet (roles, responsibilities, authority, competency, KPI) → people ----
  perform hrm.demo_positions(t);

  -- ---- training: three sessions done, one this week, one planned next month ----
  -- 1) quality policy awareness, 75 days ago, everybody on the production floor, signed off
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Quality policy, objectives & product safety';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 75, 'YYYY-MM'), ((current_date - 75) + time '10:00') at time zone 'Asia/Kolkata', ((current_date - 75) + time '11:00') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Suresh Reddy (Quality)', 'done', (current_date - 75)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, acknowledged_at)
  select t, sess, e.id, e.employee_code <> pfx || '-D016', 'scan', (current_date - 75)::timestamptz, case when e.employee_code <> pfx || '-D016' then (current_date - 74)::timestamptz end
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.department_id in (select id from hrm.departments where tenant_id = t and name in ('Production','Quality'));
  -- 2) measuring instruments & first-off, 40 days ago: pre/post test, effectiveness due (one effective, one not, rest due / overdue)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Measuring instruments & first-off inspection';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, trainer_employee_id, status, completed_at, sample)
  values (t, prog, to_char(current_date - 40, 'YYYY-MM'), ((current_date - 40) + time '14:00') at time zone 'Asia/Kolkata', ((current_date - 40) + time '18:00') at time zone 'Asia/Kolkata',
          'Quality lab, Plant 1', 'Manoj Gowda', (select id from hrm.employees where tenant_id = t and employee_code = pfx || '-D011'), 'done', (current_date - 40)::timestamptz, true) returning id into sess;
  i := 0;
  for rec in select id, employee_code, reporting_manager_id from hrm.employees where tenant_id = t and employee_code = any(array[pfx||'-D012', pfx||'-D015', pfx||'-D016', pfx||'-D020', pfx||'-D021', pfx||'-D023']) order by employee_code loop
    i := i + 1;
    insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
    values (t, sess, rec.id, true, 'scan', (current_date - 40)::timestamptz, 35 + i * 5, case when i = 5 then 55 else 70 + i * 4 end) returning id into att;
    insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id, result, rating, evidence, evaluated_by_name, evaluated_at)
    values (t, att, rec.id, sess, current_date - 10, rec.reporting_manager_id,
            case i when 1 then 'effective' when 5 then 'not_effective' end, case i when 1 then 4 when 5 then 2 end,
            case i when 1 then 'Did first-off on OP20 alone for two weeks; all readings correct' when 5 then 'Zero setting of the micrometer still missed twice in the layered audit' end,
            case when i in (1, 5) then 'Priya Sharma' end, case when i in (1, 5) then now() - interval '6 days' end);
    if i = 5 then
      insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, raised_by_name)
      values (t, rec.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Measuring instruments & first-off inspection (again)', 'retraining',
              'Training of ' || to_char(current_date - 40, 'DD Mon') || ' was not effective: zero setting missed', 'high', 'open', to_char(current_date + 20, 'YYYY-MM'), 'Priya Sharma');
    end if;
  end loop;
  -- 3) safety induction for the new joiners and contract workers, 20 days ago
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Safety induction';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, completed_at, sample)
  values (t, prog, to_char(current_date - 20, 'YYYY-MM'), ((current_date - 20) + time '09:30') at time zone 'Asia/Kolkata', ((current_date - 20) + time '12:30') at time zone 'Asia/Kolkata',
          'Training hall, Plant 1', 'Pooja Singh (EHS)', 'done', (current_date - 20)::timestamptz, true) returning id into sess;
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, attended, method, marked_at, pre_score, post_score)
  select t, sess, e.id, true, 'manual', (current_date - 20)::timestamptz, 40 + (abs(hashtext(e.id::text)) % 20), 75 + (abs(hashtext(e.id::text)) % 20)
    from hrm.employees e where e.tenant_id = t and e.email like '%@demo.kmr.test' and e.employment_type = 'contract';
  insert into hrm.training_effectiveness (tenant_id, attendance_id, employee_id, session_id, due_on, evaluator_id)
  select t, a.id, a.employee_id, sess, current_date + 10, (select reporting_manager_id from hrm.employees where id = a.employee_id)
    from hrm.training_attendance a where a.session_id = sess;
  -- 4) 8D problem solving this week (scheduled, invitations sent)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Problem solving — 8D';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, starts_at, ends_at, venue, trainer, status, invited_at, sample)
  values (t, prog, to_char(current_date + 3, 'YYYY-MM'), ((current_date + 3) + time '10:00') at time zone 'Asia/Kolkata', ((current_date + 3) + time '14:00') at time zone 'Asia/Kolkata',
          'Conference room, Plant 1', 'Prakash Babu', 'scheduled', now() - interval '2 days', true) returning id into sess;
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, topic, source, reason, priority, status, target_month, session_id, raised_by_name)
  select t, e.id, prog, (select competency_id from hrm.training_programs where id = prog), 'Problem solving — 8D', 'customer_complaint',
         'Customer complaint: burr in the cross hole (repeat) — 8D team', 'high', 'planned', to_char(current_date + 3, 'YYYY-MM'), sess, 'Suresh Reddy'
    from hrm.employees e where e.tenant_id = t and e.employee_code = any(array[pfx||'-D005', pfx||'-D006', pfx||'-D013', pfx||'-D011', pfx||'-D002']);
  insert into hrm.training_attendance (tenant_id, session_id, employee_id, need_id)
  select t, sess, n2.employee_id, n2.id from hrm.training_needs n2 where n2.session_id = sess;
  -- 5) planned next month: core tools FMEA for the engineers (from the competency gaps)
  select id into prog from hrm.training_programs where tenant_id = t and title = 'Core tools — FMEA';
  insert into hrm.training_sessions (tenant_id, program_id, plan_month, venue, trainer, status, sample)
  values (t, prog, to_char(current_date + 32, 'YYYY-MM'), 'Training hall, Plant 1', 'External — certified trainer', 'planned', true) returning id into sess;

  -- open needs of different kinds (the TNI list)
  insert into hrm.training_needs (tenant_id, employee_id, program_id, competency_id, operation_id, topic, source, reason, priority, status, target_month, raised_by_name)
  select t, e.id, x.prog, x.comp, x.op, x.topic, x.src, x.reason, x.pri, 'open', to_char(current_date + x.inm, 'YYYY-MM'), x.by
    from (values
      ('-D023', null::uuid, null::uuid, op_ids[1], 'OP10 CNC turning — 1st setup', 'skill_gap', 'Needed as a backup on OP10: only one other person is qualified in the shift', 'high', 15, 'Priya Sharma'),
      ('-D016', null, null, null, 'Quality policy, objectives & product safety', 'awareness', 'Was absent for the awareness session', 'normal', 10, 'Arun Kumar'),
      ('-D009', null, null, null, 'Change of process: new washing chemical (MSDS, concentration check)', 'process_change', 'Engineering change EC-118', 'normal', 20, 'Prakash Babu'),
      ('-D019', null, null, null, 'IATF 16949 internal auditor', 'request', 'Asked to become an internal auditor', 'low', 60, 'Harish Hegde'),
      ('-D007', null, null, null, 'Lock-out tag-out', 'audit_finding', 'Internal audit finding: LOTO not applied on HP-20T during die change', 'high', 7, 'Pooja Singh')
    ) x(code, prog, comp, op, topic, src, reason, pri, inm, by)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  update hrm.training_needs nd set program_id = p.id, competency_id = p.competency_id
    from hrm.training_programs p where nd.tenant_id = t and p.tenant_id = t and nd.program_id is null and p.title = nd.topic;

  -- ---- on-the-job training ----
  insert into hrm.ojt_templates (tenant_id, title, designation_id, operation_id, items, days, sample) values
    (t, 'New operator — CNC turning cell', d_op, op_ids[1], jsonb_build_array(
       jsonb_build_object('text', 'Machine start-up, warm-up and daily checklist', 'kind', 'task'),
       jsonb_build_object('text', 'Reading the work instruction and set-up sheet', 'kind', 'task'),
       jsonb_build_object('text', 'Loading / unloading and chip handling safely', 'kind', 'task'),
       jsonb_build_object('text', 'First-off and in-process checks with the instruments; recording', 'kind', 'task'),
       jsonb_build_object('text', 'Customer A: retain first-off parts for one shift; 100% bore check after a change', 'kind', 'csr'),
       jsonb_build_object('text', 'Consequences of an oversize bore reaching the customer: line stoppage, recall, safety', 'kind', 'nc'),
       jsonb_build_object('text', 'Reaction plan: stop, segregate, red-tag, inform the supervisor', 'kind', 'task'),
       jsonb_build_object('text', 'Works independently for 3 shifts under observation', 'kind', 'task')), 15, true);
  select id into tpl from hrm.ojt_templates where tenant_id = t and sample limit 1;
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status, completed_on, signed_off_name)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 60, '[0,1,2,3,4,5,6,7]'::jsonb, 'completed', current_date - 44, 'Priya Sharma'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D020';
  insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, done, status)
  select t, tpl, e.id, 'Manoj Gowda', current_date - 6, '[0,1,2]'::jsonb, 'in_progress'
    from hrm.employees e where e.tenant_id = t and e.employee_code = pfx || '-D023';

  -- the new joiner from the sample hiring flow gets the joiner's needs and OJT
  for rec in select id from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status in ('invited','onboarding','submitted','active')
            and id in (select employee_id from hrm.offers where tenant_id = t and employee_id is not null) loop
    insert into hrm.training_needs (tenant_id, employee_id, program_id, topic, source, reason, priority, status, target_month, raised_by_name)
    select t, rec.id, p.id, p.title, 'new_joiner', 'Joining on ' || to_char(current_date + 5, 'DD Mon YYYY'), 'high', 'open', to_char(current_date + 5, 'YYYY-MM'), 'HRM (new joiner)'
      from hrm.training_programs p where p.tenant_id = t and p.title in ('Induction — company, HR rules and facilities', 'Safety induction', 'Quality policy, objectives & product safety')
    on conflict do nothing;
    insert into hrm.ojt_records (tenant_id, template_id, employee_id, trainer, started_on, status) values (t, tpl, rec.id, 'Manoj Gowda', current_date + 5, 'in_progress')
    on conflict do nothing;
  end loop;

  -- ---- internal auditors ----
  insert into hrm.auditors (tenant_id, employee_id, kind, standards, qualification, trained_on, certificate_no, valid_until, core_tools, csr_trained, audits_per_year)
  select t, e.id, x.kind, x.std, x.qual, current_date - x.ago, x.cert, current_date - x.ago + x.valid, x.tools, x.csr, 2
    from (values ('-D005', 'qms', array['IATF 16949','ISO 9001'], 'IATF 16949 internal auditor (2 days, external)', 600, 'IA-2291', 1095, array['APQP','PPAP','FMEA','SPC','MSA'], true),
                 ('-D017', 'process', array['IATF 16949','VDA 6.3'], 'VDA 6.3 process auditor', 1050, 'VDA-0442', 1095, array['APQP','PPAP','FMEA'], true),
                 ('-D022', 'qms', array['ISO 45001','ISO 14001'], 'ISO 45001 internal auditor', 330, 'OHS-118', 365, array[]::text[], false))
         x(code, kind, std, qual, ago, cert, valid, tools, csr)
    join hrm.employees e on e.tenant_id = t and e.employee_code = pfx || x.code;
  insert into hrm.auditor_audits (tenant_id, auditor_id, audit_date, area, audit_type, role, findings)
  select t, a.id, current_date - x.ago, x.area, x.typ, x.role, x.f
    from hrm.auditors a join hrm.employees e on e.id = a.employee_id
    join (values ('-D005', 140, 'Production — turning cell 1', 'process', 'lead', 3), ('-D005', 40, 'Stores & dispatch', 'system', 'lead', 1),
                 ('-D017', 300, 'Assembly line', 'process', 'auditor', 2), ('-D022', 90, 'Plant 2 — EHS', 'system', 'lead', 4)) x(code, ago, area, typ, role, f)
      on e.employee_code = pfx || x.code
   where a.tenant_id = t;

  return n;
end $fn$;

revoke all on function hrm.demo_positions(uuid), hrm.demo_qms(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_positions(uuid), hrm.demo_qms(uuid) to service_role;

-- companies with the sample people: the old per-designation sample R&R, competencies and KPIs make way for the positions
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop
    delete from hrm.rr_roles where tenant_id = r and sample and position_id is null;
    delete from hrm.role_competencies where tenant_id = r and sample and position_id is null;
    delete from hrm.kpis where tenant_id = r and sample and position_id is null;
    delete from hrm.employee_competencies ec using hrm.employees e where e.id = ec.employee_id and e.tenant_id = r and e.email like '%@demo.kmr.test';
    perform hrm.demo_positions(r);
  end loop;
end $$;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0010_ai.sql
-- =====================================================================
-- =====================================================================
-- HRM 0010 — Free AI for the QMS. Needs 0001–0009. Safe to re-run.
-- The AI (free tiers of OpenRouter / Groq / Gemini; keys only in the server's environment) drafts and ranks;
-- people decide:
--   • job descriptions and R&R sheets it writes are marked "AI draft" until HR approves them
--   • training programmes it proposes for needs that have none wait, switched off, until a named person accepts them
--   • pre / post test questions it writes for a programme wait for acceptance before they are printed
--   • the QMS agent finds problems with fixed rules; the AI only says which to work on first
-- Every AI run is logged (what was asked about, which model answered, how long it took).
-- =====================================================================

create table if not exists hrm.ai_runs (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  agent           text not null check (agent in ('jd','sheet','programmes','quiz','qms_agent','check')),
  subject         text check (length(subject) <= 300),
  ok              boolean not null,
  provider        text,
  model           text,
  used            text check (used in ('ai','rules','none')),
  summary         text check (length(summary) <= 2000),
  output          jsonb,
  error           text check (length(error) <= 2000),
  ms              integer,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now()
);
create index if not exists ai_runs_recent on hrm.ai_runs (tenant_id, created_at desc);
alter table hrm.ai_runs enable row level security;
drop policy if exists ai_runs_hr on hrm.ai_runs;
create policy ai_runs_hr on hrm.ai_runs for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());

alter table hrm.job_descriptions add column if not exists ai_model text;          -- set when the AI wrote this version
alter table hrm.rr_roles add column if not exists ai_model text;
alter table hrm.training_programs add column if not exists ai_proposed boolean not null default false;
alter table hrm.training_programs add column if not exists ai_model text;
alter table hrm.training_programs add column if not exists ai_topics text[] not null default '{}';   -- the need topics an AI-proposed programme is for
alter table hrm.training_programs add column if not exists reviewed_by uuid;
alter table hrm.training_programs add column if not exists reviewed_by_name text;
alter table hrm.training_programs add column if not exists reviewed_at timestamptz;
alter table hrm.training_programs add column if not exists quiz jsonb not null default '[]';      -- [{q, options[4], answer 0-3}]
alter table hrm.training_programs add column if not exists quiz_status text check (quiz_status in ('ai_draft','accepted'));
alter table hrm.training_programs add column if not exists quiz_model text;
alter table hrm.qms_settings add column if not exists ai_enabled boolean not null default true;
alter table hrm.qms_settings add column if not exists agent_result jsonb;      -- the last QMS agent run: findings + ranking
alter table hrm.qms_settings add column if not exists agent_run_at timestamptz;

-- ---------- the full flush also clears the AI log ----------
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0011_engage.sql
-- =====================================================================
-- =====================================================================
-- HRM 0011 — Phase 5B: employee engagement. Needs 0001–0010. Safe to re-run.
--   • Announcements — HR posts news to everybody, a department or a plant; pinned; "please acknowledge" when it
--     must be read (safety, policy); who has read / acknowledged it
--   • Recognition — a thank-you wall: managers and HR recognise people, colleagues thank each other; Employee of the
--     month; an implemented suggestion recognises its author automatically
--   • Suggestions / Kaizen — employees send ideas from their portal; the manager or HR reviews them
--     (under review → accepted → implemented with the saving, or not taken up with the reason)       IATF 16949 7.3.2
--   • Surveys — engagement, pulse, training, canteen …; anonymous by default: the answers carry no name and the
--     list of who has answered is kept apart from the answers; results by group only when 5 or more answered
-- The free AI (0010) can draft an announcement's wording and summarise survey comments; a person reviews both.
-- =====================================================================

-- ---------- announcements ----------
create table if not exists hrm.announcements (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  title           text not null check (length(title) between 2 and 160),
  body            text not null check (length(body) between 2 and 5000),
  category        text not null default 'general' check (category in ('general','safety','quality','hr','event','policy','production')),
  audience        text not null default 'all' check (audience in ('all','department','plant')),
  department_id   uuid references hrm.departments(id) on delete cascade,
  plant_id        uuid references hrm.plants(id) on delete cascade,
  pinned          boolean not null default false,
  needs_ack       boolean not null default false,                 -- each person confirms he has read it
  notify          boolean not null default true,                  -- e-mail / WhatsApp when it is published
  status          text not null default 'draft' check (status in ('draft','published','archived')),
  publish_on      date,                                           -- a later date: published by the daily job that day
  expires_on      date,                                           -- off the board after this day
  published_at    timestamptz,
  notified_at     timestamptz,
  ai_model        text,                                           -- the AI drafted the wording (HR edited / approved it)
  sample          boolean not null default false,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);
create index if not exists announcements_board on hrm.announcements (tenant_id, status, pinned desc, published_at desc);

create table if not exists hrm.announcement_reads (
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  announcement_id uuid not null references hrm.announcements(id) on delete cascade,
  employee_id     uuid not null references hrm.employees(id) on delete cascade,
  read_at         timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key (announcement_id, employee_id)
);

-- ---------- recognition ----------
create table if not exists hrm.recognitions (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references hrm.tenants(id) on delete cascade,
  employee_id          uuid not null references hrm.employees(id) on delete cascade,     -- who is recognised
  category             text not null check (category in ('safety','quality','kaizen','teamwork','customer','attendance','helping','delivery','long_service','employee_of_month')),
  message              text not null check (length(message) between 3 and 1000),
  month                text check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),                   -- Employee of the month
  given_by             uuid,                                                              -- app user
  given_by_name        text,
  given_by_employee_id uuid references hrm.employees(id) on delete set null,
  kind                 text not null default 'manager' check (kind in ('manager','hr','peer','auto')),
  suggestion_id        uuid,
  visible              boolean not null default true,                                     -- HR can take one off the wall
  sample               boolean not null default false,
  created_at           timestamptz not null default now()
);
create index if not exists recognitions_wall on hrm.recognitions (tenant_id, created_at desc);
create unique index if not exists recognitions_eom on hrm.recognitions (tenant_id, month, employee_id) where category = 'employee_of_month';

-- ---------- suggestions / kaizen ----------
create table if not exists hrm.suggestions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  ref              text,
  employee_id      uuid not null references hrm.employees(id) on delete cascade,          -- who suggested it
  team             text check (length(team) <= 300),                                       -- others who worked on it
  title            text not null check (length(title) between 3 and 160),
  problem          text not null check (length(problem) between 3 and 2000),              -- what is wrong today
  idea             text not null check (length(idea) between 3 and 2000),                 -- what to change
  area             text check (length(area) <= 120),                                       -- line / machine / place
  category         text not null default 'productivity' check (category in ('safety','quality','productivity','cost','5s','environment','ergonomics','other')),
  status           text not null default 'submitted' check (status in ('submitted','under_review','accepted','implemented','not_taken','on_hold')),
  review_note      text check (length(review_note) <= 1000),
  benefit          text check (length(benefit) <= 1000),                                   -- what it gave (quality, safety, time …)
  saving_per_year  numeric(14,2) check (saving_per_year is null or saving_per_year >= 0),  -- rupees a year, when it saves money
  before_text      text check (length(before_text) <= 1000),
  after_text       text check (length(after_text) <= 1000),
  implemented_on   date,
  reviewed_by      uuid,
  reviewed_by_name text,
  decided_at       timestamptz,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists suggestions_list on hrm.suggestions (tenant_id, status, created_at desc);
create unique index if not exists suggestions_ref on hrm.suggestions (tenant_id, ref);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'recognitions_suggestion_fk') then
    alter table hrm.recognitions add constraint recognitions_suggestion_fk foreign key (suggestion_id) references hrm.suggestions(id) on delete set null;
  end if;
end $$;

-- SG-2026-001, SG-2026-002 … per company and year
create or replace function hrm.suggestion_ref() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
declare y text := to_char((now() at time zone 'Asia/Kolkata'), 'YYYY'); n int;
begin
  if new.ref is null then
    perform pg_advisory_xact_lock(hashtext('suggestion_ref' || new.tenant_id::text));
    select coalesce(max(substring(ref from '\d+$')::int), 0) + 1 into n from hrm.suggestions where tenant_id = new.tenant_id and ref like 'SG-' || y || '-%';
    new.ref := 'SG-' || y || '-' || lpad(n::text, 3, '0');
  end if;
  return new;
end $fn$;
drop trigger if exists suggestions_ref_set on hrm.suggestions;
create trigger suggestions_ref_set before insert on hrm.suggestions for each row execute function hrm.suggestion_ref();

-- ---------- surveys ----------
create table if not exists hrm.surveys (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  title            text not null check (length(title) between 2 and 160),
  intro            text check (length(intro) <= 2000),
  kind             text not null default 'engagement' check (kind in ('engagement','pulse','training','canteen','exit','custom')),
  anonymous        boolean not null default true,
  audience         text not null default 'all' check (audience in ('all','department','plant')),
  department_id    uuid references hrm.departments(id) on delete cascade,
  plant_id         uuid references hrm.plants(id) on delete cascade,
  questions        jsonb not null default '[]',    -- [{id, text, type: rating|enps|yesno|choice|text, options[], required}]
  status           text not null default 'draft' check (status in ('draft','open','closed')),
  opens_on         date,
  closes_on        date,
  notified_at      timestamptz,
  reminded_at      timestamptz,
  ai_summary       jsonb,                          -- {themes:[{theme, count, points[]}], actions[]} — the AI's reading of the comments
  ai_model         text,
  ai_summary_at    timestamptz,
  summary_reviewed_by_name text,                   -- a person checked the summary against the comments
  summary_reviewed_at timestamptz,
  sample           boolean not null default false,
  created_by       uuid,
  created_by_name  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (jsonb_typeof(questions) = 'array'),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);
-- who has answered (so nobody answers twice and reminders go only to the others) — kept apart from the answers
create table if not exists hrm.survey_participants (
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  survey_id    uuid not null references hrm.surveys(id) on delete cascade,
  employee_id  uuid not null references hrm.employees(id) on delete cascade,
  responded_on date not null,
  primary key (survey_id, employee_id)
);
-- the answers: no name when the survey is anonymous, and only the day (not the time) it was given
create table if not exists hrm.survey_responses (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  survey_id     uuid not null references hrm.surveys(id) on delete cascade,
  employee_id   uuid references hrm.employees(id) on delete set null,      -- only when the survey is not anonymous
  department_id uuid references hrm.departments(id) on delete set null,    -- results by department only with 5+ answers
  plant_id      uuid references hrm.plants(id) on delete set null,
  answers       jsonb not null check (jsonb_typeof(answers) = 'object' and length(answers::text) <= 20000),
  submitted_on  date not null
);
create index if not exists survey_responses_by on hrm.survey_responses (survey_id);

-- ---------- is this person in the audience? ----------
create or replace function hrm.in_audience(p_aud text, p_dept uuid, p_plant uuid) returns boolean
language sql stable security definer set search_path = hrm, public as $fn$
  select case p_aud when 'all' then true
    when 'department' then exists (select 1 from hrm.employees e where e.id = hrm.current_employee_id() and e.department_id = p_dept)
    when 'plant' then exists (select 1 from hrm.employees e where e.id = hrm.current_employee_id() and e.plant_id = p_plant)
    else false end
$fn$;
grant execute on function hrm.in_audience(text, uuid, uuid) to authenticated;

-- ---------- answering a survey: the one way in (checks it is open, for him, and not answered yet) ----------
create or replace function hrm.submit_survey(p_survey uuid, p_answers jsonb) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
declare me uuid := hrm.current_employee_id(); s hrm.surveys; e hrm.employees; today date := (now() at time zone 'Asia/Kolkata')::date;
  q jsonb; v jsonb;
begin
  if me is null then raise exception 'Only employees can answer surveys.'; end if;
  select * into s from hrm.surveys where id = p_survey and tenant_id = hrm.current_tenant_id();
  if s.id is null or s.status <> 'open' or (s.opens_on is not null and s.opens_on > today) or (s.closes_on is not null and s.closes_on < today) then
    raise exception 'This survey is not open.'; end if;
  if not hrm.in_audience(s.audience, s.department_id, s.plant_id) then raise exception 'This survey is not for you.'; end if;
  if exists (select 1 from hrm.survey_participants where survey_id = s.id and employee_id = me) then raise exception 'You have already answered this survey. Thank you!'; end if;
  if jsonb_typeof(p_answers) <> 'object' or length(p_answers::text) > 20000 then raise exception 'The answers could not be read.'; end if;
  -- every answer must belong to a question and fit its type; required questions must be answered
  for q in select * from jsonb_array_elements(s.questions) loop
    v := p_answers -> (q->>'id');
    if v is null or v = 'null'::jsonb or v = '""'::jsonb then
      if coalesce((q->>'required')::boolean, false) then raise exception 'Please answer: %', q->>'text'; end if;
      continue;
    end if;
    if q->>'type' = 'rating' and not (jsonb_typeof(v) = 'number' and (v::text)::numeric between 1 and 5) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'enps' and not (jsonb_typeof(v) = 'number' and (v::text)::numeric between 0 and 10) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'yesno' and v not in ('"yes"'::jsonb, '"no"'::jsonb) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'choice' and not (coalesce(q->'options', '[]'::jsonb) ? (v #>> '{}')) then raise exception 'Invalid answer: %', q->>'text'; end if;
    if q->>'type' = 'text' and not (jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 2000) then raise exception 'Invalid answer: %', q->>'text'; end if;
  end loop;
  if exists (select 1 from jsonb_object_keys(p_answers) k where not exists (select 1 from jsonb_array_elements(s.questions) q2 where q2->>'id' = k)) then
    raise exception 'The answers could not be read.'; end if;
  select * into e from hrm.employees where id = me;
  insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (s.tenant_id, s.id, me, today);
  insert into hrm.survey_responses (tenant_id, survey_id, employee_id, department_id, plant_id, answers, submitted_on)
    values (s.tenant_id, s.id, case when s.anonymous then null else me end, e.department_id, e.plant_id, p_answers, today);
end $fn$;
revoke all on function hrm.submit_survey(uuid, jsonb) from public, anon;
grant execute on function hrm.submit_survey(uuid, jsonb) to authenticated;

-- ---------- updated_at + audit trail (never on survey answers or who answered: that would undo the anonymity) ----------
do $$ declare t text; begin
  foreach t in array array['announcements','suggestions','surveys'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['announcements','recognitions','suggestions','surveys'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['announcements','announcement_reads','recognitions','suggestions','surveys','survey_participants','survey_responses'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- answers are written only through hrm.submit_survey; HR reads them
drop policy if exists survey_responses_hr on hrm.survey_responses;
create policy survey_responses_hr on hrm.survey_responses for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists survey_participants_hr on hrm.survey_participants;
create policy survey_participants_hr on hrm.survey_participants for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
drop policy if exists survey_participants_self on hrm.survey_participants;
create policy survey_participants_self on hrm.survey_participants for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());

-- announcements and surveys: everybody they are meant for reads them once published / open
drop policy if exists announcements_read on hrm.announcements;
create policy announcements_read on hrm.announcements for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status = 'published' and (publish_on is null or publish_on <= (now() at time zone 'Asia/Kolkata')::date)
    and (hrm.has_role('manager') or hrm.in_audience(audience, department_id, plant_id)));
drop policy if exists surveys_read on hrm.surveys;
create policy surveys_read on hrm.surveys for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status in ('open','closed') and hrm.in_audience(audience, department_id, plant_id));

-- reading / acknowledging: each person his own; a manager sees his team's
drop policy if exists announcement_reads_self on hrm.announcement_reads;
create policy announcement_reads_self on hrm.announcement_reads for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id())
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists announcement_reads_team on hrm.announcement_reads;
create policy announcement_reads_team on hrm.announcement_reads for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));

-- recognition: the wall is for everybody; anyone thanks a colleague (not himself); managers recognise their team;
-- Employee of the month is HR's
drop policy if exists recognitions_wall on hrm.recognitions;
create policy recognitions_wall on hrm.recognitions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (visible or employee_id = hrm.current_employee_id()));
drop policy if exists recognitions_give on hrm.recognitions;
create policy recognitions_give on hrm.recognitions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and given_by = auth.uid() and category <> 'employee_of_month' and kind in ('peer','manager')
    and employee_id is distinct from hrm.current_employee_id()
    and (kind = 'peer' or (hrm.has_role('manager') and hrm.is_in_my_team(employee_id))));

-- suggestions: an employee sends his own and can change it until it is picked up; the manager reviews his team's;
-- implemented ones are on the Kaizen board for everybody
drop policy if exists suggestions_self on hrm.suggestions;
create policy suggestions_self on hrm.suggestions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (employee_id = hrm.current_employee_id() or status = 'implemented'));
drop policy if exists suggestions_send on hrm.suggestions;
create policy suggestions_send on hrm.suggestions for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted' and reviewed_by is null);
drop policy if exists suggestions_edit_own on hrm.suggestions;
create policy suggestions_edit_own on hrm.suggestions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted')
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id() and status = 'submitted' and reviewed_by is null);
drop policy if exists suggestions_team on hrm.suggestions;
create policy suggestions_team on hrm.suggestions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists suggestions_team_edit on hrm.suggestions;
create policy suggestions_team_edit on hrm.suggestions for update to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id))
  with check (tenant_id = hrm.current_tenant_id() and hrm.is_in_my_team(employee_id));

-- ---------- the AI may also draft announcements and summarise survey comments ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey'));

-- ---------- clearing: engagement joins the module flush ----------
-- (recognitions and suggestions also go with their person; the sample / real flushes clear them by their own flag too,
--  so a re-load of the sample never meets the old ones)
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
                             'auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 6: + engagement) ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 6, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
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
  delete from hrm.positions where tenant_id = p_tenant;
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
  perform hrm.seed_qms_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data: engagement among the sample people (deliberately imperfect) ----------
create or replace function hrm.demo_engage(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; pfx text; n int := 0; i int; a1 uuid; a2 uuid; a3 uuid; s1 uuid; s2 uuid; sg uuid; p1 uuid;
  people uuid[]; depts uuid[]; plants uuid[]; e uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
  emp_q jsonb := '[
    {"id":"q1","text":"How likely are you to recommend us as a place to work to a friend or relative?","type":"enps","required":true},
    {"id":"q2","text":"I know what is expected of me at work","type":"rating","required":true},
    {"id":"q3","text":"I have the machines, tools and materials to do my job well","type":"rating","required":true},
    {"id":"q4","text":"My supervisor cares about me and my safety","type":"rating","required":true},
    {"id":"q5","text":"I received the training I need for my job","type":"rating","required":true},
    {"id":"q6","text":"Someone recognised my good work in the last month","type":"rating","required":true},
    {"id":"q7","text":"My suggestions are listened to and acted on","type":"rating","required":true},
    {"id":"q8","text":"I feel safe at my workplace","type":"rating","required":true},
    {"id":"q9","text":"I understand our quality policy and how my work affects the customer","type":"rating","required":true},
    {"id":"q10","text":"Do you see yourself working here two years from now?","type":"yesno","required":true},
    {"id":"q11","text":"What is one thing we should improve?","type":"text","required":false},
    {"id":"q12","text":"What do you like most about working here?","type":"text","required":false}]';
  pulse_q jsonb := '[
    {"id":"q1","text":"Quality and taste of canteen food","type":"rating","required":true},
    {"id":"q2","text":"Cleanliness of the canteen and washrooms","type":"rating","required":true},
    {"id":"q3","text":"Company bus timing","type":"choice","options":["Good","Sometimes late","Often late","I do not use the bus"],"required":true},
    {"id":"q4","text":"Anything else we should know?","type":"text","required":false}]';
  improve text[] := array['The shop floor is very hot in the afternoon; please add more fans or coolers near the CNC line',
    'Overtime is told at the last minute; please inform one day before', 'More training on new machines before we are put on them',
    'Canteen food is the same every day, please change the menu', 'Bus comes late on the second shift, we reach home very late',
    'Supervisors should explain the reason when a suggestion is not taken', 'Drinking water point is far from the assembly line',
    'Please fix the leaking roof near stores before the rains', 'Need more safety shoes in all sizes', 'Recognise good work more often, not only at the year end'];
  likes text[] := array['Good team and helpful seniors', 'Salary is paid on time every month', 'I learn new machines here',
    'Supervisor listens to us', 'Safe workplace and clean shop floor', 'Training is given properly', 'Company bus and canteen facility'];
begin
  select emp_code_prefix into pfx from hrm.tenants where id = t;
  select array_agg(id order by employee_code), array_agg(department_id order by employee_code), array_agg(plant_id order by employee_code)
    into people, depts, plants from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 12 then return 0; end if;
  if exists (select 1 from hrm.announcements where tenant_id = t and sample) then return 0; end if;    -- already there
  select id into p1 from hrm.plants where tenant_id = t and code = 'DP1';

  -- announcements
  insert into hrm.announcements (tenant_id, title, body, category, audience, pinned, needs_ack, notify, status, publish_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Safety first: safety shoes and goggles are a must in the grinding and paint areas',
    'From Monday, nobody enters the grinding or paint area without safety shoes and goggles. Supervisors will stop work if PPE is missing. New shoes in all sizes are in stores — collect yours with your ID card.' || chr(10) || chr(10) || 'Please acknowledge that you have read this.',
    'safety', 'all', true, true, true, 'published', today - 6, now() - interval '6 days', now() - interval '6 days', true, 'HR (sample)') returning id into a1;
  insert into hrm.announcements (tenant_id, title, body, category, audience, notify, status, publish_on, expires_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Ayudha Pooja: holiday and plant shutdown', 'The plant is closed for Ayudha Pooja. Machines will be cleaned and decorated the day before; pooja at 10 AM in front of the main shop. Sweets for everybody after the pooja.',
    'hr', 'all', true, 'published', today - 2, today + 20, now() - interval '2 days', now() - interval '2 days', true, 'HR (sample)') returning id into a2;
  insert into hrm.announcements (tenant_id, title, body, category, audience, plant_id, notify, status, publish_on, published_at, notified_at, sample, created_by_name)
  values (t, 'Customer audit next week — keep your area audit-ready',
    'Our customer''s quality team visits the plant next week. Keep work instructions at the machine, check sheets filled on time, 5S in your area and your ID card on. If an auditor asks you something you do not know, call your supervisor.',
    'quality', case when p1 is null then 'all' else 'plant' end, p1, true, 'published', today - 1, now() - interval '1 day', now() - interval '1 day', true, 'HR (sample)') returning id into a3;
  insert into hrm.announcements (tenant_id, title, body, category, audience, status, sample, created_by_name)
  values (t, 'Blood donation camp (draft)', 'A blood donation camp with the district hospital. Date to be fixed.', 'event', 'all', 'draft', true, 'HR (sample)');
  n := n + 4;
  -- 14 of the people have read the safety notice, 10 acknowledged it (not everybody — something for HR to chase)
  for i in 1..14 loop
    insert into hrm.announcement_reads (tenant_id, announcement_id, employee_id, read_at, acknowledged_at)
    values (t, a1, people[i], now() - make_interval(days => 6 - (i % 5)), case when i <= 10 then now() - make_interval(days => 6 - (i % 5)) end) on conflict do nothing;
    if i <= 9 then insert into hrm.announcement_reads (tenant_id, announcement_id, employee_id, read_at) values (t, a2, people[i + 3], now() - interval '1 day') on conflict do nothing; end if;
  end loop;

  -- suggestions (D003 … in turn), from fresh to implemented
  insert into hrm.suggestions (tenant_id, employee_id, title, problem, idea, area, category, status, review_note, benefit, saving_per_year, before_text, after_text, implemented_on, reviewed_by_name, decided_at, sample, created_at)
  values
   (t, people[3], 'Poka-yoke pin on the drilling fixture', 'Parts were sometimes loaded the wrong way round; 2–3 rejections a week', 'Add a fool-proof pin so the part fits only one way',
    'Line 1 · OP30 drilling', 'quality', 'implemented', 'Good idea, done by maintenance', 'Wrong loading is now impossible; zero rejections for this defect since', 48000,
    'Part could be loaded either way', 'Part fits only the right way', today - 40, 'Priya (sample)', now() - interval '40 days', true, now() - interval '60 days'),
   (t, people[11], 'Quick-change tool holder on the CNC lathe', 'Tool change takes 12 minutes', 'Use quick-change tool holders for the 4 most used tools',
    'Line 1 · CNC lathe', 'productivity', 'implemented', 'Approved; holders bought', 'Tool change 12 → 4 minutes; about 40 minutes more production per shift', 120000,
    '12 min tool change', '4 min tool change', today - 20, 'Priya (sample)', now() - interval '20 days', true, now() - interval '45 days'),
   (t, people[14], 'Coolant leak tray under the hydraulic pack', 'Oil drips on the floor; slipping risk', 'Fix a drip tray with a drain to the waste oil drum',
    'Maintenance · press shop', 'safety', 'implemented', null, 'No more oil on the floor near the press', 15000, 'Oil on floor', 'Dry floor', today - 10, 'Rahul (sample)', now() - interval '10 days', true, now() - interval '25 days'),
   (t, people[6], 'Colour-coded gauge stand', 'Gauges are mixed up between shifts', 'A shadow board with colour codes for each machine', 'Quality lab', '5s', 'accepted', 'Accepted — maintenance to make the board this month', null, null, null, null, null, 'Suresh (sample)', now() - interval '5 days', true, now() - interval '15 days'),
   (t, people[8], 'Bin labels in Tamil and English', 'New helpers pick the wrong bins', 'Labels in both languages with the part photo', 'Stores', 'quality', 'under_review', 'Checking label printer cost', null, null, null, null, null, 'HR (sample)', null, true, now() - interval '9 days'),
   (t, people[12], 'Second water cooler near the assembly line', 'Long walk to drink water in the afternoon heat', 'Put one water cooler near assembly', 'Assembly', 'ergonomics', 'submitted', null, null, null, null, null, null, null, null, true, now() - interval '12 days'),
   (t, people[16], 'Reuse packing cartons from suppliers', 'We buy new cartons while supplier cartons are thrown away', 'Collect good cartons in stores and reuse them for internal movement', 'Stores · dispatch', 'cost', 'submitted', null, null, null, null, null, null, null, null, true, now() - interval '2 days'),
   (t, people[20], 'Music on the shop floor', 'Work is boring in the night shift', 'Play music on speakers', 'Production', 'other', 'not_taken', 'Not taken: speakers would hide alarms and horns on the shop floor. Thank you for the idea — FM in the canteen is being arranged.', null, null, null, null, null, 'Priya (sample)', now() - interval '3 days', true, now() - interval '8 days');
  n := n + 8;

  -- recognition (an implemented suggestion recognises its author)
  for sg, e in select id, employee_id from hrm.suggestions where tenant_id = t and sample and status = 'implemented' loop
    insert into hrm.recognitions (tenant_id, employee_id, category, message, given_by_name, kind, suggestion_id, sample, created_at)
    select t, e, 'kaizen', 'Kaizen implemented: ' || s.title || coalesce(' — saves ₹' || to_char(s.saving_per_year, 'FM99,99,99,990') || ' a year', ''), 'KMR HRM', 'auto', sg, true, s.decided_at
      from hrm.suggestions s where s.id = sg;
    n := n + 1;
  end loop;
  insert into hrm.recognitions (tenant_id, employee_id, category, message, month, given_by_name, kind, sample, created_at)
  values (t, people[11], 'employee_of_month', 'Trained 4 new operators on the CNC line and kept zero rejections all month.', to_char(today - 30, 'YYYY-MM'), 'HR (sample)', 'hr', true, now() - interval '25 days')
  on conflict do nothing;
  insert into hrm.recognitions (tenant_id, employee_id, category, message, given_by_name, given_by_employee_id, kind, sample, created_at) values
   (t, people[5], 'customer', 'Handled the customer complaint over the weekend and sent the containment report on time.', 'Priya (sample)', people[2], 'manager', true, now() - interval '12 days'),
   (t, people[22], 'safety', 'Stopped a forklift reversing without a banksman — prevented an accident.', 'HR (sample)', null, 'hr', true, now() - interval '7 days'),
   (t, people[4], 'helping', 'Thank you for staying back to help me finish the urgent dispatch!', 'Karthik (sample)', people[3], 'peer', true, now() - interval '4 days'),
   (t, people[7], 'delivery', 'Repaired the spindle overnight; the line started on time next morning.', 'Priya (sample)', people[2], 'manager', true, now() - interval '2 days');
  n := n + 5;

  -- a closed engagement survey with 18 anonymous answers (so results by department show only where 5+ answered)
  insert into hrm.surveys (tenant_id, title, intro, kind, anonymous, audience, questions, status, opens_on, closes_on, notified_at, sample, created_by_name, created_at)
  values (t, 'Employee engagement survey', 'Your answers are anonymous: they carry no name, and results are shown only for groups of 5 or more. About 5 minutes.',
    'engagement', true, 'all', emp_q, 'closed', today - 30, today - 16, now() - interval '30 days', true, 'HR (sample)', now() - interval '31 days') returning id into s1;
  for i in 1..18 loop
    insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (t, s1, people[i], today - 30 + (i % 10));
    insert into hrm.survey_responses (tenant_id, survey_id, department_id, plant_id, answers, submitted_on)
    values (t, s1, depts[i], plants[i], jsonb_build_object(
      'q1', (array[9,10,8,7,9,6,10,8,5,9,7,10,4,8,9,3,7,9])[i],
      'q2', 3 + (i % 3), 'q3', 2 + ((i * 7) % 3), 'q4', 3 + ((i * 5) % 3), 'q5', 2 + ((i * 3) % 4),
      'q6', 1 + ((i * 11) % 4), 'q7', 2 + ((i * 13) % 3), 'q8', 3 + ((i * 2) % 3), 'q9', 3 + ((i * 17) % 3),
      'q10', case when i in (9, 13, 16) then 'no' else 'yes' end,
      'q11', case when i % 6 = 0 then '' else improve[1 + (i % array_length(improve, 1))] end,
      'q12', case when i % 4 = 0 then '' else likes[1 + (i % array_length(likes, 1))] end), today - 30 + (i % 10));
  end loop;
  -- an open pulse survey: 6 have answered; the rest (including the sample employee who signs in) still can
  insert into hrm.surveys (tenant_id, title, intro, kind, anonymous, audience, questions, status, opens_on, closes_on, notified_at, sample, created_by_name, created_at)
  values (t, 'Canteen and transport — quick pulse', 'Four quick questions. Anonymous.', 'canteen', true, 'all', pulse_q, 'open', today - 3, today + 7, now() - interval '3 days', true, 'HR (sample)', now() - interval '3 days') returning id into s2;
  for i in 1..6 loop
    insert into hrm.survey_participants (tenant_id, survey_id, employee_id, responded_on) values (t, s2, people[i], today - 2);
    insert into hrm.survey_responses (tenant_id, survey_id, department_id, plant_id, answers, submitted_on)
    values (t, s2, depts[i], plants[i], jsonb_build_object('q1', 2 + (i % 3), 'q2', 3 + (i % 2),
      'q3', (array['Good','Sometimes late','Often late','Often late','Good','I do not use the bus'])[i],
      'q4', (array['Please add a vegetable variety','','Second shift bus is late most days','','More chairs in the canteen',''])[i]), today - 2);
  end loop;
  n := n + 2;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g);
end $fn$;
revoke all on function hrm.demo_engage(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_engage(uuid), hrm.demo_flow(uuid) to service_role;

-- companies that already hold the sample people get the sample engagement records now
do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_engage(r); end loop;
end $$;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0012_compliance.sql
-- =====================================================================
-- =====================================================================
-- HRM 0012 — Phase 5C: policies, document control and the statutory compliance register. Needs 0001–0011. Safe to re-run.
--   • Controlled documents (ISO 9001 7.5): policies, procedures, formats, work instructions, manuals — document no.,
--     revision, prepared by / approved by, effective date, review due; a new revision makes the old one obsolete;
--     master list of documents (PDF)
--   • Policies are documents people must read: each person acknowledges the current revision in his portal; a new
--     revision asks again; HR sees who has not
--   • Compliance register: statutory payments, returns, registers, notices and licences (PF, ESI, PT, TDS, Form 16,
--     LWF, Bonus, Factories Act returns, POSH report, licence renewals …) — due dates worked out by fixed rules, done
--     with the reference no. and proof, reminders before the due date, overdue flagged
-- The defaults are for Karnataka and are a starting list only: dates differ by state and change — the company checks
-- them with its consultant and edits them.
-- =====================================================================

-- ---------- controlled documents ----------
create table if not exists hrm.documents (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  doc_no              text not null check (length(doc_no) between 1 and 40),
  title               text not null check (length(title) between 2 and 160),
  kind                text not null default 'policy' check (kind in ('policy','procedure','work_instruction','format','manual','other')),
  owner_department_id uuid references hrm.departments(id) on delete set null,
  owner_name          text check (length(owner_name) <= 120),                 -- who looks after it (a position, not a person, is best)
  employee_access     boolean not null default true,                          -- people can read it in their portal
  needs_ack           boolean not null default false,                         -- each person acknowledges each revision
  audience            text not null default 'all' check (audience in ('all','department','plant')),
  department_id       uuid references hrm.departments(id) on delete cascade,
  plant_id            uuid references hrm.plants(id) on delete cascade,
  review_months       integer not null default 12 check (review_months between 1 and 60),
  active              boolean not null default true,
  sample              boolean not null default false,
  created_by          uuid,
  created_by_name     text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, doc_no),
  check (audience <> 'department' or department_id is not null),
  check (audience <> 'plant' or plant_id is not null)
);

create table if not exists hrm.document_versions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references hrm.tenants(id) on delete cascade,
  document_id      uuid not null references hrm.documents(id) on delete cascade,
  revision         integer not null check (revision >= 0),
  body             text check (length(body) <= 60000),                  -- written in the HRM …
  file_path        text,                                                -- … and / or a PDF
  file_name        text,
  change_note      text check (length(change_note) <= 1000),           -- what changed in this revision
  status           text not null default 'draft' check (status in ('draft','approved','obsolete')),
  prepared_by      uuid,
  prepared_by_name text,
  approved_by      uuid,
  approved_by_name text,
  approved_at      timestamptz,
  effective_from   date,
  review_due       date,
  review_notified_at timestamptz,
  ai_model         text,                                                -- the AI drafted the text (HR edited and approved it)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (document_id, revision)
);
create index if not exists document_versions_current on hrm.document_versions (document_id, status);

create table if not exists hrm.document_acks (
  tenant_id       uuid not null references hrm.tenants(id) on delete cascade,
  version_id      uuid not null references hrm.document_versions(id) on delete cascade,
  employee_id     uuid not null references hrm.employees(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key (version_id, employee_id)
);

-- ---------- compliance register ----------
create table if not exists hrm.compliance_items (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  code          text not null check (length(code) between 1 and 30),
  title         text not null check (length(title) between 2 and 160),
  law           text check (length(law) <= 200),
  kind          text not null default 'return' check (kind in ('payment','return','register','licence','notice','report','other')),
  frequency     text not null default 'monthly' check (frequency in ('monthly','quarterly','half_yearly','yearly','once')),
  due_months    integer[] not null default '{}',             -- the months it falls due (monthly: all)
  due_day       integer not null default 15 check (due_day between 1 and 31),   -- 31 = the month's last day
  state         text check (length(state) <= 40),
  licence_no    text check (length(licence_no) <= 80),
  valid_until   date,                                         -- licences: renewal is due renew_days before this
  renew_days    integer not null default 60 check (renew_days between 0 and 365),
  remind_days   integer not null default 7 check (remind_days between 0 and 90),
  owner_name    text check (length(owner_name) <= 120),
  owner_email   text check (length(owner_email) <= 200),     -- reminders go here (blank: the company's HR managers)
  start_on      date not null default ((now() at time zone 'Asia/Kolkata')::date),   -- no tasks before this
  notes         text check (length(notes) <= 1000),
  active        boolean not null default true,
  sample        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, code)
);

create table if not exists hrm.compliance_tasks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references hrm.tenants(id) on delete cascade,
  item_id       uuid not null references hrm.compliance_items(id) on delete cascade,
  due_on        date not null,
  status        text not null default 'open' check (status in ('open','done','not_applicable')),
  done_on       date,
  done_by       uuid,
  done_by_name  text,
  reference     text check (length(reference) <= 120),        -- challan / acknowledgement / receipt no.
  evidence_path text,
  evidence_name text,
  note          text check (length(note) <= 1000),
  reminded_at   timestamptz,
  overdue_notified_at timestamptz,
  sample        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (item_id, due_on)
);
create index if not exists compliance_tasks_due on hrm.compliance_tasks (tenant_id, status, due_on);

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['documents','document_versions','compliance_items','compliance_tasks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['documents','document_versions','document_acks','compliance_items','compliance_tasks'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- payroll staff look after the statutory payments and returns too
drop policy if exists compliance_items_payroll on hrm.compliance_items;
create policy compliance_items_payroll on hrm.compliance_items for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll'));
drop policy if exists compliance_tasks_payroll on hrm.compliance_tasks;
create policy compliance_tasks_payroll on hrm.compliance_tasks for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('payroll'));
-- documents: managers read every one; employees read those open to them; only approved revisions leave HR
drop policy if exists documents_read on hrm.documents;
create policy documents_read on hrm.documents for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and active and (hrm.has_role('manager') or (employee_access and hrm.in_audience(audience, department_id, plant_id))));
drop policy if exists document_versions_read on hrm.document_versions;
create policy document_versions_read on hrm.document_versions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and status = 'approved' and exists (select 1 from hrm.documents d where d.id = document_id));
drop policy if exists document_acks_self on hrm.document_acks;
create policy document_acks_self on hrm.document_acks for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists document_acks_give on hrm.document_acks;
create policy document_acks_give on hrm.document_acks for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id()
    and exists (select 1 from hrm.document_versions v where v.id = version_id and v.status = 'approved'));
drop policy if exists document_acks_team on hrm.document_acks;
create policy document_acks_team on hrm.document_acks for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));

-- ---------- the AI may also draft documents ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey','document'));

-- ---------- defaults: a starting compliance list (Karnataka) ----------
create or replace function hrm.seed_compliance_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.compliance_items (tenant_id, code, title, law, kind, frequency, due_months, due_day, state, notes)
  select p_tenant, x.code, x.title, x.law, x.kind, x.freq, x.months, x.day, x.st, x.notes from (values
    ('PF', 'PF contribution and ECR (previous month)', 'Employees'' Provident Funds & Misc. Provisions Act, 1952', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}'::int[], 15, null::text, 'Upload the ECR from Payroll › Bank & statutory files; keep the TRRN.'),
    ('ESI', 'ESI contribution (previous month)', 'Employees'' State Insurance Act, 1948', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 15, null, 'Keep the challan no.'),
    ('PT', 'Professional tax (previous month)', 'Karnataka Tax on Professions, Trades, Callings and Employments Act, 1976', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 20, 'Karnataka', null),
    ('TDS', 'TDS on salaries — deposit (previous month)', 'Income-tax Act — section 192', 'payment', 'monthly', '{1,2,3,4,5,6,7,8,9,10,11,12}', 7, null, 'For March the due date is 30 April.'),
    ('24Q', 'TDS return — Form 24Q (quarter)', 'Income-tax Act — section 200(3)', 'return', 'quarterly', '{5,7,10,1}', 31, null, 'Q4 by 31 May, Q1 by 31 Jul, Q2 by 31 Oct, Q3 by 31 Jan.'),
    ('F16', 'Form 16 to employees', 'Income-tax Act — section 203', 'notice', 'yearly', '{6}', 15, null, null),
    ('LWF', 'Labour Welfare Fund contribution', 'Karnataka Labour Welfare Fund Act, 1965', 'payment', 'yearly', '{1}', 15, 'Karnataka', 'For the calendar year just ended.'),
    ('BONUS', 'Bonus — annual return (Form D)', 'Payment of Bonus Act, 1965', 'return', 'yearly', '{2}', 1, null, 'Bonus itself within 8 months of the accounting year end.'),
    ('FA-Y', 'Factories Act — annual return', 'Factories Act, 1948 / Karnataka Factories Rules', 'return', 'yearly', '{1}', 31, 'Karnataka', null),
    ('FA-H', 'Factories Act — half-yearly return', 'Factories Act, 1948 / Karnataka Factories Rules', 'return', 'yearly', '{7}', 31, 'Karnataka', null),
    ('POSH', 'POSH — Internal Committee annual report', 'Sexual Harassment of Women at Workplace Act, 2013', 'report', 'yearly', '{1}', 31, null, 'To the District Officer, for the calendar year.'),
    ('MW', 'Minimum wages / VDA revision — check and apply', 'Minimum Wages Act / Code on Wages', 'other', 'half_yearly', '{4,10}', 1, 'Karnataka', 'Update salary structures if the notified rates changed.'),
    ('LIC-FAC', 'Factory licence — renewal', 'Factories Act, 1948', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-SE', 'Shops & Establishments registration — renewal', 'Karnataka Shops & Commercial Establishments Act, 1961', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-CL', 'Contract labour licence — renewal', 'Contract Labour (Regulation & Abolition) Act, 1970', 'licence', 'once', '{}', 1, null, 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-FIRE', 'Fire NOC — renewal', 'Karnataka Fire Force Act, 1964', 'licence', 'once', '{}', 1, 'Karnataka', 'Enter the licence no. and valid-until date to get renewal reminders.'),
    ('LIC-PCB', 'Pollution Control Board consent — renewal', 'Water Act, 1974 / Air Act, 1981', 'licence', 'once', '{}', 1, null, 'Enter the consent no. and valid-until date to get renewal reminders.')
  ) x(code, title, law, kind, freq, months, day, st, notes)
  on conflict (tenant_id, code) do nothing;
end $fn$;
revoke all on function hrm.seed_compliance_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_compliance_defaults(uuid) to service_role;

create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  perform hrm.seed_compliance_defaults(new.id);
  return new;
end $fn$;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_compliance_defaults(t); end loop; end $$;

-- ---------- clearing ----------
-- 'all': everything; the default compliance list comes back. 'real': the company's own documents and compliance tasks
-- (the compliance list itself is company setup and stays, like plants). 'sample': sample records only.
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['compliance_tasks','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['compliance_tasks','compliance_items','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['document_acks','survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
                             'auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); perform hrm.seed_compliance_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 7: + documents and compliance) ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 7, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.compliance_items where tenant_id = p_tenant;
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
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
  delete from hrm.positions where tenant_id = p_tenant;
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
  perform hrm.seed_qms_defaults(p_tenant);
  perform hrm.seed_compliance_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data (deliberately imperfect: a review overdue, a policy not everybody has read, a late filing,
--            a licence close to expiry) ----------
create or replace function hrm.demo_compliance(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; n int := 0; people uuid[]; hrd uuid; d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; v uuid; i int; k int;
  today date := (now() at time zone 'Asia/Kolkata')::date; m date; it record;
begin
  select array_agg(id order by employee_code) into people from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 12 then return 0; end if;
  if exists (select 1 from hrm.documents where tenant_id = t and sample) then return 0; end if;
  perform hrm.seed_compliance_defaults(t);
  select id into hrd from hrm.departments where tenant_id = t and name ilike 'Human Resources%' limit 1;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, review_months, sample, created_by_name)
  values (t, 'S-HR-POL-01', 'Code of conduct', 'policy', hrd, 'HR Manager', true, true, 24, true, 'HR (sample)') returning id into d1;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d1, 0, '1. Purpose' || chr(10) || 'To set out how everybody at the company is expected to behave at work.' || chr(10) || chr(10) ||
    '2. Scope' || chr(10) || 'All employees, trainees, contract workers and visitors.' || chr(10) || chr(10) ||
    '3. What we expect' || chr(10) || '- Treat everybody with respect; no abuse, harassment or discrimination.' || chr(10) || '- Follow the safety rules and wear the PPE of your area.' || chr(10) ||
    '- Report quality problems at once; never pass a doubtful part.' || chr(10) || '- No alcohol or drugs at work; no smoking outside the smoking zone.' || chr(10) ||
    '- Do not accept gifts or money from suppliers or customers.' || chr(10) || '- Keep company and customer information confidential.' || chr(10) || chr(10) ||
    '4. If the code is broken' || chr(10) || 'Tell your supervisor or HR. Action is taken as per the certified standing orders.',
    'First issue', 'approved', 'HR Executive (sample)', 'HR Manager (sample)', now() - interval '200 days', today - 200, today + 530) returning id into v;
  for i in 1..15 loop insert into hrm.document_acks (tenant_id, version_id, employee_id, acknowledged_at) values (t, v, people[i], now() - make_interval(days => 190 - i)); end loop;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-POL-02', 'Prevention of sexual harassment (POSH) policy', 'policy', hrd, 'HR Manager', true, true, true, 'HR (sample)') returning id into d2;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d2, 1, '1. Purpose' || chr(10) || 'A workplace free of sexual harassment, as required by the POSH Act, 2013.' || chr(10) || chr(10) ||
    '2. Internal Committee' || chr(10) || 'The Internal Committee (names on the notice board) receives and enquires into complaints. A complaint can be made in writing within 3 months of the incident.' || chr(10) || chr(10) ||
    '3. Confidentiality' || chr(10) || 'The complaint, the names and the enquiry are kept confidential.' || chr(10) || chr(10) ||
    '4. No retaliation' || chr(10) || 'Nobody is punished for making a complaint in good faith.',
    'Internal Committee members updated', 'approved', 'HR Executive (sample)', 'Plant Head (sample)', now() - interval '40 days', today - 40, today + 325) returning id into v;
  for i in 1..9 loop insert into hrm.document_acks (tenant_id, version_id, employee_id, acknowledged_at) values (t, v, people[i], now() - make_interval(days => 39 - i)); end loop;

  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, review_months, sample, created_by_name)
  values (t, 'S-HR-P-01', 'Recruitment and selection procedure', 'procedure', hrd, 'HR Manager', false, false, 12, true, 'HR (sample)') returning id into d3;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d3, 1, 'Requisition → job description → sourcing → screening → interview → offer → joining, as in the HRM.', 'Old revision', 'obsolete', 'HR (sample)', 'Plant Head (sample)', now() - interval '700 days', today - 700, today - 335),
         (t, d3, 2, '1. Requisition: the department raises it in the HRM with the position, role and department.' || chr(10) || '2. Job description: written for the position and approved by HR.' || chr(10) ||
          '3. Screening: resumes scored against the must-have competencies.' || chr(10) || '4. Interview: a panel of at least two; scorecards in the HRM.' || chr(10) || '5. Offer and joining: offer letter, acceptance, self-onboarding, induction.',
          'Now done in the HRM', 'approved', 'HR (sample)', 'Plant Head (sample)', now() - interval '380 days', today - 380, today - 15);
  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-P-02', 'Competence, training and awareness procedure', 'procedure', hrd, 'HR Manager', false, false, true, 'HR (sample)') returning id into d4;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name, approved_by_name, approved_at, effective_from, review_due)
  values (t, d4, 0, 'Skill matrix, competency mapping, training needs, training plan, effectiveness and on-the-job training are kept in HRM › QMS & training (IATF 16949 7.2, 7.3).', 'First issue', 'approved', 'HR (sample)', 'Plant Head (sample)', now() - interval '90 days', today - 90, today + 275);
  insert into hrm.documents (tenant_id, doc_no, title, kind, owner_department_id, owner_name, employee_access, needs_ack, sample, created_by_name)
  values (t, 'S-HR-POL-03', 'Leave policy', 'policy', hrd, 'HR Manager', true, true, true, 'HR (sample)') returning id into d5;
  insert into hrm.document_versions (tenant_id, document_id, revision, body, change_note, status, prepared_by_name)
  values (t, d5, 0, 'Draft: casual, sick and earned leave as set in HRM › Leave policy. How to apply, who approves, carry forward and encashment.', 'First issue', 'draft', 'HR (sample)');
  n := n + 5;

  -- compliance: the last three months of the monthly items (one filed late, one still open), a licence near expiry
  insert into hrm.compliance_items (tenant_id, code, title, law, kind, frequency, due_day, state, licence_no, valid_until, renew_days, owner_name, sample, notes)
  values (t, 'S-LIC-BOILER', 'Boiler certificate — renewal (sample)', 'Boilers Act, 1923', 'licence', 'once', 1, 'Karnataka', 'KA/BLR/BC/2025/0098', today + 40, 60, 'Maintenance Head', true, 'Sample licence close to its renewal date.')
  on conflict (tenant_id, code) do nothing;
  for it in select id, code, due_day from hrm.compliance_items where tenant_id = t and code in ('PF','ESI','PT','TDS') loop
    k := 0;
    for i in 0..4 loop
      m := (date_trunc('month', today) - make_interval(months => i))::date;
      m := m + (least(it.due_day, extract(day from (m + interval '1 month - 1 day'))::int) - 1);
      if m > today or k >= 3 then continue; end if;
      k := k + 1;                                   -- k = 1 is the latest one that has fallen due
      insert into hrm.compliance_tasks (tenant_id, item_id, due_on, status, done_on, done_by_name, reference, note, sample)
      values (t, it.id, m, case when it.code = 'PT' and k = 1 then 'open' else 'done' end,
        case when it.code = 'PT' and k = 1 then null when it.code = 'ESI' and k = 2 then m + 3 else m - 2 end,
        case when it.code = 'PT' and k = 1 then null else 'Payroll (sample)' end,
        case when it.code = 'PT' and k = 1 then null else it.code || '/' || to_char(m, 'YYYYMM') || '/S' || k end,
        case when it.code = 'ESI' and k = 2 then 'Paid 3 days late — portal was down' end, true)
      on conflict (item_id, due_on) do nothing;
      n := n + 1;
    end loop;
  end loop;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int; c int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  c := hrm.demo_compliance(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g, 'compliance', c);
end $fn$;
revoke all on function hrm.demo_compliance(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_compliance(uuid), hrm.demo_flow(uuid) to service_role;

do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_compliance(r); end loop;
end $$;

notify pgrst, 'reload schema';


-- =====================================================================
-- products/hrm/0013_safety.sql
-- =====================================================================
-- =====================================================================
-- HRM 0013 — Phase 5D: safety. Needs 0001–0012. Safe to re-run.
--   • Incidents — near misses, unsafe acts / conditions (anyone reports them, employees from their portal with a photo),
--     first aid, injuries, lost-time injuries, property damage, fire, environment, dangerous occurrences; investigated
--     (why-why, root cause), corrective / preventive actions with an owner and a due date, closed by a named person
--   • Figures by fixed rules: days since the last lost-time injury, LTIFR and severity rate on the man-hours worked
--     (from attendance), near misses per injury
--   • PPE — what each department needs, what was issued to whom, when it is due for replacement; people without it
--   • Periodic medical examination register — dates only (done / next due); the HRM keeps no medical details
-- The free AI (0010) can draft the why-why and the actions for the investigator, who checks and saves them.
-- ISO 45001 9.1, 10.2 · Factories Act, 1948 (accident notice and registers — check the forms and time limits for your state).
-- =====================================================================

create table if not exists hrm.safety_settings (
  tenant_id        uuid primary key references hrm.tenants(id) on delete cascade,
  officer_name     text check (length(officer_name) <= 120),
  officer_email    text check (length(officer_email) <= 200),        -- new incidents and overdue actions are e-mailed here
  hours_per_day    numeric(4,1) not null default 8 check (hours_per_day between 1 and 24),   -- man-hours when attendance has no worked time
  ltifr_target     numeric(8,2),
  updated_at       timestamptz not null default now()
);

create table if not exists hrm.incidents (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references hrm.tenants(id) on delete cascade,
  ref                 text,
  kind                text not null check (kind in ('near_miss','unsafe_act','unsafe_condition','first_aid','injury','lost_time','property_damage','fire','environment','dangerous_occurrence')),
  occurred_at         timestamptz not null,
  plant_id            uuid references hrm.plants(id) on delete set null,
  department_id       uuid references hrm.departments(id) on delete set null,
  area                text check (length(area) <= 160),               -- line, machine, place
  description         text not null check (length(description) between 5 and 3000),
  immediate_action    text check (length(immediate_action) <= 2000),
  injured_employee_id uuid references hrm.employees(id) on delete set null,
  injured_other       text check (length(injured_other) <= 160),     -- a contract worker or visitor
  injury_nature       text check (length(injury_nature) <= 300),     -- e.g. cut on the left index finger
  days_lost           integer not null default 0 check (days_lost between 0 and 9999),
  potential           integer check (potential between 1 and 5),      -- how bad it could have been (1 minor … 5 fatal)
  status              text not null default 'reported' check (status in ('reported','investigating','action','closed')),
  investigator_name   text check (length(investigator_name) <= 120),
  why_why             text[] not null default '{}',
  root_cause          text check (length(root_cause) <= 2000),
  ai_model            text,                                           -- the AI drafted the why-why (the investigator checked it)
  ai_actions          jsonb,                                          -- actions the AI suggested; the investigator adds the ones he wants
  reportable          boolean not null default false,                 -- to the authority (Inspector of Factories, ESIC …)
  authority_notified_on date,
  authority_ref       text check (length(authority_ref) <= 120),
  photo_path          text,
  reported_by         uuid,
  reported_by_name    text,
  reported_by_employee_id uuid references hrm.employees(id) on delete set null,
  closed_at           timestamptz,
  closed_by_name      text,
  sample              boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
alter table hrm.incidents add column if not exists ai_actions jsonb;
create index if not exists incidents_list on hrm.incidents (tenant_id, occurred_at desc);
create unique index if not exists incidents_ref on hrm.incidents (tenant_id, ref);

create or replace function hrm.incident_ref() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
declare y text := to_char((new.occurred_at at time zone 'Asia/Kolkata'), 'YYYY'); n int;
begin
  if new.ref is null then
    perform pg_advisory_xact_lock(hashtext('incident_ref' || new.tenant_id::text));
    select coalesce(max(substring(ref from '\d+$')::int), 0) + 1 into n from hrm.incidents where tenant_id = new.tenant_id and ref like 'INC-' || y || '-%';
    new.ref := 'INC-' || y || '-' || lpad(n::text, 3, '0');
  end if;
  return new;
end $fn$;
drop trigger if exists incidents_ref_set on hrm.incidents;
create trigger incidents_ref_set before insert on hrm.incidents for each row execute function hrm.incident_ref();

create table if not exists hrm.incident_actions (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references hrm.tenants(id) on delete cascade,
  incident_id       uuid not null references hrm.incidents(id) on delete cascade,
  action            text not null check (length(action) between 3 and 1000),
  kind              text not null default 'corrective' check (kind in ('corrective','preventive')),
  owner_employee_id uuid references hrm.employees(id) on delete set null,
  owner_name        text check (length(owner_name) <= 120),
  due_on            date not null,
  status            text not null default 'open' check (status in ('open','done')),
  done_on           date,
  done_note         text check (length(done_note) <= 1000),
  notified_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists incident_actions_open on hrm.incident_actions (tenant_id, status, due_on);

create table if not exists hrm.ppe_items (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  name           text not null check (length(name) between 2 and 80),
  life_months    integer not null default 12 check (life_months between 1 and 120),   -- replace after
  for_all        boolean not null default false,            -- everybody must have it …
  departments    uuid[] not null default '{}',             -- … or the people of these departments
  sizes          text check (length(sizes) <= 200),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (tenant_id, name)
);
alter table hrm.ppe_items add column if not exists for_all boolean not null default false;
create table if not exists hrm.ppe_issues (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid not null references hrm.employees(id) on delete cascade,
  item_id        uuid not null references hrm.ppe_items(id) on delete cascade,
  issued_on      date not null,
  qty            integer not null default 1 check (qty between 1 and 100),
  size           text check (length(size) <= 20),
  next_due       date not null,
  issued_by_name text,
  note           text check (length(note) <= 300),
  sample         boolean not null default false,
  created_at     timestamptz not null default now()
);
create index if not exists ppe_issues_person on hrm.ppe_issues (employee_id, item_id, issued_on desc);

create table if not exists hrm.medical_checks (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  employee_id    uuid not null references hrm.employees(id) on delete cascade,
  kind           text not null default 'periodic' check (kind in ('pre_employment','periodic','hearing','vision','lung_function','other')),
  done_on        date,
  next_due       date,
  doctor         text check (length(doctor) <= 160),       -- the certifying surgeon / clinic
  certificate_path text,                                    -- the certificate (PDF), kept private
  note           text check (length(note) <= 300),          -- no medical findings here
  sample         boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists medical_checks_due on hrm.medical_checks (tenant_id, next_due);

-- ---------- man-hours worked in a period (attendance worked time; present days × hours a day when not recorded) ----------
create or replace function hrm.man_hours(p_from date, p_to date) returns numeric
language sql stable security definer set search_path = hrm, public as $fn$
  select coalesce(sum(case when a.worked_minutes > 0 then a.worked_minutes / 60.0 else a.present_days * coalesce(s.hours_per_day, 8) end), 0)
    from hrm.attendance_days a left join hrm.safety_settings s on s.tenant_id = a.tenant_id
   where a.tenant_id = hrm.current_tenant_id() and (hrm.is_hr() or hrm.has_role('manager')) and a.work_date between p_from and p_to
$fn$;
grant execute on function hrm.man_hours(date, date) to authenticated;

-- ---------- updated_at + audit trail ----------
do $$ declare t text; begin
  foreach t in array array['safety_settings','incidents','incident_actions','medical_checks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_touch', t);
    execute format('create trigger %I before update on hrm.%I for each row execute function hrm.touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['safety_settings','incidents','incident_actions','ppe_items','ppe_issues','medical_checks'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- access ----------
do $$ declare t text; begin
  foreach t in array array['safety_settings','incidents','incident_actions','ppe_items','ppe_issues','medical_checks'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_hr', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_hr', t);
  end loop;
end $$;
-- supervisors (managers) run safety on the floor: they see and record incidents and actions, and issue PPE to their team
drop policy if exists incidents_mgr on hrm.incidents;
create policy incidents_mgr on hrm.incidents for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
drop policy if exists incident_actions_mgr on hrm.incident_actions;
create policy incident_actions_mgr on hrm.incident_actions for all to authenticated
  using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager')) with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager'));
-- employees: report near misses and unsafe acts / conditions, see their own reports and the actions given to them
drop policy if exists incidents_report on hrm.incidents;
create policy incidents_report on hrm.incidents for insert to authenticated
  with check (tenant_id = hrm.current_tenant_id() and reported_by_employee_id = hrm.current_employee_id() and reported_by = auth.uid()
    and kind in ('near_miss','unsafe_act','unsafe_condition') and status = 'reported' and injured_employee_id is null);
drop policy if exists incidents_self on hrm.incidents;
create policy incidents_self on hrm.incidents for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and (reported_by_employee_id = hrm.current_employee_id() or injured_employee_id = hrm.current_employee_id()));
drop policy if exists incident_actions_self on hrm.incident_actions;
create policy incident_actions_self on hrm.incident_actions for select to authenticated
  using (tenant_id = hrm.current_tenant_id() and owner_employee_id = hrm.current_employee_id());
drop policy if exists ppe_items_read on hrm.ppe_items;
create policy ppe_items_read on hrm.ppe_items for select to authenticated using (tenant_id = hrm.current_tenant_id());
drop policy if exists ppe_issues_self on hrm.ppe_issues;
create policy ppe_issues_self on hrm.ppe_issues for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());
drop policy if exists ppe_issues_team on hrm.ppe_issues;
create policy ppe_issues_team on hrm.ppe_issues for select to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists ppe_issues_team_give on hrm.ppe_issues;
create policy ppe_issues_team_give on hrm.ppe_issues for insert to authenticated with check (tenant_id = hrm.current_tenant_id() and hrm.has_role('manager') and hrm.is_in_my_team(employee_id));
drop policy if exists medical_checks_self on hrm.medical_checks;
create policy medical_checks_self on hrm.medical_checks for select to authenticated using (tenant_id = hrm.current_tenant_id() and employee_id = hrm.current_employee_id());

-- ---------- the AI may also draft the why-why of an incident ----------
alter table hrm.ai_runs drop constraint if exists ai_runs_agent_check;
alter table hrm.ai_runs add constraint ai_runs_agent_check check (agent in ('jd','sheet','programmes','quiz','qms_agent','check','announcement','survey','document','safety'));

-- ---------- defaults: a starting PPE list ----------
create or replace function hrm.seed_safety_defaults(p_tenant uuid) returns void
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  insert into hrm.safety_settings (tenant_id) values (p_tenant) on conflict do nothing;
  insert into hrm.ppe_items (tenant_id, name, life_months, sizes)
  select p_tenant, x.n, x.m, x.s from (values
    ('Safety shoes', 12, '6,7,8,9,10,11'), ('Safety goggles', 6, null), ('Hand gloves', 1, 'M,L,XL'), ('Ear plugs', 1, null),
    ('Safety helmet', 24, null), ('Apron / coverall', 12, 'M,L,XL,XXL'), ('Dust mask', 1, null)
  ) x(n, m, s)
  on conflict (tenant_id, name) do nothing;
end $fn$;
revoke all on function hrm.seed_safety_defaults(uuid) from public, anon, authenticated;
grant execute on function hrm.seed_safety_defaults(uuid) to service_role;

create or replace function hrm.seed_new_tenant() returns trigger
language plpgsql security definer set search_path = hrm, public as $fn$
begin
  if to_regprocedure('hrm.seed_payroll_defaults(uuid)') is not null then perform hrm.seed_payroll_defaults(new.id); end if;
  if to_regprocedure('hrm.seed_recruit_defaults(uuid)') is not null then perform hrm.seed_recruit_defaults(new.id); end if;
  perform hrm.seed_qms_defaults(new.id);
  perform hrm.seed_compliance_defaults(new.id);
  perform hrm.seed_safety_defaults(new.id);
  return new;
end $fn$;
do $$ declare t uuid; begin for t in select id from hrm.tenants loop perform hrm.seed_safety_defaults(t); end loop; end $$;

-- ---------- clearing ('real' keeps the PPE list and safety settings — company setup, like plants) ----------
create or replace function hrm.module_flush(p_tenant uuid, p_mode text default 'all') returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int;
  lists text[] := case when p_mode = 'real' then array['incidents','ppe_issues','medical_checks','compliance_tasks','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','kpis','rr_roles','role_competencies','positions','operations']
                       else array['incidents','ppe_issues','medical_checks','compliance_tasks','compliance_items','documents','recognitions','suggestions','announcements','surveys','training_sessions','ojt_templates','training_programs','kpis','rr_roles','role_competencies','positions','operations','competencies'] end;
begin
  if p_mode not in ('all','real','sample') then raise exception 'Unknown flush mode %', p_mode; end if;
  if p_mode = 'all' then
    foreach t in array array['document_acks','survey_responses','survey_participants','announcement_reads','recognitions','suggestions',
                             'auditor_audits','auditors','ojt_records','training_effectiveness','training_attendance','training_needs','kpi_values','rr_acks','skill_levels','employee_competencies'] loop
      execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant; get diagnostics k = row_count; n := n + k;
    end loop;
    delete from hrm.qms_settings where tenant_id = p_tenant;
    delete from hrm.ai_runs where tenant_id = p_tenant;
    delete from hrm.ppe_items where tenant_id = p_tenant;
    delete from hrm.safety_settings where tenant_id = p_tenant;
  end if;
  foreach t in array lists loop
    execute format('delete from hrm.%I where tenant_id = $1 and (%s)', t,
      case p_mode when 'all' then 'true' when 'real' then 'not sample' else 'sample' end) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_mode = 'all' then perform hrm.seed_qms_defaults(p_tenant); perform hrm.seed_compliance_defaults(p_tenant); perform hrm.seed_safety_defaults(p_tenant); end if;
  return n;
end $fn$;
revoke all on function hrm.module_flush(uuid, text) from public, anon, authenticated;
grant execute on function hrm.module_flush(uuid, text) to service_role;

-- ---------- backup / restore (version 8: + safety) ----------
create or replace function hrm.company_export(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks',
    'safety_settings','ppe_items','ppe_issues','incidents','incident_actions','medical_checks'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    if t in ('employee_private') then
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.employee_id in (select id from hrm.employees where tenant_id = $1)', t) into rows using p_tenant;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    end if;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-hrm-backup', 'version', 8, 'exported_at', now(),
    'company', (select to_jsonb(x) - 'id' from hrm.tenants x where id = p_tenant), 'tenant_id', p_tenant, 'tables', out);
end $fn$;

create or replace function hrm.company_import(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n integer; counts jsonb := '{}'::jsonb; links jsonb;
  ins text[] := array['plants','departments','designations','positions','shifts','holidays','leave_types','notification_templates',
    'employees','employee_private','onboarding_invites','employee_documents','id_cards','attendance_devices',
    'attendance_punches','attendance_days','regularisation_requests','leave_requests','leave_ledger',
    'pay_settings','pay_components','salary_structures','loans','payroll_runs','payroll_lines','loan_recoveries',
    'recruit_settings','job_descriptions','requisitions','candidates','applications','interviews','interview_feedback','offers',
    'qms_settings','competencies','operations','role_competencies','rr_roles','rr_acks','kpis','kpi_values','employee_competencies','skill_levels',
    'training_programs','training_sessions','training_needs','training_attendance','training_effectiveness','ojt_templates','ojt_records','auditors','auditor_audits',
    'announcements','announcement_reads','suggestions','recognitions','surveys','survey_participants','survey_responses',
    'documents','document_versions','document_acks','compliance_items','compliance_tasks',
    'safety_settings','ppe_items','ppe_issues','incidents','incident_actions','medical_checks'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'employee_id', employee_id)), '[]') into links from hrm.app_users where tenant_id = p_tenant;
  perform hrm.module_flush(p_tenant, 'all');
  delete from hrm.compliance_items where tenant_id = p_tenant;
  delete from hrm.ppe_items where tenant_id = p_tenant;
  delete from hrm.safety_settings where tenant_id = p_tenant;
  delete from hrm.qms_settings where tenant_id = p_tenant;
  delete from hrm.competencies where tenant_id = p_tenant;
  delete from hrm.training_programs where tenant_id = p_tenant;
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
  delete from hrm.positions where tenant_id = p_tenant;
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
  perform hrm.seed_qms_defaults(p_tenant);
  perform hrm.seed_compliance_defaults(p_tenant);
  perform hrm.seed_safety_defaults(p_tenant);
  return counts;
end $fn$;
revoke all on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_export(uuid), hrm.company_import(uuid, jsonb) to service_role;

-- ---------- sample data (deliberately imperfect: an action overdue, a report nobody has looked at, PPE overdue,
--            people never issued shoes, a medical check overdue) ----------
create or replace function hrm.demo_safety(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t uuid := p_tenant; n int := 0; people uuid[]; depts uuid[]; plants uuid[]; i int; inc uuid; prod uuid; it record;
  today date := (now() at time zone 'Asia/Kolkata')::date; ts timestamptz;
begin
  select array_agg(id order by employee_code), array_agg(department_id order by employee_code), array_agg(plant_id order by employee_code)
    into people, depts, plants from hrm.employees where tenant_id = t and email like '%@demo.kmr.test' and status = 'active';
  if coalesce(array_length(people, 1), 0) < 22 then return 0; end if;
  if exists (select 1 from hrm.incidents where tenant_id = t and sample) then return 0; end if;
  perform hrm.seed_safety_defaults(t);
  update hrm.safety_settings set officer_name = coalesce(officer_name, 'Safety Officer (sample)') where tenant_id = t;
  select id into prod from hrm.departments where tenant_id = t and name = 'Production';
  -- production must have shoes, goggles, gloves and ear plugs (the company sets the rest)
  update hrm.ppe_items set departments = array[prod] where tenant_id = t and prod is not null and name in ('Safety shoes','Safety goggles','Hand gloves','Ear plugs') and departments = '{}' and not for_all;

  -- 1. a lost-time injury 75 days ago, investigated and closed, reported to the authority
  ts := (today - 75) + time '10:40';
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, department_id, area, description, immediate_action, injured_employee_id, injury_nature, days_lost, potential, status,
    investigator_name, why_why, root_cause, reportable, authority_notified_on, authority_ref, reported_by_name, closed_at, closed_by_name, sample)
  values (t, 'lost_time', ts, plants[15], depts[15], 'Press shop · 63 T power press', 'While removing a stuck part the operator''s hand entered the die area; the press stroked once.',
    'Press stopped and locked out; first aid; taken to the ESI hospital.', people[15], 'Crush injury to two fingers of the left hand', 4, 4, 'closed', 'Production Head (sample)',
    array['Why did the hand enter the die? — to remove a stuck part', 'Why was the part stuck? — worn ejector pin', 'Why did the press stroke? — two-hand control bypassed with a wedge',
      'Why was it bypassed? — operators found two-hand operation slow', 'Why was it not seen? — no daily check of safety devices'],
    'Two-hand control bypassed and no daily check of press safety devices.', true, today - 74, 'Form 18 / KA-FAC-2026-118', 'Supervisor (sample)', now() - interval '40 days', 'Plant Head (sample)', true)
  returning id into inc;
  insert into hrm.incident_actions (tenant_id, incident_id, action, kind, owner_name, due_on, status, done_on, done_note) values
    (t, inc, 'Remove the wedge; tamper-proof two-hand control fitted', 'corrective', 'Maintenance Head', today - 70, 'done', today - 72, 'Done the same week'),
    (t, inc, 'Daily press safety-device check added to the start-up checklist', 'preventive', 'Production Head', today - 60, 'done', today - 61, null),
    (t, inc, 'Press safety training for all press operators', 'preventive', 'HR', today - 50, 'done', today - 45, 'Done late — trainer not available');
  -- 2. first aid 30 days ago, closed
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, department_id, area, description, immediate_action, injured_employee_id, injury_nature, potential, status, investigator_name, root_cause, reported_by_name, closed_at, closed_by_name, sample)
  values (t, 'first_aid', (today - 30) + time '15:20', plants[16], depts[16], 'Deburring table', 'Small cut on the finger while deburring without gloves.', 'Cleaned and dressed at the first-aid box.',
    people[16], 'Small cut, right finger', 2, 'closed', 'Supervisor (sample)', 'Gloves not worn; cut-resistant gloves not issued at this table.', 'Supervisor (sample)', now() - interval '25 days', 'Safety Officer (sample)', true);
  -- 3. near miss 7 days ago (the forklift), actions — one overdue
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, immediate_action, potential, status, investigator_name, reported_by_name, reported_by_employee_id, sample)
  values (t, 'near_miss', (today - 7) + time '11:05', plants[22], 'Dispatch bay', 'Forklift reversed without a banksman; a helper walking behind stepped aside just in time.', 'Forklift stopped; driver counselled.',
    4, 'action', 'Safety Officer (sample)', 'Pooja (sample)', people[22], true) returning id into inc;
  insert into hrm.incident_actions (tenant_id, incident_id, action, kind, owner_employee_id, owner_name, due_on, status) values
    (t, inc, 'Reverse alarm and blue spot light on both forklifts', 'corrective', people[7], null, today - 2, 'open'),
    (t, inc, 'Marked pedestrian walkway in the dispatch bay', 'preventive', people[2], null, today + 10, 'open');
  -- 4. an unsafe condition reported from the portal 3 days ago — nobody has looked at it yet
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, potential, status, reported_by_name, reported_by_employee_id, sample)
  values (t, 'unsafe_condition', (today - 3) + time '09:30', plants[14], 'Maintenance store', 'Oil leaking from the compressor; floor slippery near the store door.', 3, 'reported', 'Deepa (sample)', people[14], true);
  -- 5. an unsafe act being investigated
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, immediate_action, potential, status, investigator_name, reported_by_name, sample)
  values (t, 'unsafe_act', (today - 2) + time '16:45', plants[12], 'Grinding', 'Operator grinding without goggles.', 'Work stopped; goggles issued.', 3, 'investigating', 'Supervisor (sample)', 'Supervisor (sample)', true);
  -- 6. property damage 15 days ago
  insert into hrm.incidents (tenant_id, kind, occurred_at, plant_id, area, description, potential, status, reported_by_name, sample)
  values (t, 'property_damage', (today - 15) + time '20:10', plants[8], 'Stores · rack B4', 'Forklift fork hit rack B4; one upright bent.', 3, 'reported', 'Stores (sample)', true);
  n := n + 6;

  -- PPE: production people got shoes / gloves at different times; some overdue, a few never issued
  for i in 1..24 loop
    if depts[i] is distinct from prod then continue; end if;
    for it in select id, name, life_months from hrm.ppe_items where tenant_id = t and name in ('Safety shoes','Hand gloves','Safety goggles') loop
      if it.name = 'Safety shoes' and i in (20, 21, 23) then continue; end if;          -- contract workers never issued shoes
      insert into hrm.ppe_issues (tenant_id, employee_id, item_id, issued_on, qty, next_due, issued_by_name, sample)
      values (t, people[i], it.id, today - (case it.name when 'Safety shoes' then 200 + i * 9 when 'Hand gloves' then 10 + i else 60 + i * 5 end),
        case when it.name = 'Hand gloves' then 2 else 1 end,
        (today - (case it.name when 'Safety shoes' then 200 + i * 9 when 'Hand gloves' then 10 + i else 60 + i * 5 end)) + make_interval(months => it.life_months), 'Stores (sample)', true);
      n := n + 1;
    end loop;
  end loop;
  -- periodic medical examination (dates only)
  for i in 1..24 loop
    if depts[i] is distinct from prod then continue; end if;
    insert into hrm.medical_checks (tenant_id, employee_id, kind, done_on, next_due, doctor, sample)
    values (t, people[i], 'periodic', today - (300 + i * 4), today - (300 + i * 4) + 365, 'Certifying surgeon (sample)', true);
    n := n + 1;
  end loop;
  return n;
end $fn$;

create or replace function hrm.demo_flow(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare r int; q int; g int; c int; s int;
begin
  r := hrm.demo_recruit(p_tenant);
  q := hrm.demo_qms(p_tenant);
  g := hrm.demo_engage(p_tenant);
  c := hrm.demo_compliance(p_tenant);
  s := hrm.demo_safety(p_tenant);
  return jsonb_build_object('recruitment', r, 'qms', q, 'engagement', g, 'compliance', c, 'safety', s);
end $fn$;
revoke all on function hrm.demo_safety(uuid), hrm.demo_flow(uuid) from public, anon, authenticated;
grant execute on function hrm.demo_safety(uuid), hrm.demo_flow(uuid) to service_role;

do $$ declare r uuid; begin
  for r in select distinct tenant_id from hrm.employees where email like '%@demo.kmr.test' loop perform hrm.demo_safety(r); end loop;
end $$;

notify pgrst, 'reload schema';


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
-- migrations/0031_sample_flow.sql
-- =====================================================================
-- =====================================================================
-- Console 0031 — the sample data runs through the whole HRM flow. Run after HRM 0007_sample_flow.sql.
--  • Grand Master › Sample Data Master › Load sample data now also loads the sample hiring flow (openings, scored
--    candidates at every stage, interviews, scorecards, offers and the new joiner). Pressing it again on a company that
--    already has the sample employees adds whatever sample parts are missing.
--  • Real-data flushes keep the sample hiring flow; the sample flush removes it (HRM 0007 › hrm.demo_flush).
--  • The Data Master's full HRM flush still clears everything, sample included.
-- Safe to re-run.
-- =====================================================================

-- recruitment data of a company; p_keep_sample keeps the sample openings, candidates and job descriptions
drop function if exists hrm.recruit_flush(uuid);
create or replace function hrm.recruit_flush(p_tenant uuid, p_keep_sample boolean default false) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; n int := 0; k int; smp boolean := p_keep_sample
  and exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'requisitions' and column_name = 'sample');
begin
  if smp then
    -- real openings (with every application to them) and real candidates (with their applications to sample openings)
    delete from hrm.requisitions where tenant_id = p_tenant and not sample; get diagnostics k = row_count; n := n + k;
    delete from hrm.candidates where tenant_id = p_tenant and not sample;   get diagnostics k = row_count; n := n + k;
    delete from hrm.job_descriptions j where j.tenant_id = p_tenant and not j.sample
       and not exists (select 1 from hrm.requisitions r where r.jd_id = j.id); get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  foreach t in array array['offers','interview_feedback','interviews','applications','candidates','requisitions','job_descriptions'] loop
    if to_regclass('hrm.' || t) is null then continue; end if;
    execute format('delete from hrm.%I where tenant_id = $1', t) using p_tenant;
    get diagnostics k = row_count; n := n + k;
  end loop;
  return n;
end $fn$;
revoke all on function hrm.recruit_flush(uuid, boolean) from public, anon, authenticated;

-- ---------- real-data flush (Grand Master): the sample hiring flow and the sample employees stay ----------
create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant, true);
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  if to_regclass('hrm.offers') is not null then
    update hrm.offers set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  end if;
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

-- ---------- Sample Data Master: load fills every HRM module, not only employees ----------
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int; k int; flow jsonb;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
      -- the rest of the HRM flow follows the sample employees (recruitment now; more modules join hrm.demo_flow)
      if to_regprocedure('hrm.demo_flow(uuid)') is not null then
        flow := hrm.demo_flow(r);
        out := out || jsonb_build_object('hrm_flow', flow);
      end if;
    else
      if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
        execute 'select count(*) from hrm.candidates where tenant_id = $1 and sample' into k using r;
        out := out || jsonb_build_object('hrm_candidates', k);
      end if;
      n := hrm.demo_flush(r);
    end if;
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

-- ---------- overview: the sample count of HRM includes the sample candidates ----------
create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
    if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
      execute 'select count(*) filter (where not sample), count(*) filter (where sample) from hrm.candidates where tenant_id = $1' into n, k using r;
      real_ := real_ || jsonb_build_object('hrm_candidates', n); smp := smp || jsonb_build_object('hrm_candidates', k);
    end if;
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


-- ---------- real-data messages name the real candidates too, and count only real people ----------
create or replace function console.grand_hrm_real_candidates(p_tenant uuid) returns integer
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare k int := 0;
begin
  if p_tenant is null or to_regclass('hrm.candidates') is null then return 0; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
    execute 'select count(*) from hrm.candidates where tenant_id = $1 and not sample' into k using p_tenant;
  else select count(*) into k from hrm.candidates where tenant_id = p_tenant; end if;
  return k;
end $fn$;
revoke all on function console.grand_hrm_real_candidates(uuid) from public, anon, authenticated;

create or replace function public.kmr_grand_real_flush(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; t text; n int;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    out := out || jsonb_build_object('hrm_candidates', console.grand_hrm_real_candidates(r));
    out := out || jsonb_build_object('hrm', hrm.real_flush(r));
  end if;
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
    if t = 'hrm' then
      -- the backup also carries the sample people as they were; the message counts only the company's own
      select count(*) into n from hrm.employees where tenant_id = console.grand_ref(cid, 'hrm') and coalesce(email, '') not like '%@demo.kmr.test';
      out := out || jsonb_build_object('hrm', n, 'hrm_candidates', console.grand_hrm_real_candidates(console.grand_ref(cid, 'hrm')));
    end if;
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


notify pgrst, 'reload schema';


-- =====================================================================
-- migrations/0032_hrm_qms.sql
-- =====================================================================
-- =====================================================================
-- Console 0032 — HRM QMS (Phase 5A) on the platform. Run after HRM 0008_qms.sql. Safe to re-run.
--  • The Data Master's full HRM flush and Grand Master › Flush real data also clear the QMS records
--    (skill matrix, competencies, training, R&R, KPIs, OJT, auditors) through hrm.module_flush — later HRM modules
--    plug into the same function, so these flushes keep covering everything.
--  • Flush real data keeps the sample QMS records; Flush sample data removes them (HRM 0008 › hrm.demo_flush).
--  • Grand Master › Load sample data loads the sample QMS records with the rest of the HRM flow (hrm.demo_flow).
-- =====================================================================

create or replace function hrm.company_flush(p_tenant uuid, p_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; emps int;
begin
  perform hrm.recruit_flush(p_tenant);
  -- QMS and every later HRM module (setup lists like the competency library stay unless the setup is reset)
  if to_regprocedure('hrm.module_flush(uuid,text)') is not null then
    if p_setup then perform hrm.module_flush(p_tenant, 'all');
    else perform hrm.module_flush(p_tenant, 'real'); perform hrm.module_flush(p_tenant, 'sample'); end if;
  end if;
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

create or replace function hrm.real_flush(p_tenant uuid) returns integer
language plpgsql security definer set search_path = hrm, public as $fn$
declare n int; demo uuid[];
begin
  perform hrm.recruit_flush(p_tenant, true);
  if to_regprocedure('hrm.module_flush(uuid,text)') is not null then perform hrm.module_flush(p_tenant, 'real'); end if;   -- QMS and later modules
  select coalesce(array_agg(id), '{}') into demo from hrm.employees where tenant_id = p_tenant and coalesce(email, '') like '%@demo.kmr.test';
  if cardinality(demo) = 0 then return (hrm.company_flush(p_tenant, false) ->> 'employees')::int; end if;
  delete from hrm.app_users where tenant_id = p_tenant and role = 'employee' and (employee_id is null or not employee_id = any(demo));
  update hrm.app_users set employee_id = null where tenant_id = p_tenant and employee_id is not null and not employee_id = any(demo);
  update hrm.employees set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  if to_regclass('hrm.offers') is not null then
    update hrm.offers set reporting_manager_id = null where tenant_id = p_tenant and reporting_manager_id is not null and not reporting_manager_id = any(demo);
  end if;
  delete from hrm.attendance_punches where tenant_id = p_tenant and (employee_id is null or not employee_id = any(demo));
  delete from hrm.employees where tenant_id = p_tenant and not id = any(demo);       -- their attendance, leave, payroll lines, loans … go with them
  get diagnostics n = row_count;
  if to_regclass('hrm.payroll_runs') is not null then
    delete from hrm.payroll_runs r where r.tenant_id = p_tenant and not exists (select 1 from hrm.payroll_lines l where l.run_id = r.id);
  end if;
  return n;
end $fn$;
revoke all on function hrm.real_flush(uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';


-- =====================================================================
-- migrations/0033_sales_flow.sql
-- =====================================================================
-- =====================================================================
-- KMR platform — Sales Flow (sales plan vs actual despatch). Needs 0011 (customer members), 0015 (Operations Master)
-- and 0029. Safe to re-run.
--  • One Sales Flow per customer company; licence product "sales" (product_ref = the customer's id).
--  • Access = the customer's user list: Administration › Users & access, role "sales" = admin / editor / viewer;
--    company administrators always have full access.
--  • Parts, customers and prices are NOT typed in: "Add parts" pulls them from the Operations Master
--    (parts + customers + the customer's rate contract valid today).
--  • A plan line = one part for one month: demand quantity + delivery schedule (specific date / daily / weekly).
--  • Actual despatch is entered per day (one figure per line per day). Pending = demand − despatched.
-- =====================================================================
do $$ begin
  if to_regclass('console.ops_records') is null then raise exception 'Run 0015_operations_master.sql first.'; end if;
  if to_regclass('console.customer_members') is null then raise exception 'Run 0011_customer_admin.sql first.'; end if;
end $$;

create table if not exists console.sf_lines (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references console.customers(id) on delete cascade,
  month         date not null check (month = date_trunc('month', month)::date),
  buyer_code    text not null default '',            -- customer code in the Operations Master (CUS-001)
  buyer_name    text not null default '',            -- customer name (copied, so history survives master changes)
  part_code     text not null check (length(trim(part_code)) > 0),
  part_name     text not null default '',
  price         numeric(14,2) not null default 0 check (price >= 0),
  currency      text not null default 'INR',
  uom           text not null default 'pcs',
  demand_qty    numeric(14,2) not null default 0 check (demand_qty >= 0),
  sched_type    text not null default 'date' check (sched_type in ('date','daily','weekly')),
  sched_date    date,                                -- sched_type = date: the delivery date
  sched_weekday smallint check (sched_weekday between 1 and 7),   -- sched_type = weekly: ISO weekday (1 = Monday)
  remarks       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    text,
  unique (customer_id, month, part_code, buyer_code)
);
create index if not exists sf_lines_month on console.sf_lines (customer_id, month);

create table if not exists console.sf_despatch (
  line_id       uuid not null references console.sf_lines(id) on delete cascade,
  customer_id   uuid not null references console.customers(id) on delete cascade,
  day           date not null,
  qty           numeric(14,2) not null check (qty >= 0),
  note          text,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  primary key (line_id, day)
);
create index if not exists sf_despatch_day on console.sf_despatch (customer_id, day);

alter table console.sf_lines    enable row level security;
alter table console.sf_despatch enable row level security;
drop policy if exists sf_lines_staff on console.sf_lines;
create policy sf_lines_staff on console.sf_lines for all to authenticated using (console.is_staff()) with check (console.is_staff());
drop policy if exists sf_despatch_staff on console.sf_despatch;
create policy sf_despatch_staff on console.sf_despatch for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- ---------- who may use it ----------
create or replace function console.sf_member(p_customer uuid, p_email text) returns boolean
language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m
                  where m.customer_id = p_customer and m.email = lower(p_email)
                    and (m.is_admin or coalesce(m.roles ->> 'sales', '') <> ''))
$$;

-- admin / editor / viewer / null (null also when the licence is not active)
create or replace function console.sf_role(p_customer uuid) returns text
language sql stable security definer set search_path = console, public as $$
  select case
    when not coalesce((select ok from console.access_state('sales', p_customer)), false) then null
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'sales', '') from console.customer_members m
           where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', '')))
  end
$$;
grant execute on function console.sf_role(uuid) to authenticated;

create or replace function public.kmr_sf_context(p_slug text) returns jsonb
language sql stable security definer set search_path = console, public as $$
  select case when console.sf_role(c.id) is null then null
              else jsonb_build_object('role', console.sf_role(c.id), 'customer_id', c.id, 'company', c.name) end
    from console.customers c where c.slug = lower(p_slug)
$$;
grant execute on function public.kmr_sf_context(text) to authenticated;

-- ---------- "Add parts": parts + customer + price from the Operations Master ----------
-- Price = the customer's rate contract for the part that is valid today (latest valid_from); falls back to a "price"
-- or "rate" held on the part itself; 0 when none is found (the planner can then type it).
create or replace function public.kmr_sf_parts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'part_code', p.code, 'part_name', p.name, 'drawing_no', p.data ->> 'drawing_no',
             'buyer_code', coalesce(p.data ->> 'customer', ''), 'buyer_name', coalesce(cu.name, p.data ->> 'customer', ''),
             'price', coalesce(rc.rate, nullif(p.data ->> 'price', '')::numeric, nullif(p.data ->> 'rate', '')::numeric, 0),
             'currency', coalesce(rc.currency, 'INR'), 'uom', coalesce(rc.uom, 'pcs'),
             'price_source', case when rc.rate is not null then 'rate contract ' || rc.code else null end)
           order by cu.name, p.code)
      from console.ops_records p
      left join console.ops_records cu on cu.customer_id = p.customer_id and cu.kind = 'customers' and cu.code = p.data ->> 'customer'
      left join lateral (
        select r.code, (r.data ->> 'rate')::numeric rate, coalesce(r.data ->> 'currency', 'INR') currency, coalesce(r.data ->> 'uom', 'pcs') uom
          from console.ops_records r
         where r.customer_id = p.customer_id and r.kind = 'rate_contracts' and r.active
           and r.data ->> 'party_type' = 'Customer' and r.data ->> 'item' = p.code
           and coalesce(r.data ->> 'rate', '') ~ '^[0-9.]+$'
           and (coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
           and (coalesce(r.data ->> 'valid_to', '')   !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date   >= today)
         order by coalesce(nullif(r.data ->> 'valid_from', ''), '0000') desc limit 1) rc on true
     where p.customer_id = cid and p.kind = 'parts' and p.active), '[]');
end $$;
grant execute on function public.kmr_sf_parts(text) to authenticated;

-- ---------- a month: plan lines + daily despatch ----------
create or replace function public.kmr_sf_month(p_slug text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; m date := date_trunc('month', p_month)::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return jsonb_build_object(
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.buyer_name, l.part_code)
                         from console.sf_lines l where l.customer_id = cid and l.month = m), '[]'),
    'despatch', coalesce((select jsonb_agg(jsonb_build_object('line_id', d.line_id, 'day', d.day, 'qty', d.qty, 'note', d.note))
                            from console.sf_despatch d join console.sf_lines l on l.id = d.line_id
                           where l.customer_id = cid and l.month = m), '[]'));
end $$;
grant execute on function public.kmr_sf_month(text, date) to authenticated;

-- ---------- save / delete a plan line (p: {id?, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom,
--            demand_qty, sched_type, sched_date, sched_weekday, remarks}); several at once as an array ----------
create or replace function public.kmr_sf_save_lines(p_slug text, p jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', '')); st text; m date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else jsonb_build_array(p) end) loop
    st := coalesce(r ->> 'sched_type', 'date');
    m  := date_trunc('month', (r ->> 'month')::date)::date;
    if st = 'date' and coalesce(r ->> 'sched_date', '') = '' then raise exception 'Choose the delivery date for % (or switch to Daily / Weekly).', r ->> 'part_code'; end if;
    if st = 'date' and date_trunc('month', (r ->> 'sched_date')::date)::date <> m then raise exception 'The delivery date of % is outside the month.', r ->> 'part_code'; end if;
    if st = 'weekly' and coalesce(r ->> 'sched_weekday', '') = '' then raise exception 'Choose the weekday for the weekly delivery of %.', r ->> 'part_code'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.sf_lines set price = coalesce((r ->> 'price')::numeric, price), demand_qty = coalesce((r ->> 'demand_qty')::numeric, demand_qty),
             sched_type = st, sched_date = case when st = 'date' then (r ->> 'sched_date')::date end,
             sched_weekday = case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
             remarks = r ->> 'remarks', updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid;
    else
      insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty,
                                    sched_type, sched_date, sched_weekday, remarks, updated_by)
      values (cid, m, coalesce(r ->> 'buyer_code', ''), coalesce(r ->> 'buyer_name', ''), trim(r ->> 'part_code'), coalesce(r ->> 'part_name', ''),
              coalesce((r ->> 'price')::numeric, 0), coalesce(r ->> 'currency', 'INR'), coalesce(r ->> 'uom', 'pcs'), coalesce((r ->> 'demand_qty')::numeric, 0),
              st, case when st = 'date' then (r ->> 'sched_date')::date end, case when st = 'weekly' then (r ->> 'sched_weekday')::smallint end,
              r ->> 'remarks', me)
      on conflict (customer_id, month, part_code, buyer_code) do update
        set demand_qty = excluded.demand_qty, price = excluded.price, sched_type = excluded.sched_type, sched_date = excluded.sched_date,
            sched_weekday = excluded.sched_weekday, remarks = excluded.remarks, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_lines(text, jsonb) to authenticated;

create or replace function public.kmr_sf_delete_line(p_slug text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change Sales Flow.'; end if;
  delete from console.sf_lines where id = p_id and customer_id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_sf_delete_line(text, uuid) to authenticated;

-- ---------- daily despatch: p_rows = [{line_id, day, qty, note?}]; qty 0 / empty removes the day's entry ----------
create or replace function public.kmr_sf_save_despatch(p_slug text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; q numeric; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from console.sf_lines where id = (r ->> 'line_id')::uuid and customer_id = cid) then raise exception 'Unknown plan line.'; end if;
    q := coalesce(nullif(r ->> 'qty', '')::numeric, 0);
    if q < 0 then raise exception 'Despatch quantity cannot be negative.'; end if;
    if (r ->> 'day')::date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'You cannot enter despatch for a future date.'; end if;
    if q = 0 then
      delete from console.sf_despatch where line_id = (r ->> 'line_id')::uuid and day = (r ->> 'day')::date;
    else
      insert into console.sf_despatch (line_id, customer_id, day, qty, note, updated_by)
      values ((r ->> 'line_id')::uuid, cid, (r ->> 'day')::date, q, r ->> 'note', me)
      on conflict (line_id, day) do update set qty = excluded.qty, note = excluded.note, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_despatch(text, jsonb) to authenticated;

-- ---------- the product in the Console ----------
insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('sales', 'Sales Flow', 'Monthly sales plan vs actual despatch, daily tracking and dashboards', '/it/sales.html', 'users', '1.0.0', 50)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes)
values ('sales', '1.0.0', 'Sales Flow: monthly plan from the Operations Master, delivery schedule, daily despatch, pending and dashboards')
on conflict do nothing;

-- ---------- portal: Sales Flow card, access and figures ----------
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
      or (l.product_code = 'sales'    and console.sf_member(l.customer_id, em))
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
             when 'sales'    then console.sf_member(l.customer_id, em)
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
    when 'sales'    then console.sf_member(cid, em)
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

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
  select product_ref into ref from console.licences where customer_id = c and product_code = 'sales';
  if ref is not null then
    out := out || jsonb_build_object('sales', jsonb_build_object(
      'Users', (select count(*) from console.customer_members m where m.customer_id = c and coalesce(m.roles ->> 'sales', '') <> ''),
      'Parts planned', (select count(*) from console.sf_lines where customer_id = c and month = date_trunc('month', today)::date)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;


-- =====================================================================
-- migrations/0034_sales_flow_company.sql
-- =====================================================================
-- Sales Flow 0034 — lets /it/sales.html find the signed-in person's company when it is opened without ?co=
-- (e.g. from the KMR Apps card). Needs 0033. Safe to re-run.
create or replace function public.kmr_sf_my_companies() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', c.slug, 'name', c.name) order by c.name), '[]')
    from console.customers c
   where c.slug is not null and console.sf_role(c.id) is not null
$$;
revoke all on function public.kmr_sf_my_companies() from public, anon;
grant execute on function public.kmr_sf_my_companies() to authenticated;


-- =====================================================================
-- migrations/0035_sales_flow_prices.sql
-- =====================================================================
-- Sales Flow 0035 — finds more prices in the Operations Master. Needs 0033. Safe to re-run.
-- Price for a part = the customer's rate contract for it (item = part number OR part name, spelling/spaces ignored):
--   1. the contract of that customer that is valid today, 2. else any customer contract valid today,
--   3. else the latest contract even if it has expired (marked "expired" in the picker), 4. else a price held on the part itself
--   (price / rate / selling_price / sale_price / unit_price). When nothing is found the price is 0 and can be typed in the plan.
create or replace function public.kmr_sf_parts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'part_code', p.code, 'part_name', p.name, 'drawing_no', p.data ->> 'drawing_no',
             'buyer_code', coalesce(cu.code, p.data ->> 'customer', ''), 'buyer_name', coalesce(cu.name, p.data ->> 'customer', ''),
             'price', coalesce(rc.rate, pp.rate, 0),
             'currency', coalesce(rc.currency, 'INR'), 'uom', coalesce(rc.uom, 'pcs'),
             'price_source', case when rc.rate is not null then 'rate contract ' || rc.code || case when rc.valid then '' else ' (expired)' end
                                  when pp.rate is not null then 'part master' else null end)
           order by coalesce(cu.name, p.data ->> 'customer', ''), p.code)
      from console.ops_records p
      left join lateral (
        select c.code, c.name from console.ops_records c
         where c.customer_id = p.customer_id and c.kind = 'customers'
           and (c.code = p.data ->> 'customer' or lower(trim(c.name)) = lower(trim(coalesce(p.data ->> 'customer', '')))) limit 1) cu on true
      left join lateral (
        select r.code, rr.rate, coalesce(nullif(r.data ->> 'currency', ''), 'INR') currency, coalesce(nullif(r.data ->> 'uom', ''), 'pcs') uom,
               ((coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
                and (coalesce(r.data ->> 'valid_to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date >= today)) as valid
          from console.ops_records r
          cross join lateral (select substring(replace(coalesce(r.data ->> 'rate', ''), ',', '') from '[0-9]+(\.[0-9]+)?')::numeric as rate) rr
         where r.customer_id = p.customer_id and r.kind = 'rate_contracts' and r.active and rr.rate is not null
           and coalesce(r.data ->> 'party_type', 'Customer') ilike 'customer%'
           and lower(trim(coalesce(r.data ->> 'item', ''))) in (lower(trim(p.code)), lower(trim(p.name)))
         order by (lower(trim(r.name)) = lower(trim(coalesce(cu.name, p.data ->> 'customer', '')))) desc,
                  ((coalesce(r.data ->> 'valid_from', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_from')::date <= today)
                   and (coalesce(r.data ->> 'valid_to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (r.data ->> 'valid_to')::date >= today)) desc,
                  coalesce(nullif(r.data ->> 'valid_from', ''), '0000') desc limit 1) rc on true
      left join lateral (
        select substring(replace(coalesce(nullif(p.data ->> 'price', ''), nullif(p.data ->> 'rate', ''), nullif(p.data ->> 'selling_price', ''),
                                          nullif(p.data ->> 'sale_price', ''), nullif(p.data ->> 'unit_price', ''), ''), ',', '') from '[0-9]+(\.[0-9]+)?')::numeric as rate) pp on true
     where p.customer_id = cid and p.kind = 'parts' and p.active), '[]');
end $$;
grant execute on function public.kmr_sf_parts(text) to authenticated;


-- =====================================================================
-- migrations/0036_sales_flow_loss.sql
-- =====================================================================
-- Sales Flow 0036 — Sales loss reasons (per plan line) and Action plans. Needs 0033. Safe to re-run.
--  • sf_lines gets loss_reason / loss_other ("Others" = customised typing).
--  • sf_actions = action plans: issue (loss reason), brief, immediate action, permanent action, responsibility,
--    target date, status (Opened / Under progress / Closed); optionally linked to one plan line (customer + part copied).
alter table console.sf_lines add column if not exists loss_reason text;
alter table console.sf_lines add column if not exists loss_other  text;

create table if not exists console.sf_actions (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references console.customers(id) on delete cascade,
  month            date,
  line_id          uuid references console.sf_lines(id) on delete set null,
  buyer_name       text not null default '',
  part_code        text not null default '',
  part_name        text not null default '',
  issue            text not null check (length(trim(issue)) > 0),
  issue_other      text,
  brief            text not null default '',
  immediate_action text not null default '',
  permanent_action text not null default '',
  responsible      text not null default '',
  target_date      date,
  status           text not null default 'Opened' check (status in ('Opened','Under progress','Closed')),
  closed_at        timestamptz,
  created_at       timestamptz not null default now(),
  created_by       text,
  updated_at       timestamptz not null default now(),
  updated_by       text
);
create index if not exists sf_actions_cust on console.sf_actions (customer_id, status, target_date);
alter table console.sf_actions enable row level security;
drop policy if exists sf_actions_staff on console.sf_actions;
create policy sf_actions_staff on console.sf_actions for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- reasons: p_rows = [{id, loss_reason, loss_other}]
create or replace function public.kmr_sf_save_loss(p_slug text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; rs text;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    rs := nullif(trim(coalesce(r ->> 'loss_reason', '')), '');
    if rs is not null and length(rs) > 80 then raise exception 'The reason is too long.'; end if;
    update console.sf_lines
       set loss_reason = rs,
           loss_other  = case when rs = 'Others' then left(nullif(trim(coalesce(r ->> 'loss_other', '')), ''), 120) end
     where id = (r ->> 'id')::uuid and customer_id = cid;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_loss(text, jsonb) to authenticated;

create or replace function public.kmr_sf_actions(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(a) - 'customer_id' order by (a.status = 'Closed'), a.target_date nulls last, a.created_at desc)
                     from console.sf_actions a where a.customer_id = cid), '[]');
end $$;
grant execute on function public.kmr_sf_actions(text) to authenticated;

-- p = {id?, issue, issue_other, line_id, month, buyer_name, part_code, part_name, brief, immediate_action, permanent_action,
--      responsible, target_date, status}
create or replace function public.kmr_sf_save_action(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); st text := coalesce(nullif(p ->> 'status', ''), 'Opened');
        rid uuid; old console.sf_actions; ln uuid; ln_row console.sf_lines;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  if st not in ('Opened','Under progress','Closed') then raise exception 'Status must be Opened, Under progress or Closed.'; end if;
  if length(trim(coalesce(p ->> 'issue', ''))) = 0 then raise exception 'Choose the issue.'; end if;
  if length(trim(coalesce(p ->> 'brief', ''))) = 0 then raise exception 'Write the issue brief.'; end if;
  if length(trim(coalesce(p ->> 'responsible', ''))) = 0 then raise exception 'Enter who is responsible.'; end if;
  if coalesce(p ->> 'target_date', '') = '' then raise exception 'Choose the target date.'; end if;
  ln := nullif(p ->> 'line_id', '')::uuid;
  if ln is not null then
    select * into ln_row from console.sf_lines where id = ln and customer_id = cid;
    if ln_row.id is null then ln := null; end if;
  end if;
  if nullif(p ->> 'id', '') is not null then
    select * into old from console.sf_actions where id = (p ->> 'id')::uuid and customer_id = cid;
    if old.id is null then raise exception 'Action plan not found.'; end if;
    update console.sf_actions set
        month = coalesce(ln_row.month, nullif(p ->> 'month', '')::date), line_id = ln,
        buyer_name = coalesce(ln_row.buyer_name, left(coalesce(p ->> 'buyer_name', ''), 200)),
        part_code = coalesce(ln_row.part_code, left(coalesce(p ->> 'part_code', ''), 80)),
        part_name = coalesce(ln_row.part_name, left(coalesce(p ->> 'part_name', ''), 200)),
        issue = left(trim(p ->> 'issue'), 80), issue_other = case when trim(p ->> 'issue') = 'Others' then left(nullif(trim(coalesce(p ->> 'issue_other', '')), ''), 120) end,
        brief = left(trim(p ->> 'brief'), 4000), immediate_action = left(trim(coalesce(p ->> 'immediate_action', '')), 4000),
        permanent_action = left(trim(coalesce(p ->> 'permanent_action', '')), 4000), responsible = left(trim(p ->> 'responsible'), 120),
        target_date = (p ->> 'target_date')::date, status = st,
        closed_at = case when st = 'Closed' then coalesce(old.closed_at, now()) else null end, updated_at = now(), updated_by = me
      where id = old.id;
    rid := old.id;
  else
    insert into console.sf_actions (customer_id, month, line_id, buyer_name, part_code, part_name, issue, issue_other, brief, immediate_action,
                                    permanent_action, responsible, target_date, status, closed_at, created_by, updated_by)
    values (cid, coalesce(ln_row.month, nullif(p ->> 'month', '')::date), ln, coalesce(ln_row.buyer_name, left(coalesce(p ->> 'buyer_name', ''), 200)),
            coalesce(ln_row.part_code, left(coalesce(p ->> 'part_code', ''), 80)), coalesce(ln_row.part_name, left(coalesce(p ->> 'part_name', ''), 200)),
            left(trim(p ->> 'issue'), 80), case when trim(p ->> 'issue') = 'Others' then left(nullif(trim(coalesce(p ->> 'issue_other', '')), ''), 120) end,
            left(trim(p ->> 'brief'), 4000), left(trim(coalesce(p ->> 'immediate_action', '')), 4000), left(trim(coalesce(p ->> 'permanent_action', '')), 4000),
            left(trim(p ->> 'responsible'), 120), (p ->> 'target_date')::date, st, case when st = 'Closed' then now() end, me, me)
    returning id into rid;
  end if;
  return jsonb_build_object('id', rid);
end $$;
grant execute on function public.kmr_sf_save_action(text, jsonb) to authenticated;

create or replace function public.kmr_sf_delete_action(p_slug text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change Sales Flow.'; end if;
  delete from console.sf_actions where id = p_id and customer_id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_sf_delete_action(text, uuid) to authenticated;


-- =====================================================================
-- migrations/0037_calibration.sql
-- =====================================================================
-- Calibration Hub 0037 (lean first version): instrument register, calibration records, gauge history, out-of-tolerance cases.
-- Needs 0011, 0033. Licence product "calib" (one per customer company); roles via Users & access: admin / editor / viewer. Safe to re-run.
create table if not exists console.cal_instruments (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  tag text not null, name text not null, itype text, make text, model text, serial_no text, range_text text, least_count text,
  location text, department text, custodian text, criticality text not null default 'Major', cal_source text not null default 'External', lab text,
  freq_months int not null default 12 check (freq_months > 0), tolerance text, status text not null default 'In use', last_cal date, next_due date, notes text,
  created_at timestamptz not null default now(), unique (customer_id, tag));
create table if not exists console.cal_records (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, cal_date date not null, next_due date, kind text, lab text, accreditation text,
  cert_no text, as_found_ok boolean, result text not null default 'Pass', max_error text, uncertainty text, temp_c numeric, humidity numeric, calibrator text,
  reviewed_by text, reviewed_at timestamptz, remarks text, created_by text, created_at timestamptz not null default now());
create table if not exists console.cal_events (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, ev_date date not null default current_date, ev_type text not null, detail text, by_email text,
  created_at timestamptz not null default now());
create table if not exists console.cal_oot (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, record_id uuid, opened_at date not null default current_date, summary text,
  last_good date, risk text, notify text, action text, status text not null default 'Open', closed_at date);
do $$ declare t text; begin foreach t in array array['cal_instruments','cal_records','cal_events','cal_oot'] loop
  execute format('alter table console.%I enable row level security', t);
  execute format('drop policy if exists %I on console.%I', t || '_staff', t);
  execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
end loop; end $$;

create or replace function console.cal_member(p_customer uuid, p_email text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.customer_members m where m.customer_id = p_customer and m.email = lower(p_email) and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')) $$;
create or replace function console.cal_role(p_customer uuid) returns text language sql stable security definer set search_path = console, public as $$
  select case when not coalesce((select ok from console.access_state('calib', p_customer)), false) then null
    when console.is_customer_admin(p_customer) then 'admin'
    else (select nullif(m.roles ->> 'calib', '') from console.customer_members m where m.customer_id = p_customer and m.email = lower(coalesce(auth.jwt() ->> 'email', ''))) end $$;

create or replace function public.kmr_cal_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.cal_role(c.id) is null then null else jsonb_build_object('role', console.cal_role(c.id), 'company', c.name) end from console.customers c where c.slug = lower(p_slug) $$;
create or replace function public.kmr_cal_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return jsonb_build_object(
    'instruments', coalesce((select jsonb_agg(to_jsonb(i) - 'customer_id' order by i.tag) from console.cal_instruments i where i.customer_id = cid), '[]'),
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.ev_date desc, e.created_at desc) from console.cal_events e where e.customer_id = cid), '[]'),
    'oot', coalesce((select jsonb_agg(to_jsonb(o) - 'customer_id' order by o.opened_at desc) from console.cal_oot o where o.customer_id = cid), '[]'));
end $$;
create or replace function console.cal_edit(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.cal_role(cid), '') not in ('admin','editor') then raise exception 'You can view Calibration Hub but not change it. Ask your administrator for editor access.'; end if;
  return cid;
end $$;
-- instrument: p = {id?, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, status, notes}
create or replace function public.kmr_cal_save_instrument(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if length(trim(coalesce(p ->> 'tag', ''))) = 0 or length(trim(coalesce(p ->> 'name', ''))) = 0 then raise exception 'Tag / ID and description are required.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_instruments set tag = trim(p ->> 'tag'), name = trim(p ->> 'name'), itype = p ->> 'itype', make = p ->> 'make', model = p ->> 'model', serial_no = p ->> 'serial_no',
      range_text = p ->> 'range_text', least_count = p ->> 'least_count', location = p ->> 'location', department = p ->> 'department', custodian = p ->> 'custodian',
      criticality = coalesce(nullif(p ->> 'criticality', ''), 'Major'), cal_source = coalesce(nullif(p ->> 'cal_source', ''), 'External'), lab = p ->> 'lab',
      freq_months = coalesce(nullif(p ->> 'freq_months', '')::int, 12), tolerance = p ->> 'tolerance', status = coalesce(nullif(p ->> 'status', ''), 'In use'), notes = p ->> 'notes'
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, notes)
    values (cid, trim(p ->> 'tag'), trim(p ->> 'name'), p ->> 'itype', p ->> 'make', p ->> 'model', p ->> 'serial_no', p ->> 'range_text', p ->> 'least_count', p ->> 'location', p ->> 'department',
      p ->> 'custodian', coalesce(nullif(p ->> 'criticality', ''), 'Major'), coalesce(nullif(p ->> 'cal_source', ''), 'External'), p ->> 'lab', coalesce(nullif(p ->> 'freq_months', '')::int, 12), p ->> 'tolerance', p ->> 'notes')
    returning id into rid;
  end if;
  return rid;
exception when unique_violation then raise exception 'An instrument with this tag / ID already exists.';
end $$;
-- calibration: p = {instrument_id, cal_date, next_due?, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks}
-- An as-found reading out of tolerance (as_found_ok = false) opens an out-of-tolerance case automatically.
create or replace function public.kmr_cal_save_record(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); i console.cal_instruments; rid uuid; nd date; me text := lower(coalesce(auth.jwt() ->> 'email', '')); lg date;
begin
  select * into i from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid;
  if i.id is null then raise exception 'Unknown instrument.'; end if;
  if coalesce(p ->> 'cal_date', '') = '' then raise exception 'Choose the calibration date.'; end if;
  nd := coalesce(nullif(p ->> 'next_due', '')::date, (p ->> 'cal_date')::date + (i.freq_months || ' months')::interval);
  select max(cal_date) into lg from console.cal_records where instrument_id = i.id and as_found_ok is not false and result = 'Pass';
  insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, remarks, created_by)
  values (cid, i.id, (p ->> 'cal_date')::date, nd, coalesce(p ->> 'kind', i.cal_source), p ->> 'lab', p ->> 'accreditation', p ->> 'cert_no', (nullif(p ->> 'as_found_ok', ''))::boolean,
    coalesce(nullif(p ->> 'result', ''), 'Pass'), p ->> 'max_error', p ->> 'uncertainty', nullif(p ->> 'temp_c', '')::numeric, nullif(p ->> 'humidity', '')::numeric, p ->> 'calibrator', p ->> 'remarks', me)
  returning id into rid;
  if coalesce(p ->> 'result', 'Pass') = 'Fail' then
    update console.cal_instruments set status = 'Quarantine' where id = i.id;
  else
    update console.cal_instruments set last_cal = (p ->> 'cal_date')::date, next_due = nd, status = case when status in ('Quarantine','Out of service') then 'In use' else status end where id = i.id;
  end if;
  if (p ->> 'as_found_ok') = 'false' then
    insert into console.cal_oot (customer_id, instrument_id, record_id, summary, last_good, risk, status)
    values (cid, i.id, rid, 'As-found out of tolerance at calibration on ' || (p ->> 'cal_date') || coalesce(' (max error ' || (p ->> 'max_error') || ')', ''), lg, 'High', 'Open');
  end if;
  return rid;
end $$;
-- history event: p = {instrument_id, ev_type, detail}; a damage report quarantines the instrument
create or replace function public.kmr_cal_event(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  insert into console.cal_events (customer_id, instrument_id, ev_type, detail, by_email) values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'ev_type', 'Note'), p ->> 'detail', me);
  if p ->> 'ev_type' = 'Damage report' then update console.cal_instruments set status = 'Quarantine' where id = (p ->> 'instrument_id')::uuid; end if;
  if p ->> 'ev_type' = 'Status change' and p ->> 'new_status' is not null then update console.cal_instruments set status = p ->> 'new_status' where id = (p ->> 'instrument_id')::uuid; end if;
  return 'ok';
end $$;
create or replace function public.kmr_cal_close_oot(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin
  update console.cal_oot set risk = coalesce(p ->> 'risk', risk), notify = p ->> 'notify', action = p ->> 'action', status = coalesce(p ->> 'status', status),
    closed_at = case when p ->> 'status' = 'Closed' then current_date end where id = p_id and customer_id = cid;
  return 'ok';
end $$;
do $$ declare f text; begin foreach f in array array['kmr_cal_context(text)','kmr_cal_load(text)','kmr_cal_save_instrument(text,jsonb)','kmr_cal_save_record(text,jsonb)','kmr_cal_event(text,jsonb)','kmr_cal_close_oot(text,uuid,jsonb)'] loop
  execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order)
values ('calib', 'Calibration Hub', 'Instrument register, calibration due control, gauge history, out-of-tolerance cases, standards alignment', '/it/calibration.html', 'users', '1.0.0', 60)
on conflict (code) do nothing;
insert into console.releases (product_code, version, notes) values ('calib', '1.0.0', 'Calibration Hub: instrument register, calibration records, gauge history card, OOT cases, standards alignment') on conflict do nothing;

-- ---------- portal: Sales Flow + Calibration Hub cards, access and figures ----------
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
      or (l.product_code = 'sales'    and console.sf_member(l.customer_id, em))
      or (l.product_code = 'calib'    and console.cal_member(l.customer_id, em))
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
             when 'sales'    then console.sf_member(l.customer_id, em)
             when 'calib'    then console.cal_member(l.customer_id, em)
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
    when 'sales'    then console.sf_member(cid, em)
    when 'calib'    then console.cal_member(cid, em)
    when 'hrm'      then exists (select 1 from hrm.app_users u join console.licences l on l.product_ref = u.tenant_id and l.product_code = 'hrm' where l.customer_id = cid and u.id = auth.uid() and u.active)
    else false end;
  if not ok then
    raise exception 'You have not been given access to this app. Your company administrator can add it under KMR Apps › Administration › Users & access.';
  end if;
  return 'ok';
end $$;
revoke all on function public.kmr_portal_join(text, text) from public, anon;
grant execute on function public.kmr_portal_join(text, text) to authenticated;

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
  select product_ref into ref from console.licences where customer_id = c and product_code = 'sales';
  if ref is not null then
    out := out || jsonb_build_object('sales', jsonb_build_object(
      'Users', (select count(*) from console.customer_members m where m.customer_id = c and coalesce(m.roles ->> 'sales', '') <> ''),
      'Parts planned', (select count(*) from console.sf_lines where customer_id = c and month = date_trunc('month', today)::date)));
  end if;
  select product_ref into ref from console.licences where customer_id = c and product_code = 'calib';
  if ref is not null then
    out := out || jsonb_build_object('calib', jsonb_build_object(
      'Instruments', (select count(*) from console.cal_instruments where customer_id = c and status = 'In use'),
      'Overdue', (select count(*) from console.cal_instruments where customer_id = c and status = 'In use' and next_due < (now() at time zone 'Asia/Kolkata')::date)));
  end if;
  return out;
end $$;
revoke all on function public.kmr_portal_stats(text) from public, anon;
grant execute on function public.kmr_portal_stats(text) to authenticated;


-- =====================================================================
-- migrations/0038_calibration_import.sql
-- =====================================================================
-- Calibration Hub 0038 — bulk import of an existing gauge register (upsert by tag). Needs 0037. Safe to re-run.
-- p_rows = [{tag, name, itype, make, model, serial_no, range_text, least_count, tolerance, department, location, custodian, criticality, cal_source, lab, freq_months, last_cal, next_due}]
create or replace function public.kmr_cal_import(p_slug text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); r jsonb; ins int := 0; upd int := 0; fm int; lc date; nd date; ex uuid;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when length(trim(coalesce(r ->> 'tag', ''))) = 0 or length(trim(coalesce(r ->> 'name', ''))) = 0;
    fm := coalesce(nullif(r ->> 'freq_months', '')::int, 12); lc := nullif(r ->> 'last_cal', '')::date;
    nd := coalesce(nullif(r ->> 'next_due', '')::date, case when lc is not null then lc + (fm || ' months')::interval end);
    select id into ex from console.cal_instruments where customer_id = cid and tag = trim(r ->> 'tag');
    if ex is null then
      insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, tolerance, department, location, custodian, criticality, cal_source, lab, freq_months, last_cal, next_due)
      values (cid, trim(r ->> 'tag'), trim(r ->> 'name'), r ->> 'itype', r ->> 'make', r ->> 'model', r ->> 'serial_no', r ->> 'range_text', r ->> 'least_count', r ->> 'tolerance', r ->> 'department', r ->> 'location',
              r ->> 'custodian', coalesce(nullif(r ->> 'criticality', ''), 'Major'), coalesce(nullif(r ->> 'cal_source', ''), 'External'), r ->> 'lab', fm, lc, nd);
      ins := ins + 1;
    else
      update console.cal_instruments set name = trim(r ->> 'name'), itype = coalesce(r ->> 'itype', itype), make = coalesce(r ->> 'make', make), model = coalesce(r ->> 'model', model), serial_no = coalesce(r ->> 'serial_no', serial_no),
        range_text = coalesce(r ->> 'range_text', range_text), least_count = coalesce(r ->> 'least_count', least_count), tolerance = coalesce(r ->> 'tolerance', tolerance), department = coalesce(r ->> 'department', department),
        location = coalesce(r ->> 'location', location), custodian = coalesce(r ->> 'custodian', custodian), lab = coalesce(r ->> 'lab', lab), freq_months = fm, last_cal = coalesce(lc, last_cal), next_due = coalesce(nd, next_due)
       where id = ex;
      upd := upd + 1;
    end if;
  end loop;
  return jsonb_build_object('inserted', ins, 'updated', upd);
end $$;
grant execute on function public.kmr_cal_import(text, jsonb) to authenticated;


-- =====================================================================
-- migrations/0039_calibration_msa.sql
-- =====================================================================
-- Calibration Hub 0039 — MSA studies (Gage R&R, average & range method; computed in the app, stored with the data). Needs 0037. Safe to re-run.
create table if not exists console.cal_msa (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade, study_type text not null default 'GRR',
  characteristic text, study_date date not null default current_date, tolerance numeric, appraisers int, parts int, trials int,
  data jsonb, results jsonb, decision text, performed_by text, created_at timestamptz not null default now());
alter table console.cal_msa enable row level security;
drop policy if exists cal_msa_staff on console.cal_msa;
create policy cal_msa_staff on console.cal_msa for all to authenticated using (console.is_staff()) with check (console.is_staff());
create or replace function public.kmr_cal_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return jsonb_build_object(
    'instruments', coalesce((select jsonb_agg(to_jsonb(i) - 'customer_id' order by i.tag) from console.cal_instruments i where i.customer_id = cid), '[]'),
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.cal_date desc) from console.cal_records r where r.customer_id = cid), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.ev_date desc, e.created_at desc) from console.cal_events e where e.customer_id = cid), '[]'),
    'oot', coalesce((select jsonb_agg(to_jsonb(o) - 'customer_id' order by o.opened_at desc) from console.cal_oot o where o.customer_id = cid), '[]'),
    'msa', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.study_date desc) from console.cal_msa s where s.customer_id = cid), '[]'));
end $$;

create or replace function public.kmr_cal_save_msa(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, data, results, decision, performed_by)
  values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'study_type', 'GRR'), p ->> 'characteristic', coalesce(nullif(p ->> 'study_date', '')::date, current_date), nullif(p ->> 'tolerance', '')::numeric,
          (p ->> 'appraisers')::int, (p ->> 'parts')::int, (p ->> 'trials')::int, p -> 'data', p -> 'results', p ->> 'decision', lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into rid;
  return rid;
end $$;
create or replace function public.kmr_cal_delete_msa(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_msa where id = p_id and customer_id = cid; return 'ok'; end $$;
grant execute on function public.kmr_cal_load(text) to authenticated;
grant execute on function public.kmr_cal_save_msa(text, jsonb) to authenticated;
grant execute on function public.kmr_cal_delete_msa(text, uuid) to authenticated;


-- =====================================================================
-- migrations/0040_calibration_ops_gauges.sql
-- =====================================================================
-- Calibration Hub 0040 — instruments saved with last calibration / next due (auto-calculated from the frequency), and gauges read from the Operations Master. Needs 0037, 0015. Safe to re-run.
create or replace function public.kmr_cal_save_instrument(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if length(trim(coalesce(p ->> 'tag', ''))) = 0 or length(trim(coalesce(p ->> 'name', ''))) = 0 then raise exception 'Tag / ID and description are required.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_instruments set tag = trim(p ->> 'tag'), name = trim(p ->> 'name'), itype = p ->> 'itype', make = p ->> 'make', model = p ->> 'model', serial_no = p ->> 'serial_no',
      range_text = p ->> 'range_text', least_count = p ->> 'least_count', location = p ->> 'location', department = p ->> 'department', custodian = p ->> 'custodian',
      criticality = coalesce(nullif(p ->> 'criticality', ''), 'Major'), cal_source = coalesce(nullif(p ->> 'cal_source', ''), 'External'), lab = p ->> 'lab',
      freq_months = coalesce(nullif(p ->> 'freq_months', '')::int, 12), tolerance = p ->> 'tolerance', status = coalesce(nullif(p ->> 'status', ''), 'In use'), notes = p ->> 'notes',
      last_cal = nullif(p ->> 'last_cal', '')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end)
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian, criticality, cal_source, lab, freq_months, tolerance, notes, last_cal, next_due)
    values (cid, trim(p ->> 'tag'), trim(p ->> 'name'), p ->> 'itype', p ->> 'make', p ->> 'model', p ->> 'serial_no', p ->> 'range_text', p ->> 'least_count', p ->> 'location', p ->> 'department',
      p ->> 'custodian', coalesce(nullif(p ->> 'criticality', ''), 'Major'), coalesce(nullif(p ->> 'cal_source', ''), 'External'), p ->> 'lab', coalesce(nullif(p ->> 'freq_months', '')::int, 12), p ->> 'tolerance', p ->> 'notes', nullif(p ->> 'last_cal', '')::date,
      coalesce(nullif(p ->> 'next_due', '')::date, case when nullif(p ->> 'last_cal', '') is not null then (p ->> 'last_cal')::date + (coalesce(nullif(p ->> 'freq_months', '')::int, 12) || ' months')::interval end))
    returning id into rid;
  end if;
  return rid;
exception when unique_violation then raise exception 'An instrument with this tag / ID already exists.';
end $$;

create or replace function public.kmr_cal_ops_gauges(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('tag', g.code, 'name', g.name, 'itype', g.data ->> 'type', 'make', g.data ->> 'make', 'range_text', g.data ->> 'range', 'least_count', g.data ->> 'least_count',
      'location', g.data ->> 'location', 'department', g.data ->> 'department', 'freq_months', nullif(substring(coalesce(g.data ->> 'cal_freq_months', '') from '[0-9]+'), '')::int,
      'last_cal', case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'last_calibrated', 10) end,
      'next_due', case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'next_due', 10) end,
      'added', exists (select 1 from console.cal_instruments i where i.customer_id = cid and i.tag = g.code)) order by g.code)
    from console.ops_records g where g.customer_id = cid and g.kind = 'gauges' and g.active), '[]');
end $$;
grant execute on function public.kmr_cal_save_instrument(text, jsonb) to authenticated;
grant execute on function public.kmr_cal_ops_gauges(text) to authenticated;


-- =====================================================================
-- migrations/0041_calibration_ops_location.sql
-- =====================================================================
-- Calibration Hub 0041 — gauge location from the Operations Master: a machine code (shown as "code · machine name") or "Gauge room · room no."
-- Operations Master › Gauges fields read: code, name, type, make, model, serial_no, range, least_count, tolerance, location (machine code or "Gauge room"),
-- gauge_room_no (only when location = Gauge room), cal_freq_months, last_calibrated, next_due, department, criticality, lab, custodian. Needs 0040. Safe to re-run.
create or replace function public.kmr_cal_ops_gauges(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('tag', g.code, 'name', g.name, 'itype', g.data ->> 'type', 'make', g.data ->> 'make', 'range_text', g.data ->> 'range', 'least_count', g.data ->> 'least_count',
      'location', case when lower(coalesce(g.data ->> 'location', '')) like 'gauge room%' then 'Gauge room' || coalesce(' · ' || nullif(trim(g.data ->> 'gauge_room_no'), ''), '')
                       else coalesce((select m.code || ' · ' || m.name from console.ops_records m where m.customer_id = cid and m.kind = 'machines' and m.code = g.data ->> 'location' limit 1), g.data ->> 'location') end,
      'department', g.data ->> 'department', 'model', g.data ->> 'model', 'serial_no', g.data ->> 'serial_no', 'tolerance', g.data ->> 'tolerance', 'criticality', g.data ->> 'criticality', 'lab', g.data ->> 'lab', 'custodian', g.data ->> 'custodian', 'cal_source', g.data ->> 'cal_source', 'freq_months', nullif(substring(coalesce(g.data ->> 'cal_freq_months', '') from '[0-9]+'), '')::int,
      'last_cal', case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'last_calibrated', 10) end,
      'next_due', case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}' then left(g.data ->> 'next_due', 10) end,
      'added', exists (select 1 from console.cal_instruments i where i.customer_id = cid and i.tag = g.code)) order by g.code)
    from console.ops_records g where g.customer_id = cid and g.kind = 'gauges' and g.active), '[]');
end $$;
grant execute on function public.kmr_cal_ops_gauges(text) to authenticated;


-- =====================================================================
-- migrations/0042_calibration_crud.sql
-- =====================================================================
-- Calibration Hub 0042 — control plan picker for MSA, machine list, and edit / delete on every screen. Needs 0037, 0039. Safe to re-run.
create or replace function console.cal_refresh(p_inst uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare r record;
begin
  select cal_date, next_due into r from console.cal_records where instrument_id = p_inst and result = 'Pass' order by cal_date desc, created_at desc limit 1;
  update console.cal_instruments set last_cal = r.cal_date, next_due = r.next_due where id = p_inst;
end $$;

create or replace function public.kmr_cal_control_plan(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; org uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  select product_ref into org from console.licences where customer_id = cid and product_code = 'pd' limit 1;
  if org is null then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('project_id', p.id, 'part_no', p.part_no, 'part_name', p.part_name, 'rev', p.rev,
      'rows', coalesce((select jsonb_agg(jsonb_build_object('char_no', r ->> 'charNo', 'op_no', r ->> 'opNo', 'char', coalesce(nullif(r ->> 'product', ''), nullif(r ->> 'process', '')),
                                                           'spec', r ->> 'spec', 'tech', r ->> 'tech', 'cls', r ->> 'cls'))
                          from jsonb_array_elements(coalesce(p.doc #> '{docs,cp,rows}', '[]'::jsonb)) r
                         where coalesce(nullif(r ->> 'product', ''), nullif(r ->> 'process', '')) is not null), '[]')) order by p.part_no)
                     from public.pd_projects p where p.org_id = org), '[]');
end $$;

create or replace function public.kmr_cal_ops_machines(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', m.code, 'name', m.name) order by m.code) from console.ops_records m where m.customer_id = cid and m.kind = 'machines' and m.active), '[]');
end $$;

create or replace function public.kmr_cal_delete_instrument(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_instruments where id = p_id and customer_id = cid; return 'ok'; end $$;

create or replace function public.kmr_cal_update_record(p_slug text, p_id uuid, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); iid uuid;
begin
  update console.cal_records set cal_date = (p ->> 'cal_date')::date, next_due = coalesce(nullif(p ->> 'next_due', '')::date, next_due), kind = p ->> 'kind', lab = p ->> 'lab', accreditation = p ->> 'accreditation',
    cert_no = p ->> 'cert_no', as_found_ok = (nullif(p ->> 'as_found_ok', ''))::boolean, result = coalesce(nullif(p ->> 'result', ''), 'Pass'), max_error = p ->> 'max_error', uncertainty = p ->> 'uncertainty',
    temp_c = nullif(p ->> 'temp_c', '')::numeric, humidity = nullif(p ->> 'humidity', '')::numeric, calibrator = p ->> 'calibrator', remarks = p ->> 'remarks'
   where id = p_id and customer_id = cid returning instrument_id into iid;
  if iid is not null then perform console.cal_refresh(iid); end if;
  return 'ok';
end $$;
create or replace function public.kmr_cal_delete_record(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); iid uuid;
begin delete from console.cal_records where id = p_id and customer_id = cid returning instrument_id into iid; if iid is not null then perform console.cal_refresh(iid); end if; return 'ok'; end $$;
create or replace function public.kmr_cal_delete_oot(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_oot where id = p_id and customer_id = cid; return 'ok'; end $$;
create or replace function public.kmr_cal_delete_event(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug);
begin delete from console.cal_events where id = p_id and customer_id = cid; return 'ok'; end $$;

-- MSA: save now also updates an existing study (p.id)
create or replace function public.kmr_cal_save_msa(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid;
begin
  if not exists (select 1 from console.cal_instruments where id = (p ->> 'instrument_id')::uuid and customer_id = cid) then raise exception 'Unknown instrument.'; end if;
  if nullif(p ->> 'id', '') is not null then
    update console.cal_msa set instrument_id = (p ->> 'instrument_id')::uuid, characteristic = p ->> 'characteristic', study_date = coalesce(nullif(p ->> 'study_date', '')::date, study_date), tolerance = nullif(p ->> 'tolerance', '')::numeric,
      appraisers = (p ->> 'appraisers')::int, parts = (p ->> 'parts')::int, trials = (p ->> 'trials')::int, data = p -> 'data', results = p -> 'results', decision = p ->> 'decision'
     where id = (p ->> 'id')::uuid and customer_id = cid returning id into rid;
  else
    insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, data, results, decision, performed_by)
    values (cid, (p ->> 'instrument_id')::uuid, coalesce(p ->> 'study_type', 'GRR'), p ->> 'characteristic', coalesce(nullif(p ->> 'study_date', '')::date, current_date), nullif(p ->> 'tolerance', '')::numeric,
            (p ->> 'appraisers')::int, (p ->> 'parts')::int, (p ->> 'trials')::int, p -> 'data', p -> 'results', p ->> 'decision', lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into rid;
  end if;
  return rid;
end $$;
do $$ declare f text; begin foreach f in array array['kmr_cal_control_plan(text)','kmr_cal_ops_machines(text)','kmr_cal_delete_instrument(text,uuid)','kmr_cal_update_record(text,uuid,jsonb)','kmr_cal_delete_record(text,uuid)','kmr_cal_delete_oot(text,uuid)','kmr_cal_delete_event(text,uuid)','kmr_cal_save_msa(text,jsonb)'] loop
  execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;


-- =====================================================================
-- migrations/0043_sales_calib_masters.sql
-- =====================================================================
-- =====================================================================
-- 0043 — Sales Flow + Calibration Hub join the Data Master, the Grand Master and the sample-data flow.
-- Needs 0031 (sample flow), 0036 (Sales Flow actions), 0039 (Calibration MSA), 0042. Safe to re-run.
--
--  • Sample data, linked to the Operations Master sample (KMR Apps › Grand Master › Sample Data Master › Load):
--      Sales Flow       — last month and this month: one plan line per sample part (customer + price from the
--                         customer's sample rate contract), daily despatch up to yesterday, loss reasons on the
--                         lines that fell short, three action plans.
--      Calibration Hub  — one instrument per Operations Master sample gauge (same ID, location, frequency and dates),
--                         two calibration records each, one damage event, one open out-of-tolerance case, one MSA study.
--    Sample rows carry sample = true; "Flush sample data" removes only them. Real data is never touched.
--  • Data Master (per app): record counts, JSON download, JSON upload (restore) and flush for Sales Flow and
--    Calibration Hub, exactly like the other apps.
--  • Grand Master: real-data counts / download / upload / flush and sample counts include both apps.
-- =====================================================================
do $$ begin
  if to_regclass('console.sf_actions') is null then raise exception 'Run 0036_sales_flow_loss.sql first.'; end if;
  if to_regclass('console.cal_msa') is null then raise exception 'Run 0039_calibration_msa.sql first.'; end if;
  if to_regprocedure('public.kmr_grand_sample(text,text)') is null then raise exception 'Run 0031_sample_flow.sql first.'; end if;
end $$;

alter table console.sf_lines        add column if not exists sample boolean not null default false;
alter table console.sf_actions      add column if not exists sample boolean not null default false;
alter table console.cal_instruments add column if not exists sample boolean not null default false;

-- the tables of each app, parents first (restore order); children of a sample parent are sample too
create or replace function console.app2_tables(p_app text) returns text[] language sql immutable as $$
  select case p_app when 'sales' then array['sf_lines','sf_despatch','sf_actions']
                    when 'calib' then array['cal_instruments','cal_records','cal_events','cal_oot','cal_msa'] end
$$;

-- does the customer have the app (any licence, sample mode included)?
create or replace function console.has_app(p_cid uuid, p_app text) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.licences where customer_id = p_cid and product_code = p_app)
$$;
revoke all on function console.has_app(uuid, text), console.app2_tables(text) from public, anon, authenticated;

-- ---------- Sales Flow sample ----------
create or replace function console.sf_sample(p_cid uuid, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  m date; p record; lid uuid; n int := 0; k int := 0; d date; days int; per numeric; f numeric; got numeric; reasons text[] :=
    array['Raw Material Issue','Machine Break Down','Customer No Pull','Manpower Absenteeism','Inspection Delay','Lack of Tool'];
begin
  if p_action = 'flush' then
    delete from console.sf_actions where customer_id = p_cid and sample;
    delete from console.sf_lines where customer_id = p_cid and sample; get diagnostics n = row_count;
    return n;
  end if;
  if exists (select 1 from console.sf_lines where customer_id = p_cid and sample) then return 0; end if;
  foreach m in array array[(date_trunc('month', today) - interval '1 month')::date, date_trunc('month', today)::date] loop
    k := 0;
    for p in
      select pr.code, pr.name, coalesce(pr.data ->> 'customer', '') buyer, coalesce(cu.name, '') buyer_name,
             coalesce(nullif(rc.data ->> 'rate', '')::numeric, 0) rate, coalesce(rc.data ->> 'currency', 'INR') cur, coalesce(rc.data ->> 'uom', 'pcs') uom
        from console.ops_records pr
        left join console.ops_records cu on cu.customer_id = pr.customer_id and cu.kind = 'customers' and cu.code = pr.data ->> 'customer'
        left join lateral (select r.data from console.ops_records r where r.customer_id = pr.customer_id and r.kind = 'rate_contracts'
                             and r.data ->> 'party_type' = 'Customer' and r.data ->> 'item' = pr.code and coalesce(r.data ->> 'rate', '') ~ '^[0-9.]+$'
                           order by r.sample desc limit 1) rc on true
       where pr.customer_id = p_cid and pr.kind = 'parts' and pr.sample and pr.active
       order by pr.code
    loop
      k := k + 1;
      insert into console.sf_lines (customer_id, month, buyer_code, buyer_name, part_code, part_name, price, currency, uom, demand_qty,
                                    sched_type, sched_date, sched_weekday, remarks, updated_by, sample)
      values (p_cid, m, p.buyer, p.buyer_name, p.code, p.name, p.rate, p.cur, p.uom, 300 + (k * 137 % 9) * 100,
              (array['daily','weekly','date'])[1 + k % 3],
              case when k % 3 = 2 then m + 19 end, case when k % 3 = 1 then 1 + k % 6 end, 'Sample plan', 'sample', true)
      on conflict (customer_id, month, part_code, buyer_code) do nothing
      returning id into lid;
      continue when lid is null;
      n := n + 1;
      -- despatch on working days (Mon–Sat) up to yesterday; each part runs at its own fulfilment level
      days := (select count(*) from generate_series(m, (m + interval '1 month - 1 day')::date, '1 day') x where extract(isodow from x) < 7);
      per := (300 + (k * 137 % 9) * 100)::numeric / greatest(days, 1);
      f := (array[1.05, 0.98, 0.92, 0.85, 0.74, 1.0, 0.66])[1 + k % 7];
      for d in select x::date from generate_series(m, least((m + interval '1 month - 1 day')::date, today - 1), '1 day') x where extract(isodow from x) < 7 loop
        insert into console.sf_despatch (line_id, customer_id, day, qty, updated_by)
        values (lid, p_cid, d, greatest(0, round(per * f * (0.8 + ((extract(day from d)::int * 7 + k) % 5) * 0.1))), 'sample')
        on conflict do nothing;
      end loop;
      -- a short line in a finished month gets a loss reason
      if m < date_trunc('month', today)::date and f < 0.9 then
        update console.sf_lines set loss_reason = reasons[1 + k % array_length(reasons, 1)] where id = lid;
      end if;
    end loop;
  end loop;
  -- three action plans on the short lines of last month
  insert into console.sf_actions (customer_id, month, line_id, buyer_name, part_code, part_name, issue, brief, immediate_action, permanent_action,
                                  responsible, target_date, status, created_by, updated_by, sample)
  select p_cid, l.month, l.id, l.buyer_name, l.part_code, l.part_name, l.loss_reason,
         'Despatch short of plan for ' || l.part_name || ' (sample)',
         (array['Arranged material from alternate stock','Shifted the job to a standby machine','Added an overtime shift'])[rn],
         (array['Second source approved for the bar size','Preventive maintenance plan revised','Skill matrix updated; operators cross-trained'])[rn],
         (array['Purchase head','Maintenance head','Production head'])[rn], today + (rn::int) * 7,
         (array['Opened','Under progress','Closed'])[rn], 'sample', 'sample', true
    from (select l.*, row_number() over (order by l.part_code)::int rn from console.sf_lines l
           where l.customer_id = p_cid and l.sample and l.loss_reason is not null) l
   where rn <= 3;
  return n;
end $$;
revoke all on function console.sf_sample(uuid, text) from public, anon, authenticated;

-- ---------- Calibration Hub sample ----------
create or replace function console.cal_sample(p_cid uuid, p_action text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  g record; iid uuid; n int := 0; fm int; lc date; first_id uuid; rec uuid;
begin
  if p_action = 'flush' then
    delete from console.cal_instruments where customer_id = p_cid and sample; get diagnostics n = row_count;   -- records, events, OOT and MSA follow
    return n;
  end if;
  if exists (select 1 from console.cal_instruments where customer_id = p_cid and sample) then return 0; end if;
  for g in select * from console.ops_records where customer_id = p_cid and kind = 'gauges' and sample and active order by code loop
    fm := coalesce(nullif(regexp_replace(coalesce(g.data ->> 'cal_freq_months', ''), '\D', '', 'g'), '')::int, 12);
    lc := case when coalesce(g.data ->> 'last_calibrated', '') ~ '^\d{4}-\d{2}-\d{2}$' then (g.data ->> 'last_calibrated')::date else today - 40 end;
    insert into console.cal_instruments (customer_id, tag, name, itype, make, model, serial_no, range_text, least_count, location, department, custodian,
                                         criticality, cal_source, lab, freq_months, tolerance, status, last_cal, next_due, notes, sample)
    values (p_cid, g.code, g.name, g.data ->> 'type', g.data ->> 'make', g.data ->> 'model', g.data ->> 'serial_no', g.data ->> 'range', g.data ->> 'least_count',
            coalesce(g.data ->> 'location', 'Gauge room'), coalesce(g.data ->> 'department', 'Quality'), 'QA inspector',
            case when g.data ->> 'type' in ('CMM','Bore gauge','Plug gauge') then 'Critical' else 'Major' end,
            case when g.data ->> 'type' in ('Plug gauge','Ring gauge') then 'In-house' else 'External' end, 'NABL lab (sample)',
            fm, g.data ->> 'tolerance', 'In use', lc, coalesce(case when coalesce(g.data ->> 'next_due', '') ~ '^\d{4}-\d{2}-\d{2}$' then (g.data ->> 'next_due')::date end, (lc + (fm || ' months')::interval)::date),
            'Sample instrument (from the Operations Master sample gauge)', true)
    on conflict (customer_id, tag) do nothing
    returning id into iid;
    continue when iid is null;
    n := n + 1; first_id := coalesce(first_id, iid);
    insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, accreditation, cert_no, as_found_ok, result, max_error, uncertainty, temp_c, humidity, calibrator, created_by)
    values (p_cid, iid, (lc - (fm || ' months')::interval)::date, lc, 'Periodic', 'NABL lab (sample)', 'NABL', 'CAL/' || g.code || '/1', true, 'Pass', '0.002', '0.001', 20, 50, 'Lab engineer', 'sample'),
           (p_cid, iid, lc, (lc + (fm || ' months')::interval)::date, 'Periodic', 'NABL lab (sample)', 'NABL', 'CAL/' || g.code || '/2', true, 'Pass', '0.002', '0.001', 20, 50, 'Lab engineer', 'sample');
  end loop;
  if first_id is not null then
    insert into console.cal_events (customer_id, instrument_id, ev_date, ev_type, detail, by_email)
    values (p_cid, first_id, today - 3, 'Issued', 'Issued to CNC turning cell (sample)', 'sample');
    -- one out-of-tolerance case on the second instrument
    select id into iid from console.cal_instruments where customer_id = p_cid and sample and id <> first_id order by tag limit 1;
    if iid is not null then
      insert into console.cal_records (customer_id, instrument_id, cal_date, next_due, kind, lab, cert_no, as_found_ok, result, max_error, remarks, created_by)
      values (p_cid, iid, today - 2, null, 'Unscheduled', 'NABL lab (sample)', 'CAL/OOT/1', false, 'Fail', '0.018', 'Found out of tolerance after a drop (sample)', 'sample')
      returning id into rec;
      insert into console.cal_oot (customer_id, instrument_id, record_id, opened_at, summary, last_good, risk, notify, action, status)
      values (p_cid, iid, rec, today - 2, 'As-found error 0.018 mm beyond tolerance (sample)', today - 40, 'Parts measured since the last good calibration may be affected',
              'Quality head; customer if parts were despatched', 'Recall check of lots measured since last good calibration', 'Open');
      update console.cal_instruments set status = 'Quarantine' where id = iid;
    end if;
    insert into console.cal_msa (customer_id, instrument_id, study_type, characteristic, study_date, tolerance, appraisers, parts, trials, decision, performed_by)
    values (p_cid, first_id, 'GRR', 'Ø40 +0.025/0 bore (sample)', today - 20, 0.025, 3, 10, 3, 'Acceptable', 'QA engineer');
  end if;
  return n;
end $$;
revoke all on function console.cal_sample(uuid, text) from public, anon, authenticated;

-- ---------- export / clear / restore of the two apps (real_only: the Grand Master's real-data card) ----------
create or replace function console.app2_export(p_app text, p_cid uuid, p_real_only boolean) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare t text; rows jsonb; tabs jsonb := '{}'; parent text;
begin
  foreach t in array console.app2_tables(p_app) loop
    parent := case when t in ('sf_lines','sf_actions','cal_instruments') then null when p_app = 'sales' then 'sf_lines' else 'cal_instruments' end;
    if not p_real_only then
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x where x.customer_id = $1', t) into rows using p_cid;
    elsif parent is null then
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x where x.customer_id = $1 and not x.sample', t) into rows using p_cid;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''customer_id''), ''[]'') from console.%I x join console.%I p on p.id = x.%I where x.customer_id = $1 and not p.sample',
                     t, parent, case when parent = 'sf_lines' then 'line_id' else 'instrument_id' end) into rows using p_cid;
    end if;
    tabs := tabs || jsonb_build_object(t, rows);
  end loop;
  return tabs;
end $$;

create or replace function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare n bigint := 0; k bigint;
begin
  if p_app = 'sales' then
    delete from console.sf_actions where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;
    delete from console.sf_lines where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;
  elsif p_app = 'calib' then
    delete from console.cal_instruments where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;
  end if;
  return n;
end $$;

create or replace function console.app2_restore(p_app text, p_cid uuid, p_tables jsonb, p_real_only boolean) returns bigint
language plpgsql security definer set search_path = console, public as $$
declare t text; rows jsonb; tot bigint := 0; k bigint;
begin
  perform console.app2_clear(p_app, p_cid, p_real_only);
  foreach t in array console.app2_tables(p_app) loop
    -- every row goes back into THIS company, whatever the file says; restored real data is never marked sample
    rows := (select coalesce(jsonb_agg(r || jsonb_build_object('customer_id', p_cid)
                       || case when t in ('sf_lines','sf_actions','cal_instruments') and p_real_only then '{"sample":false}'::jsonb else '{}'::jsonb end), '[]')
               from jsonb_array_elements(coalesce(p_tables -> t, '[]')) r);
    execute format('insert into console.%I select * from jsonb_populate_recordset(null::console.%I, $1) on conflict do nothing', t, t) using rows;
    get diagnostics k = row_count; tot := tot + k;
  end loop;
  return tot;
end $$;
revoke all on function console.app2_export(text, uuid, boolean), console.app2_clear(text, uuid, boolean), console.app2_restore(text, uuid, jsonb, boolean) from public, anon, authenticated;

-- =====================================================================
-- Data Master: the two apps next to the others
-- =====================================================================
create or replace function console.data_target(p_slug text, p_app text, out cid uuid, out ref uuid)
language plpgsql stable security definer set search_path = console, public as $$
begin
  select c.id into cid from console.customers c where c.slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company administrator can manage app data.'; end if;
  if p_app = 'ops' then ref := cid; return; end if;
  if p_app in ('sales','calib') then
    if not console.has_app(cid, p_app) then raise exception 'Your company does not have this app yet.'; end if;
    ref := cid; return;
  end if;
  if p_app not in ('hrm','balloon','pd','capacity') then raise exception 'Unknown app %', p_app; end if;
  select l.product_ref into ref from console.licences l where l.customer_id = cid and l.product_code = p_app and l.product_ref is not null limit 1;
  if ref is null then raise exception 'Your company does not have this app yet.'; end if;
end $$;
revoke all on function console.data_target(text, text) from public, anon, authenticated;

create or replace function public.kmr_data_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; l record; out jsonb := '[]'::jsonb; t text; n bigint; det jsonb; tot bigint; a text;
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
  foreach a in array array['sales','calib'] loop
    continue when not console.has_app(cid, a);
    det := '{}'; tot := 0;
    foreach t in array console.app2_tables(a) loop
      execute format('select count(*) from console.%I where customer_id = $1', t) into n using cid;
      det := det || jsonb_build_object(t, n); tot := tot + n;
    end loop;
    out := out || jsonb_build_array(jsonb_build_object('app', a, 'records', tot, 'detail', det));
  end loop;
  select count(*) into n from console.ops_records where customer_id = cid;
  out := out || jsonb_build_array(jsonb_build_object('app', 'ops', 'records', n, 'detail', jsonb_build_object('ops_records', n)));
  return out;
end $$;
grant execute on function public.kmr_data_overview(text) to authenticated;

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
  elsif p_app in ('sales','calib') then
    tabs := console.app2_export(p_app, tg.cid, false);
  else
    foreach t in array console.data_tables(p_app) loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x where x.org_id = $1', t) into rows using tg.ref;
      tabs := tabs || jsonb_build_object(t, rows);
    end loop;
  end if;
  return jsonb_build_object('format', 'kmr-app-data', 'version', 1, 'app', p_app, 'company', lower(p_slug), 'exported_at', now(), 'tables', tabs);
end $$;
grant execute on function public.kmr_data_export(text, text) to authenticated;

create or replace function public.kmr_data_flush(p_slug text, p_app text, p_hrm_setup boolean default false) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record;
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_app = 'hrm' then return hrm.company_flush(tg.ref, coalesce(p_hrm_setup, false)); end if;
  if p_app in ('sales','calib') then return jsonb_build_object('removed', console.app2_clear(p_app, tg.cid, false)); end if;
  return jsonb_build_object('removed', console.data_clear(p_app, tg.cid, tg.ref));
end $$;
grant execute on function public.kmr_data_flush(text, text, boolean) to authenticated;

create or replace function public.kmr_data_import(p_slug text, p_app text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare tg record; t text; rows jsonb; n bigint; k bigint; tot bigint := 0; pass int; todo text[];
begin
  select * into tg from console.data_target(p_slug, p_app);
  if p_data ->> 'format' is distinct from 'kmr-app-data' then raise exception 'This is not a KMR Data Master file.'; end if;
  if p_data ->> 'app' is distinct from p_app then raise exception 'This file is a backup of another app (%).', p_data ->> 'app'; end if;
  if p_app = 'hrm' then
    return jsonb_build_object('restored', hrm.company_import(tg.ref, p_data -> 'tables' -> 'hrm'));
  end if;
  if p_app in ('sales','calib') then
    return jsonb_build_object('restored', console.app2_restore(p_app, tg.cid, p_data -> 'tables', false));
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

-- =====================================================================
-- Grand Master
-- =====================================================================
create or replace function public.kmr_grand_sample(p_slug text, p_action text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); out jsonb := '{}'; r uuid; n int; k int; flow jsonb;
begin
  if p_action not in ('load','flush') then raise exception 'Unknown action.'; end if;
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    if p_action = 'load' then
      if exists (select 1 from hrm.employees where tenant_id = r and email like '%@demo.kmr.test') then n := 0;
      else n := hrm.demo_load(r); perform hrm.demo_payroll(r); end if;
      if to_regprocedure('hrm.demo_flow(uuid)') is not null then
        flow := hrm.demo_flow(r);
        out := out || jsonb_build_object('hrm_flow', flow);
      end if;
    else
      if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
        execute 'select count(*) from hrm.candidates where tenant_id = $1 and sample' into k using r;
        out := out || jsonb_build_object('hrm_candidates', k);
      end if;
      n := hrm.demo_flush(r);
    end if;
    out := out || jsonb_build_object('hrm', n, 'hrm_tenant', r);
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_ops_sample_drawing(p_slug, p_action));
  end if;
  if p_action = 'load' then
    -- the Operations Master first: Sales Flow and Calibration Hub are built from its sample parts, rate contracts and gauges
    out := out || jsonb_build_object('ops', (public.kmr_ops_sample_load(p_slug) ->> 'added')::int);
    if console.has_app(cid, 'sales') then out := out || jsonb_build_object('sales', console.sf_sample(cid, 'load')); end if;
    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'load')); end if;
  else
    if console.has_app(cid, 'sales') then out := out || jsonb_build_object('sales', console.sf_sample(cid, 'flush')); end if;
    if console.has_app(cid, 'calib') then out := out || jsonb_build_object('calib', console.cal_sample(cid, 'flush')); end if;
    out := out || jsonb_build_object('ops', public.kmr_ops_sample_flush(p_slug));
  end if;
  return out;
end $$;
revoke all on function public.kmr_grand_sample(text, text) from public, anon;
grant execute on function public.kmr_grand_sample(text, text) to authenticated;

create or replace function public.kmr_grand_overview(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.grand_customer(p_slug); r uuid; real_ jsonb := '{}'; smp jsonb := '{}'; t text; n bigint; k bigint; c console.customers%rowtype;
begin
  r := console.grand_ref(cid, 'hrm');
  if r is not null then
    select count(*) filter (where coalesce(email, '') not like '%@demo.kmr.test'), count(*) filter (where coalesce(email, '') like '%@demo.kmr.test')
      into n, k from hrm.employees where tenant_id = r;
    real_ := real_ || jsonb_build_object('hrm', n); smp := smp || jsonb_build_object('hrm', k);
    if exists (select 1 from information_schema.columns where table_schema = 'hrm' and table_name = 'candidates' and column_name = 'sample') then
      execute 'select count(*) filter (where not sample), count(*) filter (where sample) from hrm.candidates where tenant_id = $1' into n, k using r;
      real_ := real_ || jsonb_build_object('hrm_candidates', n); smp := smp || jsonb_build_object('hrm_candidates', k);
    end if;
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
  if console.has_app(cid, 'sales') then
    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.sf_lines where customer_id = cid;
    real_ := real_ || jsonb_build_object('sales', n); smp := smp || jsonb_build_object('sales', k);
  end if;
  if console.has_app(cid, 'calib') then
    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.cal_instruments where customer_id = cid;
    real_ := real_ || jsonb_build_object('calib', n); smp := smp || jsonb_build_object('calib', k);
  end if;
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
  foreach t in array array['sales','calib'] loop
    if console.has_app(cid, t) then apps := apps || jsonb_build_object(t, jsonb_build_object('format', 'kmr-app-real', 'tables', console.app2_export(t, cid, true))); end if;
  end loop;
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
  if r is not null then
    out := out || jsonb_build_object('hrm_candidates', console.grand_hrm_real_candidates(r));
    out := out || jsonb_build_object('hrm', hrm.real_flush(r));
  end if;
  if console.grand_ref(cid, 'balloon') is not null and to_regclass('public.bi_reports') is not null then
    out := out || jsonb_build_object('balloon', public.kmr_balloon_own_flush(p_slug));
  end if;
  foreach t in array array['pd','capacity'] loop
    r := console.grand_ref(cid, t);
    if r is not null then out := out || jsonb_build_object(t, console.data_clear(t, cid, r)); end if;
  end loop;
  -- Sales Flow / Calibration Hub: count the parent records (plan lines, instruments) removed, sample ones stay
  if console.has_app(cid, 'sales') then
    select count(*) into n from console.sf_lines where customer_id = cid and not sample;
    perform console.app2_clear('sales', cid, true); out := out || jsonb_build_object('sales', n);
  end if;
  if console.has_app(cid, 'calib') then
    select count(*) into n from console.cal_instruments where customer_id = cid and not sample;
    perform console.app2_clear('calib', cid, true); out := out || jsonb_build_object('calib', n);
  end if;
  delete from console.ops_records where customer_id = cid and not sample; get diagnostics n = row_count;
  return out || jsonb_build_object('ops', n);
end $$;
revoke all on function public.kmr_grand_real_flush(text) from public, anon;
grant execute on function public.kmr_grand_real_flush(text) to authenticated;

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
    if t = 'hrm' then
      select count(*) into n from hrm.employees where tenant_id = console.grand_ref(cid, 'hrm') and coalesce(email, '') not like '%@demo.kmr.test';
      out := out || jsonb_build_object('hrm', n, 'hrm_candidates', console.grand_hrm_real_candidates(console.grand_ref(cid, 'hrm')));
    end if;
  end loop;
  a := p_data -> 'apps' -> 'balloon';
  if a is not null and console.grand_ref(cid, 'balloon') is not null then
    perform public.kmr_balloon_own_flush(p_slug);
    if jsonb_array_length(coalesce(a -> 'tables' -> 'bi_reports', '[]')) > 0 then
      out := out || jsonb_build_object('balloon', public.kmr_balloon_own_load(p_slug, a));
    else out := out || jsonb_build_object('balloon', 0); end if;
  end if;
  -- Operations Master before Sales Flow / Calibration Hub (they point at its parts and gauges by code)
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
  foreach t in array array['sales','calib'] loop
    a := p_data -> 'apps' -> t;
    if a is null or not console.has_app(cid, t) then continue; end if;
    perform console.app2_restore(t, cid, a -> 'tables', true);
    if t = 'sales' then select count(*) into n from console.sf_lines where customer_id = cid and not sample;
    else select count(*) into n from console.cal_instruments where customer_id = cid and not sample; end if;
    out := out || jsonb_build_object(t, n);
  end loop;
  return out;
end $$;
revoke all on function public.kmr_grand_real_import(text, jsonb) from public, anon;
grant execute on function public.kmr_grand_real_import(text, jsonb) to authenticated;


-- =====================================================================
-- migrations/0044_website_apps_pricing.sql
-- =====================================================================
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
