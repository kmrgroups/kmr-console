-- =====================================================================
-- KMR HRM & Payroll - SHIFT ROSTER (needs 0072 and 0073).
--  Rotating shifts: which shift each person works on each day (General / Morning / Night ...).
--  A day with no roster entry uses the person's own shift, as before. Nothing existing is changed.
-- Safe to re-run.
-- =====================================================================
create table if not exists console.hrms_roster (
  customer_id uuid not null references console.customers(id) on delete cascade,
  employee_id uuid not null references console.hrms_employees(id) on delete cascade,
  work_date date not null,
  shift_id uuid not null references console.hrms_shifts(id) on delete cascade,
  sample boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (employee_id, work_date));
create index if not exists hrms_roster_date on console.hrms_roster (customer_id, work_date);
alter table console.hrms_roster enable row level security;
drop policy if exists hrms_roster_staff on console.hrms_roster;
create policy hrms_roster_staff on console.hrms_roster for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- the roster of a date range: [{e: employee, d: date, s: shift}]
create or replace function public.kmr_hrms_roster_get(p_slug text, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'hrms');
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.attendance');
  if p_from is null or p_to is null or p_to < p_from then raise exception 'Choose the dates.'; end if;
  if p_to - p_from > 92 then raise exception 'Choose at most three months at a time.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('e', r.employee_id, 'd', r.work_date, 's', r.shift_id)) from console.hrms_roster r where r.customer_id = cid and r.work_date between p_from and p_to), '[]');
end $$;
revoke all on function public.kmr_hrms_roster_get(text, date, date) from public, anon;
grant execute on function public.kmr_hrms_roster_get(text, date, date) to authenticated;

-- set (or, with a null shift, clear) the shift of people on days: rows [{employee_id, work_date, shift_id}]
create or replace function public.kmr_hrms_roster_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'hrms'); r jsonb; d date; emp console.hrms_employees%rowtype; sh uuid; saved int := 0; cleared int := 0; locked int := 0;
begin
  perform console.require_feature(p_slug, 'hrms', 'hrms.attendance');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Nothing to save.'; end if;
  if jsonb_array_length(p -> 'rows') > 6000 then raise exception 'Send at most 6,000 days at a time.'; end if;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    d := (r ->> 'work_date')::date; sh := nullif(r ->> 'shift_id', '')::uuid;
    select * into emp from console.hrms_employees where id = (r ->> 'employee_id')::uuid and customer_id = cid; if not found then continue; end if;
    if console.hrms_locked(cid, d) then locked := locked + 1; continue; end if;
    if sh is null then
      delete from console.hrms_roster where employee_id = emp.id and work_date = d; cleared := cleared + 1;
    else
      if not exists (select 1 from console.hrms_shifts where id = sh and customer_id = cid) then continue; end if;
      insert into console.hrms_roster (customer_id, employee_id, work_date, shift_id, sample) values (cid, emp.id, d, sh, emp.sample)
      on conflict (employee_id, work_date) do update set shift_id = excluded.shift_id, updated_at = now();
      saved := saved + 1;
    end if;
  end loop;
  return jsonb_build_object('saved', saved, 'cleared', cleared, 'locked', locked);
end $$;
revoke all on function public.kmr_hrms_roster_save(text, jsonb) from public, anon;
grant execute on function public.kmr_hrms_roster_save(text, jsonb) to authenticated;
