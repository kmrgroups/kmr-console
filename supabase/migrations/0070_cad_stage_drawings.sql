-- 0070 — KMR CAD Draft ↔ Process Documents: stage drawings for the SOP
--
-- Process Documents freezes the characteristics made at each operation (doc.plan.freeze: rev, date, by,
-- operation → balloon numbers). KMR CAD Draft reads the frozen plan and the ballooned drawing, draws one
-- stage drawing per operation and stores them in pd_projects.stages. The SOP shows and prints them, and
-- flags them as out of date when the dimensions are frozen again.
--
-- Access: reading and writing go through these functions with the CAD Draft role of the KMR company
-- (viewer reads, editor/admin writes), the same way APQP / PPAP read Process Documents data.
-- Run after 0069. Safe to run more than once.

do $$ begin
  if to_regclass('public.pd_projects') is not null then
    alter table public.pd_projects add column if not exists stages jsonb;
  else
    raise notice 'public.pd_projects not found — Process Documents is not installed; the stage drawing link stays off.';
  end if;
end $$;

-- ---------- the company's Process Documents projects (no geometry) for the stage-drawing picker ----------
create or replace function public.kmr_cad_pd_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'cad'); org uuid;
begin
  org := console.grand_ref(cid, 'pd');
  if org is null or to_regclass('public.pd_projects') is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'part_no', p.part_no, 'part_name', p.part_name, 'rev', p.rev, 'drawing_no', p.drawing_no, 'customer', p.customer,
      'status', p.status, 'updated_at', p.updated_at,
      'freeze', case when jsonb_typeof(p.doc -> 'plan' -> 'freeze') = 'object' then (p.doc -> 'plan' -> 'freeze') - 'map' - 'spec' end,
      'ops', console.jlen(p.doc -> 'plan' -> 'ops'), 'chars', console.jlen(p.doc -> 'plan' -> 'chars'),
      'stages_at', p.stages ->> 'at', 'stages_rev', p.stages ->> 'freezeRev', 'bi', p.bi_report_id is not null) order by p.updated_at desc)
    from public.pd_projects p where p.org_id = org), '[]'::jsonb);
end $$;

-- ---------- one project: the frozen plan, the SOP checks and the ballooned drawing it came from ----------
create or replace function public.kmr_cad_pd_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'cad'); org uuid; r record; bi jsonb;
begin
  org := console.grand_ref(cid, 'pd');
  if org is null or to_regclass('public.pd_projects') is null then raise exception 'Your company does not have Process Documents.'; end if;
  select p.id, p.part_no, p.part_name, p.rev, p.drawing_no, p.customer, p.status, p.doc, p.source, p.bi_report_id, p.stages into r
    from public.pd_projects p where p.id = p_id and p.org_id = org;
  if r.id is null then raise exception 'Process Documents project not found.'; end if;
  if r.bi_report_id is not null and to_regclass('public.bi_reports') is not null then
    select jsonb_build_object('id', b.id, 'file_path', b.file_path, 'file_name', b.file_name, 'sheets', b.data -> 'sheets', 'items', b.data -> 'items', 'desk', b.data -> 'desk')
      into bi from public.bi_reports b where b.id = r.bi_report_id and b.org_id = console.grand_ref(cid, 'balloon');   -- only this company's Balloon Inspector
  end if;
  return jsonb_build_object('id', r.id, 'part_no', r.part_no, 'part_name', r.part_name, 'rev', r.rev, 'drawing_no', r.drawing_no, 'customer', r.customer, 'status', r.status,
    'header', r.doc -> 'plan' -> 'header', 'freeze', r.doc -> 'plan' -> 'freeze', 'chars', coalesce(r.doc -> 'plan' -> 'chars', '[]'),
    'ops', coalesce((select jsonb_agg(jsonb_build_object('opNo', o -> 'opNo', 'key', o -> 'key', 'name', o -> 'name', 'machine', o -> 'machine', 'chars', o -> 'chars') order by ord)
                     from jsonb_array_elements(case when jsonb_typeof(r.doc -> 'plan' -> 'ops') = 'array' then r.doc -> 'plan' -> 'ops' else '[]' end) with ordinality x(o, ord)), '[]'),
    'gauges', coalesce((select jsonb_agg(jsonb_build_object('id', g -> 'id', 'name', g -> 'name', 'range', g -> 'range'))
                     from jsonb_array_elements(case when jsonb_typeof(r.doc -> 'plan' -> 'gauges') = 'array' then r.doc -> 'plan' -> 'gauges' else '[]' end) g), '[]'),
    'sop', jsonb_build_object('docNo', r.doc -> 'docs' -> 'sop' ->> 'docNo', 'rev', r.doc -> 'docs' -> 'sop' ->> 'rev',
      'sections', coalesce((select jsonb_agg(jsonb_build_object('opNo', s -> 'opNo', 'docNo', s -> 'docNo', 'checks', s -> 'checks') order by ord)
                     from jsonb_array_elements(case when jsonb_typeof(r.doc -> 'docs' -> 'sop' -> 'sections') = 'array' then r.doc -> 'docs' -> 'sop' -> 'sections' else '[]' end) with ordinality x(s, ord)), '[]')),
    'source', jsonb_build_object('fileName', r.source ->> 'fileName', 'items', r.source -> 'items', 'sheets', r.source -> 'sheets', 'desk', r.source -> 'desk', 'manual', r.source -> 'manual'),
    'bi', bi,
    'stages', case when r.stages is null then null else jsonb_build_object('at', r.stages ->> 'at', 'by', r.stages ->> 'by', 'freezeRev', r.stages ->> 'freezeRev') end);
end $$;

-- ---------- store the stage drawings (editor / admin); only for the dimensions frozen right now ----------
create or replace function public.kmr_cad_pd_stages(p_slug text, p_id uuid, p_stages jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'cad'); org uuid; fz jsonb; t timestamptz := now(); n int;
begin
  org := console.grand_ref(cid, 'pd');
  if org is null or to_regclass('public.pd_projects') is null then raise exception 'Your company does not have Process Documents.'; end if;
  if not console.product_ok('pd', org) then raise exception 'Your company''s Process Documents access is paused, so the SOP cannot be updated.'; end if;
  if coalesce(jsonb_typeof(p_stages), '') <> 'object' or coalesce(jsonb_typeof(p_stages -> 'ops'), '') <> 'object' then raise exception 'The stage drawings are not valid.'; end if;
  if exists (select 1 from jsonb_each(p_stages -> 'ops') o where jsonb_typeof(o.value) <> 'array')
     or exists (select 1 from jsonb_each(p_stages -> 'ops') o, jsonb_array_elements(case when jsonb_typeof(o.value) = 'array' then o.value else '[]' end) x
                where coalesce(x ->> 'img', '') !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$') then
    raise exception 'The stage drawings are not valid (each must be a PNG or JPEG picture).';
  end if;
  if octet_length(p_stages::text) > 30000000 then raise exception 'The stage drawings are too large to store (over 30 MB). Make them with a smaller image size.'; end if;
  select p.doc -> 'plan' -> 'freeze' into fz from public.pd_projects p where p.id = p_id and p.org_id = org for update;
  if not found then raise exception 'Process Documents project not found.'; end if;
  if fz is null or jsonb_typeof(fz) <> 'object' then raise exception 'Freeze the dimensions in Process Documents first (Process plan › Freeze dimensions).'; end if;
  if (p_stages ->> 'freezeRev') is distinct from (fz ->> 'rev') or (p_stages ? 'freezeAt' and (p_stages ->> 'freezeAt') is distinct from (fz ->> 'at')) then
    raise exception 'The dimensions are now frozen as rev % in Process Documents. Make the stage drawings again.', fz ->> 'rev';
  end if;
  update public.pd_projects set stages = p_stages || jsonb_build_object('at', t, 'by', console.cad_me()) where id = p_id;
  select count(*) into n from jsonb_object_keys(p_stages -> 'ops');
  return jsonb_build_object('at', t, 'ops', n);
end $$;

revoke all on function public.kmr_cad_pd_list(text), public.kmr_cad_pd_get(text, uuid), public.kmr_cad_pd_stages(text, uuid, jsonb) from public, anon;
grant execute on function public.kmr_cad_pd_list(text), public.kmr_cad_pd_get(text, uuid), public.kmr_cad_pd_stages(text, uuid, jsonb) to authenticated;
