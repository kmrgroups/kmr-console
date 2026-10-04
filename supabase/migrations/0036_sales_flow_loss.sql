-- Sales Flow 0036 — Sales loss reasons (per plan line) and Action plans. Needs 0033. Safe to re-run.
--  • sf_lines gets loss_reason / loss_other ("Others" = customised typing).
--  • sf_actions = action plans: issue (loss reason), brief, immediate action, permanent action, responsibility,
--    target date, status (Opened / Under progress / Closed); optionally linked to one plan line (customer + part copied).
alter table console.sf_lines add column if not exists loss_reason text;
alter table console.sf_lines add column if not exists loss_other  text;

create table if not exists console.sf_actions (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references console.customers(id) on delete cascade,
  month            date,
  line_id          uuid references console.sf_lines(id) on delete set null,
  buyer_name       text not null default '',
  part_code        text not null default '',
  part_name        text not null default '',
  issue            text not null check (length(trim(issue)) > 0),
  issue_other      text,
  brief            text not null default '',
  immediate_action text not null default '',
  permanent_action text not null default '',
  responsible      text not null default '',
  target_date      date,
  status           text not null default 'Opened' check (status in ('Opened','Under progress','Closed')),
  closed_at        timestamptz,
  created_at       timestamptz not null default now(),
  created_by       text,
  updated_at       timestamptz not null default now(),
  updated_by       text
);
create index if not exists sf_actions_cust on console.sf_actions (customer_id, status, target_date);
alter table console.sf_actions enable row level security;
drop policy if exists sf_actions_staff on console.sf_actions;
create policy sf_actions_staff on console.sf_actions for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- reasons: p_rows = [{id, loss_reason, loss_other}]
create or replace function public.kmr_sf_save_loss(p_slug text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; rs text;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    rs := nullif(trim(coalesce(r ->> 'loss_reason', '')), '');
    if rs is not null and length(rs) > 80 then raise exception 'The reason is too long.'; end if;
    update console.sf_lines
       set loss_reason = rs,
           loss_other  = case when rs = 'Others' then left(nullif(trim(coalesce(r ->> 'loss_other', '')), ''), 120) end
     where id = (r ->> 'id')::uuid and customer_id = cid;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_sf_save_loss(text, jsonb) to authenticated;

create or replace function public.kmr_sf_actions(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.sf_role(cid) is null then raise exception 'You have no access to Sales Flow.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(a) - 'customer_id' order by (a.status = 'Closed'), a.target_date nulls last, a.created_at desc)
                     from console.sf_actions a where a.customer_id = cid), '[]');
end $$;
grant execute on function public.kmr_sf_actions(text) to authenticated;

-- p = {id?, issue, issue_other, line_id, month, buyer_name, part_code, part_name, brief, immediate_action, permanent_action,
--      responsible, target_date, status}
create or replace function public.kmr_sf_save_action(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); st text := coalesce(nullif(p ->> 'status', ''), 'Opened');
        rid uuid; old console.sf_actions; ln uuid; ln_row console.sf_lines;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view Sales Flow but not change it. Ask your administrator for editor access.';
  end if;
  if st not in ('Opened','Under progress','Closed') then raise exception 'Status must be Opened, Under progress or Closed.'; end if;
  if length(trim(coalesce(p ->> 'issue', ''))) = 0 then raise exception 'Choose the issue.'; end if;
  if length(trim(coalesce(p ->> 'brief', ''))) = 0 then raise exception 'Write the issue brief.'; end if;
  if length(trim(coalesce(p ->> 'responsible', ''))) = 0 then raise exception 'Enter who is responsible.'; end if;
  if coalesce(p ->> 'target_date', '') = '' then raise exception 'Choose the target date.'; end if;
  ln := nullif(p ->> 'line_id', '')::uuid;
  if ln is not null then
    select * into ln_row from console.sf_lines where id = ln and customer_id = cid;
    if ln_row.id is null then ln := null; end if;
  end if;
  if nullif(p ->> 'id', '') is not null then
    select * into old from console.sf_actions where id = (p ->> 'id')::uuid and customer_id = cid;
    if old.id is null then raise exception 'Action plan not found.'; end if;
    update console.sf_actions set
        month = coalesce(ln_row.month, nullif(p ->> 'month', '')::date), line_id = ln,
        buyer_name = coalesce(ln_row.buyer_name, left(coalesce(p ->> 'buyer_name', ''), 200)),
        part_code = coalesce(ln_row.part_code, left(coalesce(p ->> 'part_code', ''), 80)),
        part_name = coalesce(ln_row.part_name, left(coalesce(p ->> 'part_name', ''), 200)),
        issue = left(trim(p ->> 'issue'), 80), issue_other = case when trim(p ->> 'issue') = 'Others' then left(nullif(trim(coalesce(p ->> 'issue_other', '')), ''), 120) end,
        brief = left(trim(p ->> 'brief'), 4000), immediate_action = left(trim(coalesce(p ->> 'immediate_action', '')), 4000),
        permanent_action = left(trim(coalesce(p ->> 'permanent_action', '')), 4000), responsible = left(trim(p ->> 'responsible'), 120),
        target_date = (p ->> 'target_date')::date, status = st,
        closed_at = case when st = 'Closed' then coalesce(old.closed_at, now()) else null end, updated_at = now(), updated_by = me
      where id = old.id;
    rid := old.id;
  else
    insert into console.sf_actions (customer_id, month, line_id, buyer_name, part_code, part_name, issue, issue_other, brief, immediate_action,
                                    permanent_action, responsible, target_date, status, closed_at, created_by, updated_by)
    values (cid, coalesce(ln_row.month, nullif(p ->> 'month', '')::date), ln, coalesce(ln_row.buyer_name, left(coalesce(p ->> 'buyer_name', ''), 200)),
            coalesce(ln_row.part_code, left(coalesce(p ->> 'part_code', ''), 80)), coalesce(ln_row.part_name, left(coalesce(p ->> 'part_name', ''), 200)),
            left(trim(p ->> 'issue'), 80), case when trim(p ->> 'issue') = 'Others' then left(nullif(trim(coalesce(p ->> 'issue_other', '')), ''), 120) end,
            left(trim(p ->> 'brief'), 4000), left(trim(coalesce(p ->> 'immediate_action', '')), 4000), left(trim(coalesce(p ->> 'permanent_action', '')), 4000),
            left(trim(p ->> 'responsible'), 120), (p ->> 'target_date')::date, st, case when st = 'Closed' then now() end, me, me)
    returning id into rid;
  end if;
  return jsonb_build_object('id', rid);
end $$;
grant execute on function public.kmr_sf_save_action(text, jsonb) to authenticated;

create or replace function public.kmr_sf_delete_action(p_slug text, p_id uuid) returns text
language plpgsql security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.sf_role(cid), '') not in ('admin','editor') then raise exception 'You cannot change Sales Flow.'; end if;
  delete from console.sf_actions where id = p_id and customer_id = cid;
  return 'ok';
end $$;
grant execute on function public.kmr_sf_delete_action(text, uuid) to authenticated;
