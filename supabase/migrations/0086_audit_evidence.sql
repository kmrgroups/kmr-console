-- =====================================================================
-- 0086 — Audit evidence (extends Internal Audit, product code 'aud'; needs 0082 and 0085)
--  • Each checklist question keeps an evidence reference number and its 6M group (Man, Machine, Material, Method, Measurement, Mother nature, Management).
--  • Files (photos, PDFs, records) can be attached to a question or to a finding. Images, PDF, text, CSV, Word and Excel up to about 1.5 MB each.
--  • An audit report can be issued only when every answered question of the clause library has the actual finding (what was seen) and an evidence reference.
-- Safe to re-run. No new priced feature.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_aud_nc_save(text, jsonb)') is null then raise exception 'Run 0085_audit_management.sql first.'; end if;
end $$;

-- ---------- attachments ----------
create table if not exists console.aud_files (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  audit_id uuid not null references console.aud_audits(id) on delete cascade, ref text not null,
  name text not null, mime text not null, size int not null, data text not null,
  sample boolean not null default false, created_by text, created_at timestamptz not null default now());
create index if not exists aud_files_audit on console.aud_files (audit_id, ref);
do $$ begin
  alter table console.aud_files enable row level security;
  if not exists (select 1 from pg_policies where schemaname = 'console' and tablename = 'aud_files' and policyname = 'aud_files_staff') then
    create policy aud_files_staff on console.aud_files for all using (console.is_staff()) with check (console.is_staff());
  end if;
  revoke all on console.aud_files from public, anon, authenticated;
end $$;

create or replace function public.kmr_aud_file_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); me text := console.aud_me(); au console.aud_audits; f console.aud_files; nm text := console.aud_txt(p, 'name'); mt text := lower(coalesce(console.aud_txt(p, 'mime'), '')); dt text := coalesce(p ->> 'data', ''); rf text := console.aud_txt(p, 'ref');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into au from console.aud_audits where id = nullif(p ->> 'audit_id', '')::uuid and customer_id = cid; if au.id is null then raise exception 'Audit not found.'; end if;
  if au.status not in ('planned', 'reported') then raise exception 'This audit is %. An administrator can reopen it.', au.status; end if;
  if rf is null then raise exception 'Say which question or finding the file belongs to.'; end if;
  if nm is null then raise exception 'The file has no name.'; end if;
  if not (mt like 'image/%' or mt in ('application/pdf', 'text/plain', 'text/csv', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')) then
    raise exception 'This kind of file cannot be attached. Use a photo, PDF, text, CSV, Word or Excel file.'; end if;
  if dt = '' or dt !~ '^[A-Za-z0-9+/=]+$' then raise exception 'The file could not be read.'; end if;
  if length(dt) > 2100000 then raise exception 'The file is too large. The limit is about 1.5 MB; reduce the photo or PDF size.'; end if;
  if (select count(*) from console.aud_files where audit_id = au.id and ref = rf) >= 12 then raise exception 'At most 12 files can be attached to one question or finding.'; end if;
  if (select count(*) from console.aud_files where audit_id = au.id) >= 80 then raise exception 'At most 80 files can be attached to one audit.'; end if;
  insert into console.aud_files (customer_id, audit_id, ref, name, mime, size, data, created_by) values (cid, au.id, rf, left(nm, 200), mt, (length(dt) * 3) / 4, dt, me) returning * into f;
  perform console.aud_log(cid, au.id, 'File attached: ' || f.name, au.sample);
  return jsonb_build_object('id', f.id, 'ref', f.ref, 'name', f.name, 'mime', f.mime, 'size', f.size, 'by', f.created_by, 'at', f.created_at);
end $$;
create or replace function public.kmr_aud_file_list(p_slug text, p_audit_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud');
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'ref', f.ref, 'name', f.name, 'mime', f.mime, 'size', f.size, 'by', f.created_by, 'at', f.created_at) order by f.created_at) from console.aud_files f where f.audit_id = p_audit_id and f.customer_id = cid), '[]');
end $$;
create or replace function public.kmr_aud_file_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'aud'); f console.aud_files;
begin
  perform console.require_feature(p_slug, 'aud', 'aud.audit-programme-and-reports');
  select * into f from console.aud_files where id = p_id and customer_id = cid; if f.id is null then raise exception 'File not found.'; end if;
  return jsonb_build_object('id', f.id, 'ref', f.ref, 'name', f.name, 'mime', f.mime, 'size', f.size, 'data', f.data);
end $$;
create or replace function public.kmr_aud_file_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'aud'); f console.aud_files; au console.aud_audits;
begin
  select * into f from console.aud_files where id = p_id and customer_id = cid; if f.id is null then raise exception 'File not found.'; end if;
  select * into au from console.aud_audits where id = f.audit_id;
  if au.status not in ('planned', 'reported') and console.qp_role(cid, 'aud') <> 'admin' then raise exception 'This audit is %. An administrator can remove files.', au.status; end if;
  delete from console.aud_files where id = f.id;
  perform console.aud_log(cid, au.id, 'File removed: ' || f.name, au.sample);
end $$;

-- ---------- questions keep evidence reference and 6M group; issue needs the actual and the evidence ----------
do $patch$
declare def text; nw text;
begin
  def := pg_get_functiondef('public.kmr_aud_audit_save(text, jsonb)'::regprocedure); nw := def;
  if position('''evr''' in def) = 0 then
    nw := replace(nw, $a$'pt', console.aud_txt(item, 'pt')$a$, $b$'pt', console.aud_txt(item, 'pt'), 'evr', console.aud_txt(item, 'evr'), 'm', console.aud_txt(item, 'm')$b$);
    if position('''evr''' in nw) = 0 then raise exception 'kmr_aud_audit_save was not updated'; end if;
    execute nw;
  end if;
  def := pg_get_functiondef('public.kmr_aud_issue(text, uuid)'::regprocedure); nw := def;
  if position('evidence reference number' in def) = 0 then
    nw := replace(nw, $a$  if r.type = 'Process' and console.aud_has(p_slug, 'aud.vda-6-3-scoring')$a$, $b$  select count(*) into n from jsonb_array_elements(r.checklist) x where coalesce(x ->> 'cl', '') <> '' and coalesce(x ->> 'rating', '') not in ('', 'NA')
     and (coalesce(trim(x ->> 'note'), '') = '' or coalesce(trim(x ->> 'evr'), '') = '');
  if n > 0 then raise exception '% question(s) need the actual finding (what was seen) and an evidence reference number.', n; end if;
  if r.type = 'Process' and console.aud_has(p_slug, 'aud.vda-6-3-scoring')$b$);
    if position('evidence reference number' in nw) = 0 then raise exception 'kmr_aud_issue was not updated'; end if;
    execute nw;
  end if;
end $patch$;

-- ---------- platform: backup of the new table ----------
do $patch$
declare rec record; def text; nw text;
begin
  for rec in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'console' and p.proname = 'app2_tables' loop
    def := pg_get_functiondef(rec.oid);
    if position('aud_files' in def) = 0 then
      nw := replace(def, $a$'aud_ncs','aud_points']$a$, $b$'aud_ncs','aud_points','aud_files']$b$);
      if nw = def then raise exception 'app2_tables was not updated'; end if;
      execute nw;
    end if;
  end loop;
end $patch$;

-- ---------- product listing ----------
update console.products set current_version = '1.2.0' where code = 'aud';
insert into console.releases (product_code, version, notes) select 'aud', '1.2.0', 'Evidence reference number and file attachments on every question and finding, 6M checklists for process and product audits, IQA schedule by process, nonconformity summary by process and clause.'
 where not exists (select 1 from console.releases where product_code = 'aud' and version = '1.2.0');

-- ---------- permissions ----------
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_aud_' loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
