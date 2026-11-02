-- =====================================================================
-- 0092 — Daily Work Management: one DWM sheet per employee, and the company dashboard over all of them
--  • documents:  'staff'  = the employee list;  'dwm:YYYY-MM:<employee id>'  = that employee's sheet for the month
--  • the earlier Plant Head sheet and Executive Director register (0091 keys) are removed — DWM now starts empty
--  • kmr_dwm_month returns every employee's sheet of a month (for the Dashboards screen and the Presentation)
--  • kmr_dwm_delete removes an employee's sheets
-- Needs 0091. Safe to re-run.
-- =====================================================================
delete from console.dwm_docs where doc_key !~ '^(staff|dwm:[0-9]{4}-[0-9]{2}:[a-z0-9]{3,20})$';
alter table console.dwm_docs drop constraint if exists dwm_docs_doc_key_check;
alter table console.dwm_docs add constraint dwm_docs_doc_key_check check (doc_key ~ '^(staff|dwm:[0-9]{4}-[0-9]{2}:[a-z0-9]{3,20})$');

create or replace function public.kmr_dwm_save(p_slug text, p_key text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dwm'); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if p_key !~ '^(staff|dwm:[0-9]{4}-[0-9]{2}:[a-z0-9]{3,20})$' then raise exception 'Unknown document.'; end if;
  if p_doc is null or jsonb_typeof(p_doc) <> 'object' then raise exception 'Nothing to save.'; end if;
  if length(p_doc::text) > 2000000 then raise exception 'The sheet is too large.'; end if;
  insert into console.dwm_docs (customer_id, doc_key, doc, updated_by) values (cid, p_key, p_doc, me)
  on conflict (customer_id, doc_key) do update set doc = excluded.doc, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('ok', true, 'saved_at', now());
end $$;

create or replace function public.kmr_dwm_month(p_slug text, p_month text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'dwm');
begin
  if p_month !~ '^[0-9]{4}-[0-9]{2}$' then raise exception 'Unknown month.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key', d.doc_key, 'doc', d.doc) order by d.doc_key)
                     from console.dwm_docs d where d.customer_id = cid and d.doc_key like 'dwm:' || p_month || ':%'), '[]'::jsonb);
end $$;

create or replace function public.kmr_dwm_delete(p_slug text, p_emp text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dwm'); n bigint;
begin
  if p_emp !~ '^[a-z0-9]{3,20}$' then raise exception 'Unknown employee.'; end if;
  delete from console.dwm_docs where customer_id = cid and doc_key like 'dwm:%:' || p_emp; get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'removed', n);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_dwm_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
