-- ---------- HRM & Payroll 1.1: employee mobile access, permissions, hours per day, attendance bonus, fixed pay ----------
alter table console.hrms_employees add column if not exists hours_per_day numeric(4,1) not null default 8 check (hours_per_day > 0 and hours_per_day <= 24);
alter table console.hrms_employees add column if not exists bonus_eligible boolean not null default false;
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'console.hrms_employees'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%pay_type%' loop
    execute format('alter table console.hrms_employees drop constraint %I', c.conname);
  end loop;
  alter table console.hrms_employees add constraint hrms_employees_pay_type_chk check (pay_type in ('monthly', 'daily', 'fixed'));
end $$;

-- a permission (a few hours off inside a working day) is kept next to leave
alter table console.hrms_leaves add column if not exists kind text not null default 'leave';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'hrms_leaves_kind_chk') then alter table console.hrms_leaves add constraint hrms_leaves_kind_chk check (kind in ('leave', 'permission')); end if;
end $$;
alter table console.hrms_leaves add column if not exists from_time text;
alter table console.hrms_leaves add column if not exists to_time text;
alter table console.hrms_leaves add column if not exists minutes int;

-- employee sign-in (employee ID + date of birth): short sessions, lock after 5 wrong tries
create table if not exists console.hrms_sessions (
  token_hash text primary key, customer_id uuid not null references console.customers(id) on delete cascade,
  employee_id uuid not null references console.hrms_employees(id) on delete cascade, expires_at timestamptz not null, created_at timestamptz not null default now());
create index if not exists hrms_sess_exp on console.hrms_sessions (expires_at);
create table if not exists console.hrms_login_fails (
  customer_id uuid not null references console.customers(id) on delete cascade, emp_code text not null, fails int not null default 0, first_at timestamptz not null default now(), primary key (customer_id, emp_code));
alter table console.hrms_sessions enable row level security;
alter table console.hrms_login_fails enable row level security;

create or replace function console.hrms_licence_ok(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.licences l where l.customer_id = p_cid and l.product_code = 'hrms' and l.status in ('trial', 'pilot', 'active') and (l.valid_until is null or l.valid_until >= current_date)) $$;
revoke all on function console.hrms_licence_ok(uuid) from public, anon, authenticated;

create or replace function console.hrms_ess_on(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select console.hrms_licence_ok(p_cid) and coalesce((select data ->> 'ess_enabled' from console.hrms_settings where customer_id = p_cid), 'true') <> 'false' $$;
revoke all on function console.hrms_ess_on(uuid) from public, anon, authenticated;

create or replace function console.hrms_ess_who(p_token text) returns console.hrms_sessions language plpgsql security definer set search_path = console, public as $$
declare s console.hrms_sessions;
begin
  select * into s from console.hrms_sessions where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') and expires_at > now();
  if not found or not console.hrms_ess_on(s.customer_id) or not exists (select 1 from console.hrms_employees e where e.id = s.employee_id and e.status = 'active') then raise exception 'Please sign in again.'; end if;
  return s;
end $$;
revoke all on function console.hrms_ess_who(text) from public, anon, authenticated;

create or replace function public.kmr_hrms_me_login(p_slug text, p_code text, p_dob date) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid; emp console.hrms_employees%rowtype; f console.hrms_login_fails%rowtype; tok text; code text := upper(trim(coalesce(p_code, '')));
begin
  select id into cid from console.customers where slug = lower(trim(coalesce(p_slug, '')));
  if cid is null or not console.hrms_ess_on(cid) then return jsonb_build_object('ok', false, 'error', 'This link is not active. Please ask your HR.'); end if;
  if code = '' or p_dob is null then return jsonb_build_object('ok', false, 'error', 'Enter your employee ID and date of birth.'); end if;
  select * into f from console.hrms_login_fails where customer_id = cid and emp_code = code;
  if found and f.first_at <= now() - interval '15 minutes' then delete from console.hrms_login_fails where customer_id = cid and emp_code = code; f.fails := 0; found := false; end if;
  if found and f.fails >= 5 then return jsonb_build_object('ok', false, 'error', 'Too many wrong attempts. Please try again after 15 minutes.'); end if;
  select * into emp from console.hrms_employees where customer_id = cid and upper(emp_code) = code and status = 'active' and dob is not null and dob = p_dob;
  if not found then
    insert into console.hrms_login_fails (customer_id, emp_code, fails) values (cid, code, 1) on conflict (customer_id, emp_code) do update set fails = console.hrms_login_fails.fails + 1;
    return jsonb_build_object('ok', false, 'error', 'Employee ID or date of birth is not correct.');
  end if;
  delete from console.hrms_login_fails where customer_id = cid and emp_code = code;
  delete from console.hrms_sessions where expires_at < now();
  tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into console.hrms_sessions (token_hash, customer_id, employee_id, expires_at) values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), cid, emp.id, now() + interval '12 hours');
  return jsonb_build_object('ok', true, 'token', tok, 'name', emp.name, 'company', (select name from console.customers where id = cid));
end $$;

create or replace function public.kmr_hrms_me_logout(p_token text) returns void language sql security definer set search_path = console, public as $$
  delete from console.hrms_sessions where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') $$;

-- everything the employee sees about himself for a month (the screen works out the live attendance and pay with the same rules as HR)
create or replace function public.kmr_hrms_me_data(p_token text, p_period text default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare s console.hrms_sessions := console.hrms_ess_who(p_token); e console.hrms_employees%rowtype; tz text := console.hrms_tz(s.customer_id); per text := coalesce(nullif(p_period, ''), to_char(now() at time zone console.hrms_tz(s.customer_id), 'YYYY-MM')); f date; t date; yr int;
begin
  if per !~ '^\d{4}-\d{2}$' then raise exception 'Choose the month.'; end if;
  select * into e from console.hrms_employees where id = s.employee_id;
  f := (per || '-01')::date; t := (f + interval '1 month - 1 day')::date; yr := extract(year from f)::int;
  return jsonb_build_object('period', per, 'today', (now() at time zone tz)::date, 'company', (select name from console.customers where id = s.customer_id),
    'employee', (to_jsonb(e) - 'customer_id' - 'sample' - 'notes' - 'bank_account' - 'address') || jsonb_build_object('bank_last4', right(coalesce(e.bank_account, ''), 4)),
    'settings', coalesce((select data from console.hrms_settings where customer_id = s.customer_id), '{}'),
    'shift', (select to_jsonb(x) - 'customer_id' from console.hrms_shifts x where x.id = e.shift_id),
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('hdate', h.hdate, 'name', h.name) order by h.hdate) from console.hrms_holidays h where h.customer_id = s.customer_id and extract(year from h.hdate) in (yr, yr + 1)), '[]'),
    'leave_types', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'code', x.code, 'name', x.name, 'paid', x.paid, 'annual_quota', x.annual_quota) order by x.code) from console.hrms_leave_types x where x.customer_id = s.customer_id and x.active), '[]'),
    'attendance', coalesce((select jsonb_agg((to_jsonb(a) - 'customer_id' - 'sample') order by a.work_date) from console.hrms_attendance a where a.employee_id = e.id and a.work_date between f and t), '[]'),
    'punches', coalesce((select jsonb_agg(jsonb_build_object('at', x.punched_at, 'verify', x.verify, 'direction', x.direction) order by x.punched_at) from console.hrms_punches x
        where x.customer_id = s.customer_id and (x.employee_id = e.id or (e.bio_id is not null and x.bio_id = e.bio_id)) and x.punched_at >= ((f - 1)::timestamp at time zone tz) and x.punched_at < ((t + 2)::timestamp at time zone tz)), '[]'),
    'leaves', coalesce((select jsonb_agg((to_jsonb(l) - 'customer_id' - 'sample' - 'employee_id') order by l.from_date desc, l.created_at desc) from console.hrms_leaves l where l.employee_id = e.id and (extract(year from l.from_date) = yr or extract(year from l.to_date) = yr)), '[]'),
    'payslips', coalesce((select jsonb_agg(jsonb_build_object('period', r.period, 'status', r.status, 'month_days', r.month_days, 'slip', to_jsonb(p) - 'customer_id' - 'sample' - 'run_id' - 'employee_id') order by r.period desc)
        from console.hrms_payslips p join console.hrms_payroll_runs r on r.id = p.run_id where p.employee_id = e.id and r.period >= to_char(f - interval '2 months', 'YYYY-MM') and r.period <= per), '[]'),
    'locked', coalesce((select jsonb_agg(r.period) from console.hrms_payroll_runs r where r.customer_id = s.customer_id and r.status = 'final'), '[]'));
end $$;

create or replace function public.kmr_hrms_me_leave_apply(p_token text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare s console.hrms_sessions := console.hrms_ess_who(p_token); e console.hrms_employees%rowtype; lt console.hrms_leave_types%rowtype; f date := (p ->> 'from_date')::date; t date := (p ->> 'to_date')::date; half boolean := coalesce((p ->> 'half')::boolean, false); v_id uuid; d numeric;
begin
  select * into e from console.hrms_employees where id = s.employee_id;
  select * into lt from console.hrms_leave_types where id = nullif(p ->> 'leave_type_id', '')::uuid and customer_id = s.customer_id and active; if not found then raise exception 'Choose the leave type.'; end if;
  if f is null or t is null or t < f then raise exception 'Choose the leave dates (to-date cannot be before from-date).'; end if;
  if t - f > 60 then raise exception 'Apply for at most 60 days at a time.'; end if;
  if half and f <> t then raise exception 'A half day is for one date.'; end if;
  if f < current_date - 31 then raise exception 'You can apply for leave of the last 30 days and later. Please ask your HR for older dates.'; end if;
  if console.hrms_locked(s.customer_id, f) or console.hrms_locked(s.customer_id, t) then raise exception 'The salary of that month is already finalised. Please ask your HR.'; end if;
  if exists (select 1 from console.hrms_leaves l where l.employee_id = e.id and l.kind = 'leave' and l.status in ('Pending', 'Approved') and l.from_date <= t and l.to_date >= f) then raise exception 'You already have a leave request for some of these dates.'; end if;
  d := case when half then 0.5 else (t - f + 1) end;
  insert into console.hrms_leaves (customer_id, employee_id, leave_type_id, leave_code, from_date, to_date, half, days, reason, sample, created_by, kind)
  values (s.customer_id, e.id, lt.id, lt.code, f, t, half, d, console.hrms_txt(p, 'reason'), e.sample, 'employee ' || e.emp_code, 'leave') returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.kmr_hrms_me_perm_apply(p_token text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare s console.hrms_sessions := console.hrms_ess_who(p_token); e console.hrms_employees%rowtype; d date := (p ->> 'pdate')::date; a text := console.hrms_txt(p, 'from_time'); b text := console.hrms_txt(p, 'to_time'); m int; v_id uuid;
begin
  select * into e from console.hrms_employees where id = s.employee_id;
  if d is null then raise exception 'Choose the date.'; end if;
  if a is null or b is null or a !~ '^\d{2}:\d{2}$' or b !~ '^\d{2}:\d{2}$' then raise exception 'Enter the permission time (from and to).'; end if;
  m := (split_part(b, ':', 1)::int * 60 + split_part(b, ':', 2)::int) - (split_part(a, ':', 1)::int * 60 + split_part(a, ':', 2)::int);
  if m <= 0 or m > 480 then raise exception 'The permission time must be between 1 minute and 8 hours (to-time after from-time).'; end if;
  if d < current_date - 31 then raise exception 'You can apply for permission of the last 30 days and later. Please ask your HR for older dates.'; end if;
  if console.hrms_locked(s.customer_id, d) then raise exception 'The salary of that month is already finalised. Please ask your HR.'; end if;
  insert into console.hrms_leaves (customer_id, employee_id, leave_code, from_date, to_date, half, days, reason, sample, created_by, kind, from_time, to_time, minutes)
  values (s.customer_id, e.id, 'PERM', d, d, false, 0, console.hrms_txt(p, 'reason'), e.sample, 'employee ' || e.emp_code, 'permission', a, b, m) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.kmr_hrms_me_cancel(p_token text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare s console.hrms_sessions := console.hrms_ess_who(p_token);
begin
  update console.hrms_leaves set status = 'Cancelled' where id = p_id and employee_id = s.employee_id and status = 'Pending';
  if not found then raise exception 'Only a request that is still waiting can be cancelled.'; end if;
end $$;

-- HR: a permission request typed in for an employee
create or replace function public.kmr_hrms_perm_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); v_id uuid := nullif(p ->> 'id', '')::uuid; emp console.hrms_employees%rowtype; d date := (p ->> 'pdate')::date; a text := console.hrms_txt(p, 'from_time'); b text := console.hrms_txt(p, 'to_time'); m int;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.leave');
  select * into emp from console.hrms_employees where id = (p ->> 'employee_id')::uuid and customer_id = cid; if not found then raise exception 'Choose the employee.'; end if;
  if d is null then raise exception 'Choose the date.'; end if;
  if a is null or b is null or a !~ '^\d{2}:\d{2}$' or b !~ '^\d{2}:\d{2}$' then raise exception 'Enter the permission time (from and to).'; end if;
  m := (split_part(b, ':', 1)::int * 60 + split_part(b, ':', 2)::int) - (split_part(a, ':', 1)::int * 60 + split_part(a, ':', 2)::int);
  if m <= 0 or m > 480 then raise exception 'The permission time must be between 1 minute and 8 hours (to-time after from-time).'; end if;
  if v_id is null then
    insert into console.hrms_leaves (customer_id, employee_id, leave_code, from_date, to_date, half, days, reason, sample, created_by, kind, from_time, to_time, minutes)
    values (cid, emp.id, 'PERM', d, d, false, 0, console.hrms_txt(p, 'reason'), emp.sample, lower(coalesce(auth.jwt() ->> 'email', '')), 'permission', a, b, m) returning id into v_id;
  else
    update console.hrms_leaves set employee_id = emp.id, from_date = d, to_date = d, from_time = a, to_time = b, minutes = m, reason = console.hrms_txt(p, 'reason') where id = v_id and customer_id = cid and kind = 'permission' and status = 'Pending';
    if not found then raise exception 'Only a pending request can be changed.'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- who may call what: the employee calls are open to the sign-in page (they check the session themselves); the HR calls need a signed-in HR user
revoke all on function public.kmr_hrms_me_login(text, text, date), public.kmr_hrms_me_logout(text), public.kmr_hrms_me_data(text, text), public.kmr_hrms_me_leave_apply(text, jsonb), public.kmr_hrms_me_perm_apply(text, jsonb), public.kmr_hrms_me_cancel(text, uuid) from public;
grant execute on function public.kmr_hrms_me_login(text, text, date), public.kmr_hrms_me_logout(text), public.kmr_hrms_me_data(text, text), public.kmr_hrms_me_leave_apply(text, jsonb), public.kmr_hrms_me_perm_apply(text, jsonb), public.kmr_hrms_me_cancel(text, uuid) to anon, authenticated;
revoke all on function public.kmr_hrms_perm_save(text, jsonb) from public, anon;
grant execute on function public.kmr_hrms_perm_save(text, jsonb) to authenticated;
