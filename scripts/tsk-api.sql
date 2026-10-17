-- ---------- helpers ----------
create or replace function console.tsk_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.tsk_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.tsk_counters.n + 1 returning n $$;
revoke all on function console.tsk_next(uuid, text) from public, anon, authenticated;

create or replace function console.tsk_me() returns text language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
create or replace function console.tsk_name(p_cid uuid, p_email text) returns text language sql stable security definer set search_path = console, public as $$
  select coalesce((select nullif(trim(m.full_name), '') from console.customer_members m where m.customer_id = p_cid and m.email = lower(p_email)), initcap(replace(split_part(coalesce(p_email, ''), '@', 1), '.', ' '))) $$;
-- administrators and editors see and manage every task; everybody else works with the tasks they gave or got
create or replace function console.tsk_full(p_cid uuid) returns boolean language sql stable security definer set search_path = console, public as $$
  select coalesce(console.qp_role(p_cid, 'tsk'), '') in ('admin', 'editor') $$;
create or replace function console.tsk_today(p jsonb) returns date language sql stable as $$
  select case when coalesce(p ->> 'today', '') ~ '^\d{4}-\d{2}-\d{2}$' then (p ->> 'today')::date else (now() at time zone 'Asia/Kolkata')::date end $$;
revoke all on function console.tsk_full(uuid) from public, anon, authenticated;

create or replace function console.tsk_note(p_cid uuid, p_to text, p_task uuid, p_kind text, p_title text, p_body text) returns void language plpgsql security definer set search_path = console, public as $$
begin
  if coalesce(p_to, '') = '' or p_to = console.tsk_me() then return; end if;
  insert into console.tsk_notifications (customer_id, to_email, task_id, kind, title, body) values (p_cid, lower(p_to), p_task, p_kind, left(p_title, 160), left(p_body, 300));
end $$;
revoke all on function console.tsk_note(uuid, text, uuid, text, text, text) from public, anon, authenticated;

create or replace function console.tsk_event(p_cid uuid, p_task uuid, p_text text) returns void language sql security definer set search_path = console, public as $$
  insert into console.tsk_comments (customer_id, task_id, author, author_name, body, kind) values (p_cid, p_task, console.tsk_me(), console.tsk_name(p_cid, console.tsk_me()), p_text, 'event') $$;
revoke all on function console.tsk_event(uuid, uuid, text) from public, anon, authenticated;

-- one task as the screen needs it
create or replace function console.tsk_json(t console.tsk_tasks, today date) returns jsonb language sql stable security definer set search_path = console, public as $$
  select jsonb_build_object('id', t.id, 'no', t.no, 'title', t.title, 'detail', t.detail, 'assignee', t.assignee, 'assignee_name', coalesce(t.assignee_name, console.tsk_name(t.customer_id, t.assignee)),
    'assigned_by', t.assigned_by, 'assigned_by_name', coalesce(t.assigned_by_name, console.tsk_name(t.customer_id, t.assigned_by)), 'priority', t.priority, 'status', t.status, 'due', t.due,
    'done_at', t.done_at, 'tags', t.tags, 'checklist', t.checklist, 'source_app', t.source_app, 'source_ref', t.source_ref, 'source_label', t.source_label, 'source_url', t.source_url,
    'created_at', t.created_at, 'updated_at', t.updated_at, 'sample', t.sample,
    'overdue', (t.status in ('open', 'progress', 'blocked') and t.due is not null and t.due < today),
    'comments', (select count(*) from console.tsk_comments c where c.task_id = t.id and c.kind = 'comment')) $$;
revoke all on function console.tsk_json(console.tsk_tasks, date) from public, anon, authenticated;

-- ---------- people, access ----------
create or replace function public.kmr_tsk_enabled(p_slug text) returns boolean language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  return cid is not null and console.qp_role(cid, 'tsk') is not null;
end $$;

create or replace function public.kmr_tsk_people(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me();
begin
  return jsonb_build_object('me', jsonb_build_object('email', me, 'name', console.tsk_name(cid, me)), 'role', console.qp_role(cid, 'tsk'), 'can_assign', console.tsk_full(cid),
    'people', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'name', coalesce(nullif(trim(m.full_name), ''), initcap(replace(split_part(m.email, '@', 1), '.', ' ')))) order by lower(coalesce(nullif(trim(m.full_name), ''), m.email)))
      from console.customer_members m where m.customer_id = cid and (m.is_admin or coalesce(m.roles ->> 'tsk', '') <> '')), '[]'));
end $$;

-- ---------- tasks ----------
create or replace function public.kmr_tsk_list(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); full_ boolean; today date := console.tsk_today(p); scope text := coalesce(nullif(p ->> 'scope', ''), 'mine');
        st text := coalesce(nullif(p ->> 'status', ''), 'active'); q text := nullif(trim(coalesce(p ->> 'q', '')), '');
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.my-tasks');
  full_ := console.tsk_full(cid);
  if scope in ('all', 'person') then perform console.require_feature(p_slug, 'tsk', 'tsk.assign-track'); end if;
  return coalesce((select jsonb_agg(console.tsk_json(t, today) order by (t.status in ('done', 'cancelled')), t.due nulls last, case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.created_at desc)
    from console.tsk_tasks t where t.id in (select t.id from console.tsk_tasks t where t.customer_id = cid
      and case scope when 'mine' then t.assignee = me when 'by_me' then t.assigned_by = me and coalesce(t.assignee, '') <> me
                     when 'person' then (full_ or t.assignee = me or t.assigned_by = me) and t.assignee = lower(coalesce(p ->> 'assignee', ''))
                     else (full_ or t.assignee = me or t.assigned_by = me) end
      and case st when 'active' then t.status in ('open', 'progress', 'blocked') when 'done' then t.status in ('done', 'cancelled') when 'all' then true else t.status = st end
      and (nullif(p ->> 'priority', '') is null or t.priority = p ->> 'priority')
      and (nullif(p ->> 'source_app', '') is null or t.source_app = p ->> 'source_app')
      and (q is null or t.title ilike '%' || q || '%' or t.no ilike '%' || q || '%' or coalesce(t.detail, '') ilike '%' || q || '%' or coalesce(t.tags, '') ilike '%' || q || '%')
      order by t.updated_at desc limit 500)), '[]');
end $$;

create or replace function public.kmr_tsk_get(p_slug text, p_id uuid, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks; full_ boolean := console.tsk_full(cid);
begin
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null or not (full_ or t.assignee = me or t.assigned_by = me) then raise exception 'Task not found.'; end if;
  return console.tsk_json(t, console.tsk_today(p)) || jsonb_build_object('can_edit', full_ or t.assigned_by = me, 'can_delete', full_ or t.assigned_by = me,
    'thread', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'author', c.author, 'name', coalesce(c.author_name, c.author), 'body', c.body, 'kind', c.kind, 'at', c.created_at) order by c.created_at) from console.tsk_comments c where c.task_id = t.id), '[]'));
end $$;

create or replace function public.kmr_tsk_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); full_ boolean := console.tsk_full(cid); v_id uuid := nullif(p ->> 'id', '')::uuid; t console.tsk_tasks;
        ttl text := console.hrms_txt(p, 'title'); asg text := lower(coalesce(console.hrms_txt(p, 'assignee'), '')); pr text := coalesce(console.hrms_txt(p, 'priority'), 'normal'); dd date := nullif(p ->> 'due', '')::date;
        cl jsonb := case when jsonb_typeof(p -> 'checklist') = 'array' then p -> 'checklist' else null end; sk text := console.hrms_txt(p, 'source_key'); old_asg text; nno text; src text := console.hrms_txt(p, 'source_app'); who text;
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.my-tasks');
  if pr not in ('low', 'normal', 'high', 'urgent') then raise exception 'Priority must be low, normal, high or urgent.'; end if;
  if asg <> '' and asg !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Pick the person from the list.'; end if;
  if v_id is null then
    if ttl is null then raise exception 'Enter what has to be done.'; end if;
    if asg = '' then asg := me; end if;
    if asg <> me then
      if not full_ then raise exception 'You can give tasks to other people only with editor access. Create it for yourself, or ask your administrator.'; end if;
      perform console.require_feature(p_slug, 'tsk', 'tsk.assign-track');
    end if;
    if sk is not null then
      select * into t from console.tsk_tasks where customer_id = cid and source_key = sk;
      if t.id is not null then return jsonb_build_object('id', t.id, 'no', t.no, 'existing', true); end if;
    end if;
    nno := 'T-' || lpad(console.tsk_next(cid, 'TSK')::text, 4, '0');
    insert into console.tsk_tasks (customer_id, no, title, detail, assignee, assignee_name, assigned_by, assigned_by_name, priority, due, tags, checklist, source_app, source_ref, source_label, source_url, source_key)
    values (cid, nno, ttl, console.hrms_txt(p, 'detail'), asg, console.tsk_name(cid, asg), me, console.tsk_name(cid, me), pr, dd, console.hrms_txt(p, 'tags'), coalesce(cl, '[]'),
            src, console.hrms_txt(p, 'source_ref'), console.hrms_txt(p, 'source_label'), console.hrms_txt(p, 'source_url'), sk) returning * into t;
    perform console.tsk_event(cid, t.id, 'Task created' || case when src is not null then ' from ' || coalesce(console.hrms_txt(p, 'source_label'), src) else '' end || case when asg <> me then ' and assigned to ' || t.assignee_name else '' end || '.');
    perform console.tsk_note(cid, asg, t.id, 'assigned', 'New task: ' || ttl, console.tsk_name(cid, me) || ' assigned you ' || nno || case when dd is not null then ', due ' || to_char(dd, 'DD Mon') else '' end || '.');
    return jsonb_build_object('id', t.id, 'no', t.no);
  end if;
  select * into t from console.tsk_tasks where id = v_id and customer_id = cid;
  if t.id is null then raise exception 'Task not found.'; end if;
  old_asg := t.assignee;
  if not (full_ or t.assigned_by = me) then raise exception 'Only the person who gave this task, or an editor, can change it. You can update its status and add comments.'; end if;
  if ttl is null then raise exception 'Enter what has to be done.'; end if;
  if asg = '' then asg := coalesce(t.assignee, me); end if;
  if asg <> t.assignee and asg <> me then perform console.require_feature(p_slug, 'tsk', 'tsk.assign-track'); end if;
  update console.tsk_tasks set title = ttl, detail = console.hrms_txt(p, 'detail'), assignee = asg, assignee_name = case when asg = t.assignee then t.assignee_name else console.tsk_name(cid, asg) end,
         priority = pr, due = dd, tags = console.hrms_txt(p, 'tags'), checklist = coalesce(cl, t.checklist), last_due_note = case when dd is distinct from t.due then null else t.last_due_note end, updated_at = now()
   where id = t.id returning * into t;
  if asg is distinct from old_asg then
    perform console.tsk_event(cid, t.id, 'Reassigned from ' || coalesce(console.tsk_name(cid, old_asg), 'nobody') || ' to ' || t.assignee_name || '.');
    perform console.tsk_note(cid, asg, t.id, 'assigned', 'Task for you: ' || t.title, console.tsk_name(cid, me) || ' assigned you ' || t.no || '.');
  end if;
  return jsonb_build_object('id', t.id, 'no', t.no);
end $$;

create or replace function public.kmr_tsk_reassign(p_slug text, p_id uuid, p_assignee text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks; asg text := lower(trim(coalesce(p_assignee, '')));
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.assign-track');
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null then raise exception 'Task not found.'; end if;
  if not (console.tsk_full(cid) or t.assigned_by = me) then raise exception 'Only the person who gave this task, or an editor, can hand it to someone else.'; end if;
  if asg !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Pick the person from the list.'; end if;
  if asg = t.assignee then return; end if;
  update console.tsk_tasks set assignee = asg, assignee_name = console.tsk_name(cid, asg), last_due_note = null, updated_at = now() where id = t.id;
  perform console.tsk_event(cid, t.id, 'Reassigned from ' || coalesce(t.assignee_name, t.assignee, 'nobody') || ' to ' || console.tsk_name(cid, asg) || '.');
  perform console.tsk_note(cid, asg, t.id, 'assigned', 'Task for you: ' || t.title, console.tsk_name(cid, me) || ' handed you ' || t.no || '.');
end $$;

create or replace function public.kmr_tsk_status(p_slug text, p_id uuid, p_status text, p_note text default null) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks; lbl text; nm text := console.tsk_name(console.qp_cid(p_slug, 'tsk'), console.tsk_me());
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.my-tasks');
  if p_status not in ('open', 'progress', 'blocked', 'done', 'cancelled') then raise exception 'Unknown status.'; end if;
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null or not (console.tsk_full(cid) or t.assignee = me or t.assigned_by = me) then raise exception 'Task not found.'; end if;
  if t.status = p_status then return; end if;
  lbl := case p_status when 'open' then 'To do' when 'progress' then 'In progress' when 'blocked' then 'Blocked' when 'done' then 'Done' else 'Cancelled' end;
  update console.tsk_tasks set status = p_status, done_at = case when p_status = 'done' then now() else null end, updated_at = now() where id = t.id;
  perform console.tsk_event(cid, t.id, 'Status changed to ' || lbl || case when nullif(trim(coalesce(p_note, '')), '') is not null then ': ' || trim(p_note) else '.' end);
  -- tell the other side
  perform console.tsk_note(cid, case when t.assigned_by <> me then t.assigned_by else null end, t.id, 'status', t.no || ' is ' || lbl, nm || ' moved "' || t.title || '" to ' || lbl || '.');
  if t.assignee <> me and t.assignee is distinct from t.assigned_by then perform console.tsk_note(cid, t.assignee, t.id, 'status', t.no || ' is ' || lbl, nm || ' moved "' || t.title || '" to ' || lbl || '.'); end if;
end $$;

create or replace function public.kmr_tsk_check(p_slug text, p_id uuid, p_checklist jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks;
begin
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null or not (console.tsk_full(cid) or t.assignee = me or t.assigned_by = me) then raise exception 'Task not found.'; end if;
  if jsonb_typeof(p_checklist) <> 'array' then raise exception 'Checklist must be a list.'; end if;
  update console.tsk_tasks set checklist = p_checklist, updated_at = now() where id = t.id;
end $$;

create or replace function public.kmr_tsk_comment(p_slug text, p_id uuid, p_body text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks; nm text; b text := nullif(trim(coalesce(p_body, '')), '');
begin
  if b is null then raise exception 'Write a comment first.'; end if;
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null or not (console.tsk_full(cid) or t.assignee = me or t.assigned_by = me) then raise exception 'Task not found.'; end if;
  nm := console.tsk_name(cid, me);
  insert into console.tsk_comments (customer_id, task_id, author, author_name, body) values (cid, t.id, me, nm, left(b, 2000));
  update console.tsk_tasks set updated_at = now() where id = t.id;
  perform console.tsk_note(cid, t.assignee, t.id, 'comment', 'New comment on ' || t.no, nm || ': ' || b);
  if t.assigned_by is distinct from t.assignee then perform console.tsk_note(cid, t.assigned_by, t.id, 'comment', 'New comment on ' || t.no, nm || ': ' || b); end if;
end $$;

create or replace function public.kmr_tsk_delete(p_slug text, p_id uuid) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); t console.tsk_tasks;
begin
  select * into t from console.tsk_tasks where id = p_id and customer_id = cid;
  if t.id is null then return; end if;
  if not (console.tsk_full(cid) or t.assigned_by = me) then raise exception 'Only the person who gave this task, or an editor, can delete it.'; end if;
  delete from console.tsk_tasks where id = t.id;
end $$;

-- ---------- dashboard ----------
create or replace function public.kmr_tsk_dashboard(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me(); today date := console.tsk_today(p); team boolean; out jsonb;
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.dashboard');
  team := coalesce(p ->> 'scope', 'mine') = 'team' and console.tsk_full(cid);
  with t as (select * from console.tsk_tasks x where x.customer_id = cid and (team or x.assignee = me)),
       a as (select * from t where status in ('open', 'progress', 'blocked'))
  select jsonb_build_object('team', team,
    'open', (select count(*) from a where status = 'open'), 'progress', (select count(*) from a where status = 'progress'), 'blocked', (select count(*) from a where status = 'blocked'),
    'overdue', (select count(*) from a where due < today), 'due_today', (select count(*) from a where due = today), 'due_week', (select count(*) from a where due > today and due <= today + 7),
    'no_date', (select count(*) from a where due is null),
    'done_week', (select count(*) from t where status = 'done' and done_at >= (today - 6)::timestamptz), 'done_total', (select count(*) from t where status = 'done'), 'total', (select count(*) from t),
    'by_person', coalesce((select jsonb_agg(r order by (r ->> 'overdue')::int desc, (r ->> 'open')::int desc) from (
        select jsonb_build_object('email', coalesce(assignee, ''), 'name', coalesce(max(assignee_name), console.tsk_name(cid, assignee), 'Unassigned'),
          'open', count(*) filter (where status in ('open', 'progress', 'blocked')), 'overdue', count(*) filter (where status in ('open', 'progress', 'blocked') and due < today),
          'done', count(*) filter (where status = 'done')) r from t group by assignee) z where (r ->> 'open')::int + (r ->> 'done')::int > 0), '[]'),
    'by_priority', jsonb_build_object('urgent', (select count(*) from a where priority = 'urgent'), 'high', (select count(*) from a where priority = 'high'), 'normal', (select count(*) from a where priority = 'normal'), 'low', (select count(*) from a where priority = 'low')),
    'by_source', coalesce((select jsonb_agg(jsonb_build_object('app', app, 'label', lbl, 'n', n) order by n desc) from (select coalesce(source_app, 'direct') app, coalesce(max(source_label), '') lbl, count(*) n from a group by coalesce(source_app, 'direct')) s), '[]'),
    'trend', (select jsonb_agg(jsonb_build_object('d', d, 'created', (select count(*) from t where t.created_at::date = d), 'done', (select count(*) from t where t.status = 'done' and t.done_at::date = d)) order by d)
              from (select (today - g)::date d from generate_series(0, 13) g) q),
    'late', coalesce((select jsonb_agg(console.tsk_json(x, today) order by x.due) from (select * from a where due < today order by due limit 8) x), '[]')) into out;
  return out;
end $$;

-- ---------- notifications ----------
create or replace function public.kmr_tsk_notes(p_slug text, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me();
begin
  return jsonb_build_object('unread', (select count(*) from console.tsk_notifications where customer_id = cid and to_email = me and not is_read),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'task_id', n.task_id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'read', n.is_read, 'at', n.created_at) order by n.created_at desc)
      from (select * from console.tsk_notifications where customer_id = cid and to_email = me order by created_at desc limit least(coalesce(nullif(p ->> 'limit', '')::int, 30), 100)) n), '[]'));
end $$;

create or replace function public.kmr_tsk_notes_read(p_slug text, p jsonb default '{}') returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me();
begin
  if jsonb_typeof(p -> 'ids') = 'array' then
    update console.tsk_notifications set is_read = true where customer_id = cid and to_email = me and id in (select (v #>> '{}')::uuid from jsonb_array_elements(p -> 'ids') v);
  else update console.tsk_notifications set is_read = true where customer_id = cid and to_email = me and not is_read; end if;
end $$;

create or replace function public.kmr_tsk_push_subscribe(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk'); me text := console.tsk_me();
begin
  perform console.require_feature(p_slug, 'tsk', 'tsk.notifications');
  if console.hrms_txt(p, 'endpoint') is null or console.hrms_txt(p, 'p256dh') is null or console.hrms_txt(p, 'auth') is null then raise exception 'This device did not give a valid notification address.'; end if;
  insert into console.tsk_push_subs (customer_id, email, endpoint, p256dh, auth, ua) values (cid, me, p ->> 'endpoint', p ->> 'p256dh', p ->> 'auth', left(p ->> 'ua', 200))
  on conflict (endpoint) do update set customer_id = excluded.customer_id, email = excluded.email, p256dh = excluded.p256dh, auth = excluded.auth, ua = excluded.ua;
end $$;
create or replace function public.kmr_tsk_push_unsubscribe(p_slug text, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk');
begin delete from console.tsk_push_subs where customer_id = cid and email = console.tsk_me() and endpoint = p ->> 'endpoint'; end $$;
create or replace function public.kmr_tsk_push_devices(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'tsk');
begin return coalesce((select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'ua', ua, 'at', created_at) order by created_at desc) from console.tsk_push_subs where customer_id = cid and email = console.tsk_me()), '[]'); end $$;

-- called only by the Console server (service role): sends pending notifications as phone / desktop pushes and raises due-date reminders
create or replace function public.kmr_tsk_due_scan() returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; today date := (now() at time zone 'Asia/Kolkata')::date; t record;
begin
  for t in select * from console.tsk_tasks x where x.status in ('open', 'progress', 'blocked') and x.assignee is not null and x.due is not null and x.due <= today + 1 and x.last_due_note is distinct from today
             and coalesce((select ok from console.access_state('tsk', x.customer_id)), false) loop
    insert into console.tsk_notifications (customer_id, to_email, task_id, kind, title, body)
    values (t.customer_id, t.assignee, t.id, case when t.due < today then 'overdue' when t.due = today then 'due' else 'soon' end,
            case when t.due < today then 'Overdue: ' when t.due = today then 'Due today: ' else 'Due tomorrow: ' end || left(t.title, 120),
            t.no || ' · ' || initcap(t.priority) || ' priority' || case when t.due < today then ' · ' || (today - t.due) || ' day(s) late' else '' end);
    update console.tsk_tasks set last_due_note = today where id = t.id;
    n := n + 1;
  end loop;
  return n;
end $$;
create or replace function public.kmr_tsk_push_take(p_limit integer default 100) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare out jsonb;
begin
  with take as (select id from console.tsk_notifications where not pushed order by created_at limit least(coalesce(p_limit, 100), 500) for update skip locked),
       mark as (update console.tsk_notifications n set pushed = true from take where n.id = take.id returning n.*)
  select coalesce(jsonb_agg(jsonb_build_object('nid', m.id, 'title', m.title, 'body', m.body, 'task_id', m.task_id, 'slug', c.slug, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)), '[]') into out
    from mark m join console.customers c on c.id = m.customer_id join console.tsk_push_subs s on s.customer_id = m.customer_id and s.email = m.to_email;
  return out;
end $$;
create or replace function public.kmr_tsk_push_drop(p_endpoint text) returns void language sql security definer set search_path = console, public as $$
  delete from console.tsk_push_subs where endpoint = p_endpoint $$;
revoke all on function public.kmr_tsk_due_scan(), public.kmr_tsk_push_take(integer), public.kmr_tsk_push_drop(text) from public, anon, authenticated;
grant execute on function public.kmr_tsk_due_scan(), public.kmr_tsk_push_take(integer), public.kmr_tsk_push_drop(text) to service_role;

-- ---------- sample data: tasks to try the flow with, deleted again from Data Master ----------
create or replace function console.tsk_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; me text := coalesce(nullif(console.tsk_me(), ''), 'you@sample.example'); today date := (now() at time zone 'Asia/Kolkata')::date; i int; r record; tid uuid; nno text;
begin
  if p_action = 'flush' then
    delete from console.tsk_notifications where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.tsk_comments where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.tsk_tasks where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.tsk_tasks where customer_id = p_cid and sample) then return 0; end if;
  for r in select * from (values
    (1, 'Send revised quotation to Apex Auto', 'Include the new tooling cost and the 8-week lead time.', 'ravi@sample.example', 'Ravi Kumar', 'high', 'open', 1, 'sales', 'Sales Flow', 'Enquiry follow-up'),
    (2, 'Close corrective action for customer complaint', 'Root cause and containment are done; attach the 8D report.', null, 'You', 'urgent', 'progress', -2, 'mom', 'Minutes of Meetings', 'Quality review'),
    (3, 'Calibrate micrometer set MC-04', null, 'priya@sample.example', 'Priya Nair', 'normal', 'open', 3, null, null, 'Calibration'),
    (4, 'Update the control plan after the process change', 'Reflect the new torque value on station 3.', null, 'You', 'high', 'open', 0, 'mom', 'Minutes of Meetings', 'Quality review'),
    (5, 'Arrange packing material for the PO due next week', null, 'ravi@sample.example', 'Ravi Kumar', 'normal', 'blocked', -1, null, null, 'Stores'),
    (6, 'Share the monthly sales report', null, null, 'You', 'low', 'done', -4, 'sales', 'Sales Flow', 'Reports'),
    (7, 'Book a vendor audit slot', 'Two vendors are pending: surface treatment and casting.', 'priya@sample.example', 'Priya Nair', 'normal', 'progress', 5, null, null, 'Quality'),
    (8, 'Fix the loose guard on press P-12', 'Safety item raised in the shop-floor round.', 'anil@sample.example', 'Anil Shah', 'urgent', 'open', -3, 'mom', 'Minutes of Meetings', 'Safety')) v(i, ttl, det, who, nm, pr, st, off, sa, sl, tg)
  loop
    nno := 'T-' || lpad(console.tsk_next(p_cid, 'TSK')::text, 4, '0');
    insert into console.tsk_tasks (customer_id, no, title, detail, assignee, assignee_name, assigned_by, assigned_by_name, priority, status, due, done_at, tags, source_app, source_label, sample, checklist)
    values (p_cid, nno, r.ttl, r.det, coalesce(r.who, me), r.nm, me, 'You', r.pr, r.st, today + r.off, case when r.st = 'done' then now() - interval '2 days' else null end, r.tg, r.sa, r.sl, true,
            case when r.i = 2 then '[{"t":"Root cause written","d":true},{"t":"Containment checked","d":true},{"t":"8D report attached","d":false}]'::jsonb else '[]'::jsonb end) returning id into tid;
    insert into console.tsk_comments (customer_id, task_id, author, author_name, body, kind, sample) values (p_cid, tid, me, 'You', 'Task created.', 'event', true);
    n := n + 1;
  end loop;
  insert into console.tsk_notifications (customer_id, to_email, task_id, kind, title, body, sample)
  select p_cid, me, t.id, 'overdue', 'Overdue: ' || t.title, t.no || ' · ' || initcap(t.priority) || ' priority', true from console.tsk_tasks t where t.customer_id = p_cid and t.sample and t.assignee = me and t.status <> 'done' and t.due < today;
  return n;
end $$;
revoke all on function console.tsk_sample(uuid, text) from public, anon, authenticated;
