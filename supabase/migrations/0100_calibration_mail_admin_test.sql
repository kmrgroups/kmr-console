-- Calibration Hub 0100 — the mail alert screen is for administrators only, and a "send test mail" lists today's upcoming-due gauges to one address without marking anything as mailed. Needs 0098. Safe to re-run.
create or replace function console.cal_admin(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is distinct from 'admin' then raise exception 'Only an administrator can use the mail alert.'; end if;
  return cid;
end $$;
revoke all on function console.cal_admin(text) from public, anon, authenticated;

create or replace function public.kmr_cal_alert_get(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; s console.cal_alert_settings;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is distinct from 'admin' then raise exception 'Only an administrator can open the mail alert.'; end if;
  select * into s from console.cal_alert_settings where customer_id = cid;
  return jsonb_build_object('enabled', coalesce(s.enabled, false), 'days_before', coalesce(s.days_before, 12), 'recipients', coalesce(s.recipients, ''), 'include_users', coalesce(s.include_users, false),
    'users', coalesce((select jsonb_agg(m.email order by m.email) from console.customer_members m where m.customer_id = cid and m.email is not null and (m.is_admin or coalesce(m.roles ->> 'calib', '') <> '')), '[]'),
    'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
create or replace function public.kmr_cal_alert_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_admin(p_slug); d int := coalesce(nullif(p ->> 'days_before', '')::int, 12); en boolean := coalesce(p ->> 'enabled', '') in ('true', 't', '1');
  iu boolean := coalesce(p ->> 'include_users', '') in ('true', 't', '1'); rc text := lower(trim(coalesce(p ->> 'recipients', '')));
begin
  if d < 1 or d > 365 then raise exception 'Days before due must be between 1 and 365.'; end if;
  if en and rc = '' and not iu then raise exception 'Add at least one e-mail address, or tick "all Calibration Hub users".'; end if;
  insert into console.cal_alert_settings (customer_id, enabled, days_before, recipients, include_users, updated_at, updated_by)
  values (cid, en, d, rc, iu, now(), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id) do update set enabled = excluded.enabled, days_before = excluded.days_before, recipients = excluded.recipients, include_users = excluded.include_users, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;

-- the gauges inside the alert window today (mailed or not), for the "send test mail" button — administrator only
create or replace function public.kmr_cal_test_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.cal_admin(p_slug); d0 date := (now() at time zone 'Asia/Kolkata')::date; dy int; rws jsonb; cname text;
begin
  select coalesce((select days_before from console.cal_alert_settings where customer_id = cid), 12) into dy;
  select name into cname from console.customers where id = cid;
  select coalesce(jsonb_agg(jsonb_build_object('tag', i.tag, 'name', i.name, 'gauge_class', i.gauge_class, 'department', i.department, 'location', i.location, 'supplier', i.supplier,
                                               'next_due', i.next_due, 'days_left', i.next_due - d0) order by i.next_due, i.tag), '[]')
    into rws from console.cal_instruments i
   where i.customer_id = cid and i.status = 'In use' and i.next_due is not null and i.next_due >= d0 and i.next_due <= d0 + dy;
  return jsonb_build_object('slug', lower(p_slug), 'company', cname, 'days_before', dy, 'me', lower(coalesce(auth.jwt() ->> 'email', '')), 'rows', rws);
end $$;
grant execute on function public.kmr_cal_alert_get(text), public.kmr_cal_alert_save(text, jsonb), public.kmr_cal_test_list(text) to authenticated;
