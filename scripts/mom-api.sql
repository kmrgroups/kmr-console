-- ---------- helpers ----------
create or replace function console.mom_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.mom_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.mom_counters.n + 1 returning n $$;
revoke all on function console.mom_next(uuid, text) from public, anon, authenticated;

-- one meeting with its point counts
create or replace function console.mom_view(p_id uuid) returns jsonb language sql stable security definer set search_path = console, public as $$
  select to_jsonb(m) - 'customer_id' || jsonb_build_object(
    'points', (select count(*) from console.mom_points p where p.meeting_id = m.id),
    'open_points', (select count(*) from console.mom_points p where p.meeting_id = m.id and p.status in ('Open', 'In progress')),
    'done_points', (select count(*) from console.mom_points p where p.meeting_id = m.id and p.status = 'Done'),
    'segments', (select count(*) from console.mom_segments s where s.meeting_id = m.id))
  from console.mom_meetings m where m.id = p_id $$;
revoke all on function console.mom_view(uuid) from public, anon, authenticated;

-- ---------- reads ----------
create or replace function public.kmr_mom_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mom');
begin
  return jsonb_build_object(
    'meetings', coalesce((select jsonb_agg(console.mom_view(m.id) order by m.meeting_date desc, m.meeting_no desc) from (select id, meeting_date, meeting_no from console.mom_meetings where customer_id = cid order by meeting_date desc, meeting_no desc limit 1000) m), '[]'),
    'people', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name, 'role', r.data ->> 'cft_role', 'function', r.data ->> 'function', 'email', r.data ->> 'email') order by r.name) from console.ops_records r where r.customer_id = cid and r.kind = 'cft' and r.active), '[]'),
    'today', (now() at time zone 'Asia/Kolkata')::date);
end $$;

create or replace function public.kmr_mom_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mom');
begin
  if not exists (select 1 from console.mom_meetings where id = p_id and customer_id = cid) then raise exception 'Meeting not found.'; end if;
  return jsonb_build_object('meeting', console.mom_view(p_id),
    'points', coalesce((select jsonb_agg(to_jsonb(p) - 'customer_id' order by p.seq, p.created_at) from console.mom_points p where p.meeting_id = p_id), '[]'),
    'segments', coalesce((select jsonb_agg(to_jsonb(s) - 'customer_id' order by s.spoken_at, s.created_at) from console.mom_segments s where s.meeting_id = p_id), '[]'));
end $$;

-- open actions across all meetings
create or replace function public.kmr_mom_actions(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mom');
begin
  perform console.require_feature(p_slug, 'mom', 'mom.action-tracker');
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'meeting_id', m.id, 'meeting_no', m.meeting_no, 'meeting_date', m.meeting_date, 'topic', p.topic, 'what', p.what, 'who', p.who,
           'due_on', p.when_on, 'status', p.status, 'ptype', p.ptype, 'where_at', p.where_at) order by p.when_on nulls last, m.meeting_date)
      from console.mom_points p join console.mom_meetings m on m.id = p.meeting_id
     where p.customer_id = cid and m.status <> 'void' and p.status in ('Open', 'In progress') and p.ptype in ('Action', 'Decision', 'Risk / concern', 'Query')), '[]');
end $$;

-- ---------- meetings ----------
create or replace function public.kmr_mom_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); v_id uuid := nullif(p ->> 'id', '')::uuid; m console.mom_meetings%rowtype; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
        md date := nullif(p ->> 'meeting_date', '')::date; stt text := nullif(trim(coalesce(p ->> 'start_time', '')), ''); ent text := nullif(trim(coalesce(p ->> 'end_time', '')), ''); no text;
begin
  if jsonb_typeof(p -> 'attendees') not in ('array') and p ? 'attendees' then raise exception 'Attendees must be a list.'; end if;
  if v_id is null then
    if coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter the meeting title.'; end if;
    if md is null then raise exception 'Enter the meeting date.'; end if;
  else
    select * into m from console.mom_meetings where id = v_id and customer_id = cid for update;
    if not found then raise exception 'Meeting not found.'; end if;
    if m.status <> 'open' then raise exception 'This meeting is finalised. Re-open it to change the details.'; end if;
    if p ? 'title' and coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter the meeting title.'; end if;
    if p ? 'meeting_date' and md is null then raise exception 'Enter the meeting date.'; end if;
  end if;
  if (stt is not null and stt !~ '^\d{2}:\d{2}') or (ent is not null and ent !~ '^\d{2}:\d{2}') then raise exception 'Enter the time as HH:MM.'; end if;
  stt := left(stt, 5); ent := left(ent, 5);
  if stt is not null and ent is not null and ent < stt then raise exception 'End time is before start time.'; end if;
  if v_id is null then
    no := 'MOM-' || to_char(md, 'YYMM') || '-' || lpad(console.mom_next(cid, 'MOM-' || to_char(md, 'YYMM'))::text, 4, '0');
    insert into console.mom_meetings (customer_id, meeting_no, title, mtype, meeting_date, start_time, end_time, venue, chairperson, scribe, language, attendees, agenda, prev_ref, next_date, distribution, created_by)
    values (cid, no, trim(p ->> 'title'), nullif(trim(coalesce(p ->> 'mtype', '')), ''), md, stt, ent, nullif(trim(coalesce(p ->> 'venue', '')), ''), nullif(trim(coalesce(p ->> 'chairperson', '')), ''), nullif(trim(coalesce(p ->> 'scribe', '')), ''),
            coalesce(nullif(trim(p ->> 'language'), ''), 'en-IN'), coalesce(case when jsonb_typeof(p -> 'attendees') = 'array' then p -> 'attendees' end, '[]'), nullif(trim(coalesce(p ->> 'agenda', '')), ''), nullif(trim(coalesce(p ->> 'prev_ref', '')), ''),
            nullif(p ->> 'next_date', '')::date, nullif(trim(coalesce(p ->> 'distribution', '')), ''), me) returning id into v_id;
  else
    update console.mom_meetings set
      title = case when p ? 'title' then trim(p ->> 'title') else title end, mtype = case when p ? 'mtype' then nullif(trim(coalesce(p ->> 'mtype', '')), '') else mtype end,
      meeting_date = coalesce(md, meeting_date), start_time = case when p ? 'start_time' then stt else start_time end, end_time = case when p ? 'end_time' then ent else end_time end,
      venue = case when p ? 'venue' then nullif(trim(coalesce(p ->> 'venue', '')), '') else venue end, chairperson = case when p ? 'chairperson' then nullif(trim(coalesce(p ->> 'chairperson', '')), '') else chairperson end,
      scribe = case when p ? 'scribe' then nullif(trim(coalesce(p ->> 'scribe', '')), '') else scribe end, language = coalesce(nullif(trim(p ->> 'language'), ''), language),
      attendees = case when jsonb_typeof(p -> 'attendees') = 'array' then p -> 'attendees' else attendees end, agenda = case when p ? 'agenda' then nullif(trim(coalesce(p ->> 'agenda', '')), '') else agenda end,
      prev_ref = case when p ? 'prev_ref' then nullif(trim(coalesce(p ->> 'prev_ref', '')), '') else prev_ref end, next_date = case when p ? 'next_date' then nullif(p ->> 'next_date', '')::date else next_date end,
      distribution = case when p ? 'distribution' then nullif(trim(coalesce(p ->> 'distribution', '')), '') else distribution end, updated_at = now()
     where id = v_id;
  end if;
  return console.mom_view(v_id);
end $$;

create or replace function public.kmr_mom_close(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  select * into m from console.mom_meetings where id = p_id and customer_id = cid for update;
  if not found or m.status <> 'open' then raise exception 'Only an open meeting can be finalised.'; end if;
  if not exists (select 1 from console.mom_points where meeting_id = p_id) and not exists (select 1 from console.mom_segments where meeting_id = p_id) then raise exception 'Record at least one discussion point before finalising.'; end if;
  update console.mom_meetings set status = 'closed', closed_by = lower(coalesce(auth.jwt() ->> 'email', '')), closed_at = now(), updated_at = now() where id = p_id;
  return console.mom_view(p_id);
end $$;

create or replace function public.kmr_mom_reopen(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  if console.qp_role(cid, 'mom') <> 'admin' then raise exception 'Only an administrator can re-open finalised minutes.'; end if;
  select * into m from console.mom_meetings where id = p_id and customer_id = cid for update;
  if not found or m.status <> 'closed' then raise exception 'Only a finalised meeting can be re-opened.'; end if;
  update console.mom_meetings set status = 'open', closed_by = null, closed_at = null, updated_at = now() where id = p_id;
  return console.mom_view(p_id);
end $$;

create or replace function public.kmr_mom_void(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  if console.qp_role(cid, 'mom') <> 'admin' then raise exception 'Only an administrator can void a meeting.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the meeting.'; end if;
  select * into m from console.mom_meetings where id = p_id and customer_id = cid for update;
  if not found or m.status = 'void' then raise exception 'Meeting not found.'; end if;
  update console.mom_meetings set status = 'void', void_reason = trim(p_reason), updated_at = now() where id = p_id;
end $$;

-- ---------- 5W1H points ----------
create or replace function public.kmr_mom_point_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); v_id uuid := nullif(p ->> 'id', '')::uuid; r console.mom_points%rowtype; m console.mom_meetings%rowtype; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
        st text := nullif(trim(coalesce(p ->> 'status', '')), ''); pt text := nullif(trim(coalesce(p ->> 'ptype', '')), ''); sq int;
begin
  if v_id is not null then
    select * into r from console.mom_points where id = v_id and customer_id = cid for update;
    if not found then raise exception 'Point not found.'; end if;
    select * into m from console.mom_meetings where id = r.meeting_id;
  else
    select * into m from console.mom_meetings where id = nullif(p ->> 'meeting_id', '')::uuid and customer_id = cid for update;
    if not found then raise exception 'Meeting not found.'; end if;
  end if;
  if m.status = 'void' then raise exception 'This meeting is void.'; end if;
  if m.status = 'closed' and v_id is null then raise exception 'This meeting is finalised. Re-open it to add points.'; end if;
  if st is not null and st not in ('Open', 'In progress', 'Done', 'Dropped') then raise exception 'Status must be one of: Open, In progress, Done, Dropped.'; end if;
  if pt is not null and pt not in ('Discussion', 'Decision', 'Action', 'Information', 'Risk / concern', 'Query') then raise exception 'Choose a valid point type.'; end if;
  if v_id is null then
    if coalesce(trim(p ->> 'what'), '') = '' then raise exception 'Write what was discussed or decided (the “What” of 5W1H).'; end if;
    select coalesce(max(seq), 0) + 1 into sq from console.mom_points where meeting_id = m.id;
    insert into console.mom_points (customer_id, meeting_id, seq, topic, what, why, who, when_on, when_note, where_at, how, ptype, status, lang, remarks, source, created_by)
    values (cid, m.id, sq, nullif(trim(coalesce(p ->> 'topic', '')), ''), trim(p ->> 'what'), nullif(trim(coalesce(p ->> 'why', '')), ''), nullif(trim(coalesce(p ->> 'who', '')), ''), nullif(p ->> 'when_on', '')::date,
            nullif(trim(coalesce(p ->> 'when_note', '')), ''), nullif(trim(coalesce(p ->> 'where_at', '')), ''), nullif(trim(coalesce(p ->> 'how', '')), ''), coalesce(pt, 'Discussion'), coalesce(st, 'Open'),
            nullif(trim(coalesce(p ->> 'lang', '')), ''), nullif(trim(coalesce(p ->> 'remarks', '')), ''), case when p ->> 'source' = 'voice' then 'voice' else 'typed' end, me) returning id into v_id;
  elsif m.status = 'closed' then
    -- finalised minutes: only the follow-up fields can move
    update console.mom_points set status = coalesce(st, status), remarks = case when p ? 'remarks' then nullif(trim(coalesce(p ->> 'remarks', '')), '') else remarks end,
           when_on = case when p ? 'when_on' then nullif(p ->> 'when_on', '')::date else when_on end, when_note = case when p ? 'when_note' then nullif(trim(coalesce(p ->> 'when_note', '')), '') else when_note end, updated_at = now() where id = v_id;
  else
    if p ? 'what' and coalesce(trim(p ->> 'what'), '') = '' then raise exception 'The “What” of a point cannot be empty.'; end if;
    update console.mom_points set topic = case when p ? 'topic' then nullif(trim(coalesce(p ->> 'topic', '')), '') else topic end, what = case when p ? 'what' then trim(p ->> 'what') else what end,
           why = case when p ? 'why' then nullif(trim(coalesce(p ->> 'why', '')), '') else why end, who = case when p ? 'who' then nullif(trim(coalesce(p ->> 'who', '')), '') else who end,
           when_on = case when p ? 'when_on' then nullif(p ->> 'when_on', '')::date else when_on end, when_note = case when p ? 'when_note' then nullif(trim(coalesce(p ->> 'when_note', '')), '') else when_note end,
           where_at = case when p ? 'where_at' then nullif(trim(coalesce(p ->> 'where_at', '')), '') else where_at end, how = case when p ? 'how' then nullif(trim(coalesce(p ->> 'how', '')), '') else how end,
           ptype = coalesce(pt, ptype), status = coalesce(st, status), lang = case when p ? 'lang' then nullif(trim(coalesce(p ->> 'lang', '')), '') else lang end,
           remarks = case when p ? 'remarks' then nullif(trim(coalesce(p ->> 'remarks', '')), '') else remarks end, updated_at = now() where id = v_id;
  end if;
  if m.status = 'open' and jsonb_typeof(p -> 'seg_ids') = 'array' then
    update console.mom_points set seg_ids = p -> 'seg_ids' where id = v_id;
    update console.mom_segments set point_id = v_id where customer_id = cid and meeting_id = m.id and id::text in (select jsonb_array_elements_text(p -> 'seg_ids'));
  end if;
  return (select to_jsonb(x) - 'customer_id' from console.mom_points x where x.id = v_id);
end $$;

create or replace function public.kmr_mom_point_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  select mm.* into m from console.mom_points p join console.mom_meetings mm on mm.id = p.meeting_id where p.id = p_id and p.customer_id = cid;
  if not found then raise exception 'Point not found.'; end if;
  if m.status <> 'open' then raise exception 'This meeting is finalised. Re-open it to delete points.'; end if;
  delete from console.mom_points where id = p_id;
end $$;

-- translations of one point: {"hi-IN": {"what": "...", "why": "..."}}
create or replace function public.kmr_mom_translate_save(p_slug text, p_id uuid, p_lang text, p_tr jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  perform console.require_feature(p_slug, 'mom', 'mom.translation');
  if coalesce(trim(p_lang), '') = '' then raise exception 'Choose the language.'; end if;
  if jsonb_typeof(p_tr) is distinct from 'object' then raise exception 'Translation is missing.'; end if;
  select mm.* into m from console.mom_points p join console.mom_meetings mm on mm.id = p.meeting_id where p.id = p_id and p.customer_id = cid;
  if not found then raise exception 'Point not found.'; end if;
  if m.status = 'void' then raise exception 'This meeting is void.'; end if;
  update console.mom_points set translations = translations || jsonb_build_object(trim(p_lang), p_tr) where id = p_id;
end $$;

-- ---------- voice transcript ----------
-- the browser sends finished sentences in small batches; client_id makes a repeated send harmless
create or replace function public.kmr_mom_seg_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype; g jsonb; ids jsonb := '{}'; sid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  perform console.require_feature(p_slug, 'mom', 'mom.voice-capture');
  select * into m from console.mom_meetings where id = nullif(p ->> 'meeting_id', '')::uuid and customer_id = cid for update;
  if not found then raise exception 'Meeting not found.'; end if;
  if m.status <> 'open' then raise exception 'This meeting is finalised. Re-open it to record.'; end if;
  if jsonb_typeof(p -> 'segs') <> 'array' then raise exception 'Nothing to save.'; end if;
  if jsonb_array_length(p -> 'segs') > 200 then raise exception 'Too many lines in one save.'; end if;
  for g in select * from jsonb_array_elements(p -> 'segs') loop
    if coalesce(trim(g ->> 'client_id'), '') = '' or coalesce(trim(g ->> 'text'), '') = '' then continue; end if;
    insert into console.mom_segments (customer_id, meeting_id, client_id, lang, text, spoken_at, speaker, created_by)
    values (cid, m.id, g ->> 'client_id', nullif(trim(coalesce(g ->> 'lang', '')), ''), left(trim(g ->> 'text'), 5000), coalesce(nullif(g ->> 'spoken_at', '')::timestamptz, now()), nullif(trim(coalesce(g ->> 'speaker', '')), ''), me)
    on conflict (meeting_id, client_id) do nothing;
    select id into sid from console.mom_segments where meeting_id = m.id and client_id = g ->> 'client_id';
    ids := ids || jsonb_build_object(g ->> 'client_id', sid);
  end loop;
  return jsonb_build_object('ids', ids);
end $$;

create or replace function public.kmr_mom_seg_update(p_slug text, p_id uuid, p_text text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  perform console.require_feature(p_slug, 'mom', 'mom.voice-capture');
  select mm.* into m from console.mom_segments s join console.mom_meetings mm on mm.id = s.meeting_id where s.id = p_id and s.customer_id = cid;
  if not found then raise exception 'Line not found.'; end if;
  if m.status <> 'open' then raise exception 'This meeting is finalised.'; end if;
  if coalesce(trim(p_text), '') = '' then raise exception 'The line cannot be empty.'; end if;
  update console.mom_segments set text = left(trim(p_text), 5000) where id = p_id;
end $$;

create or replace function public.kmr_mom_seg_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  perform console.require_feature(p_slug, 'mom', 'mom.voice-capture');
  select mm.* into m from console.mom_segments s join console.mom_meetings mm on mm.id = s.meeting_id where s.id = p_id and s.customer_id = cid;
  if not found then return; end if;
  if m.status <> 'open' then raise exception 'This meeting is finalised.'; end if;
  delete from console.mom_segments where id = p_id;
end $$;

-- ---------- sample data ----------
create or replace function console.mom_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; me text := 'sample'; today date := (now() at time zone 'Asia/Kolkata')::date; mid uuid; pid uuid; d date; ppl jsonb;
begin
  if p_action = 'flush' then
    delete from console.mom_segments where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mom_points where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mom_meetings where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.mom_meetings where customer_id = p_cid and sample) then return 0; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'function', x.fn, 'email', x.em, 'present', true)), '[]') into ppl
    from (select r.name, r.data ->> 'function' fn, r.data ->> 'email' em from console.ops_records r where r.customer_id = p_cid and r.kind = 'cft' and r.active order by r.name limit 5) x;

  d := today - 9;
  insert into console.mom_meetings (customer_id, meeting_no, title, mtype, meeting_date, start_time, end_time, venue, chairperson, scribe, language, attendees, agenda, next_date, status, closed_by, closed_at, sample, created_by)
  values (p_cid, 'MOM-' || to_char(d, 'YYMM') || '-' || lpad(console.mom_next(p_cid, 'MOM-' || to_char(d, 'YYMM'))::text, 4, '0'), 'Weekly quality review', 'Quality review', d, '10:00', '11:00', 'Conference room', 'Head – Quality', 'Design Engineer', 'en-IN', ppl,
          'Customer complaints; scrap trend; audit actions', today - 2, 'closed', me, now() - interval '9 days', true, me) returning id into mid;
  insert into console.mom_points (customer_id, meeting_id, seq, topic, what, why, who, when_on, where_at, how, ptype, status, sample, created_by) values
    (p_cid, mid, 1, 'Customer complaint C-112', 'Burr on the bore of part 4471-B reported by the customer', 'Deburring tool worn beyond its life', 'Production Manager', today - 2, 'CNC turning cell', 'Reduce tool life limit to 800 pcs; add a burr check to the Control Plan', 'Action', 'Done', true, me),
    (p_cid, mid, 2, 'Scrap trend', 'Scrap is 2.4% against the 1.5% target', 'Insert chipping on VMC-02', 'Maintenance Engineer', today + 3, 'VMC', 'Trial with a new insert grade; review after 5 days of data', 'Action', 'In progress', true, me),
    (p_cid, mid, 3, 'Audit', 'Internal audit schedule for next month approved', null, 'Head – Quality', null, null, null, 'Decision', 'Done', true, me);
  n := n + 4;

  d := today - 1;
  insert into console.mom_meetings (customer_id, meeting_no, title, mtype, meeting_date, start_time, end_time, venue, chairperson, scribe, language, attendees, status, sample, created_by)
  values (p_cid, 'MOM-' || to_char(d, 'YYMM') || '-' || lpad(console.mom_next(p_cid, 'MOM-' || to_char(d, 'YYMM'))::text, 4, '0'), 'Daily production meeting', 'Daily production', d, '09:00', '09:20', 'Shop floor', 'Production Manager', 'Maintenance Engineer', 'en-IN', ppl, 'open', true, me) returning id into mid;
  insert into console.mom_points (customer_id, meeting_id, seq, topic, what, why, who, when_on, where_at, how, ptype, status, sample, created_by) values
    (p_cid, mid, 1, 'Material shortage', 'Forging lot for part 5520 is delayed by two days', 'Supplier furnace breakdown', 'Purchase Manager', today + 1, 'Stores', 'Expedite with the supplier; arrange an alternate lot from the second source', 'Action', 'Open', true, me) returning id into pid;
  insert into console.mom_segments (customer_id, meeting_id, client_id, lang, text, spoken_at, speaker, point_id, sample, created_by) values
    (p_cid, mid, 'sample-1', 'en-IN', 'The forging lot for part 5520 is delayed by two days. Purchase to follow up with the supplier by tomorrow.', now() - interval '1 day', 'Production Manager', pid, true, me),
    (p_cid, mid, 'sample-2', 'hi-IN', 'कल तक मशीन दो की मरम्मत पूरी करनी है।', now() - interval '1 day' + interval '90 seconds', 'Maintenance Engineer', null, true, me);
  n := n + 4;
  return n;
end $$;
revoke all on function console.mom_sample(uuid, text) from public, anon, authenticated;
