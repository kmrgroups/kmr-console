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
