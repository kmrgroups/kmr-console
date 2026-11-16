-- KMR 0131 — Profit & Loss (pnl): make the app known to the platform lists (portal "my apps", join, Data Master / clear data, year backup).
-- Without this the app could be bought but not added to a customer's users or opened. Safe to re-run.
do $wrap$ begin
  if to_regprocedure('console.app2_tables_pnl_base(text)') is null then
    alter function console.app2_tables(text) rename to app2_tables_pnl_base;
    create function console.app2_tables(p_app text) returns text[] language sql immutable as 'select case when p_app = ''pnl'' then array[''pnl_heads'',''pnl_alias'',''pnl_rules'',''pnl_stock'',''pnl_settings''] else console.app2_tables_pnl_base(p_app) end';
    revoke all on function console.app2_tables(text) from public, anon, authenticated;
  end if;
  if to_regprocedure('console.app2_clear_pnl_base(text,uuid,boolean)') is null then
    alter function console.app2_clear(text, uuid, boolean) rename to app2_clear_pnl_base;
    create function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
    declare n bigint := 0; m bigint;
    begin
      if p_app = 'pnl' then
        if p_real_only then return 0; end if;
        delete from console.pnl_stock where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.pnl_rules where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.pnl_alias where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.pnl_heads where customer_id = p_cid; get diagnostics m = row_count; n := n + m;
        delete from console.pnl_settings where customer_id = p_cid;
        return n;
      end if;
      return console.app2_clear_pnl_base(p_app, p_cid, p_real_only);
    end $f$;
    revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
    revoke all on function console.app2_clear_pnl_base(text, uuid, boolean) from public, anon, authenticated;
  end if;
end $wrap$;

do $patch$
declare rec record; def text; nw text; n int := 0;
begin
  for rec in select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname in ('kmr_portal', 'kmr_portal_join') loop
    def := pg_get_functiondef(rec.oid); nw := def;
    if position('''pnl''' in def) = 0 then
      nw := regexp_replace(nw, $re$(\n\s*)(when 'dwm'\s+then console\.qp_member\(([a-z_.]+), em, 'dwm'\))$re$, E'\\1when ''pnl'' then console.qp_member(\\3, em, ''pnl'')\\1\\2');
    end if;
    if nw <> def then execute nw; n := n + 1; end if;
  end loop;
  raise notice 'PNL: % portal functions updated', n;
end $patch$;

create or replace function console.yb_apps() returns text[] language sql immutable as $$
  select array['ops','hrm','hrms','balloon','pd','capacity','sales','calib','dcg','inv','rmp','mmd','mnt','apqp','ppap','msa','spc','crm','d8','aud','tsk','mom','cad','layout','dwm','off','connect','pnl'] $$;
