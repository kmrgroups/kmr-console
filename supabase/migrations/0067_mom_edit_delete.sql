-- =====================================================================
-- 0067 — Minutes Of Meetings: edit finalised minutes, delete a meeting
--  • Editors can open finalised minutes for editing (Edit minutes); finalise again when done.
--  • Administrator can delete a meeting permanently (with its points and transcript). Void still keeps the record.
-- Needs 0066. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_mom_load(text)') is null then raise exception 'Run 0066_minutes_of_meetings.sql first.'; end if;
end $$;

create or replace function public.kmr_mom_reopen(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom'); m console.mom_meetings%rowtype;
begin
  select * into m from console.mom_meetings where id = p_id and customer_id = cid for update;
  if not found or m.status <> 'closed' then raise exception 'Only a finalised meeting can be opened for editing.'; end if;
  update console.mom_meetings set status = 'open', closed_by = null, closed_at = null, updated_at = now() where id = p_id;
  return console.mom_view(p_id);
end $$;

create or replace function public.kmr_mom_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mom');
begin
  if console.qp_role(cid, 'mom') <> 'admin' then raise exception 'Only an administrator can delete a meeting.'; end if;
  if not exists (select 1 from console.mom_meetings where id = p_id and customer_id = cid) then raise exception 'Meeting not found.'; end if;
  delete from console.mom_meetings where id = p_id;   -- points and transcript lines go with it
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('kmr_mom_reopen', 'kmr_mom_delete') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
