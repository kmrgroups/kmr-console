-- =====================================================================
-- 0090 — Factory & Office Layout Studio as a full KMR app (same level as Sales Flow)
--  • company sign-in and licence through console.qp_role (same as the other apps)
--  • layout projects saved per company (tables come from 0089)
--  • report reference numbers (LAY-R-YYMM-####) kept in the layout history
--  • status control: draft, review, approved, superseded
--  • sample layouts for the demo workspace, the Data Master and the sample buttons
-- Needs 0089 first. Safe to re-run.
-- =====================================================================

-- ---------- context (role, company, logo, staff flag) ----------
create or replace function public.kmr_layout_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.qp_role(c.id, 'layout') is null then null
    else jsonb_build_object('role', console.qp_role(c.id, 'layout'), 'company', c.name, 'logo_url', c.logo_url, 'is_staff', coalesce(console.is_staff(), false)) end
  from console.customers c where c.slug = lower(p_slug) $$;

-- ---------- status ----------
create or replace function public.kmr_layout_status(p_slug text, p_id uuid, p_status text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'layout'); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_status not in ('draft', 'review', 'approved', 'superseded') then raise exception 'Unknown status.'; end if;
  if p_status = 'approved' and console.qp_role(cid, 'layout') <> 'admin' then raise exception 'Only an administrator can approve a layout.'; end if;
  update console.layout_projects
     set status = p_status, updated_by = me, updated_at = now(),
         history = history || jsonb_build_array(jsonb_build_object('t', 'status', 'status', p_status, 'at', now(), 'by', me))
   where id = p_id and customer_id = cid;
  if not found then raise exception 'Layout project not found.'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- report: a new reference number every time a report is issued ----------
create or replace function public.kmr_layout_report(p_slug text, p_id uuid, p_option int) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'layout'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); ref text; t timestamptz := now(); r console.layout_projects;
begin
  select * into r from console.layout_projects where id = p_id and customer_id = cid;
  if not found then raise exception 'Layout project not found.'; end if;
  ref := 'LAY-R-' || to_char(t, 'YYMM') || '-' || lpad(console.layout_next(cid, 'report')::text, 4, '0');
  update console.layout_projects
     set history = history || jsonb_build_array(jsonb_build_object('t', 'report', 'ref', ref, 'option', p_option, 'at', t, 'by', me)), updated_at = t, updated_by = me
   where id = p_id;
  return jsonb_build_object('ref', ref, 'issued_at', t, 'issued_by', me, 'no', r.no);
end $$;

-- ---------- sample layouts ----------
create or replace function console.layout_sample(p_cid uuid, p_action text) returns bigint language plpgsql security definer set search_path = console, public as $$
declare n bigint := 0; me text := lower(coalesce(auth.jwt() ->> 'email', 'sample')); m jsonb; r jsonb; ym text := to_char(now(), 'YYMM');
begin
  delete from console.layout_projects where customer_id = p_cid and sample;
  get diagnostics n = row_count;
  if p_action = 'flush' then return n; end if;
  m := '[
{"id":"NEJ-04","type":"cnc","name":"NEJ-04","w":3.7,"h":2.3,"cell":"CNC Turning"},{"id":"B-20","type":"cnc","name":"B-20","w":3.5,"h":2.5,"cell":"CNC Turning"},{"id":"NEB-102","type":"cnc","name":"NEB 102","w":2.8,"h":2.0,"cell":"CNC Turning"},{"id":"B-08","type":"cnc","name":"B-08","w":3.7,"h":2.5,"cell":"CNC Turning"},{"id":"B-82","type":"cnc","name":"B-82","w":2.95,"h":1.8,"cell":"CNC Turning"},{"id":"NE1.5-1","type":"cnc","name":"NE 1.5 #1","w":1.5,"h":1.3,"cell":"CNC Turning"},{"id":"NE1.5-2","type":"cnc","name":"NE 1.5 #2","w":1.5,"h":1.3,"cell":"CNC Turning"},{"id":"NM1.7","type":"cnc","name":"NM 1.7","w":1.5,"h":1.3,"cell":"CNC Turning"},{"id":"NE-61","type":"cnc","name":"NE-61","w":2.0,"h":1.4,"cell":"CNC Turning"},{"id":"NE44","type":"cnc","name":"NE44","w":3.0,"h":2.3,"cell":"CNC Turning"},{"id":"B-19","type":"cnc","name":"B-19","w":2.6,"h":1.54,"cell":"CNC Turning"},{"id":"B-01","type":"cnc","name":"B-01","w":1.8,"h":1.7,"cell":"CNC Turning"},{"id":"B-07","type":"cnc","name":"B-07","w":2.3,"h":1.3,"cell":"CNC Turning"},{"id":"NET21","type":"cnc","name":"NET 21","w":2.3,"h":1.6,"cell":"CNC Turning"},
{"id":"HMC","type":"vmc","name":"HMC NEJ-01","w":3.2,"h":2.3,"cell":"VMC / HMC"},{"id":"B-02-1","type":"vmc","name":"VMC B-02 #1","w":3.2,"h":2.3,"cell":"VMC / HMC"},{"id":"B-02-2","type":"vmc","name":"VMC B-02 #2","w":3.2,"h":2.3,"cell":"VMC / HMC"},{"id":"B-02-3","type":"vmc","name":"VMC B-02 #3","w":3.2,"h":2.3,"cell":"VMC / HMC"},{"id":"B-86","type":"vmc","name":"BED MILL B-86","w":6.0,"h":2.2,"cell":"VMC / HMC"},{"id":"B-92","type":"vmc","name":"VMC B-92","w":4.0,"h":2.2,"cell":"VMC / HMC"},{"id":"B-51","type":"vmc","name":"VMC B-51","w":3.9,"h":2.5,"cell":"VMC / HMC"},{"id":"B-74-1","type":"vmc","name":"TAP B-74 #1","w":2.1,"h":1.3,"cell":"VMC / HMC"},{"id":"B-74-2","type":"vmc","name":"TAP B-74 #2","w":2.1,"h":1.3,"cell":"VMC / HMC"},{"id":"B-74-3","type":"vmc","name":"TAP B-74 #3","w":2.1,"h":1.3,"cell":"VMC / HMC"},{"id":"B-74-4","type":"vmc","name":"TAP B-74 #4","w":2.1,"h":1.3,"cell":"VMC / HMC"},
{"id":"GT-LT","type":"conv","name":"GT / VT / LT Bank","w":3.7,"h":1.5,"cell":"Conventional"},{"id":"B-88","type":"conv","name":"B-88 Grinder","w":1.8,"h":1.3,"cell":"Conventional"},{"id":"B-89","type":"conv","name":"B-89 Grinder","w":1.8,"h":1.3,"cell":"Conventional"},{"id":"B-58","type":"conv","name":"B-58 Drill","w":1.37,"h":0.97,"cell":"Conventional"},{"id":"B-59","type":"conv","name":"B-59 Drill","w":1.0,"h":0.8,"cell":"Conventional"},{"id":"B-60","type":"conv","name":"B-60 Drill","w":1.0,"h":0.8,"cell":"Conventional"},{"id":"B-61","type":"conv","name":"B-61 Drill","w":1.0,"h":0.8,"cell":"Conventional"},{"id":"B-62","type":"conv","name":"B-62 Drill","w":1.37,"h":0.99,"cell":"Conventional"},{"id":"B-64","type":"conv","name":"B-64 Tap","w":1.14,"h":0.9,"cell":"Conventional"},
{"id":"IC-STUD","type":"msa","name":"IC STUD 3 TABLE (CMM)","w":4.1,"h":0.6,"cell":"Quality / MSA"},{"id":"2-TABLE","type":"msa","name":"2 TABLE (Air/Bore)","w":3.0,"h":0.6,"cell":"Quality / MSA"},{"id":"SRSE","type":"msa","name":"3 TABLE (SRSE PARTS)","w":4.4,"h":0.6,"cell":"Quality / MSA"},
{"id":"PARKAR","type":"finish","name":"PARKAR ARIA (Tanks)","w":3.0,"h":2.2,"cell":"Finish & Pack"},{"id":"ROTOR","type":"finish","name":"HOUSING & T-ROTOR ASSY","w":6.4,"h":2.4,"cell":"Finish & Pack"},{"id":"DRIVE-S","type":"finish","name":"DRIVE S AR Line","w":2.5,"h":0.6,"cell":"Finish & Pack"},{"id":"PACK","type":"finish","name":"PACK TABLE & BOX","w":1.9,"h":1.0,"cell":"Finish & Pack"}]'::jsonb;
  insert into console.layout_projects (customer_id, no, title, kind, concept, dimensions, source_file, machines, options, selected_option, status, sample, created_by, updated_by)
  values (p_cid, 'LAY-' || ym || '-S001', 'Example machine shop — 41 machines', 'factory', 'straight-flow',
    '{"width":24,"depth":36,"hallDepth":30,"qcDepth":6,"aisle":2.8,"opClearance":1.2,"maintClearance":1.5}', null, m,
    '[{"name":"Option A: U-cells","short":"U-cells","key":"cellular-u","travel":115.4,"util":43.2,"saving":25.4,"grade":"A","placed":41,"total":41,"noFit":0},{"name":"Option B: Heavy perimeter","short":"Heavy perimeter","key":"cellular-heavy","travel":154.7,"util":37.5,"saving":0,"grade":"C","placed":38,"total":41,"noFit":3},{"name":"Option C: Straight flow","short":"Straight flow","key":"straight-flow","travel":80.9,"util":46,"saving":47.7,"grade":"A+","placed":41,"total":41,"noFit":0}]',
    3, 'approved', true, me, me);
  insert into console.layout_projects (customer_id, no, title, kind, concept, dimensions, machines, options, selected_option, status, sample, created_by, updated_by)
  values (p_cid, 'LAY-' || ym || '-S002', 'Example office floor', 'office', 'office-ergonomic',
    '{"width":20,"depth":30,"hallDepth":24,"qcDepth":5.4,"aisle":2.8,"opClearance":1.2,"maintClearance":1.5}',
    '[{"id":"BOSS","type":"office","kind":"private","name":"Executive cabin (MD)","w":4.5,"h":3.8},{"id":"CONF-1","type":"office","kind":"public","name":"Board conference room (12 seats)","w":6,"h":4.5},{"id":"CONF-2","type":"office","kind":"public","name":"Meeting room 2 (6 seats)","w":4,"h":3.5},{"id":"DESKS","type":"office","kind":"open","name":"Open workstation pod (16 desks)","w":11,"h":6.5},{"id":"RECEP","type":"office","kind":"public","name":"Reception and visitor lounge","w":5,"h":4.5},{"id":"PANTRY","type":"office","kind":"service","name":"Pantry and dining","w":4.5,"h":4},{"id":"SERVER","type":"office","kind":"service","name":"IT server and documentation vault","w":3.5,"h":3},{"id":"TOILETS","type":"office","kind":"service","name":"Restrooms (men / women)","w":4.5,"h":3.5}]',
    '[{"name":"Option A: Reception first","short":"Reception first","key":"o1","travel":35.7,"util":36.4,"saving":44.4,"grade":"A","placed":8,"total":8,"noFit":0},{"name":"Option B: Open plan centre","short":"Open plan centre","key":"o2","travel":33.5,"util":36.4,"saving":47.8,"grade":"A+","placed":8,"total":8,"noFit":0},{"name":"Option C: Private zone","short":"Private zone","key":"o3","travel":64.2,"util":36.4,"saving":0,"grade":"B+","placed":8,"total":8,"noFit":0}]',
    2, 'review', true, me, me);
  return n + 2;
end $$;
revoke all on function console.layout_sample(uuid, text) from public, anon, authenticated;

-- the 0089 sample function now loads these two layouts
create or replace function public.kmr_layout_sample(p_slug text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'layout');
begin
  return jsonb_build_object('ok', true, 'layout', console.layout_sample(cid, 'load'));
end $$;

-- ---------- platform functions: Data Master, sample buttons ----------
do $wrap$ begin
  if to_regprocedure('console.app2_tables_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''layout'' then array[''layout_counters'',''layout_projects''] else console.app2_tables_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint;
    begin
      if p_app = 'layout' then
        delete from console.layout_projects where customer_id = p_cid and (not p_real_only or sample); get diagnostics n = row_count;
        if not p_real_only then delete from console.layout_counters where customer_id = p_cid; end if;
        return n;
      end if;
      return console.app2_clear_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
  if to_regprocedure('public.kmr_app_sample_base(text,text,text)') is null then
    alter function public.kmr_app_sample(text, text, text) rename to kmr_app_sample_base;
    create function public.kmr_app_sample(p_slug text, p_app text, p_action text) returns jsonb language plpgsql security definer set search_path = console, public as $f$
    declare cid uuid;
    begin
      if p_app = 'layout' then
        if not coalesce(console.is_staff(), false) then raise exception 'Only the KMR developer login can load or remove sample data here.'; end if;
        if p_action not in ('load', 'flush') then raise exception 'Unknown action.'; end if;
        select id into cid from console.customers where slug = lower(p_slug);
        if cid is null then raise exception 'Unknown company link.'; end if;
        if not console.has_app(cid, 'layout') then raise exception 'This company does not have that app.'; end if;
        return jsonb_build_object('layout', console.layout_sample(cid, p_action));
      end if;
      return public.kmr_app_sample_base(p_slug, p_app, p_action);
    end $f$;
    revoke all on function public.kmr_app_sample(text, text, text) from public, anon;
    grant execute on function public.kmr_app_sample(text, text, text) to authenticated;
    revoke all on function public.kmr_app_sample_base(text, text, text) from public, anon, authenticated;
  end if;
end $wrap$;

-- text patches (read back, changed, re-created; a function that already has the change is left alone)
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where (s.nspname = 'public' and p.proname in ('kmr_data_overview', 'kmr_grand_sample', 'kmr_portal', 'kmr_portal_join'))
        or (s.nspname = 'console' and p.proname in ('data_target'))
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('layout' in def) = 0 then
      if rec.proname = 'kmr_data_overview' then
        nw := regexp_replace(nw, $re$'aud',\s*'off'\]$re$, '''aud'',''off'',''layout'']');
        nw := regexp_replace(nw, $re$'d8','aud'\]$re$, '''d8'',''aud'',''layout'']');
      elsif rec.proname = 'kmr_grand_sample' then
        nw := replace(nw, $a$if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'load')); end if;$a$,
          $b$if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'load')); end if;
    if console.has_app(cid, 'layout') then out := out || jsonb_build_object('layout', console.layout_sample(cid, 'load')); end if;$b$);
        nw := replace(nw, $a$if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'flush')); end if;$a$,
          $b$if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'flush')); end if;
    if console.has_app(cid, 'layout') then out := out || jsonb_build_object('layout', console.layout_sample(cid, 'flush')); end if;$b$);
      elsif rec.proname in ('kmr_portal', 'kmr_portal_join') then
        nw := regexp_replace(nw, $re$(\n\s*when 'off'\s+then console\.qp_member\(([a-z_.]+), em, 'off'\))$re$, E'\\1\n     when ''layout'' then console.qp_member(\\2, em, ''layout'')', 'g');
      end if;
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'Layout Studio: % platform functions updated', n;
end $patch$;

-- ---------- grants ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_layout_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- ---------- demo workspace: also load these samples ----------
do $$ begin
  update console.products set description = '1:1 scale factory machine shop and office layout generator — three options with computed route length and floor use, standards alignment, controlled reports with reference numbers, DXF export', current_version = '1.1.0' where code = 'layout';
  insert into console.releases (product_code, version, notes) values ('layout', '1.1.0', 'Full KMR app: company sign-in and licence, saved projects, status control, standards alignment, reports with logo and reference number, presentation with action plans') on conflict do nothing;
end $$;
