-- ---------- helpers ----------
create or replace function console.mnt_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.mnt_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.mnt_counters.n + 1 returning n $$;
revoke all on function console.mnt_next(uuid, text) from public, anon, authenticated;

-- a closed breakdown books its downtime in MMD loss hours (one row per calendar day) against the chosen D code
create or replace function console.mnt_book_loss(p_cid uuid, p_bd uuid, p_me text) returns void language plpgsql security definer set search_path = console, public as $$
declare b console.mnt_breakdowns%rowtype; t timestamptz; nxt timestamptz; mins numeric; dn text; ist text := 'Asia/Kolkata';
begin
  select * into b from console.mnt_breakdowns where id = p_bd;
  delete from console.mmd_loss where customer_id = p_cid and ref = b.bd_no;
  if b.d_code is null or b.ended_at is null or not exists (select 1 from console.licences where customer_id = p_cid and product_code = 'mmd') then return; end if;
  select name into dn from console.ops_records where customer_id = p_cid and kind = 'loss_codes' and code = b.d_code;
  t := b.started_at;
  while t < b.ended_at loop
    nxt := least(b.ended_at, ((date_trunc('day', t at time zone ist) + interval '1 day') at time zone ist));
    mins := round(extract(epoch from (nxt - t)) / 60);
    if mins >= 1 then
      insert into console.mmd_loss (customer_id, loss_date, shift, machine_code, d_code, d_name, minutes, remark, operator, ref, sample, created_by)
      values (p_cid, (t at time zone ist)::date, b.shift, b.machine_code, b.d_code, dn, least(1440, mins), 'Breakdown ' || b.bd_no || ': ' || left(b.problem, 120), b.reported_by, b.bd_no, b.sample, p_me);
    end if;
    t := nxt;
  end loop;
end $$;
revoke all on function console.mnt_book_loss(uuid, uuid, text) from public, anon, authenticated;

create or replace function console.mnt_freq(p text) returns int language sql immutable as $$
  select case lower(coalesce(p, '')) when 'daily' then 1 when 'weekly' then 7 when 'monthly' then 30 when 'quarterly' then 90 when 'half-yearly' then 182 when 'yearly' then 365 else null end $$;

-- ---------- reads ----------
create or replace function public.kmr_mnt_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mnt');
begin
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.active), '[]'),
    'loss_codes', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'loss_codes' and r.active), '[]'),
    'shifts', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name) || r.data order by r.code) from console.ops_records r where r.customer_id = cid and r.kind = 'shifts' and r.active), '[]'),
    'plant', (select r.data from console.ops_records r where r.customer_id = cid and r.kind = 'plant_standards' and r.active order by r.code limit 1),
    'has_mmd', exists (select 1 from console.licences where customer_id = cid and product_code = 'mmd'),
    'today', (now() at time zone 'Asia/Kolkata')::date, 'now', now());
end $$;

create or replace function public.kmr_mnt_data(p_slug text, p_days int default 180) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mnt'); since timestamptz := now() - make_interval(days => greatest(7, least(coalesce(p_days, 180), 1100)));
begin
  return jsonb_build_object(
    'breakdowns', coalesce((select jsonb_agg(to_jsonb(b) - 'customer_id' order by b.started_at desc) from console.mnt_breakdowns b where b.customer_id = cid and b.status <> 'void' and (b.status in ('open', 'attended') or b.started_at >= since or b.ended_at >= since)), '[]'),
    'plans', coalesce((select jsonb_agg(to_jsonb(p) - 'customer_id' order by p.next_due, p.machine_code) from console.mnt_pm_plans p where p.customer_id = cid and p.active), '[]'),
    'pm_log', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.done_on desc, l.created_at desc) from console.mnt_pm_log l where l.customer_id = cid and l.status = 'ok' and l.done_on >= (since at time zone 'Asia/Kolkata')::date), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.event_date desc) from console.mnt_events e where e.customer_id = cid and e.status = 'ok' and e.event_date >= (since at time zone 'Asia/Kolkata')::date), '[]'),
    'losses', case when exists (select 1 from console.licences where customer_id = cid and product_code = 'mmd')
                   then coalesce((select jsonb_agg(jsonb_build_object('loss_date', l.loss_date, 'machine_code', l.machine_code, 'd_code', l.d_code, 'd_name', l.d_name, 'minutes', l.minutes) order by l.loss_date desc)
                                    from console.mmd_loss l where l.customer_id = cid and l.status = 'ok' and l.ref is null and l.loss_date >= (since at time zone 'Asia/Kolkata')::date), '[]') else '[]'::jsonb end,
    'today', (now() at time zone 'Asia/Kolkata')::date, 'now', now());
end $$;

-- the machine history card: everything ever recorded for one machine
create or replace function public.kmr_mnt_card(p_slug text, p_machine text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'mnt'); m record;
begin
  perform console.require_feature(p_slug, 'mnt', 'mnt.machine-history-card');
  select r.code, r.name, r.data into m from console.ops_records r where r.customer_id = cid and r.kind = 'machines' and r.code = p_machine;
  if not found then raise exception 'Machine “%” is not in Operations Master › Machines.', coalesce(p_machine, ''); end if;
  return jsonb_build_object('machine', jsonb_build_object('code', m.code, 'name', m.name) || m.data,
    'breakdowns', coalesce((select jsonb_agg(to_jsonb(b) - 'customer_id' order by b.started_at desc) from console.mnt_breakdowns b where b.customer_id = cid and b.machine_code = p_machine and b.status <> 'void'), '[]'),
    'pm_log', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.done_on desc) from console.mnt_pm_log l where l.customer_id = cid and l.machine_code = p_machine and l.status = 'ok'), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(e) - 'customer_id' order by e.event_date desc) from console.mnt_events e where e.customer_id = cid and e.machine_code = p_machine and e.status = 'ok'), '[]'),
    'plans', coalesce((select jsonb_agg(to_jsonb(p) - 'customer_id' order by p.next_due) from console.mnt_pm_plans p where p.customer_id = cid and p.machine_code = p_machine and p.active), '[]'),
    'today', (now() at time zone 'Asia/Kolkata')::date, 'now', now());
end $$;

-- ---------- breakdowns ----------
create or replace function public.kmr_mnt_bd_start(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); mc text := trim(coalesce(p ->> 'machine_code', '')); mn text; st timestamptz := coalesce(nullif(p ->> 'started_at', '')::timestamptz, now()); pr text := trim(coalesce(p ->> 'problem', ''));
        v_id uuid; no text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select name into mn from console.ops_records where customer_id = cid and kind = 'machines' and code = mc;
  if mn is null and not exists (select 1 from console.ops_records where customer_id = cid and kind = 'machines' and code = mc) then raise exception 'Choose the machine (Operations Master › Machines).'; end if;
  if pr = '' then raise exception 'Describe the problem.'; end if;
  if st > now() + interval '5 minutes' then raise exception 'The breakdown cannot start in the future.'; end if;
  if exists (select 1 from console.mnt_breakdowns where customer_id = cid and machine_code = mc and status in ('open', 'attended')) then raise exception 'Machine % already has an open breakdown. Close it first.', mc; end if;
  no := 'BD-' || to_char(st at time zone 'Asia/Kolkata', 'YYMM') || '-' || lpad(console.mnt_next(cid, 'BD-' || to_char(st at time zone 'Asia/Kolkata', 'YYMM'))::text, 4, '0');
  insert into console.mnt_breakdowns (customer_id, bd_no, machine_code, machine_name, started_at, shift, reported_by, problem, category, created_by)
  values (cid, no, mc, mn, st, nullif(p ->> 'shift', ''), coalesce(nullif(trim(p ->> 'reported_by'), ''), me), pr, nullif(p ->> 'category', ''), me) returning id into v_id;
  return (select to_jsonb(b) - 'customer_id' from console.mnt_breakdowns b where b.id = v_id);
end $$;

create or replace function public.kmr_mnt_bd_attend(p_slug text, p_id uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); b console.mnt_breakdowns%rowtype; at timestamptz := coalesce(nullif(p ->> 'attended_at', '')::timestamptz, now());
begin
  select * into b from console.mnt_breakdowns where id = p_id and customer_id = cid for update;
  if not found or b.status <> 'open' then raise exception 'Only a breakdown that is waiting for attention can be marked as attended.'; end if;
  if at < b.started_at then raise exception 'Attended time is before the breakdown started.'; end if;
  update console.mnt_breakdowns set attended_at = at, attended_by = coalesce(nullif(trim(p ->> 'attended_by'), ''), lower(coalesce(auth.jwt() ->> 'email', ''))), status = 'attended' where id = p_id;
end $$;

create or replace function public.kmr_mnt_bd_close(p_slug text, p_id uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); b console.mnt_breakdowns%rowtype; en timestamptz := coalesce(nullif(p ->> 'ended_at', '')::timestamptz, now()); dc text := nullif(trim(coalesce(p ->> 'd_code', '')), '');
        me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select * into b from console.mnt_breakdowns where id = p_id and customer_id = cid for update;
  if not found or b.status not in ('open', 'attended') then raise exception 'This breakdown is already closed.'; end if;
  if en <= b.started_at then raise exception 'The machine cannot be restored before the breakdown started.'; end if;
  if en > now() + interval '5 minutes' then raise exception 'The restore time cannot be in the future.'; end if;
  if coalesce(trim(p ->> 'category'), '') = '' then raise exception 'Choose the cause category.'; end if;
  if coalesce(trim(p ->> 'root_cause'), '') = '' then raise exception 'Enter the root cause.'; end if;
  if coalesce(trim(p ->> 'action_taken'), '') = '' then raise exception 'Enter the corrective action taken.'; end if;
  if dc is not null and not exists (select 1 from console.ops_records where customer_id = cid and kind = 'loss_codes' and code = dc) then raise exception 'Loss code % is not in Operations Master › Loss codes.', dc; end if;
  update console.mnt_breakdowns set ended_at = en, status = 'closed', closed_by = me, category = trim(p ->> 'category'), d_code = dc, root_cause = trim(p ->> 'root_cause'), action_taken = trim(p ->> 'action_taken'),
         preventive_action = nullif(trim(coalesce(p ->> 'preventive_action', '')), ''), spares = coalesce(case when jsonb_typeof(p -> 'spares') = 'array' then p -> 'spares' end, '[]'), attended_by = coalesce(attended_by, nullif(trim(p ->> 'attended_by'), '')),
         attended_at = coalesce(attended_at, nullif(p ->> 'attended_at', '')::timestamptz) where id = p_id;
  perform console.mnt_book_loss(cid, p_id, me);
end $$;

create or replace function public.kmr_mnt_bd_void(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); b console.mnt_breakdowns%rowtype;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the breakdown.'; end if;
  select * into b from console.mnt_breakdowns where id = p_id and customer_id = cid for update;
  if not found or b.status = 'void' then raise exception 'Breakdown not found.'; end if;
  update console.mnt_breakdowns set status = 'void', void_reason = trim(p_reason) where id = p_id;
  delete from console.mmd_loss where customer_id = cid and ref = b.bd_no;
end $$;

-- ---------- preventive maintenance ----------
create or replace function public.kmr_mnt_pm_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); v_id uuid := nullif(p ->> 'id', '')::uuid; mc text := trim(coalesce(p ->> 'machine_code', '')); fq int := nullif(p ->> 'frequency_days', '')::int; nd date := nullif(p ->> 'next_due', '')::date;
        mn text; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  perform console.require_feature(p_slug, 'mnt', 'mnt.preventive-maintenance');
  select name into mn from console.ops_records where customer_id = cid and kind = 'machines' and code = mc;
  if not exists (select 1 from console.ops_records where customer_id = cid and kind = 'machines' and code = mc) then raise exception 'Choose the machine.'; end if;
  if coalesce(trim(p ->> 'task'), '') = '' then raise exception 'Enter the maintenance task.'; end if;
  if fq is null or fq < 1 or fq > 1100 then raise exception 'Enter the frequency in days (1–1100).'; end if;
  if v_id is null then
    insert into console.mnt_pm_plans (customer_id, machine_code, machine_name, task, frequency_days, est_min, next_due, created_by)
    values (cid, mc, mn, trim(p ->> 'task'), fq, nullif(p ->> 'est_min', '')::int, coalesce(nd, today + fq), lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into v_id;
  else
    update console.mnt_pm_plans set machine_code = mc, machine_name = mn, task = trim(p ->> 'task'), frequency_days = fq, est_min = nullif(p ->> 'est_min', '')::int, next_due = coalesce(nd, next_due), active = coalesce((p ->> 'active')::boolean, true)
     where id = v_id and customer_id = cid;
  end if;
  return v_id;
end $$;

-- one plan per machine from the PM frequency written in the Operations Master (Weekly, Monthly, Quarterly, Half-yearly, Yearly); first due dates are spread over the period
create or replace function public.kmr_mnt_pm_seed(p_slug text) returns integer language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); r record; n int := 0; fq int; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  perform console.require_feature(p_slug, 'mnt', 'mnt.preventive-maintenance');
  for r in select code, name, data ->> 'pm_frequency' pf from console.ops_records where customer_id = cid and kind = 'machines' and active loop
    fq := console.mnt_freq(r.pf);
    if fq is null or exists (select 1 from console.mnt_pm_plans where customer_id = cid and machine_code = r.code and active) then continue; end if;
    insert into console.mnt_pm_plans (customer_id, machine_code, machine_name, task, frequency_days, next_due, created_by)
    values (cid, r.code, r.name, 'Preventive maintenance as per the PM checklist (' || r.pf || ')', fq, today + (abs(hashtext(r.code)) % fq), lower(coalesce(auth.jwt() ->> 'email', '')));
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.kmr_mnt_pm_done(p_slug text, p_plan uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); pl console.mnt_pm_plans%rowtype; dn date := coalesce(nullif(p ->> 'done_on', '')::date, (now() at time zone 'Asia/Kolkata')::date); me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  perform console.require_feature(p_slug, 'mnt', 'mnt.preventive-maintenance');
  select * into pl from console.mnt_pm_plans where id = p_plan and customer_id = cid for update;
  if not found then raise exception 'Plan not found.'; end if;
  if dn > (now() at time zone 'Asia/Kolkata')::date then raise exception 'The date done cannot be in the future.'; end if;
  insert into console.mnt_pm_log (customer_id, plan_id, machine_code, task, done_on, due_on, done_by, duration_min, findings, created_by)
  values (cid, pl.id, pl.machine_code, pl.task, dn, pl.next_due, coalesce(nullif(trim(p ->> 'done_by'), ''), me), nullif(p ->> 'duration_min', '')::int, nullif(trim(coalesce(p ->> 'findings', '')), ''), me);
  update console.mnt_pm_plans set last_done = greatest(coalesce(last_done, dn), dn), next_due = greatest(coalesce(last_done, dn), dn) + frequency_days where id = pl.id;
end $$;

create or replace function public.kmr_mnt_pm_void(p_slug text, p_log uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); l console.mnt_pm_log%rowtype; ld date;
begin
  perform console.require_feature(p_slug, 'mnt', 'mnt.preventive-maintenance');
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the record.'; end if;
  select * into l from console.mnt_pm_log where id = p_log and customer_id = cid for update;
  if not found or l.status = 'void' then raise exception 'Record not found.'; end if;
  update console.mnt_pm_log set status = 'void', void_reason = trim(p_reason) where id = p_log;
  if l.plan_id is not null then
    select max(done_on) into ld from console.mnt_pm_log where plan_id = l.plan_id and status = 'ok';
    update console.mnt_pm_plans set last_done = ld, next_due = case when ld is null then coalesce(l.due_on, next_due) else ld + frequency_days end where id = l.plan_id;
  end if;
end $$;

-- ---------- machine history: modifications, overhauls, spares, relocations ----------
create or replace function public.kmr_mnt_event_save(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt'); mc text := trim(coalesce(p ->> 'machine_code', '')); v_id uuid;
begin
  if not exists (select 1 from console.ops_records where customer_id = cid and kind = 'machines' and code = mc) then raise exception 'Choose the machine.'; end if;
  if coalesce(trim(p ->> 'type'), '') = '' then raise exception 'Choose the type of entry.'; end if;
  if coalesce(trim(p ->> 'description'), '') = '' then raise exception 'Describe what was done.'; end if;
  insert into console.mnt_events (customer_id, machine_code, event_date, type, description, cost, done_by, created_by)
  values (cid, mc, coalesce(nullif(p ->> 'event_date', '')::date, (now() at time zone 'Asia/Kolkata')::date), trim(p ->> 'type'), trim(p ->> 'description'), nullif(p ->> 'cost', '')::numeric, nullif(trim(coalesce(p ->> 'done_by', '')), ''), lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into v_id;
  return v_id;
end $$;
create or replace function public.kmr_mnt_event_void(p_slug text, p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'mnt');
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Give the reason for voiding the entry.'; end if;
  update console.mnt_events set status = 'void', void_reason = trim(p_reason) where id = p_id and customer_id = cid;
end $$;

-- ---------- sample data: breakdowns in every state, PM plans (some overdue), history entries ----------
create or replace function console.mnt_sample(p_cid uuid, p_action text) returns integer language plpgsql security definer set search_path = console, public as $$
declare n int := 0; k int; me text := 'sample'; ist text := 'Asia/Kolkata'; today date := (now() at time zone 'Asia/Kolkata')::date; m record; i int := 0; j int; cnt int; d int; hr int; dur int; st timestamptz; en timestamptz; bid uuid;
        cats text[] := array['Mechanical', 'Electrical', 'Hydraulic / pneumatic', 'Tooling', 'Control / software', 'Utilities', 'Mechanical', 'Electrical'];
        probs text[] := array['Spindle bearing noise and heat', 'Servo drive fault alarm', 'Hydraulic chuck pressure drop', 'Turret not indexing', 'Controller hang / restart', 'Coolant pump failure', 'Axis backlash high', 'Limit switch fault'];
        roots text[] := array['Bearing worn — lubrication interval exceeded', 'Loose connector at drive', 'Leaking seal on chuck cylinder', 'Index sensor misaligned', 'Corrupted parameter file', 'Impeller choked with swarf', 'Ball screw nut wear', 'Switch damaged by coolant'];
        acts text[] := array['Replaced spindle bearing, regreased', 'Re-seated and locked connector', 'Replaced cylinder seal kit', 'Re-aligned sensor and tested 50 indexes', 'Restored parameters from backup', 'Cleaned pump and fitted strainer', 'Adjusted nut preload', 'Replaced switch, sealed cable gland'];
        prev text[] := array['Add bearing greasing to weekly PM', 'Torque-mark connectors; check monthly', 'Seal kit kept as critical spare', 'Add sensor check to weekly PM', 'Parameter backup after every change', 'Fit strainer; clean weekly', 'Check backlash quarterly', 'Cable glands to IP67 type'];
        dcs text[] := array['D01', 'D02', 'D03', 'D09', 'D01', 'D03', 'D01', 'D02'];
begin
  if p_action = 'flush' then
    delete from console.mmd_loss where customer_id = p_cid and sample and ref is not null; get diagnostics k = row_count; n := n + k;
    delete from console.mnt_pm_log where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mnt_pm_plans where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mnt_events where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    delete from console.mnt_breakdowns where customer_id = p_cid and sample; get diagnostics k = row_count; n := n + k;
    return n;
  end if;
  if exists (select 1 from console.mnt_breakdowns where customer_id = p_cid and sample) then return 0; end if;
  for m in select code, name, data from console.ops_records where customer_id = p_cid and kind = 'machines' and active order by code limit 8 loop
    i := i + 1;
    -- history: installation, and for some a modification
    insert into console.mnt_events (customer_id, machine_code, event_date, type, description, cost, done_by, sample, created_by)
    values (p_cid, m.code, today - (900 + i * 37), 'Installation', 'Installed and commissioned; trial run and accuracy check passed', null, 'Supplier engineer', true, me);
    if i % 3 = 0 then insert into console.mnt_events (customer_id, machine_code, event_date, type, description, cost, done_by, sample, created_by)
      values (p_cid, m.code, today - (200 + i * 11), 'Modification', 'Coolant filtration unit added', 38000, 'Maintenance', true, me); end if;
    if i % 4 = 1 then insert into console.mnt_events (customer_id, machine_code, event_date, type, description, cost, done_by, sample, created_by)
      values (p_cid, m.code, today - (320 + i * 5), 'Overhaul', 'Annual overhaul: spindle, guideways, hydraulics', 145000, 'OEM service', true, me); end if;
    -- breakdowns over the last 150 days: a few machines fail more often
    cnt := case when i % 4 = 2 then 9 when i % 3 = 0 then 6 else 4 end;
    for j in 1..cnt loop
      d := 6 + ((i * 17 + j * 29) % 140); hr := 6 + ((i * 5 + j * 3) % 14); dur := 25 + ((i * 37 + j * 53) % 260);
      st := ((today - d)::timestamp + make_interval(hours => hr)) at time zone ist; en := st + make_interval(mins => dur);
      insert into console.mnt_breakdowns (customer_id, bd_no, machine_code, machine_name, started_at, attended_at, ended_at, shift, reported_by, attended_by, problem, category, d_code, root_cause, action_taken, preventive_action, spares, status, closed_by, sample, created_by, created_at)
      values (p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM') || '-' || lpad(console.mnt_next(p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM'))::text, 4, '0'), m.code, m.name, st, st + make_interval(mins => 5 + (j * 7) % 20), en,
              case when hr < 14 then 'A' else 'B' end, 'Operator', 'Maintenance', probs[1 + (i + j) % 8], cats[1 + (i + j) % 8],
              case when exists (select 1 from console.ops_records where customer_id = p_cid and kind = 'loss_codes' and code = dcs[1 + (i + j) % 8]) then dcs[1 + (i + j) % 8] end,
              roots[1 + (i + j) % 8], acts[1 + (i + j) % 8], prev[1 + (i + j) % 8], case when (i + j) % 3 = 0 then '[{"spare": "Bearing set", "qty": 1}]'::jsonb else '[]'::jsonb end, 'closed', me, true, me, st) returning id into bid;
      perform console.mnt_book_loss(p_cid, bid, me); n := n + 1;
    end loop;
    -- two machines have a breakdown right now
    if i = 2 then
      st := now() - interval '95 minutes';
      insert into console.mnt_breakdowns (customer_id, bd_no, machine_code, machine_name, started_at, shift, reported_by, problem, category, status, sample, created_by)
      values (p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM') || '-' || lpad(console.mnt_next(p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM'))::text, 4, '0'), m.code, m.name, st, 'A', 'Operator', 'Spindle will not start — drive alarm', 'Electrical', 'open', true, me); n := n + 1;
    elsif i = 4 then
      st := now() - interval '3 hours';
      insert into console.mnt_breakdowns (customer_id, bd_no, machine_code, machine_name, started_at, attended_at, attended_by, shift, reported_by, problem, category, status, sample, created_by)
      values (p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM') || '-' || lpad(console.mnt_next(p_cid, 'BD-' || to_char(st at time zone ist, 'YYMM'))::text, 4, '0'), m.code, m.name, st, st + interval '20 minutes', 'Maintenance', 'A', 'Operator', 'Coolant leak at the tank — pump replacement awaited', 'Utilities', 'attended', true, me); n := n + 1;
    end if;
    -- PM plans: weekly lubrication and a monthly PM; some overdue
    insert into console.mnt_pm_plans (customer_id, machine_code, machine_name, task, frequency_days, est_min, last_done, next_due, sample, created_by)
    values (p_cid, m.code, m.name, 'Weekly: lubrication, cleaning, coolant level, guard and safety check', 7, 45, today - (3 + i % 6), today - (3 + i % 6) + 7, true, me),
           (p_cid, m.code, m.name, 'Monthly PM: filters, belts, alignment check, electrical tightness', 30, 180, today - (12 + i * 4), today - (12 + i * 4) + 30, true, me);
    for j in 1..3 loop
      insert into console.mnt_pm_log (customer_id, plan_id, machine_code, task, done_on, due_on, done_by, duration_min, findings, sample, created_by)
      select p_cid, pl.id, m.code, pl.task, today - (3 + i % 6) - 7 * (j - 1), today - (3 + i % 6) - 7 * (j - 1), 'Maintenance', 40 + j, case when j = 1 then 'OK' else 'OK — minor oil top-up' end, true, me from console.mnt_pm_plans pl where pl.customer_id = p_cid and pl.machine_code = m.code and pl.sample and pl.frequency_days = 7 limit 1;
    end loop;
    n := n + 5;
  end loop;
  return n;
end $$;
revoke all on function console.mnt_sample(uuid, text) from public, anon, authenticated;
