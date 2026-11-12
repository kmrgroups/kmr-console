-- Calibration Hub 0101 — the alert / test mail carries the customer's own name, logo and plant details (not KMR's). Needs 0098 and 0100. Safe to re-run.
create or replace function console.cal_brand(p_customer uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object(
    'name', coalesce(par.name, c.name),
    'plant', case when par.id is not null then coalesce(nullif(c.plant_code, ''), '') || case when nullif(c.plant_code, '') is not null and nullif(c.name, '') is not null then ' · ' else '' end || coalesce(nullif(trim(split_part(c.name, ' – ', 2)), ''), c.name) else null end,
    'logo', coalesce(nullif(c.logo_url, ''), nullif(par.logo_url, ''), ''),
    'address', concat_ws(', ', nullif(c.address, ''), nullif(c.city, ''), nullif(c.state, ''), nullif(c.postal_code, '')),
    'email', coalesce(nullif(c.contact_email, ''), nullif(par.contact_email, ''), ''),
    'phone', coalesce(nullif(c.contact_phone, ''), nullif(par.contact_phone, ''), ''))
  from console.customers c left join console.customers par on par.id = c.parent_id where c.id = p_customer;
$$;
revoke all on function console.cal_brand(uuid) from public, anon, authenticated;

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
       and i.alert_sent_due is distinct from i.next_due;
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

create or replace function public.kmr_cal_test_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.cal_admin(p_slug); d0 date := (now() at time zone 'Asia/Kolkata')::date; dy int; rws jsonb; cname text;
begin
  select coalesce((select days_before from console.cal_alert_settings where customer_id = cid), 12) into dy;
  select name into cname from console.customers where id = cid;
  select coalesce(jsonb_agg(jsonb_build_object('tag', i.tag, 'name', i.name, 'gauge_class', i.gauge_class, 'department', i.department, 'location', i.location, 'supplier', i.supplier,
                                               'next_due', i.next_due, 'days_left', i.next_due - d0) order by i.next_due, i.tag), '[]')
    into rws from console.cal_instruments i
   where i.customer_id = cid and i.status = 'In use' and i.next_due is not null and i.next_due >= d0 and i.next_due <= d0 + dy;
  return jsonb_build_object('slug', lower(p_slug), 'company', cname, 'brand', console.cal_brand(cid), 'days_before', dy, 'me', lower(coalesce(auth.jwt() ->> 'email', '')), 'rows', rws);
end $$;
grant execute on function public.kmr_cal_test_list(text) to authenticated;
