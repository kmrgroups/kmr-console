-- =====================================================================
-- 0096 — Daily Work Management enabled for every user of the company
--  • every member of a company (existing and future) gets the DWM role "editor": they can open the app and mark planned days;
--    the table itself stays locked to administrators and the KMR developer admin (0095)
--  • the KMR Apps page now recognises DWM for a company member (it showed DWM greyed out because the portal did not know the app)
-- Needs 0091 and 0095. Safe to re-run.
-- =====================================================================
create or replace function console.dwm_default_role() returns trigger language plpgsql as $$
begin
  new.roles := coalesce(new.roles, '{}'::jsonb);
  if coalesce(new.roles ->> 'dwm', '') = '' then new.roles := new.roles || '{"dwm":"editor"}'::jsonb; end if;
  return new;
end $$;
drop trigger if exists dwm_default_role on console.customer_members;
create trigger dwm_default_role before insert or update on console.customer_members for each row execute function console.dwm_default_role();
update console.customer_members set roles = coalesce(roles, '{}'::jsonb) || '{"dwm":"editor"}'::jsonb where coalesce(roles ->> 'dwm', '') = '';

-- the apps page and the app-opening check: add DWM next to the other company-level apps (anchored on the HRM line, which exists in both functions)
do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join')
  loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''dwm''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'hrm'\s+then)$re$, E'\\1when ''dwm'' then console.qp_member(' || case when rec.proname = 'kmr_portal' then 'l.customer_id' else 'cid' end || E', em, ''dwm'')\\1\\2');
      if rec.proname = 'kmr_portal' then
        nw := regexp_replace(nw, $re$(\n\s*)(or \(l\.product_code = 'hrm')$re$, E'\\1or (l.product_code = ''dwm'' and console.qp_member(l.customer_id, em, ''dwm''))\\1\\2');
      end if;
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'DWM: % portal functions updated', n;
  if position('''dwm''' in pg_get_functiondef('public.kmr_portal(text)'::regprocedure)) = 0 then raise exception 'kmr_portal was not updated for DWM'; end if;
  if position('''dwm''' in pg_get_functiondef('public.kmr_portal_join(text,text)'::regprocedure)) = 0 then raise exception 'kmr_portal_join was not updated for DWM'; end if;
end $patch$;
