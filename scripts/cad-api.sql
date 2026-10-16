-- ---------- helpers ----------
create or replace function console.cad_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.cad_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.cad_counters.n + 1 returning n $$;
revoke all on function console.cad_next(uuid, text) from public, anon, authenticated;

create or replace function console.cad_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

-- one history line
create or replace function console.cad_hist(p_rev text, p_status text, p_note text) returns jsonb language sql stable as $$
  select jsonb_build_array(jsonb_build_object('rev', p_rev, 'status', p_status, 'at', now(), 'by', console.cad_me(), 'note', nullif(trim(coalesce(p_note, '')), ''))) $$;

-- ---------- reads ----------
-- every revision without the geometry (the register hides superseded revisions unless asked)
create or replace function public.kmr_cad_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'cad');
begin
  return coalesce((select jsonb_agg(to_jsonb(d) - 'customer_id' - 'data' - 'history' || jsonb_build_object('revs', (select count(*) from console.cad_drawings x where x.customer_id = cid and x.number = d.number))
                   order by d.number, d.created_at desc)
     from console.cad_drawings d where d.customer_id = cid), '[]');
end $$;

create or replace function public.kmr_cad_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'cad'); r jsonb;
begin
  select to_jsonb(d) - 'customer_id' into r from console.cad_drawings d where d.id = p_id and d.customer_id = cid;
  if r is null then raise exception 'Drawing not found.'; end if;
  return r;
end $$;

-- ---------- save: new drawing, details, geometry; restore from a JSON export (administrator) ----------
create or replace function public.kmr_cad_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'cad'); v_id uuid := nullif(p ->> 'id', '')::uuid; d console.cad_drawings%rowtype; me text := console.cad_me();
        no text := nullif(trim(coalesce(p ->> 'number', '')), ''); rv text := coalesce(nullif(trim(coalesce(p ->> 'rev', '')), ''), 'A'); k text;
        restore boolean := coalesce((p ->> 'restore')::boolean, false); st text := coalesce(nullif(p ->> 'status', ''), 'draft');
begin
  if p ? 'data' and jsonb_typeof(p -> 'data') <> 'object' then raise exception 'The drawing data is not valid.'; end if;
  if p ? 'data' and octet_length((p -> 'data')::text) > 25000000 then raise exception 'This drawing is too large to store (over 25 MB). Purge unused blocks or split it into sheets.'; end if;
  if p ? 'thumb' and octet_length(coalesce(p ->> 'thumb', '')) > 400000 then p := p - 'thumb'; end if;
  if restore then
    if console.qp_role(cid, 'cad') <> 'admin' then raise exception 'Only an administrator can restore drawings.'; end if;
    if no is null or coalesce(trim(p ->> 'title'), '') = '' then raise exception 'A drawing in the file has no number or title.'; end if;
    if st not in ('draft', 'review', 'released', 'superseded', 'obsolete') then st := 'draft'; end if;
    insert into console.cad_drawings (customer_id, number, title, rev, part_no, customer, notes, units, status, data, thumb, ents, history, created_by, updated_by)
    values (cid, no, trim(p ->> 'title'), rv, nullif(trim(coalesce(p ->> 'part_no', '')), ''), nullif(trim(coalesce(p ->> 'customer', '')), ''), nullif(p ->> 'notes', ''), coalesce(nullif(p ->> 'units', ''), 'mm'), st,
            coalesce(p -> 'data', '{}'), p ->> 'thumb', coalesce((p ->> 'ents')::int, 0), coalesce(case when jsonb_typeof(p -> 'history') = 'array' then p -> 'history' end, '[]') || console.cad_hist(rv, st, 'Restored from a JSON export'), me, me)
    on conflict (customer_id, number, rev) do update set title = excluded.title, part_no = excluded.part_no, customer = excluded.customer, notes = excluded.notes, units = excluded.units, status = excluded.status,
      data = excluded.data, thumb = excluded.thumb, ents = excluded.ents, history = excluded.history, updated_by = me, updated_at = now()
    returning * into d;
    return jsonb_build_object('id', d.id, 'number', d.number, 'rev', d.rev, 'updated_at', d.updated_at);
  end if;
  if v_id is null then
    if coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter a title.'; end if;
    if no is null then
      k := 'DRG-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMM');
      loop
        no := k || '-' || lpad(console.cad_next(cid, k)::text, 4, '0');
        exit when not exists (select 1 from console.cad_drawings where customer_id = cid and number = no);
      end loop;
    elsif exists (select 1 from console.cad_drawings where customer_id = cid and number = no and rev = rv) then
      raise exception 'Drawing % rev % already exists. Open it, or make a new revision of it.', no, rv;
    end if;
    insert into console.cad_drawings (customer_id, number, title, rev, part_no, customer, notes, units, data, thumb, ents, history, created_by, updated_by)
    values (cid, no, trim(p ->> 'title'), rv, nullif(trim(coalesce(p ->> 'part_no', '')), ''), nullif(trim(coalesce(p ->> 'customer', '')), ''), nullif(p ->> 'notes', ''), coalesce(nullif(p ->> 'units', ''), 'mm'),
            coalesce(p -> 'data', '{}'), p ->> 'thumb', coalesce((p ->> 'ents')::int, 0), console.cad_hist(rv, 'draft', 'Created'), me, me)
    returning * into d;
  else
    select * into d from console.cad_drawings where id = v_id and customer_id = cid for update;
    if not found then raise exception 'Drawing not found.'; end if;
    if d.status in ('released', 'superseded', 'obsolete') then raise exception 'Drawing % rev % is % and locked. Make a new revision to change it.', d.number, d.rev, d.status; end if;
    if p ? 'title' and coalesce(trim(p ->> 'title'), '') = '' then raise exception 'Enter a title.'; end if;
    if p ? 'rev' and rv <> d.rev and exists (select 1 from console.cad_drawings where customer_id = cid and number = d.number and rev = rv) then raise exception 'Revision % of % already exists.', rv, d.number; end if;
    update console.cad_drawings set
      title = case when p ? 'title' then trim(p ->> 'title') else title end, rev = case when p ? 'rev' then rv else rev end,
      part_no = case when p ? 'part_no' then nullif(trim(coalesce(p ->> 'part_no', '')), '') else part_no end, customer = case when p ? 'customer' then nullif(trim(coalesce(p ->> 'customer', '')), '') else customer end,
      notes = case when p ? 'notes' then nullif(p ->> 'notes', '') else notes end, units = case when p ? 'units' then coalesce(nullif(p ->> 'units', ''), units) else units end,
      data = case when p ? 'data' then p -> 'data' else data end, thumb = case when p ? 'thumb' then p ->> 'thumb' else thumb end, ents = case when p ? 'ents' then coalesce((p ->> 'ents')::int, ents) else ents end,
      updated_by = me, updated_at = now()
     where id = v_id returning * into d;
  end if;
  return jsonb_build_object('id', d.id, 'number', d.number, 'rev', d.rev, 'updated_at', d.updated_at);
end $$;

-- ---------- workflow: review, release (administrator), obsolete, back to draft ----------
create or replace function public.kmr_cad_status(p_slug text, p_id uuid, p_status text, p_note text default null) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'cad'); d console.cad_drawings%rowtype; ok text[];
begin
  select * into d from console.cad_drawings where id = p_id and customer_id = cid for update;
  if not found then raise exception 'Drawing not found.'; end if;
  ok := case d.status when 'draft' then array['review', 'released'] when 'review' then array['released', 'draft'] when 'released' then array['obsolete'] when 'obsolete' then array['draft'] else array[]::text[] end;
  if not p_status = any(ok) then raise exception 'A % drawing cannot be set to %.', d.status, p_status; end if;
  if p_status in ('released', 'obsolete') and console.qp_role(cid, 'cad') <> 'admin' then raise exception 'Only an administrator can release a drawing or mark it obsolete.'; end if;
  if p_status = 'released' and coalesce(jsonb_array_length(case when jsonb_typeof(d.data -> 'ents') = 'array' then d.data -> 'ents' end), 0) = 0 then raise exception 'The drawing is empty. Draw or import it before releasing.'; end if;
  if p_status = 'released' then
    update console.cad_drawings set status = 'superseded', history = history || console.cad_hist(rev, 'superseded', 'Replaced by rev ' || d.rev), updated_at = now()
     where customer_id = cid and number = d.number and status = 'released' and id <> d.id;
  end if;
  update console.cad_drawings set status = p_status, history = history || console.cad_hist(rev, p_status, p_note), updated_by = console.cad_me(), updated_at = now() where id = p_id;
end $$;

-- a new revision (draft copy) of a released drawing; the released one stays valid until the new one is released
create or replace function public.kmr_cad_revise(p_slug text, p_id uuid, p_note text, p_rev text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'cad'); d console.cad_drawings%rowtype; o console.cad_drawings%rowtype; rv text := nullif(trim(coalesce(p_rev, '')), ''); nid uuid;
begin
  select * into d from console.cad_drawings where id = p_id and customer_id = cid;
  if not found then raise exception 'Drawing not found.'; end if;
  if d.status <> 'released' then raise exception 'Only a released drawing can be revised.'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'Write the change note for the new revision.'; end if;
  if rv is null then raise exception 'Enter the new revision.'; end if;
  select * into o from console.cad_drawings where customer_id = cid and number = d.number and status in ('draft', 'review') limit 1;
  if found then raise exception 'Revision % of % is already being prepared.', o.rev, d.number; end if;
  if exists (select 1 from console.cad_drawings where customer_id = cid and number = d.number and rev = rv) then raise exception 'Revision % of % already exists.', rv, d.number; end if;
  insert into console.cad_drawings (customer_id, number, title, rev, part_no, customer, notes, units, status, data, thumb, ents, history, created_by, updated_by)
  values (cid, d.number, d.title, rv, d.part_no, d.customer, d.notes, d.units, 'draft', d.data, d.thumb, d.ents, d.history || console.cad_hist(rv, 'draft', p_note), console.cad_me(), console.cad_me())
  returning id into nid;
  return jsonb_build_object('id', nid, 'rev', rv);
end $$;

create or replace function public.kmr_cad_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'cad'); d console.cad_drawings%rowtype;
begin
  if console.qp_role(cid, 'cad') <> 'admin' then raise exception 'Only an administrator can delete a drawing.'; end if;
  select * into d from console.cad_drawings where id = p_id and customer_id = cid for update;
  if not found then raise exception 'Drawing not found.'; end if;
  if d.status in ('released', 'superseded') then raise exception 'A released or superseded drawing cannot be deleted — mark it obsolete instead.'; end if;
  delete from console.cad_drawings where id = p_id;
end $$;

-- ---------- sample data ----------
create or replace function console.cad_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; s jsonb := $json$--@@SAMPLE@@$json$::jsonb; x jsonb;
begin
  if p_action = 'flush' then
    delete from console.cad_drawings where customer_id = p_cid and sample; get diagnostics n = row_count;
    return n;
  end if;
  if exists (select 1 from console.cad_drawings where customer_id = p_cid and sample) then return 0; end if;
  for x in select * from jsonb_array_elements(s) loop
    if exists (select 1 from console.cad_drawings where customer_id = p_cid and number = x ->> 'number' and rev = x ->> 'rev') then continue; end if;
    insert into console.cad_drawings (customer_id, number, title, rev, part_no, customer, units, status, data, thumb, ents, history, sample, created_by, updated_by, updated_at)
    values (p_cid, x ->> 'number', x ->> 'title', x ->> 'rev', x ->> 'part_no', x ->> 'customer', x ->> 'units', x ->> 'status', x -> 'data', x ->> 'thumb', jsonb_array_length(x -> 'data' -> 'ents'),
            (select coalesce(jsonb_agg(h || jsonb_build_object('at', now() - make_interval(days => greatest(1, 140 - i::int * 40)), 'by', 'sample')), '[]') from jsonb_array_elements(x -> 'history') with ordinality t(h, i)),
            true, 'sample', 'sample', now() - interval '2 days');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function console.cad_sample(uuid, text) from public, anon, authenticated;
