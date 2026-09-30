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
