-- =====================================================================
-- KMR apps - PRESENTATION SCREEN: action plans with owner, date and status.
--  One table shared by every app (app = the app key, e.g. hrms). Each app's access is checked with its own product code.
-- Safe to re-run.
-- =====================================================================
create table if not exists console.app_actions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  app text not null,
  kpi text,
  title text not null,
  standard text,
  owner text,
  due date,
  status text not null default 'Open' check (status in ('Open', 'In progress', 'Done')),
  note text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists app_actions_app on console.app_actions (customer_id, app);
alter table console.app_actions enable row level security;
drop policy if exists app_actions_staff on console.app_actions;
create policy app_actions_staff on console.app_actions for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_pres_actions_get(p_slug text, p_code text, p_app text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, p_code);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kpi', a.kpi, 'title', a.title, 'standard', a.standard, 'owner', a.owner, 'due', a.due, 'status', a.status, 'note', a.note, 'created_by', a.created_by, 'updated_at', a.updated_at) order by a.due nulls last, a.created_at)
    from console.app_actions a where a.customer_id = cid and a.app = p_app), '[]');
end $$;
revoke all on function public.kmr_pres_actions_get(text, text, text) from public, anon;
grant execute on function public.kmr_pres_actions_get(text, text, text) to authenticated;

create or replace function public.kmr_pres_action_save(p_slug text, p_code text, p_app text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, p_code); v_id uuid := nullif(p ->> 'id', '')::uuid; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if v_id is not null and exists (select 1 from console.app_actions where id = v_id and customer_id = cid and app = p_app) then
    update console.app_actions set
      kpi = case when p ? 'kpi' then nullif(p ->> 'kpi', '') else kpi end,
      title = case when p ? 'title' then coalesce(nullif(trim(p ->> 'title'), ''), title) else title end,
      standard = case when p ? 'standard' then nullif(p ->> 'standard', '') else standard end,
      owner = case when p ? 'owner' then nullif(p ->> 'owner', '') else owner end,
      due = case when p ? 'due' then nullif(p ->> 'due', '')::date else due end,
      status = case when p ? 'status' then p ->> 'status' else status end,
      note = case when p ? 'note' then nullif(p ->> 'note', '') else note end,
      updated_at = now()
    where id = v_id;
    return v_id;
  end if;
  if nullif(trim(p ->> 'title'), '') is null then raise exception 'Write the action.'; end if;
  insert into console.app_actions (customer_id, app, kpi, title, standard, owner, due, status, note, created_by)
  values (cid, p_app, nullif(p ->> 'kpi', ''), trim(p ->> 'title'), nullif(p ->> 'standard', ''), nullif(p ->> 'owner', ''), nullif(p ->> 'due', '')::date, coalesce(nullif(p ->> 'status', ''), 'Open'), nullif(p ->> 'note', ''), me)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.kmr_pres_action_save(text, text, text, jsonb) from public, anon;
grant execute on function public.kmr_pres_action_save(text, text, text, jsonb) to authenticated;

create or replace function public.kmr_pres_action_delete(p_slug text, p_code text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, p_code);
begin
  delete from console.app_actions where id = p_id and customer_id = cid;
end $$;
revoke all on function public.kmr_pres_action_delete(text, text, uuid) from public, anon;
grant execute on function public.kmr_pres_action_delete(text, text, uuid) to authenticated;
