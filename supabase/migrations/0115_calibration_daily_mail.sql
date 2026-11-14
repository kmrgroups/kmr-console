-- Calibration Hub 0115 — the due-date mail goes out EVERY morning (not once per due date): every gauge that is still inside the alert window (due within N days) is listed each day until it is calibrated. Needs 0101. Safe to re-run.
create or replace function public.kmr_cal_due_scan() returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d0 date := (now() at time zone 'Asia/Kolkata')::date; res jsonb := '[]'; s record; rws jsonb; rcp text[];
begin
  for s in select a.customer_id, a.days_before, a.recipients, a.include_users, c.slug, c.name as company
             from console.cal_alert_settings a join console.customers c on c.id = a.customer_id where a.enabled loop
    if not coalesce((select ok from console.access_state('calib', s.customer_id)), false) then continue; end if;
    select jsonb_agg(jsonb_build_object('id', i.id, 'tag', i.tag, 'name', i.name, 'gauge_class', i.gauge_class, 'department', i.department, 'location', i.location, 'supplier', i.supplier,
                                        'next_due', i.next_due, 'days_left', i.next_due - d0) order by i.next_due, i.tag)
      into rws
      from console.cal_instruments i
     where i.customer_id = s.customer_id and i.status = 'In use' and i.next_due is not null and i.next_due >= d0 and i.next_due <= d0 + s.days_before
;
    continue when rws is null;
    select coalesce(array_agg(distinct z.e), '{}') into rcp from (
      select lower(trim(x)) as e from regexp_split_to_table(coalesce(s.recipients, ''), '[,;[:space:]]+') as x
      union
      select m.email as e from console.customer_members m where s.include_users and m.customer_id = s.customer_id and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')) z
     where z.e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$';
    continue when coalesce(array_length(rcp, 1), 0) = 0;
    res := res || jsonb_build_array(jsonb_build_object('customer_id', s.customer_id, 'slug', s.slug, 'company', s.company, 'brand', console.cal_brand(s.customer_id), 'days_before', s.days_before, 'recipients', to_jsonb(rcp), 'rows', rws));
  end loop;
  return res;
end $$;
revoke all on function public.kmr_cal_due_scan() from public, anon, authenticated;
grant execute on function public.kmr_cal_due_scan() to service_role;
