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
