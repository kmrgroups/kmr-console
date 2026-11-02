-- =====================================================================
-- 0095 — Daily Work Management: only an administrator (and the KMR developer admin) may change the table
--  • administrators / developer admin: everything
--  • editors: only mark an already planned day as Plan / Completed / Missed / Concession and write the missed-concession record
--    (activities, frequency, days planned, employees, targets, signatures stay frozen) — enforced here in the database, not only on screen
--  • viewers: read only (unchanged)
-- Needs 0091 and 0092. Safe to re-run.
-- =====================================================================
create or replace function console.dwm_strip(d jsonb) returns jsonb language sql immutable as $$
  select (d - 'log') || jsonb_build_object('acts', coalesce((select jsonb_agg(a - 'cells' order by o) from jsonb_array_elements(coalesce(d -> 'acts', '[]'::jsonb)) with ordinality t(a, o)), '[]'::jsonb))
$$;

-- an editor's change of the day cells: a planned day stays planned (O C X E), a day that is off stays off
create or replace function console.dwm_cells_ok(p_old jsonb, p_new jsonb) returns boolean language plpgsql immutable as $$
declare i int; n int := coalesce(jsonb_array_length(p_old -> 'acts'), 0); o text[]; w text[]; k int;
begin
  if n <> coalesce(jsonb_array_length(p_new -> 'acts'), 0) then return false; end if;
  for i in 0 .. n - 1 loop
    o := regexp_split_to_array(coalesce(p_old -> 'acts' -> i ->> 'cells', ''), '');
    w := regexp_split_to_array(coalesce(p_new -> 'acts' -> i ->> 'cells', ''), '');
    if coalesce(array_length(o, 1), 0) <> coalesce(array_length(w, 1), 0) then return false; end if;
    for k in 1 .. coalesce(array_length(o, 1), 0) loop
      if o[k] = '–' and w[k] <> '–' then return false; end if;
      if o[k] <> '–' and w[k] not in ('O', 'C', 'X', 'E') then return false; end if;
    end loop;
  end loop;
  return true;
end $$;
revoke all on function console.dwm_strip(jsonb), console.dwm_cells_ok(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.kmr_dwm_save(p_slug text, p_key text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dwm'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); old jsonb;
begin
  if p_key !~ '^(staff|dwm:[0-9]{4}-[0-9]{2}:[a-z0-9]{3,20})$' then raise exception 'Unknown document.'; end if;
  if p_doc is null or jsonb_typeof(p_doc) <> 'object' then raise exception 'Nothing to save.'; end if;
  if length(p_doc::text) > 2000000 then raise exception 'The sheet is too large.'; end if;
  if console.qp_role(cid, 'dwm') <> 'admin' then
    if p_key = 'staff' then raise exception 'Only an administrator can change the employee list.'; end if;
    select doc into old from console.dwm_docs where customer_id = cid and doc_key = p_key;
    if old is null then raise exception 'Only an administrator can create a DWM sheet.'; end if;
    if console.dwm_strip(old) is distinct from console.dwm_strip(p_doc) or not console.dwm_cells_ok(old, p_doc) then
      raise exception 'The table is locked. You can mark planned days as Completed, Missed or Concession; only an administrator can change anything else.';
    end if;
  end if;
  insert into console.dwm_docs (customer_id, doc_key, doc, updated_by) values (cid, p_key, p_doc, me)
  on conflict (customer_id, doc_key) do update set doc = excluded.doc, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('ok', true, 'saved_at', now());
end $$;

create or replace function public.kmr_dwm_delete(p_slug text, p_emp text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dwm'); n bigint;
begin
  if console.qp_role(cid, 'dwm') <> 'admin' then raise exception 'Only an administrator can remove an employee.'; end if;
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
