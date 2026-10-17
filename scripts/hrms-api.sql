-- ---------- helpers ----------
create or replace function console.hrms_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.hrms_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.hrms_counters.n + 1 returning n $$;
revoke all on function console.hrms_next(uuid, text) from public, anon, authenticated;

-- salary, bank and payslip data are for editors and administrators only
create or replace function console.hrms_money_ok(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select coalesce(console.qp_role(p_cid, 'hrms'), '') in ('admin', 'editor') $$;
revoke all on function console.hrms_money_ok(uuid) from public, anon, authenticated;

-- a month whose payroll is finalised is locked for attendance changes
create or replace function console.hrms_locked(p_cid uuid, p_date date) returns boolean language sql stable security definer set search_path = console, public as $$
  select exists (select 1 from console.hrms_payroll_runs where customer_id = p_cid and status = 'final' and period = to_char(p_date, 'YYYY-MM')) $$;
revoke all on function console.hrms_locked(uuid, date) from public, anon, authenticated;

create or replace function console.hrms_tz(p_cid uuid) returns text language sql stable security definer set search_path = console, public as $$
  select coalesce(nullif((select data ->> 'tz' from console.hrms_settings where customer_id = p_cid), ''), 'Asia/Kolkata') $$;
revoke all on function console.hrms_tz(uuid) from public, anon, authenticated;

create or replace function console.hrms_num(p jsonb, k text, d numeric default 0) returns numeric language sql immutable as $$
  select case when p ? k and coalesce(p ->> k, '') <> '' then (p ->> k)::numeric else d end $$;
create or replace function console.hrms_txt(p jsonb, k text) returns text language sql immutable as $$ select nullif(trim(coalesce(p ->> k, '')), '') $$;

-- one employee: create or change (used by the screen and by the bulk import)
create or replace function console.hrms_emp_upsert(p_cid uuid, p jsonb, me text) returns uuid language plpgsql security definer set search_path = console, public as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; code text := console.hrms_txt(p, 'emp_code'); pay text := coalesce(console.hrms_txt(p, 'pay_type'), 'monthly'); sh uuid := nullif(p ->> 'shift_id', '')::uuid;
        pre text := coalesce(nullif((select data ->> 'emp_prefix' from console.hrms_settings where customer_id = p_cid), ''), 'E'); sm boolean := false; st text := coalesce(console.hrms_txt(p, 'status'), 'active');
begin
  if v_id is null and console.hrms_txt(p, 'name') is null then raise exception 'Enter the employee''s name.'; end if;
  if p ? 'name' and console.hrms_txt(p, 'name') is null then raise exception 'Enter the employee''s name.'; end if;
  if pay not in ('monthly', 'daily') then raise exception 'Pay type must be monthly or daily.'; end if;
  if st not in ('active', 'left') then raise exception 'Status must be active or left.'; end if;
  if sh is not null and not exists (select 1 from console.hrms_shifts where id = sh and customer_id = p_cid) then raise exception 'Shift not found.'; end if;
  if console.hrms_num(p, 'basic') < 0 or console.hrms_num(p, 'hra') < 0 or console.hrms_num(p, 'special') < 0 or console.hrms_num(p, 'other_allow') < 0 then raise exception 'Salary amounts cannot be negative.'; end if;
  begin
    if v_id is null then
      if code is null then code := upper(left(regexp_replace(pre, '[^A-Za-z0-9]', '', 'g'), 5)) || '-' || lpad(console.hrms_next(p_cid, 'EMP')::text, 4, '0'); end if;
      insert into console.hrms_employees (customer_id, emp_code, name, gender, dob, doj, dol, department, designation, grade, mobile, email, address, status, shift_id, bio_id, pay_type, basic, hra, special, other_allow, pf, esi, pt, ot_eligible, uan, esi_no, pan, bank_name, bank_account, ifsc, notes)
      values (p_cid, code, console.hrms_txt(p, 'name'), console.hrms_txt(p, 'gender'), nullif(p ->> 'dob', '')::date, nullif(p ->> 'doj', '')::date, nullif(p ->> 'dol', '')::date, console.hrms_txt(p, 'department'), console.hrms_txt(p, 'designation'), console.hrms_txt(p, 'grade'),
              console.hrms_txt(p, 'mobile'), console.hrms_txt(p, 'email'), console.hrms_txt(p, 'address'), st, sh, console.hrms_txt(p, 'bio_id'), pay, console.hrms_num(p, 'basic'), console.hrms_num(p, 'hra'), console.hrms_num(p, 'special'), console.hrms_num(p, 'other_allow'),
              coalesce((p ->> 'pf')::boolean, false), coalesce((p ->> 'esi')::boolean, false), coalesce((p ->> 'pt')::boolean, false), coalesce((p ->> 'ot_eligible')::boolean, false),
              console.hrms_txt(p, 'uan'), console.hrms_txt(p, 'esi_no'), console.hrms_txt(p, 'pan'), console.hrms_txt(p, 'bank_name'), console.hrms_txt(p, 'bank_account'), console.hrms_txt(p, 'ifsc'), console.hrms_txt(p, 'notes')) returning id into v_id;
    else
      select sample into sm from console.hrms_employees where id = v_id and customer_id = p_cid; if not found then raise exception 'Employee not found.'; end if;
      update console.hrms_employees set
        emp_code = coalesce(code, emp_code), name = case when p ? 'name' then console.hrms_txt(p, 'name') else name end,
        gender = case when p ? 'gender' then console.hrms_txt(p, 'gender') else gender end, dob = case when p ? 'dob' then nullif(p ->> 'dob', '')::date else dob end,
        doj = case when p ? 'doj' then nullif(p ->> 'doj', '')::date else doj end, dol = case when p ? 'dol' then nullif(p ->> 'dol', '')::date else dol end,
        department = case when p ? 'department' then console.hrms_txt(p, 'department') else department end, designation = case when p ? 'designation' then console.hrms_txt(p, 'designation') else designation end,
        grade = case when p ? 'grade' then console.hrms_txt(p, 'grade') else grade end, mobile = case when p ? 'mobile' then console.hrms_txt(p, 'mobile') else mobile end,
        email = case when p ? 'email' then console.hrms_txt(p, 'email') else email end, address = case when p ? 'address' then console.hrms_txt(p, 'address') else address end,
        status = case when p ? 'status' then st else status end, shift_id = case when p ? 'shift_id' then sh else shift_id end, bio_id = case when p ? 'bio_id' then console.hrms_txt(p, 'bio_id') else bio_id end,
        pay_type = case when p ? 'pay_type' then pay else pay_type end,
        basic = case when p ? 'basic' then console.hrms_num(p, 'basic') else basic end, hra = case when p ? 'hra' then console.hrms_num(p, 'hra') else hra end,
        special = case when p ? 'special' then console.hrms_num(p, 'special') else special end, other_allow = case when p ? 'other_allow' then console.hrms_num(p, 'other_allow') else other_allow end,
        pf = case when p ? 'pf' then (p ->> 'pf')::boolean else pf end, esi = case when p ? 'esi' then (p ->> 'esi')::boolean else esi end, pt = case when p ? 'pt' then (p ->> 'pt')::boolean else pt end,
        ot_eligible = case when p ? 'ot_eligible' then (p ->> 'ot_eligible')::boolean else ot_eligible end,
        uan = case when p ? 'uan' then console.hrms_txt(p, 'uan') else uan end, esi_no = case when p ? 'esi_no' then console.hrms_txt(p, 'esi_no') else esi_no end, pan = case when p ? 'pan' then console.hrms_txt(p, 'pan') else pan end,
        bank_name = case when p ? 'bank_name' then console.hrms_txt(p, 'bank_name') else bank_name end, bank_account = case when p ? 'bank_account' then console.hrms_txt(p, 'bank_account') else bank_account end,
        ifsc = case when p ? 'ifsc' then console.hrms_txt(p, 'ifsc') else ifsc end, notes = case when p ? 'notes' then console.hrms_txt(p, 'notes') else notes end, updated_at = now()
       where id = v_id;
    end if;
  exception when unique_violation then
    if sqlerrm like '%hrms_emp_bio%' then raise exception 'The machine / card number % is already given to another employee.', console.hrms_txt(p, 'bio_id'); end if;
    raise exception 'The employee code % is already used.', coalesce(code, console.hrms_txt(p, 'emp_code'));
  end;
  -- punches that came before the machine number was given to the employee now belong to them
  update console.hrms_punches x set employee_id = e.id from console.hrms_employees e where e.id = v_id and x.customer_id = p_cid and x.employee_id is null and e.bio_id is not null and x.bio_id = e.bio_id;
  return v_id;
end $$;
revoke all on function console.hrms_emp_upsert(uuid, jsonb, text) from public, anon, authenticated;

-- add punches (from a machine, a file or by hand); duplicates are ignored
create or replace function console.hrms_punch_add(p_cid uuid, p_dev uuid, p_source text, p_rows jsonb, me text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare tz text := console.hrms_tz(p_cid); r jsonb; t timestamptz; ts text; b text; v text; d text; emp uuid; k int; added int := 0; dup int := 0; bad int := 0; unk jsonb := '[]'; dsample boolean := false; lastp timestamptz;
begin
  if p_dev is not null then select sample into dsample from console.hrms_devices where id = p_dev; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    b := coalesce(console.hrms_txt(r, 'bio_id'), console.hrms_txt(r, 'pin'), console.hrms_txt(r, 'user_id'), console.hrms_txt(r, 'userid')); ts := coalesce(console.hrms_txt(r, 'time'), console.hrms_txt(r, 'timestamp'), console.hrms_txt(r, 'datetime'));
    if b is null or ts is null then bad := bad + 1; continue; end if;
    begin
      if ts ~ '(Z|[+-]\d{2}:?\d{2})$' then t := ts::timestamptz; else t := ts::timestamp at time zone tz; end if;
    exception when others then bad := bad + 1; continue; end;
    v := lower(coalesce(console.hrms_txt(r, 'verify'), 'other')); if v not in ('finger', 'face', 'card', 'password', 'palm', 'manual', 'other') then v := 'other'; end if;
    d := lower(coalesce(console.hrms_txt(r, 'direction'), '')); if d not in ('in', 'out') then d := null; end if;
    emp := coalesce(nullif(r ->> 'employee_id', '')::uuid, (select e.id from console.hrms_employees e where e.customer_id = p_cid and e.bio_id = b limit 1));
    if emp is null and not exists (select 1 from jsonb_array_elements_text(unk) u where u = b) then unk := unk || to_jsonb(b); end if;
    insert into console.hrms_punches (customer_id, device_id, employee_id, bio_id, punched_at, verify, direction, source, sample, created_by)
    values (p_cid, p_dev, emp, b, t, v, d, p_source, coalesce((select e.sample from console.hrms_employees e where e.id = emp), dsample), me)
    on conflict (customer_id, bio_id, punched_at) do nothing;
    get diagnostics k = row_count; if k > 0 then added := added + 1; lastp := greatest(coalesce(lastp, t), t); else dup := dup + 1; end if;
  end loop;
  if p_dev is not null then update console.hrms_devices set last_seen = now(), last_punch = greatest(coalesce(last_punch, lastp), coalesce(lastp, last_punch)), punches_total = punches_total + added where id = p_dev; end if;
  return jsonb_build_object('added', added, 'duplicate', dup, 'invalid', bad, 'unknown_ids', unk);
end $$;
revoke all on function console.hrms_punch_add(uuid, uuid, text, jsonb, text) from public, anon, authenticated;

-- a machine / bridge pushes punches. Only the server calls this (service key); the machine is known by serial number or by its push key.
create or replace function console.hrms_ingest(p_mode text, p_id text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare dv console.hrms_devices%rowtype; res jsonb;
begin
  if p_mode = 'serial' then select * into dv from console.hrms_devices where lower(serial) = lower(trim(p_id)) and enabled;
  else select * into dv from console.hrms_devices where push_key = trim(p_id) and enabled; end if;
  if not found then return jsonb_build_object('ok', false, 'error', 'Unknown or switched-off machine.'); end if;
  if not exists (select 1 from console.licences l where l.customer_id = dv.customer_id and l.product_code = 'hrms' and l.status in ('trial', 'pilot', 'active') and (l.valid_until is null or l.valid_until >= current_date)) then
    return jsonb_build_object('ok', false, 'error', 'The HRM licence is not active.');
  end if;
  res := console.hrms_punch_add(dv.customer_id, dv.id, case when p_mode = 'serial' then 'device' else 'json' end, p_rows, 'machine ' || dv.name);
  if jsonb_array_length(coalesce(p_rows, '[]')) = 0 then update console.hrms_devices set last_seen = now() where id = dv.id; end if;
  return res || jsonb_build_object('ok', true, 'device', dv.name);
end $$;
revoke all on function console.hrms_ingest(text, text, jsonb) from public, anon, authenticated;
grant execute on function console.hrms_ingest(text, text, jsonb) to service_role;

-- ---------- reads ----------
create or replace function public.kmr_hrms_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms'); sal boolean := console.hrms_money_ok(cid);
begin
  return jsonb_build_object('role', console.qp_role(cid, 'hrms'), 'money', sal,
    'settings', coalesce((select data from console.hrms_settings where customer_id = cid), '{}'),
    'shifts', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.name) from console.hrms_shifts s where s.customer_id = cid), '[]'),
    'holidays', coalesce((select jsonb_agg(to_jsonb(h) - 'customer_id' order by h.hdate) from console.hrms_holidays h where h.customer_id = cid), '[]'),
    'leave_types', coalesce((select jsonb_agg(to_jsonb(t) - 'customer_id' order by t.code) from console.hrms_leave_types t where t.customer_id = cid), '[]'),
    'devices', coalesce((select jsonb_agg((to_jsonb(d) - 'customer_id' - 'push_key') || case when sal then jsonb_build_object('push_key', d.push_key) else '{}'::jsonb end order by d.name) from console.hrms_devices d where d.customer_id = cid), '[]'),
    'employees', coalesce((select jsonb_agg((to_jsonb(e) - 'customer_id') - case when sal then array[]::text[] else array['basic', 'hra', 'special', 'other_allow', 'bank_name', 'bank_account', 'ifsc', 'uan', 'esi_no', 'pan', 'pf', 'esi', 'pt'] end order by e.emp_code) from console.hrms_employees e where e.customer_id = cid), '[]'),
    'today', (now() at time zone console.hrms_tz(cid))::date);
end $$;

-- attendance rows, punches and approved leave for a date range (at most 93 days)
create or replace function public.kmr_hrms_att_get(p_slug text, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms'); tz text;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.attendance');
  if p_from is null or p_to is null or p_to < p_from then raise exception 'Choose the dates.'; end if;
  if p_to - p_from > 92 then raise exception 'Choose at most three months at a time.'; end if;
  tz := console.hrms_tz(cid);
  return jsonb_build_object(
    'attendance', coalesce((select jsonb_agg((to_jsonb(a) - 'customer_id' - 'sample') order by a.work_date) from console.hrms_attendance a where a.customer_id = cid and a.work_date between p_from and p_to), '[]'),
    'punches', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'employee_id', x.employee_id, 'bio_id', x.bio_id, 'at', x.punched_at, 'verify', x.verify, 'direction', x.direction, 'device_id', x.device_id, 'source', x.source) order by x.punched_at)
        from console.hrms_punches x where x.customer_id = cid and x.punched_at >= ((p_from - 1)::timestamp at time zone tz) and x.punched_at < ((p_to + 2)::timestamp at time zone tz)), '[]'),
    'leaves', coalesce((select jsonb_agg(jsonb_build_object('employee_id', l.employee_id, 'from_date', l.from_date, 'to_date', l.to_date, 'half', l.half, 'leave_code', l.leave_code, 'paid', coalesce((select t.paid from console.hrms_leave_types t where t.id = l.leave_type_id), true)))
        from console.hrms_leaves l where l.customer_id = cid and l.status = 'Approved' and l.from_date <= p_to and l.to_date >= p_from), '[]'),
    'locked', coalesce((select jsonb_agg(r.period) from console.hrms_payroll_runs r where r.customer_id = cid and r.status = 'final'), '[]'));
end $$;

create or replace function public.kmr_hrms_leaves(p_slug text, p_year int) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms'); y int := coalesce(p_year, extract(year from (now() at time zone console.hrms_tz(cid)))::int);
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.leave');
  return coalesce((select jsonb_agg((to_jsonb(l) - 'customer_id' - 'sample') || jsonb_build_object('emp_name', e.name, 'emp_code', e.emp_code) order by l.from_date desc, l.created_at desc)
    from console.hrms_leaves l join console.hrms_employees e on e.id = l.employee_id
   where l.customer_id = cid and (extract(year from l.from_date) = y or extract(year from l.to_date) = y)), '[]');
end $$;

-- ---------- setup: settings, shifts, holidays, leave types ----------
create or replace function public.kmr_hrms_settings_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  if jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object.'; end if;
  insert into console.hrms_settings (customer_id, data) values (cid, p) on conflict (customer_id) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.kmr_hrms_shift_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); v_id uuid := nullif(p ->> 'id', '')::uuid; wo int[]; stt text := coalesce(console.hrms_txt(p, 'start_time'), '09:00'); ent text := coalesce(console.hrms_txt(p, 'end_time'), '18:00');
begin
  if console.hrms_txt(p, 'name') is null then raise exception 'Enter the shift name.'; end if;
  if stt !~ '^\d{2}:\d{2}$' or ent !~ '^\d{2}:\d{2}$' then raise exception 'Enter the shift times as HH:MM.'; end if;
  wo := coalesce((select array_agg(x::int) from jsonb_array_elements_text(case when jsonb_typeof(p -> 'weekly_off') = 'array' then p -> 'weekly_off' else '[]'::jsonb end) x), '{}');
  if exists (select 1 from unnest(wo) d where d not between 0 and 6) then raise exception 'Weekly off days are 0 (Sunday) to 6 (Saturday).'; end if;
  begin
    if v_id is null then
      insert into console.hrms_shifts (customer_id, name, start_time, end_time, grace_min, break_min, half_day_min, full_day_min, night, weekly_off, active)
      values (cid, trim(p ->> 'name'), stt, ent, console.hrms_num(p, 'grace_min', 10)::int, console.hrms_num(p, 'break_min', 30)::int, console.hrms_num(p, 'half_day_min', 240)::int, console.hrms_num(p, 'full_day_min', 450)::int,
              coalesce((p ->> 'night')::boolean, false), wo, coalesce((p ->> 'active')::boolean, true)) returning id into v_id;
    else
      update console.hrms_shifts set name = trim(p ->> 'name'), start_time = stt, end_time = ent, grace_min = console.hrms_num(p, 'grace_min', 10)::int, break_min = console.hrms_num(p, 'break_min', 30)::int,
        half_day_min = console.hrms_num(p, 'half_day_min', 240)::int, full_day_min = console.hrms_num(p, 'full_day_min', 450)::int, night = coalesce((p ->> 'night')::boolean, false), weekly_off = wo, active = coalesce((p ->> 'active')::boolean, true)
       where id = v_id and customer_id = cid;
      if not found then raise exception 'Shift not found.'; end if;
    end if;
  exception when unique_violation then raise exception 'A shift named % already exists.', trim(p ->> 'name'); end;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.kmr_hrms_shift_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  if exists (select 1 from console.hrms_employees where shift_id = p_id and customer_id = cid) then raise exception 'Employees are on this shift. Move them to another shift first (or untick Active).'; end if;
  delete from console.hrms_shifts where id = p_id and customer_id = cid;
end $$;

create or replace function public.kmr_hrms_holiday_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); rows jsonb := case when jsonb_typeof(p -> 'rows') = 'array' then p -> 'rows' else jsonb_build_array(p) end; r jsonb;
begin
  for r in select * from jsonb_array_elements(rows) loop
    if nullif(r ->> 'hdate', '') is null or console.hrms_txt(r, 'name') is null then raise exception 'Enter the holiday date and name.'; end if;
    if nullif(r ->> 'id', '') is not null then update console.hrms_holidays set hdate = (r ->> 'hdate')::date, name = trim(r ->> 'name') where id = (r ->> 'id')::uuid and customer_id = cid;
    else insert into console.hrms_holidays (customer_id, hdate, name) values (cid, (r ->> 'hdate')::date, trim(r ->> 'name')) on conflict (customer_id, hdate) do update set name = excluded.name; end if;
  end loop;
exception when unique_violation then raise exception 'There is already a holiday on that date.';
end $$;
create or replace function public.kmr_hrms_holiday_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin delete from console.hrms_holidays where id = p_id and customer_id = cid; end $$;

create or replace function public.kmr_hrms_leave_type_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.leave');
  if console.hrms_txt(p, 'code') is null or console.hrms_txt(p, 'name') is null then raise exception 'Enter the leave code and name.'; end if;
  begin
    if v_id is null then insert into console.hrms_leave_types (customer_id, code, name, paid, annual_quota, active) values (cid, upper(trim(p ->> 'code')), trim(p ->> 'name'), coalesce((p ->> 'paid')::boolean, true), console.hrms_num(p, 'annual_quota'), coalesce((p ->> 'active')::boolean, true));
    else update console.hrms_leave_types set code = upper(trim(p ->> 'code')), name = trim(p ->> 'name'), paid = coalesce((p ->> 'paid')::boolean, true), annual_quota = console.hrms_num(p, 'annual_quota'), active = coalesce((p ->> 'active')::boolean, true) where id = v_id and customer_id = cid; end if;
  exception when unique_violation then raise exception 'Leave code % already exists.', upper(trim(p ->> 'code'));
  end;
end $$;
create or replace function public.kmr_hrms_leave_type_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  if exists (select 1 from console.hrms_leaves where leave_type_id = p_id and customer_id = cid) then raise exception 'This leave type is used in leave requests. Untick Active instead.'; end if;
  delete from console.hrms_leave_types where id = p_id and customer_id = cid;
end $$;

-- ---------- biometric machines ----------
create or replace function public.kmr_hrms_device_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); v_id uuid := nullif(p ->> 'id', '')::uuid; proto text := coalesce(console.hrms_txt(p, 'protocol'), 'adms'); md text[]; ser text := console.hrms_txt(p, 'serial'); pkey text;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.biometric-machines');
  if console.hrms_txt(p, 'name') is null then raise exception 'Enter a name for the machine (for example Gate 1 fingerprint).'; end if;
  if proto not in ('adms', 'json', 'file') then raise exception 'Choose how the machine sends its punches.'; end if;
  if proto = 'adms' and ser is null then raise exception 'Enter the machine''s serial number (printed on the machine and shown in its menu under System info).'; end if;
  md := coalesce((select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(p -> 'modes') = 'array' then p -> 'modes' else '["finger"]'::jsonb end) x where x in ('finger', 'face', 'card', 'palm', 'password')), '{finger}');
  begin
    if v_id is null then
      insert into console.hrms_devices (customer_id, name, vendor, model, modes, serial, protocol, location, ip, enabled, notes)
      values (cid, trim(p ->> 'name'), coalesce(console.hrms_txt(p, 'vendor'), 'Other'), console.hrms_txt(p, 'model'), md, ser, proto, console.hrms_txt(p, 'location'), console.hrms_txt(p, 'ip'), coalesce((p ->> 'enabled')::boolean, true), console.hrms_txt(p, 'notes')) returning id, push_key into v_id, pkey;
    else
      update console.hrms_devices set name = trim(p ->> 'name'), vendor = coalesce(console.hrms_txt(p, 'vendor'), vendor), model = console.hrms_txt(p, 'model'), modes = md, serial = ser, protocol = proto,
             location = console.hrms_txt(p, 'location'), ip = console.hrms_txt(p, 'ip'), enabled = coalesce((p ->> 'enabled')::boolean, true), notes = console.hrms_txt(p, 'notes')
       where id = v_id and customer_id = cid returning push_key into pkey;
      if not found then raise exception 'Machine not found.'; end if;
    end if;
  exception when unique_violation then raise exception 'Another machine already has the serial number %.', ser; end;
  return jsonb_build_object('id', v_id, 'push_key', pkey);
end $$;
create or replace function public.kmr_hrms_device_key(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); k text := replace(gen_random_uuid()::text, '-', '');
begin
  update console.hrms_devices set push_key = k where id = p_id and customer_id = cid; if not found then raise exception 'Machine not found.'; end if; return k;
end $$;
create or replace function public.kmr_hrms_device_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin delete from console.hrms_devices where id = p_id and customer_id = cid; end $$;

-- punches typed in or read from a file exported from any machine; p = {source, device_id, rows: [{bio_id, time, verify, direction, employee_id}]}
create or replace function public.kmr_hrms_punch_import(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); src text := coalesce(console.hrms_txt(p, 'source'), 'import'); dev uuid := nullif(p ->> 'device_id', '')::uuid;
begin
  if src not in ('import', 'manual') then raise exception 'Unknown source.'; end if;
  perform console.require_feature(p_slug, 'hrms', case when src = 'manual' then 'hrms.attendance' else 'hrms.biometric-machines' end);
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'No punches to add.'; end if;
  if jsonb_array_length(p -> 'rows') > 20000 then raise exception 'Send at most 20,000 punches at a time.'; end if;
  if dev is not null and not exists (select 1 from console.hrms_devices where id = dev and customer_id = cid) then raise exception 'Machine not found.'; end if;
  return console.hrms_punch_add(cid, dev, src, p -> 'rows', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
create or replace function public.kmr_hrms_punch_delete(p_slug text, p_ids jsonb) returns integer language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); n int;
begin
  delete from console.hrms_punches where customer_id = cid and id in (select (x)::uuid from jsonb_array_elements_text(p_ids) x); get diagnostics n = row_count; return n;
end $$;

-- ---------- employees ----------
create or replace function public.kmr_hrms_employee_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  return jsonb_build_object('id', console.hrms_emp_upsert(cid, p, lower(coalesce(auth.jwt() ->> 'email', ''))));
end $$;
create or replace function public.kmr_hrms_employees_import(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); r jsonb; n int := 0; errs jsonb := '[]'; i int := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'No employees to add.'; end if;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    i := i + 1;
    begin
      if nullif(r ->> 'shift_name', '') is not null and nullif(r ->> 'shift_id', '') is null then r := r || jsonb_build_object('shift_id', (select id from console.hrms_shifts where customer_id = cid and lower(name) = lower(trim(r ->> 'shift_name')) limit 1)); end if;
      perform console.hrms_emp_upsert(cid, r - 'id', me); n := n + 1;
    exception when others then errs := errs || jsonb_build_object('row', i, 'error', sqlerrm); end;
  end loop;
  return jsonb_build_object('added', n, 'errors', errs);
end $$;
create or replace function public.kmr_hrms_employee_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  if console.qp_role(cid, 'hrms') <> 'admin' then raise exception 'Only the administrator can delete an employee. To stop an employee, set the status to Left.'; end if;
  if exists (select 1 from console.hrms_payslips where employee_id = p_id and customer_id = cid) then raise exception 'This employee has payslips. Set the status to Left instead of deleting.'; end if;
  delete from console.hrms_employees where id = p_id and customer_id = cid;
end $$;

-- ---------- attendance ----------
-- p = {mode: 'auto' | 'manual', rows: [{employee_id, work_date, in_at, out_at, worked_min, late_min, early_min, ot_min, status, leave_code, remarks}]}
-- 'auto' (the screen working attendance out from punches, leave, holidays) never overwrites a day that was entered by hand
create or replace function public.kmr_hrms_att_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); mode text := coalesce(p ->> 'mode', 'auto'); r jsonb; d date; emp console.hrms_employees%rowtype; saved int := 0; locked int := 0; kept int := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
        st text; ex console.hrms_attendance%rowtype;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.attendance');
  if mode not in ('auto', 'manual') then raise exception 'Unknown mode.'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Nothing to save.'; end if;
  if jsonb_array_length(p -> 'rows') > 6000 then raise exception 'Send at most 6,000 days at a time.'; end if;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    d := (r ->> 'work_date')::date; st := r ->> 'status';
    if st not in ('P', 'HD', 'A', 'L', 'U', 'WO', 'H', 'MP') then raise exception 'Unknown attendance status %.', st; end if;
    select * into emp from console.hrms_employees where id = (r ->> 'employee_id')::uuid and customer_id = cid; if not found then continue; end if;
    if console.hrms_locked(cid, d) then locked := locked + 1; continue; end if;
    select * into ex from console.hrms_attendance where employee_id = emp.id and work_date = d;
    if mode = 'auto' and found and ex.source = 'manual' then kept := kept + 1; continue; end if;
    insert into console.hrms_attendance (customer_id, employee_id, work_date, in_at, out_at, worked_min, late_min, early_min, ot_min, status, leave_code, source, remarks, sample, updated_by)
    values (cid, emp.id, d, nullif(r ->> 'in_at', '')::timestamptz, nullif(r ->> 'out_at', '')::timestamptz, console.hrms_num(r, 'worked_min')::int, console.hrms_num(r, 'late_min')::int, console.hrms_num(r, 'early_min')::int, console.hrms_num(r, 'ot_min')::int,
            st, console.hrms_txt(r, 'leave_code'), case when mode = 'manual' then 'manual' else coalesce(nullif(r ->> 'source', ''), 'punch') end, console.hrms_txt(r, 'remarks'), emp.sample, me)
    on conflict (employee_id, work_date) do update set in_at = excluded.in_at, out_at = excluded.out_at, worked_min = excluded.worked_min, late_min = excluded.late_min, early_min = excluded.early_min, ot_min = excluded.ot_min,
      status = excluded.status, leave_code = excluded.leave_code, source = excluded.source, remarks = excluded.remarks, updated_by = excluded.updated_by, updated_at = now();
    saved := saved + 1;
  end loop;
  return jsonb_build_object('saved', saved, 'locked', locked, 'kept_manual', kept);
end $$;
-- hand-entered days go back to being worked out from punches
create or replace function public.kmr_hrms_att_reset(p_slug text, p_employee uuid, p_from date, p_to date) returns integer language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); n int;
begin
  delete from console.hrms_attendance where customer_id = cid and employee_id = p_employee and work_date between p_from and p_to and source = 'manual' and not console.hrms_locked(cid, work_date); get diagnostics n = row_count; return n;
end $$;

-- ---------- leave ----------
create or replace function public.kmr_hrms_leave_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); v_id uuid := nullif(p ->> 'id', '')::uuid; emp console.hrms_employees%rowtype; lt console.hrms_leave_types%rowtype; f date := (p ->> 'from_date')::date; t date := (p ->> 'to_date')::date; dys numeric := console.hrms_num(p, 'days', 0);
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.leave');
  select * into emp from console.hrms_employees where id = (p ->> 'employee_id')::uuid and customer_id = cid; if not found then raise exception 'Choose the employee.'; end if;
  select * into lt from console.hrms_leave_types where id = nullif(p ->> 'leave_type_id', '')::uuid and customer_id = cid; if not found then raise exception 'Choose the leave type.'; end if;
  if f is null or t is null or t < f then raise exception 'Choose the leave dates (to-date cannot be before from-date).'; end if;
  if dys <= 0 then dys := (t - f + 1); end if;
  if v_id is null then
    insert into console.hrms_leaves (customer_id, employee_id, leave_type_id, leave_code, from_date, to_date, half, days, reason, sample, created_by)
    values (cid, emp.id, lt.id, lt.code, f, t, coalesce((p ->> 'half')::boolean, false), dys, console.hrms_txt(p, 'reason'), emp.sample, lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into v_id;
  else
    update console.hrms_leaves set leave_type_id = lt.id, leave_code = lt.code, from_date = f, to_date = t, half = coalesce((p ->> 'half')::boolean, false), days = dys, reason = console.hrms_txt(p, 'reason')
     where id = v_id and customer_id = cid and status = 'Pending';
    if not found then raise exception 'Only a pending request can be changed.'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.kmr_hrms_leave_decide(p_slug text, p_id uuid, p_status text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); l console.hrms_leaves%rowtype;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.leave');
  if p_status not in ('Approved', 'Rejected', 'Cancelled', 'Pending') then raise exception 'Unknown status.'; end if;
  select * into l from console.hrms_leaves where id = p_id and customer_id = cid; if not found then raise exception 'Leave request not found.'; end if;
  if p_status = 'Approved' and (console.hrms_locked(cid, l.from_date) or console.hrms_locked(cid, l.to_date)) then raise exception 'The payroll of that month is finalised. Re-open the payroll first.'; end if;
  update console.hrms_leaves set status = p_status, decided_by = lower(coalesce(auth.jwt() ->> 'email', '')), decided_at = now() where id = p_id;
  -- days entered by hand for these dates are cleared so the approved leave shows when attendance is worked out again
  if p_status in ('Approved', 'Cancelled', 'Rejected') then
    delete from console.hrms_attendance where customer_id = cid and employee_id = l.employee_id and work_date between l.from_date and l.to_date and source in ('leave', 'rule') and not console.hrms_locked(cid, work_date);
  end if;
end $$;
create or replace function public.kmr_hrms_leave_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  delete from console.hrms_leaves where id = p_id and customer_id = cid and status in ('Pending', 'Rejected', 'Cancelled');
  if not found then raise exception 'Only a pending, rejected or cancelled request can be deleted. Cancel an approved one first.'; end if;
end $$;

-- ---------- payroll ----------
create or replace function public.kmr_hrms_payroll_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms');
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.automated-payroll');
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  return coalesce((select jsonb_agg((to_jsonb(r) - 'customer_id' - 'sample') order by r.period desc) from console.hrms_payroll_runs r where r.customer_id = cid), '[]');
end $$;
create or replace function public.kmr_hrms_payroll_get(p_slug text, p_period text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms'); r console.hrms_payroll_runs%rowtype;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.automated-payroll');
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  select * into r from console.hrms_payroll_runs where customer_id = cid and period = p_period;
  if not found then return null; end if;
  return jsonb_build_object('run', to_jsonb(r) - 'customer_id' - 'sample',
    'slips', coalesce((select jsonb_agg((to_jsonb(s) - 'customer_id' - 'sample') order by s.emp_code) from console.hrms_payslips s where s.run_id = r.id), '[]'));
end $$;
-- p = {period, month_days, note, slips: [...]}: makes (or remakes) the DRAFT run of the month
create or replace function public.kmr_hrms_payroll_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); per text := p ->> 'period'; run console.hrms_payroll_runs%rowtype; s jsonb; emp console.hrms_employees%rowtype; all_sample boolean := true; n int := 0;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.automated-payroll');
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then raise exception 'Choose the payroll month.'; end if;
  if jsonb_typeof(p -> 'slips') <> 'array' or jsonb_array_length(p -> 'slips') = 0 then raise exception 'There are no employees to pay for this month.'; end if;
  select * into run from console.hrms_payroll_runs where customer_id = cid and period = per for update;
  if found and run.status = 'final' then raise exception 'The payroll of % is finalised. Re-open it first to change it.', per; end if;
  if not found then
    insert into console.hrms_payroll_runs (customer_id, period, month_days, note, created_by) values (cid, per, console.hrms_num(p, 'month_days', 30)::int, console.hrms_txt(p, 'note'), lower(coalesce(auth.jwt() ->> 'email', ''))) returning * into run;
  else
    delete from console.hrms_payslips where run_id = run.id;
    update console.hrms_payroll_runs set month_days = console.hrms_num(p, 'month_days', 30)::int, note = console.hrms_txt(p, 'note'), updated_at = now() where id = run.id;
  end if;
  for s in select * from jsonb_array_elements(p -> 'slips') loop
    select * into emp from console.hrms_employees where id = nullif(s ->> 'employee_id', '')::uuid and customer_id = cid;
    if not emp.sample or emp.id is null then all_sample := false; end if;
    insert into console.hrms_payslips (customer_id, run_id, employee_id, emp_code, emp_name, department, designation, paid_days, lop_days, ot_hours, earnings, deductions, gross, deduct, net, info, sample)
    values (cid, run.id, emp.id, coalesce(console.hrms_txt(s, 'emp_code'), emp.emp_code), coalesce(console.hrms_txt(s, 'emp_name'), emp.name), console.hrms_txt(s, 'department'), console.hrms_txt(s, 'designation'),
            console.hrms_num(s, 'paid_days'), console.hrms_num(s, 'lop_days'), console.hrms_num(s, 'ot_hours'), coalesce(s -> 'earnings', '[]'), coalesce(s -> 'deductions', '[]'),
            console.hrms_num(s, 'gross'), console.hrms_num(s, 'deduct'), console.hrms_num(s, 'net'), coalesce(s -> 'info', '{}'), coalesce(emp.sample, false));
    n := n + 1;
  end loop;
  update console.hrms_payroll_runs r set sample = all_sample, totals = (select jsonb_build_object('employees', count(*), 'gross', coalesce(sum(gross), 0), 'deduct', coalesce(sum(deduct), 0), 'net', coalesce(sum(net), 0)) from console.hrms_payslips where run_id = r.id) where r.id = run.id;
  return jsonb_build_object('id', run.id, 'slips', n);
end $$;
-- one payslip adjusted by hand (extra earning, advance recovery, ...) while the run is a draft
create or replace function public.kmr_hrms_payslip_save(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); sl console.hrms_payslips%rowtype; run console.hrms_payroll_runs%rowtype;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.automated-payroll');
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  select * into sl from console.hrms_payslips where id = (p ->> 'id')::uuid and customer_id = cid; if not found then raise exception 'Payslip not found.'; end if;
  select * into run from console.hrms_payroll_runs where id = sl.run_id;
  if run.status = 'final' then raise exception 'The payroll is finalised. Re-open it to change a payslip.'; end if;
  update console.hrms_payslips set earnings = coalesce(p -> 'earnings', earnings), deductions = coalesce(p -> 'deductions', deductions), gross = console.hrms_num(p, 'gross', gross), deduct = console.hrms_num(p, 'deduct', deduct), net = console.hrms_num(p, 'net', net), info = coalesce(p -> 'info', info) where id = sl.id;
  update console.hrms_payroll_runs r set updated_at = now(), totals = (select jsonb_build_object('employees', count(*), 'gross', coalesce(sum(gross), 0), 'deduct', coalesce(sum(deduct), 0), 'net', coalesce(sum(net), 0)) from console.hrms_payslips where run_id = r.id) where r.id = run.id;
end $$;
create or replace function public.kmr_hrms_payroll_final(p_slug text, p_id uuid, p_final boolean) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); run console.hrms_payroll_runs%rowtype; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.automated-payroll');
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  select * into run from console.hrms_payroll_runs where id = p_id and customer_id = cid; if not found then raise exception 'Payroll run not found.'; end if;
  if p_final then
    if run.status = 'final' then raise exception 'Already finalised.'; end if;
    update console.hrms_payroll_runs set status = 'final', finalised_by = me, finalised_at = now(), updated_at = now() where id = run.id;
  else
    if console.qp_role(cid, 'hrms') <> 'admin' then raise exception 'Only the administrator can re-open a finalised payroll.'; end if;
    update console.hrms_payroll_runs set status = 'draft', finalised_by = null, finalised_at = null, updated_at = now() where id = run.id;
  end if;
end $$;
create or replace function public.kmr_hrms_payroll_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms');
begin
  if not console.hrms_money_ok(cid) then raise exception 'Payroll is for editors and administrators.'; end if;
  delete from console.hrms_payroll_runs where id = p_id and customer_id = cid and status = 'draft';
  if not found then raise exception 'Only a draft payroll can be deleted. Re-open a finalised one first.'; end if;
end $$;

-- ---------- sample data (marked sample = true; deleted again by Grand Master / Data Master) ----------
create or replace function console.hrms_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; today date := (now() at time zone 'Asia/Kolkata')::date; me text := 'sample'; sg uuid; sb uuid; d1 uuid; d2 uuid; lcl uuid; lsl uuid; first_day date := (date_trunc('month', (now() at time zone 'Asia/Kolkata')::date - interval '1 month'))::date;
begin
  if p_action = 'flush' then
    delete from console.hrms_payslips where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_payroll_runs where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_leaves where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_attendance where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_punches where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_employees where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_devices where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_leave_types where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_holidays where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_shifts where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.hrms_settings where customer_id = p_cid and sample;
    return n;
  end if;
  if exists (select 1 from console.hrms_employees where customer_id = p_cid and sample) then return 0; end if;

  insert into console.hrms_settings (customer_id, data, sample) values (p_cid, jsonb_build_object('tz', 'Asia/Kolkata', 'emp_prefix', 'EMP'), true) on conflict (customer_id) do nothing;
  -- setup that already exists (real data) is kept; the sample only adds what is missing
  insert into console.hrms_shifts (customer_id, name, start_time, end_time, grace_min, break_min, half_day_min, full_day_min, night, weekly_off, sample) values
    (p_cid, 'General', '09:00', '18:00', 10, 30, 240, 450, false, '{0}', true), (p_cid, 'Second shift', '14:00', '22:00', 10, 30, 240, 420, false, '{0}', true) on conflict (customer_id, name) do nothing;
  select id into sg from console.hrms_shifts where customer_id = p_cid and name = 'General'; select id into sb from console.hrms_shifts where customer_id = p_cid and name = 'Second shift';
  insert into console.hrms_leave_types (customer_id, code, name, paid, annual_quota, sample) values
    (p_cid, 'CL', 'Casual leave', true, 12, true), (p_cid, 'SL', 'Sick leave', true, 12, true), (p_cid, 'EL', 'Earned leave', true, 15, true), (p_cid, 'LOP', 'Leave without pay', false, 0, true) on conflict (customer_id, code) do nothing;
  select id into lcl from console.hrms_leave_types where customer_id = p_cid and code = 'CL'; select id into lsl from console.hrms_leave_types where customer_id = p_cid and code = 'SL';
  insert into console.hrms_holidays (customer_id, hdate, name, sample) values
    (p_cid, first_day + 14, 'Company foundation day (sample)', true), (p_cid, today + 12, 'Festival holiday (sample)', true) on conflict (customer_id, hdate) do nothing;
  insert into console.hrms_devices (customer_id, name, vendor, model, modes, serial, protocol, location, enabled, last_seen, last_punch, notes, sample) values
    (p_cid, 'Gate 1 fingerprint (sample)', 'eSSL / ZKTeco', 'eSSL MB160', '{finger}', 'SAMPLE-ESSL-0001', 'adms', 'Main gate', true, now() - interval '2 minutes', now() - interval '5 minutes', 'Sample machine: pushes to the ADMS address shown on the Machines screen.', true),
    (p_cid, 'Shop floor face (sample)', 'Realtime', 'Realtime T1100 face', '{face,card}', 'SAMPLE-RT-0002', 'json', 'Shop floor', true, now() - interval '3 minutes', now() - interval '6 minutes', 'Sample machine: pushes JSON from a bridge program.', true);
  select id into d1 from console.hrms_devices where customer_id = p_cid and serial = 'SAMPLE-ESSL-0001'; select id into d2 from console.hrms_devices where customer_id = p_cid and serial = 'SAMPLE-RT-0002';

  -- 24 employees: 20 monthly (PF / ESI by salary), 4 daily-wage; 16 on General, 8 on the second shift
  insert into console.hrms_employees (customer_id, emp_code, name, gender, doj, department, designation, mobile, status, shift_id, bio_id, pay_type, basic, hra, special, other_allow, pf, esi, pt, ot_eligible, bank_name, ifsc, notes, sample)
  select p_cid, 'EMP-S' || lpad(i::text, 3, '0'), nm, g, today - (200 + i * 47), dept, des, '90000' || lpad((10000 + i)::text, 5, '0'), 'active', case when i % 3 = 0 then sb else sg end, (1000 + i)::text,
         case when i > 20 then 'daily' else 'monthly' end, bs, round(bs * 0.4), round(bs * 0.2), case when i % 4 = 0 then 500 else 0 end, bs <= 15000 or i > 20, bs + round(bs * 0.4) + round(bs * 0.2) <= 21000, true, i <= 12 or i > 20,
         'Sample Bank', 'SBIN0000001', 'Sample employee', true
    from (values
      (1, 'Ravi Kumar', 'M', 'Management', 'Plant Head', 52000), (2, 'Meena Iyer', 'F', 'Purchase', 'Purchase Manager', 38000), (3, 'Suresh Patil', 'M', 'Production', 'Production Manager', 41000),
      (4, 'Anil Sharma', 'M', 'Maintenance', 'Maintenance Engineer', 30000), (5, 'Karthik Rao', 'M', 'Quality', 'Design Engineer', 32000), (6, 'Divya Nair', 'F', 'Quality', 'Quality Engineer', 28000),
      (7, 'Imran Shaikh', 'M', 'Production', 'CNC Operator', 14500), (8, 'Lakshmi Devi', 'F', 'Stores', 'Store Keeper', 13500), (9, 'Prakash Gowda', 'M', 'Production', 'VMC Operator', 15000),
      (10, 'Sunita Rao', 'F', 'Accounts', 'Accountant', 24000), (11, 'Mohan Das', 'M', 'Production', 'CNC Operator', 14000), (12, 'Farida Khan', 'F', 'HR', 'HR Executive', 26000),
      (13, 'Rajesh Singh', 'M', 'Production', 'Setter', 21000), (14, 'Naveen Reddy', 'M', 'Quality', 'Inspector', 17500), (15, 'Geeta Menon', 'F', 'Quality', 'Inspector', 17000),
      (16, 'Vikram Joshi', 'M', 'Maintenance', 'Technician', 16500), (17, 'Arjun Pillai', 'M', 'Production', 'Operator', 13200), (18, 'Salma Begum', 'F', 'Production', 'Operator', 12800),
      (19, 'Dinesh Kumar', 'M', 'Despatch', 'Despatch Clerk', 15500), (20, 'Harish Naik', 'M', 'Production', 'Operator', 13000),
      (21, 'Ramu', 'M', 'Production', 'Helper (daily wage)', 520), (22, 'Basavaraj', 'M', 'Production', 'Helper (daily wage)', 520), (23, 'Shankar', 'M', 'Stores', 'Loader (daily wage)', 480), (24, 'Yellappa', 'M', 'Maintenance', 'Helper (daily wage)', 500)
    ) v(i, nm, g, dept, des, bs);
  select count(*) into k from console.hrms_employees where customer_id = p_cid and sample; n := n + k;

  -- leave: two approved last month, one pending, one rejected
  insert into console.hrms_leaves (customer_id, employee_id, leave_type_id, leave_code, from_date, to_date, half, days, reason, status, decided_by, decided_at, sample, created_by)
  select p_cid, e.id, x.lt, x.code, x.f, x.t, false, x.dys, x.reason, x.st, case when x.st in ('Approved', 'Rejected') then me end, case when x.st in ('Approved', 'Rejected') then now() end, true, me
    from (values ('EMP-S007', lcl, 'CL', first_day + 8, first_day + 9, 2, 'Family function', 'Approved'), ('EMP-S011', lsl, 'SL', first_day + 17, first_day + 17, 1, 'Fever', 'Approved'),
                 ('EMP-S006', lcl, 'CL', today + 3, today + 4, 2, 'Personal work', 'Pending'), ('EMP-S013', lcl, 'CL', first_day + 4, first_day + 4, 1, 'Late application', 'Rejected')) x(code0, lt, code, f, t, dys, reason, st)
    join console.hrms_employees e on e.customer_id = p_cid and e.emp_code = x.code0;
  get diagnostics k = row_count; n := n + k;

  -- punches for last month and this month so far: each person comes in on working days with a little spread (late, half day, missed punch, overtime, absent)
  insert into console.hrms_punches (customer_id, device_id, employee_id, bio_id, punched_at, verify, direction, source, sample, created_by)
  select p_cid, case when e.bio_id::int % 2 = 0 then d1 else d2 end, e.id, e.bio_id, p.ts_at, case when e.bio_id::int % 2 = 0 then 'finger' else 'face' end, w.dir, 'device', true, me
    from console.hrms_employees e join console.hrms_shifts s on s.id = e.shift_id
   cross join generate_series(first_day::timestamp, (today - 1)::timestamp, interval '1 day') g(dd)
   cross join lateral (select abs(hashtext(e.emp_code || g.dd::text)) % 100 r, abs(hashtext('a' || e.emp_code || g.dd::text)) % 35 j1, abs(hashtext('b' || e.emp_code || g.dd::text)) % 60 j2) x
   cross join lateral (values (1, 'in'), (2, 'out')) w(k, dir)
   cross join lateral (select (g.dd::date + s.start_time::time)::timestamp at time zone 'Asia/Kolkata' + case
           when w.k = 1 then make_interval(mins => case when x.r between 5 and 19 then 12 + x.j1 else x.j1 % 9 - 5 end)
           when x.r between 20 and 24 then make_interval(mins => 265 + x.j1)
           else (case when s.night then interval '1 day' else interval '0' end) + (g.dd::date + s.end_time::time - (g.dd::date + s.start_time::time)) - interval '0' + make_interval(mins => case when e.ot_eligible and x.r between 30 and 49 then 60 + x.j2 else x.j1 % 12 end) end as ts_at) p
   where e.customer_id = p_cid and e.sample and extract(dow from g.dd)::int <> all (s.weekly_off)
     and not exists (select 1 from console.hrms_holidays h where h.customer_id = p_cid and h.hdate = g.dd::date)
     and not exists (select 1 from console.hrms_leaves l where l.employee_id = e.id and l.status = 'Approved' and g.dd::date between l.from_date and l.to_date)
     and x.r >= 5 and not (w.k = 2 and x.r between 25 and 27);
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function console.hrms_sample(uuid, text) from public, anon, authenticated;

-- the Capacity Planner takes its working days from this holiday calendar
