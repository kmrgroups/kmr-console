-- =====================================================================
-- KMR DEMO DATA — for sales demos and testing. Remove it any time with DEMO_FLUSH.sql.
-- Fills an existing HRM company (created from the Console) with 24 employees, two plants,
-- 30 days of biometric punches, leave balances and pending requests; adds demo customers to the Console.
-- Everything is tagged: employees use @demo.kmr.test emails, customers have source 'KMR demo data'.
--
-- BEFORE: switch on the HRM for a customer in the Console (e.g. "Demo Engineering").
-- 1. Set demo_company below to that company's short name (the ?co= value in its sign-in link).
-- 2. SQL Editor → paste → Run. Ends with: DEMO DATA READY
-- 3. In the HRM: Attendance → Recalculate attendance → From = 30 days ago, To = today → Recalculate.
-- =====================================================================
create temp table demo_cfg as select 'demo-engineering'::text as demo_company;

do $$
declare
  t uuid; pfx text; p1 uuid; p2 uuid; d0 date := current_date - 30;
  fn text[] := array['Arun','Priya','Karthik','Divya','Suresh','Lakshmi','Rahul','Meena','Vijay','Anitha','Manoj','Kavya','Ravi','Deepa','Ganesh','Sowmya','Prakash','Nandini','Harish','Revathi','Naveen','Pooja','Senthil','Bhavya'];
  ln text[] := array['Kumar','Sharma','Raj','Nair','Reddy','Iyer','Verma','Pillai','Rao','Menon','Gowda','Das','Shetty','Patel','Murthy','Joshi','Babu','Krishnan','Hegde','Naidu','Prasad','Singh','Mani','Rangan'];
  dept text[] := array['Human Resources','Production','Production','Production','Quality','Quality','Maintenance','Stores','Production Planning & Control','Production','Production','Production','Quality','Maintenance','Production','Production','Engineering','Accounts & Finance','Purchase','Production','Production','EHS','Production','Production'];
  desig text[] := array['Manager','Supervisor','Operator','Operator','Engineer','Technician','Technician','Senior Operator','Engineer','Operator','Senior Operator','Operator','Technician','Operator','Operator','Operator','Senior Engineer','Assistant Manager','Engineer','Operator','Operator','Engineer','Operator','Operator'];
  shiftc text[] := array['G','G','A','A','G','A','B','G','G','A','B','B','C','C','A','B','G','G','G',null,null,'G',null,'C'];
  i int; e uuid; mgr uuid; sid uuid; att text; d date; st int; en int; late int; emp record;
begin
  select id, emp_code_prefix into t, pfx from hrm.tenants where slug = (select demo_company from demo_cfg);
  if t is null then raise exception 'No HRM company "%". Switch on the HRM for a customer in the Console first, and use its short name.', (select demo_company from demo_cfg); end if;
  if exists (select 1 from hrm.employees where tenant_id = t and email like '%@demo.kmr.test') then
    raise exception 'Demo data is already loaded for this company. Run DEMO_FLUSH.sql first to load it again.';
  end if;

  insert into hrm.plants (tenant_id, code, name, state) values (t, 'DP1', 'Plant 1 — Bommasandra', 'Karnataka') returning id into p1;
  insert into hrm.plants (tenant_id, code, name, state) values (t, 'DP2', 'Plant 2 — Hosur', 'Tamil Nadu') returning id into p2;

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
end $$;

-- Console: demo customers across countries and stages
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

-- Pilot requests and support tickets for the service screens
insert into console.leads (name, company, email, phone, country, products, message, source) values
  ('Mahesh Gowda', 'Tumkur Castings', 'mahesh@tumkurcast.demo.kmr.test', '+91 99000 44444', 'India', '{hrm}', '180 workmen across 2 shifts, using eSSL devices', 'website'),
  ('Elena Rossi', 'Rossi Meccanica Srl', 'elena@rossimec.demo.kmr.test', '+39 011 555 0177', 'Italy', '{balloon,pd}', 'PPAP documents for an Indian OEM customer', 'website');
do $$
declare t uuid; tk uuid;
begin
  select id into t from hrm.tenants where slug = (select demo_company from demo_cfg);
  insert into console.tickets (product_code, product_ref, raised_by_email, raised_by_name, subject, priority, status)
  values ('hrm', t, 'priya.sharma@demo.kmr.test', 'Priya Sharma', 'Night shift punches showing on the next day', 'high', 'in_progress') returning id into tk;
  insert into console.ticket_messages (ticket_id, author_kind, author_name, body, created_at) values
    (tk, 'customer', 'Priya Sharma', 'For C-shift workers the out punch at 6 AM appears as a separate day in the register.', now() - interval '26 hours'),
    (tk, 'kmr', 'KMR Support', 'Thanks Priya. Please set those employees to shift C (or leave the shift empty for auto-detection) under Employee → Attendance, then recalculate. The out punch will join the night it started.', now() - interval '20 hours');
  insert into console.tickets (product_code, product_ref, raised_by_email, raised_by_name, subject, priority)
  values ('hrm', t, 'arun.kumar@demo.kmr.test', 'Arun Kumar', 'Can we add a Saturday half-day rule?', 'low') returning id into tk;
  insert into console.ticket_messages (ticket_id, author_kind, author_name, body) values
    (tk, 'customer', 'Arun Kumar', 'Our office staff work Saturday till 1 PM. How do we set that up?');
end $$;

drop table demo_cfg;
select 'DEMO DATA READY' as result,
       (select count(*) from hrm.employees where email like '%@demo.kmr.test') as demo_employees,
       (select count(*) from hrm.attendance_punches p join hrm.employees e on e.id = p.employee_id where e.email like '%@demo.kmr.test') as demo_punches,
       (select count(*) from console.customers where source = 'KMR demo data') as demo_customers;
