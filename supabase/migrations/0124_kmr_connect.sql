-- =====================================================================
-- 0124 — KMR Connect — a new KMR app, company level (our own AnyDesk / UltraViewer + video meeting)
--  • Remote devices: a laptop / PC runs the small KMR Connect helper, is paired once with a code, and then can be seen and controlled
--    (screen, mouse, keyboard, files, programs) from any browser or phone after the KMR sign-in. Every session is written to an audit list.
--  • Meetings: video room inside KMR Apps (free, peer to peer) or a Microsoft Teams / Google Meet link; recording with voice;
--    every spoken line is typed out in the speaker's own language and can be sent to Minutes Of Meetings as minutes.
-- Needs 0048 (qp_*), 0056 (require_feature), 0066 (Minutes Of Meetings), 0091 / 0113 (portal patch anchors). Safe to re-run.
-- =====================================================================

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('connect', 'KMR Connect', 'Remote screen control of laptops and PCs, video meetings with Teams / Google Meet links, recording and automatic minutes in many languages', '/it/connect.html', 'users', '1.0.0', 170)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;

insert into console.releases (product_code, version, notes) values
  ('connect', '1.0.0', 'KMR Connect: paired remote devices with screen, mouse, keyboard, files and programs; video room, Teams / Google Meet links, recording, voice typed in every language, minutes sent to Minutes Of Meetings; standards alignment')
on conflict do nothing;

insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0124) — change in Console • Billing'
  from (values ('connect', 'month', 2000), ('connect', 'year', 20000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;

insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('connect', 'KMR Connect', 'See and control your laptops from anywhere, and meet online with recording and automatic minutes in your language.',
   E'Remote screen, mouse, keyboard, files and programs on paired laptops and PCs\nVideo meeting room inside KMR Apps, with Microsoft Teams and Google Meet links\nMeeting recording with voice and every spoken line typed out in many languages\nOne click to send the talk to Minutes Of Meetings', 170, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);

insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('connect', 'Video meetings', 'Video room, Teams and Google Meet links, meeting list and attendance', true, 1000, 0, 5000, 10),
  ('connect', 'Remote devices', 'Pair laptops and PCs and work on them from a browser: screen, mouse, keyboard, files, programs; audit list of every session', false, 1000, 0, 5000, 20),
  ('connect', 'Recording and minutes', 'Record the meeting with voice, type every spoken line in the speaker''s language, send it to Minutes Of Meetings', false, 800, 0, 5000, 30)
on conflict (product_code, name) do nothing;
update console.app_features set price_year = price_month * 10 where product_code = 'connect' and price_year = 0;
select console.sync_app_price('connect');

-- ---------- tables ----------
create table if not exists console.cn_counters (
  customer_id uuid not null references console.customers(id) on delete cascade, key text not null, n bigint not null default 0, sample boolean not null default false,
  primary key (customer_id, key));

create table if not exists console.cn_devices (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  name text not null, os_name text, plant text, secret text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  pair_hash text, pair_expires timestamptz, pair_tries int not null default 0, token_hash text,
  status text not null default 'waiting' check (status in ('waiting', 'paired', 'disabled')),
  last_seen timestamptz, info jsonb not null default '{}', sample boolean not null default false,
  created_by text, created_at timestamptz not null default now(),
  unique (customer_id, name));

create table if not exists console.cn_sessions (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  device_id uuid references console.cn_devices(id) on delete set null, device_name text,
  started_by text not null, started_at timestamptz not null default now(), ended_at timestamptz, note text, sample boolean not null default false);

create table if not exists console.cn_meetings (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  meeting_no text not null, title text not null, scheduled_at timestamptz, provider text not null default 'kmr' check (provider in ('kmr', 'teams', 'meet')),
  ext_url text, room_key text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), language text not null default 'en-IN',
  attendees jsonb not null default '[]', agenda text,
  status text not null default 'planned' check (status in ('planned', 'live', 'ended', 'void')),
  started_at timestamptz, ended_at timestamptz, mom_id uuid references console.mom_meetings(id) on delete set null,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (customer_id, meeting_no));

create table if not exists console.cn_segments (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  meeting_id uuid not null references console.cn_meetings(id) on delete cascade, client_id text not null,
  speaker text, lang text, text text not null, spoken_at timestamptz not null default now(), sample boolean not null default false,
  created_by text, created_at timestamptz not null default now(), unique (meeting_id, client_id));

create table if not exists console.cn_recordings (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  meeting_id uuid not null references console.cn_meetings(id) on delete cascade, path text not null, mime text, bytes bigint, seconds int,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now());

create index if not exists cn_meet_date on console.cn_meetings (customer_id, scheduled_at desc);
create index if not exists cn_seg_meet on console.cn_segments (meeting_id, spoken_at);
create index if not exists cn_sess_dev on console.cn_sessions (customer_id, started_at desc);
do $$ declare t text; begin foreach t in array array['cn_counters','cn_devices','cn_sessions','cn_meetings','cn_segments','cn_recordings'] loop
  execute format('alter table console.%I enable row level security', t);
  execute format('drop policy if exists %I on console.%I', t || '_staff', t);
  execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
end loop; end $$;

-- recordings are kept in a private storage bucket, one folder per company: <customer id>/<meeting id>/<file>
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-recordings', 'kmr-recordings', false, 52428800) on conflict (id) do nothing;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_rec_insert on storage.objects';
    execute $p$create policy kmr_rec_insert on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-recordings' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
      and console.qp_role(((storage.foldername(name))[1])::uuid, 'connect') is not null)$p$;
    execute 'drop policy if exists kmr_rec_select on storage.objects';
    execute $p$create policy kmr_rec_select on storage.objects for select to authenticated using (
      bucket_id = 'kmr-recordings' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
      and console.qp_role(((storage.foldername(name))[1])::uuid, 'connect') is not null)$p$;
    execute 'drop policy if exists kmr_rec_delete on storage.objects';
    execute $p$create policy kmr_rec_delete on storage.objects for delete to authenticated using (
      bucket_id = 'kmr-recordings' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
      and console.is_customer_admin(((storage.foldername(name))[1])::uuid))$p$;
  end if;
end $$;

-- ---------- helpers ----------
create or replace function console.cn_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.cn_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.cn_counters.n + 1 returning n $$;
revoke all on function console.cn_next(uuid, text) from public, anon, authenticated;

create or replace function console.cn_sha(p_text text) returns text language sql immutable as $$ select encode(sha256(convert_to(coalesce(p_text, ''), 'utf8')), 'hex') $$;
revoke all on function console.cn_sha(text) from public, anon, authenticated;

-- a pairing code people can read out: 4 + 4 letters and digits without look-alikes
create or replace function console.cn_code() returns text language plpgsql volatile as $$
declare chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; out text := ''; i int; b bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
begin
  for i in 0..7 loop out := out || substr(chars, (get_byte(b, i) % 32) + 1, 1); if i = 3 then out := out || '-'; end if; end loop;
  return out;
end $$;
revoke all on function console.cn_code() from public, anon, authenticated;

create or replace function console.cn_dev_view(p_id uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select to_jsonb(d) - 'customer_id' - 'secret' - 'pair_hash' - 'token_hash' - 'pair_tries' || jsonb_build_object(
    'online', d.last_seen is not null and d.last_seen > now() - interval '90 seconds') from console.cn_devices d where d.id = p_id $$;
revoke all on function console.cn_dev_view(uuid) from public, anon, authenticated;

create or replace function console.cn_meet_view(p_id uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select to_jsonb(m) - 'customer_id' - 'room_key' || jsonb_build_object(
    'lines', (select count(*) from console.cn_segments s where s.meeting_id = m.id),
    'recordings', (select count(*) from console.cn_recordings r where r.meeting_id = m.id))
  from console.cn_meetings m where m.id = p_id $$;
revoke all on function console.cn_meet_view(uuid) from public, anon, authenticated;

-- ---------- sign-in context + load ----------
create or replace function public.kmr_cn_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'connect') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'connect'), 'cid', c.id, 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false),
      'has_mom', console.has_app(c.id, 'mom'), 'email', lower(coalesce(auth.jwt() ->> 'email', ''))) end
  from console.customers c where c.slug = lower(p_slug) $$;

create or replace function public.kmr_cn_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect');
begin
  return jsonb_build_object(
    'devices', coalesce((select jsonb_agg(console.cn_dev_view(d.id) order by d.name) from console.cn_devices d where d.customer_id = cid), '[]'),
    'meetings', coalesce((select jsonb_agg(console.cn_meet_view(m.id) order by m.scheduled_at desc nulls last, m.meeting_no desc) from (select id, scheduled_at, meeting_no from console.cn_meetings where customer_id = cid and status <> 'void' order by scheduled_at desc nulls last, meeting_no desc limit 100) m), '[]'),
    'sessions', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.started_at desc) from (select * from console.cn_sessions where customer_id = cid order by started_at desc limit 60) s), '[]'),
    'people', coalesce((select jsonb_agg(jsonb_build_object('email', m.email) order by m.email) from console.customer_members m where m.customer_id = cid), '[]'),
    'today', (now() at time zone 'Asia/Kolkata')::date);
end $$;

-- ---------- remote devices ----------
create or replace function public.kmr_cn_device_add(p_slug text, p_name text, p_os text, p_plant text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); v_id uuid; code text := console.cn_code(); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can add a device.'; end if;
  perform console.require_feature(p_slug, 'connect', 'connect.remote-devices');
  if coalesce(trim(p_name), '') = '' then raise exception 'Enter a name for the device, for example “Accounts laptop”.'; end if;
  if exists (select 1 from console.cn_devices where customer_id = cid and lower(name) = lower(trim(p_name))) then raise exception 'A device with this name already exists.'; end if;
  insert into console.cn_devices (customer_id, name, os_name, plant, pair_hash, pair_expires, created_by)
  values (cid, trim(p_name), nullif(trim(coalesce(p_os, '')), ''), nullif(trim(coalesce(p_plant, '')), ''), console.cn_sha(code), now() + interval '2 hours', me) returning id into v_id;
  return jsonb_build_object('id', v_id, 'pair_code', code);
end $$;

create or replace function public.kmr_cn_device_repair(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); code text := console.cn_code();
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can pair a device again.'; end if;
  update console.cn_devices set pair_hash = console.cn_sha(code), pair_expires = now() + interval '2 hours', pair_tries = 0, token_hash = null, status = 'waiting',
         secret = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where id = p_id and customer_id = cid;
  if not found then raise exception 'Device not found.'; end if;
  return jsonb_build_object('id', p_id, 'pair_code', code);
end $$;

create or replace function public.kmr_cn_device_status(p_slug text, p_id uuid, p_status text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect');
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can switch a device on or off.'; end if;
  if p_status not in ('paired', 'disabled') then raise exception 'Unknown status.'; end if;
  update console.cn_devices set status = case when p_status = 'paired' and token_hash is null then 'waiting' else p_status end where id = p_id and customer_id = cid;
end $$;

create or replace function public.kmr_cn_device_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect');
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can remove a device.'; end if;
  delete from console.cn_devices where id = p_id and customer_id = cid;
end $$;

-- the helper on the laptop pairs with the code shown in the app (called without a sign-in, so it is guarded: 2 hours, 5 tries)
create or replace function public.kmr_cn_agent_pair(p_device uuid, p_code text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d console.cn_devices%rowtype; tok text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  select * into d from console.cn_devices where id = p_device for update;
  if not found or d.pair_hash is null or d.pair_expires is null or d.pair_expires < now() then raise exception 'This pairing code is not valid any more. Ask the administrator for a new one.'; end if;
  if d.pair_tries >= 5 then return jsonb_build_object('error', 'Too many wrong tries. Ask the administrator for a new code.'); end if;
  if d.pair_hash <> console.cn_sha(upper(replace(coalesce(p_code, ''), ' ', ''))) then   -- answered, not raised, so the count of wrong tries is kept
    update console.cn_devices set pair_tries = pair_tries + 1 where id = d.id; return jsonb_build_object('error', 'The pairing code is wrong.'); end if;
  update console.cn_devices set token_hash = console.cn_sha(tok), pair_hash = null, pair_expires = null, pair_tries = 0, status = 'paired', last_seen = now() where id = d.id;
  return jsonb_build_object('device', d.id, 'token', tok, 'secret', d.secret, 'name', d.name, 'company', (select name from console.customers where id = d.customer_id));
end $$;

-- the helper tells the platform every 30 seconds that it is awake; it gets back whether it may be used
create or replace function public.kmr_cn_agent_ping(p_device uuid, p_token text, p_info jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d console.cn_devices%rowtype;
begin
  select * into d from console.cn_devices where id = p_device;
  if not found or d.token_hash is null or d.token_hash <> console.cn_sha(p_token) then return jsonb_build_object('ok', false, 'reason', 'unknown'); end if;
  if d.status = 'disabled' then return jsonb_build_object('ok', false, 'reason', 'disabled'); end if;
  update console.cn_devices set last_seen = now(), info = coalesce(p_info, info) where id = d.id;
  return jsonb_build_object('ok', true, 'secret', d.secret);
end $$;
revoke all on function public.kmr_cn_agent_pair(uuid, text), public.kmr_cn_agent_ping(uuid, text, jsonb) from public;
grant execute on function public.kmr_cn_agent_pair(uuid, text), public.kmr_cn_agent_ping(uuid, text, jsonb) to anon, authenticated;

-- open a remote session: gives the private channel name and writes the audit line
create or replace function public.kmr_cn_connect(p_slug text, p_device uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'connect'); d console.cn_devices%rowtype; sid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  perform console.require_feature(p_slug, 'connect', 'connect.remote-devices');
  select * into d from console.cn_devices where id = p_device and customer_id = cid;
  if not found then raise exception 'Device not found.'; end if;
  if d.status <> 'paired' then raise exception 'This device is not paired or has been switched off.'; end if;
  insert into console.cn_sessions (customer_id, device_id, device_name, started_by) values (cid, d.id, d.name, me) returning id into sid;
  return jsonb_build_object('secret', d.secret, 'session', sid, 'name', d.name);
end $$;

create or replace function public.kmr_cn_session_end(p_slug text, p_session uuid, p_note text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect');
begin
  update console.cn_sessions set ended_at = coalesce(ended_at, now()), note = coalesce(nullif(left(trim(coalesce(p_note, '')), 500), ''), note)
   where id = p_session and customer_id = cid and started_by = lower(coalesce(auth.jwt() ->> 'email', ''));
end $$;

-- ---------- meetings ----------
create or replace function public.kmr_cn_meeting_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'connect'); v_id uuid := nullif(p ->> 'id', '')::uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); no text; prov text := coalesce(nullif(p ->> 'provider', ''), 'kmr');
        at timestamptz := nullif(p ->> 'scheduled_at', '')::timestamptz; url text := nullif(trim(coalesce(p ->> 'ext_url', '')), '');
begin
  if prov not in ('kmr', 'teams', 'meet') then raise exception 'Choose KMR video room, Microsoft Teams or Google Meet.'; end if;
  if prov <> 'kmr' and url is not null and url !~* '^https://' then raise exception 'The meeting link must start with https://'; end if;
  if v_id is null then
    if coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter the meeting title.'; end if;
    no := 'CN-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMM') || '-' || lpad(console.cn_next(cid, 'CN-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMM'))::text, 4, '0');
    insert into console.cn_meetings (customer_id, meeting_no, title, scheduled_at, provider, ext_url, language, attendees, agenda, created_by)
    values (cid, no, trim(p ->> 'title'), coalesce(at, now()), prov, url, coalesce(nullif(trim(p ->> 'language'), ''), 'en-IN'),
            coalesce(case when jsonb_typeof(p -> 'attendees') = 'array' then p -> 'attendees' end, '[]'), nullif(trim(coalesce(p ->> 'agenda', '')), ''), me) returning id into v_id;
  else
    if not exists (select 1 from console.cn_meetings where id = v_id and customer_id = cid and status in ('planned', 'live')) then raise exception 'Meeting not found or already ended.'; end if;
    update console.cn_meetings set title = coalesce(nullif(trim(p ->> 'title'), ''), title), scheduled_at = coalesce(at, scheduled_at), provider = prov, ext_url = url,
      language = coalesce(nullif(trim(p ->> 'language'), ''), language), attendees = case when jsonb_typeof(p -> 'attendees') = 'array' then p -> 'attendees' else attendees end,
      agenda = case when p ? 'agenda' then nullif(trim(coalesce(p ->> 'agenda', '')), '') else agenda end, updated_at = now() where id = v_id;
  end if;
  return console.cn_meet_view(v_id);
end $$;

create or replace function public.kmr_cn_meeting_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); m console.cn_meetings%rowtype;
begin
  select * into m from console.cn_meetings where id = p_id and customer_id = cid;
  if not found then raise exception 'Meeting not found.'; end if;
  return jsonb_build_object('meeting', console.cn_meet_view(p_id), 'room', case when m.provider = 'kmr' then m.room_key end,
    'segments', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.spoken_at, s.created_at) from console.cn_segments s where s.meeting_id = p_id), '[]'),
    'recordings', coalesce((select jsonb_agg(to_jsonb(r) - 'customer_id' order by r.created_at) from console.cn_recordings r where r.meeting_id = p_id), '[]'));
end $$;

create or replace function public.kmr_cn_meeting_state(p_slug text, p_id uuid, p_state text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'connect');
begin
  if p_state not in ('live', 'ended') then raise exception 'Unknown state.'; end if;
  update console.cn_meetings set status = p_state, started_at = case when p_state = 'live' then coalesce(started_at, now()) else started_at end,
         ended_at = case when p_state = 'ended' then now() else ended_at end, updated_at = now() where id = p_id and customer_id = cid and status in ('planned', 'live');
  return console.cn_meet_view(p_id);
end $$;

create or replace function public.kmr_cn_meeting_void(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect');
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can delete a meeting.'; end if;
  update console.cn_meetings set status = 'void', updated_at = now() where id = p_id and customer_id = cid;
end $$;

-- every person in the room saves the lines they spoke (typed out on their own device in their own language)
create or replace function public.kmr_cn_seg_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); mid uuid := nullif(p ->> 'meeting_id', '')::uuid; g jsonb; me text := lower(coalesce(auth.jwt() ->> 'email', '')); n int := 0;
begin
  perform console.require_feature(p_slug, 'connect', 'connect.recording-and-minutes');
  if not exists (select 1 from console.cn_meetings where id = mid and customer_id = cid and status in ('planned', 'live')) then raise exception 'Meeting not found or already ended.'; end if;
  if jsonb_typeof(p -> 'segs') <> 'array' then raise exception 'Nothing to save.'; end if;
  if jsonb_array_length(p -> 'segs') > 200 then raise exception 'Too many lines in one save.'; end if;
  for g in select * from jsonb_array_elements(p -> 'segs') loop
    if coalesce(trim(g ->> 'client_id'), '') = '' or coalesce(trim(g ->> 'text'), '') = '' then continue; end if;
    insert into console.cn_segments (customer_id, meeting_id, client_id, speaker, lang, text, spoken_at, created_by)
    values (cid, mid, g ->> 'client_id', nullif(trim(coalesce(g ->> 'speaker', '')), ''), nullif(trim(coalesce(g ->> 'lang', '')), ''), left(trim(g ->> 'text'), 5000), coalesce(nullif(g ->> 'spoken_at', '')::timestamptz, now()), me)
    on conflict (meeting_id, client_id) do nothing;
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n);
end $$;

create or replace function public.kmr_cn_rec_add(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); mid uuid := nullif(p ->> 'meeting_id', '')::uuid; rid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  perform console.require_feature(p_slug, 'connect', 'connect.recording-and-minutes');
  if not exists (select 1 from console.cn_meetings where id = mid and customer_id = cid) then raise exception 'Meeting not found.'; end if;
  if split_part(coalesce(p ->> 'path', ''), '/', 1) <> cid::text then raise exception 'The recording must be saved in your company folder.'; end if;
  insert into console.cn_recordings (customer_id, meeting_id, path, mime, bytes, seconds, created_by)
  values (cid, mid, p ->> 'path', p ->> 'mime', nullif(p ->> 'bytes', '')::bigint, nullif(p ->> 'seconds', '')::int, me) returning id into rid;
  return jsonb_build_object('id', rid);
end $$;

create or replace function public.kmr_cn_rec_delete(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'connect'); pth text;
begin
  if not console.is_customer_admin(cid) and not coalesce(console.is_staff(), false) then raise exception 'Only the company administrator can delete a recording.'; end if;
  delete from console.cn_recordings where id = p_id and customer_id = cid returning path into pth;
  return pth;
end $$;

-- send the talk to Minutes Of Meetings: a new minutes record with every spoken line, ready for 5W1H points
create or replace function public.kmr_cn_to_mom(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'connect'); m console.cn_meetings%rowtype; mid uuid; no text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
        md date; att jsonb;
begin
  perform console.require_feature(p_slug, 'connect', 'connect.recording-and-minutes');
  if not console.has_app(cid, 'mom') then raise exception 'Minutes Of Meetings is not part of your subscription. To add it, contact KMR Group of Companies - www.kmr-groups.com/contact.'; end if;
  if console.qp_role(cid, 'mom') is null then raise exception 'You have no access to Minutes Of Meetings.'; end if;
  select * into m from console.cn_meetings where id = p_id and customer_id = cid for update;
  if not found then raise exception 'Meeting not found.'; end if;
  if m.mom_id is not null and exists (select 1 from console.mom_meetings where id = m.mom_id) then return jsonb_build_object('mom_id', m.mom_id, 'already', true); end if;
  md := (coalesce(m.started_at, m.scheduled_at, now()) at time zone 'Asia/Kolkata')::date;
  no := 'MOM-' || to_char(md, 'YYMM') || '-' || lpad(console.mom_next(cid, 'MOM-' || to_char(md, 'YYMM'))::text, 4, '0');
  att := coalesce((select jsonb_agg(jsonb_build_object('name', a ->> 'email', 'present', true)) from jsonb_array_elements(case when jsonb_typeof(m.attendees) = 'array' then m.attendees else '[]'::jsonb end) a), '[]');
  insert into console.mom_meetings (customer_id, meeting_no, title, mtype, meeting_date, start_time, end_time, venue, language, attendees, agenda, created_by)
  values (cid, no, m.title, 'Other', md, to_char(m.started_at at time zone 'Asia/Kolkata', 'HH24:MI'), to_char(m.ended_at at time zone 'Asia/Kolkata', 'HH24:MI'),
          case m.provider when 'teams' then 'Microsoft Teams' when 'meet' then 'Google Meet' else 'KMR Connect video room' end, m.language, att, m.agenda, me) returning id into mid;
  insert into console.mom_segments (customer_id, meeting_id, client_id, lang, text, spoken_at, speaker, created_by)
  select cid, mid, s.client_id, s.lang, s.text, s.spoken_at, s.speaker, me from console.cn_segments s where s.meeting_id = m.id order by s.spoken_at;
  update console.cn_meetings set mom_id = mid, updated_at = now() where id = m.id;
  return jsonb_build_object('mom_id', mid, 'meeting_no', no);
end $$;

-- ---------- who may call what ----------
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname like 'kmr\_cn\_%' and p.proname not in ('kmr_cn_agent_pair', 'kmr_cn_agent_ping') loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- ---------- platform functions: Data Master, clear-data, apps list in the portal ----------
do $wrap$ begin
  if to_regprocedure('console.app2_tables_cn_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_cn_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''connect'' then array[''cn_counters'',''cn_devices'',''cn_sessions'',''cn_meetings'',''cn_segments'',''cn_recordings''] else console.app2_tables_cn_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_cn_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_cn_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint := 0; m bigint;
    begin
      if p_app = 'connect' then
        if p_real_only then return 0; end if;          -- no sample data in this app: only a full clear removes the records
        delete from console.cn_recordings where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.cn_segments where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.cn_meetings where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.cn_sessions where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.cn_devices where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.cn_counters where customer_id = p_cid;
        return n;
      end if;
      return console.app2_clear_cn_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_cn_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;

do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join')
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''connect''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'dwm'\s+then console\.qp_member\(([a-z_.]+), em, 'dwm'\))$re$, E'\\1when ''connect'' then console.qp_member(\\3, em, ''connect'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'KMR Connect: % portal functions updated', n;
end $patch$;
