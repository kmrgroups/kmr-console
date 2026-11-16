-- KMR 0128 — Daily management mail: ONE mail per plant every morning with every app's dashboard figures (production efficiency, delivery, DC & GRN, calibration,
-- maintenance, HRM attendance, actions, audit findings, invoicing). Settings sit in the customer's Administration page (Daily management mail).
-- The figures are worked out here (digest_kpis); the traffic lights, "what to do" text and the mail itself are made by the Console (lib/digest.ts).
-- It replaces the separate Calibration Hub due-date mail: the old recipients are copied over once, and the gauge list is a section of this mail.
-- Needs 0098 (cal_alert_settings), 0113 (dc & grn), 0118 (invoicing), 0121 (production history). Safe to re-run.

create table if not exists console.digest_settings (
  customer_id uuid primary key references console.customers(id) on delete cascade,
  enabled boolean not null default false,
  recipients text not null default '',
  include_users boolean not null default false,            -- also every company administrator
  send_days text not null default 'daily' check (send_days in ('daily', 'mon_sat')),
  sections jsonb not null default '{}',                    -- {"production": false} switches a section off; missing = on
  targets jsonb not null default '{}',                     -- eff_target, attendance_target, despatch_target, cal_days
  last_sent_on date,
  updated_at timestamptz not null default now(), updated_by text);
alter table console.digest_settings enable row level security;
drop policy if exists digest_settings_staff on console.digest_settings;
create policy digest_settings_staff on console.digest_settings for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- the old calibration due-date mail settings become the first version of the new mail's settings (recipients carry over, nothing is lost)
insert into console.digest_settings (customer_id, enabled, recipients, include_users, targets)
select a.customer_id, a.enabled, a.recipients, a.include_users, jsonb_build_object('cal_days', a.days_before) from console.cal_alert_settings a
on conflict (customer_id) do nothing;

-- ---------- the figures ----------
create or replace function console.digest_kpis(p_cid uuid, p jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare
  d0 date := (now() at time zone 'Asia/Kolkata')::date;
  ms date := date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date;
  pms date := (date_trunc('month', (now() at time zone 'Asia/Kolkata')) - interval '1 month')::date;
  cal_days int := greatest(1, least(365, coalesce(nullif(p ->> 'cal_days', '')::int, 14)));
  res jsonb := '{}'; r jsonb; n bigint; ld date;
  ok boolean;
begin
  -- ---- production (MMD): efficiency from the ERP production history (rows with an efficiency and hours; hours-weighted), plus live route-sheet data
  ok := coalesce((select a.ok from console.access_state('mmd', p_cid) a), false);
  if ok then
    select max(prod_date) into ld from console.mmd_hist where customer_id = p_cid and prod_date <= d0 and coalesce(hours, 0) > 0;
    select count(*) into n from console.mmd_entries where customer_id = p_cid and not sample and status = 'ok';
    if ld is not null or n > 0 then
      select jsonb_build_object(
        'last_date', ld, 'today', d0, 'month_start', ms,
        'mtd', (select jsonb_build_object('eff', round((sum(eff * hours) / nullif(sum(hours), 0))::numeric, 1), 'rows', count(*), 'days', count(distinct prod_date), 'machines', count(distinct machine),
                                          'hours', round(sum(hours)::numeric), 'qty', round(sum(qty)))
                  from console.mmd_hist where customer_id = p_cid and prod_date between ms and d0 and eff > 0 and hours > 0),
        'mtd_scrap', (select jsonb_build_object('qty', round(coalesce(sum(qty), 0)), 'scrap', round(coalesce(sum(scrap), 0)), 'idle_hrs', round(coalesce(sum(idle_hrs), 0)::numeric), 'mc_hrs', round(coalesce(sum(mc_hrs), 0)::numeric))
                  from console.mmd_hist where customer_id = p_cid and prod_date between ms and d0),
        'prev_month_eff', (select round((sum(eff * hours) / nullif(sum(hours), 0))::numeric, 1) from console.mmd_hist where customer_id = p_cid and prod_date >= pms and prod_date < ms and eff > 0 and hours > 0),
        'last_day', (select jsonb_build_object('eff', round((sum(eff * hours) / nullif(sum(hours), 0))::numeric, 1), 'machines', count(distinct machine), 'qty', round(sum(qty)))
                  from console.mmd_hist where customer_id = p_cid and prod_date = ld and eff > 0 and hours > 0),
        'days', coalesce((select jsonb_agg(jsonb_build_object('d', g.d, 'eff', x.eff, 'machines', x.m, 'qty', x.q) order by g.d)
                  from generate_series(d0 - 6, d0, interval '1 day') gs(d0x) cross join lateral (select gs.d0x::date as d) g
                  left join lateral (select round((sum(eff * hours) / nullif(sum(hours), 0))::numeric, 1) as eff, count(distinct machine) as m, round(sum(qty)) as q
                                       from console.mmd_hist h where h.customer_id = p_cid and h.prod_date = g.d and h.eff > 0 and h.hours > 0) x on true), '[]'),
        'machines', coalesce((select jsonb_agg(jsonb_build_object('m', t.machine, 'eff', t.eff, 'hours', t.hrs) order by t.eff, t.machine)
                  from (select machine, round((sum(eff * hours) / nullif(sum(hours), 0))::numeric, 1) as eff, round(sum(hours)::numeric) as hrs
                          from console.mmd_hist where customer_id = p_cid and prod_date between ms and d0 and eff > 0 and hours > 0 and coalesce(machine, '') <> '' group by machine) t), '[]'),
        'live', case when n > 0 then (select jsonb_build_object('ok', round(coalesce(sum(ok_qty), 0)), 'rej', round(coalesce(sum(rej_qty), 0)), 'rew', round(coalesce(sum(rew_qty), 0)))
                  from console.mmd_entries where customer_id = p_cid and not sample and status = 'ok' and kind = 'process' and (entry_at at time zone 'Asia/Kolkata')::date between ms and d0) end,
        'loss', coalesce((select jsonb_agg(jsonb_build_object('reason', t.nm, 'min', t.mins) order by t.mins desc)
                  from (select coalesce(nullif(d_name, ''), d_code) as nm, sum(minutes) as mins from console.mmd_loss where customer_id = p_cid and not sample and status = 'ok' and loss_date between ms and d0 group by 1 order by 2 desc limit 3) t), '[]')
      ) into r;
      res := res || jsonb_build_object('production', r);
    end if;
  end if;

  -- ---- delivery (Sales Flow): this month's demand against what has gone out
  ok := coalesce((select a.ok from console.access_state('sales', p_cid) a), false);
  if ok and exists (select 1 from console.sf_lines where customer_id = p_cid and month = ms and not sample) then
    select jsonb_build_object(
      'lines', count(*), 'demand', round(sum(l.demand_qty)), 'despatched', round(sum(least(l.demand_qty, coalesce(x.q, 0)))), 'despatched_all', round(sum(coalesce(x.q, 0))),
      'value_demand', round(sum(l.demand_qty * l.price)), 'value_despatched', round(sum(least(l.demand_qty, coalesce(x.q, 0)) * l.price)),
      'lines_complete', count(*) filter (where l.demand_qty > 0 and coalesce(x.q, 0) >= l.demand_qty),
      'late_lines', count(*) filter (where l.sched_type = 'date' and l.sched_date < d0 and coalesce(x.q, 0) < l.demand_qty and l.demand_qty > 0),
      'last_despatch', (select max(day) from console.sf_despatch where customer_id = p_cid and qty > 0 and day <= d0),
      'late_top', coalesce((select jsonb_agg(jsonb_build_object('buyer', t.buyer_name, 'part', t.part_code, 'due', t.sched_date, 'short', t.short) order by t.sched_date, t.short desc)
                    from (select l2.buyer_name, l2.part_code, l2.sched_date, round(l2.demand_qty - coalesce(x2.q, 0)) as short
                            from console.sf_lines l2 left join lateral (select sum(qty) as q from console.sf_despatch d where d.line_id = l2.id and d.day <= d0) x2 on true
                           where l2.customer_id = p_cid and l2.month = ms and not l2.sample and l2.sched_type = 'date' and l2.sched_date < d0 and l2.demand_qty > coalesce(x2.q, 0)
                           order by l2.sched_date, (l2.demand_qty - coalesce(x2.q, 0)) desc limit 5) t), '[]'),
      'actions_open', (select count(*) from console.sf_actions a where a.customer_id = p_cid and not a.sample and a.status <> 'Closed'),
      'actions_overdue', (select count(*) from console.sf_actions a where a.customer_id = p_cid and not a.sample and a.status <> 'Closed' and a.target_date < d0))
      into r
      from console.sf_lines l left join lateral (select sum(qty) as q from console.sf_despatch d where d.line_id = l.id and d.day <= d0) x on true
     where l.customer_id = p_cid and l.month = ms and not l.sample;
    res := res || jsonb_build_object('delivery', r);
  end if;

  -- ---- delivery challans and GRN / purchase orders
  ok := coalesce((select a.ok from console.access_state('dcg', p_cid) a), false);
  if ok and exists (select 1 from console.dcg_dc where customer_id = p_cid) then
    select jsonb_build_object(
      'dc_open', count(*) filter (where kind = 'returnable' and status in ('issued', 'part_returned')),
      'dc_overdue', count(*) filter (where kind = 'returnable' and status in ('issued', 'part_returned') and expected_return < d0),
      'dc_overdue_max_days', coalesce(max(d0 - expected_return) filter (where kind = 'returnable' and status in ('issued', 'part_returned') and expected_return < d0), 0),
      'dc_no_return_date', count(*) filter (where kind = 'returnable' and status in ('issued', 'part_returned') and expected_return is null and dc_date < d0 - 30),
      'dc_draft_old', count(*) filter (where status = 'draft' and dc_date < d0 - 3),
      'dc_issued_month', count(*) filter (where status <> 'cancelled' and status <> 'draft' and dc_date between ms and d0),
      'dc_top', coalesce((select jsonb_agg(jsonb_build_object('no', t.dc_no, 'party', t.party_name, 'days', t.days, 'purpose', t.purpose) order by t.days desc)
                    from (select dc_no, party_name, purpose, d0 - expected_return as days from console.dcg_dc where customer_id = p_cid and kind = 'returnable' and status in ('issued', 'part_returned') and expected_return < d0
                           order by expected_return limit 5) t), '[]'))
      into r from console.dcg_dc where customer_id = p_cid;
    r := r || (select jsonb_build_object(
      'po_open', count(*) filter (where status in ('open', 'part_received')),
      'po_part', count(*) filter (where status = 'part_received'),
      'po_open_30', count(*) filter (where status in ('open', 'part_received') and po_date < d0 - 30),
      'po_open_90', count(*) filter (where status in ('open', 'part_received') and po_date < d0 - 90)) from console.dcg_po where customer_id = p_cid);
    r := r || (select jsonb_build_object('grn_month', count(*) filter (where status = 'posted' and grn_date between ms and d0), 'grn_last', max(grn_date) filter (where status = 'posted' and grn_date <= d0))
                 from console.dcg_grn where customer_id = p_cid);
    res := res || jsonb_build_object('dcg', r);
  end if;

  -- ---- calibration (gauges)
  ok := coalesce((select a.ok from console.access_state('calib', p_cid) a), false);
  if ok and exists (select 1 from console.cal_instruments where customer_id = p_cid and not sample) then
    with i as (
      select x.*, exists (select 1 from console.dcg_dc_lines l join console.dcg_dc d on d.id = l.dc_id
                           where l.instrument_id = x.id and d.customer_id = p_cid and d.kind = 'returnable'
                             and (d.status in ('issued', 'part_returned') or (d.status = 'draft' and d.dc_date >= d0 - 30))) as on_dc
        from console.cal_instruments x where x.customer_id = p_cid and not x.sample and x.status = 'In use')
    select jsonb_build_object(
      'in_use', count(*), 'overdue', count(*) filter (where next_due < d0), 'overdue_on_dc', count(*) filter (where next_due < d0 and on_dc),
      'due_soon', count(*) filter (where next_due >= d0 and next_due <= d0 + cal_days and not on_dc), 'due_days', cal_days,
      'on_dc', count(*) filter (where on_dc), 'no_due_date', count(*) filter (where next_due is null),
      'critical_overdue', count(*) filter (where next_due < d0 and criticality = 'Critical'),
      'oot_open', (select count(*) from console.cal_oot o where o.customer_id = p_cid and o.status = 'Open'),
      'top', coalesce((select jsonb_agg(jsonb_build_object('tag', t.tag, 'name', t.name, 'days', t.days, 'on_dc', t.on_dc) order by t.days desc)
                    from (select tag, name, d0 - next_due as days, on_dc from i where next_due < d0 and not on_dc order by next_due, tag limit 5) t), '[]'))
      into r from i;
    res := res || jsonb_build_object('calibration', r);
  end if;

  -- ---- maintenance
  ok := coalesce((select a.ok from console.access_state('mnt', p_cid) a), false);
  if ok and (exists (select 1 from console.mnt_breakdowns where customer_id = p_cid and not sample) or exists (select 1 from console.mnt_pm_plans where customer_id = p_cid and not sample)) then
    select jsonb_build_object(
      'open', count(*) filter (where status in ('open', 'attended')),
      'oldest_open_hrs', coalesce(round(max(extract(epoch from (now() - started_at)) / 3600) filter (where status in ('open', 'attended'))::numeric), 0),
      'month_count', count(*) filter (where status <> 'void' and (started_at at time zone 'Asia/Kolkata')::date between ms and d0),
      'month_down_hrs', coalesce(round((sum(extract(epoch from (ended_at - started_at)) / 3600) filter (where status = 'closed' and (started_at at time zone 'Asia/Kolkata')::date between ms and d0))::numeric, 1), 0),
      'mttr_hrs', round((avg(extract(epoch from (ended_at - started_at)) / 3600) filter (where status = 'closed' and (started_at at time zone 'Asia/Kolkata')::date between ms and d0))::numeric, 1),
      'top', coalesce((select jsonb_agg(jsonb_build_object('no', t.bd_no, 'machine', t.machine_code, 'hrs', t.hrs, 'problem', left(t.problem, 60)) order by t.hrs desc)
                    from (select bd_no, machine_code, problem, round(extract(epoch from (now() - started_at)) / 3600) as hrs from console.mnt_breakdowns
                           where customer_id = p_cid and not sample and status in ('open', 'attended') order by started_at limit 5) t), '[]'))
      into r from console.mnt_breakdowns where customer_id = p_cid and not sample;
    r := r || (select jsonb_build_object('pm_plans', count(*), 'pm_overdue', count(*) filter (where next_due < d0), 'pm_week', count(*) filter (where next_due >= d0 and next_due <= d0 + 7))
                 from console.mnt_pm_plans where customer_id = p_cid and not sample and active);
    res := res || jsonb_build_object('maintenance', r);
  end if;

  -- ---- HRM attendance (latest day that has attendance)
  ok := coalesce((select a.ok from console.access_state('hrms', p_cid) a), false);
  if ok then
    select max(work_date) into ld from console.hrms_attendance where customer_id = p_cid and not sample and work_date <= d0;
    if ld is not null then
      select jsonb_build_object('att_date', ld, 'today', d0,
        'employees', (select count(*) from console.hrms_employees where customer_id = p_cid and not sample and status = 'active'),
        'present', count(*) filter (where status = 'P'), 'half', count(*) filter (where status = 'HD'), 'absent', count(*) filter (where status in ('A', 'U')),
        'leave', count(*) filter (where status = 'L'), 'late', count(*) filter (where late_min > 0), 'missing_punch', count(*) filter (where status = 'MP'),
        'ot_hrs_day', round((coalesce(sum(ot_min), 0) / 60.0)::numeric, 1),
        'ot_hrs_month', (select round((coalesce(sum(ot_min), 0) / 60.0)::numeric) from console.hrms_attendance where customer_id = p_cid and not sample and work_date between ms and d0),
        'days', coalesce((select jsonb_agg(jsonb_build_object('d', t.work_date, 'pct', t.pct, 'present', t.pres, 'absent', t.abs) order by t.work_date)
                    from (select work_date, round(100.0 * (count(*) filter (where status = 'P') + 0.5 * count(*) filter (where status = 'HD')) / nullif(count(*) filter (where status in ('P', 'HD', 'A', 'U', 'L', 'MP')), 0), 1) as pct,
                                 count(*) filter (where status = 'P') as pres, count(*) filter (where status in ('A', 'U')) as abs
                            from console.hrms_attendance where customer_id = p_cid and not sample and work_date between d0 - 6 and d0 group by work_date having count(*) filter (where status in ('P', 'HD', 'A', 'U', 'L', 'MP')) > 0) t), '[]'))
        into r from console.hrms_attendance where customer_id = p_cid and not sample and work_date = ld;
      res := res || jsonb_build_object('hrm', r);
    end if;
  end if;

  -- ---- actions: ActionTrack tasks and meeting action points
  ok := coalesce((select a.ok from console.access_state('tsk', p_cid) a), false);
  if ok and exists (select 1 from console.tsk_tasks where customer_id = p_cid and not sample) then
    select jsonb_build_object(
      'open', count(*) filter (where status in ('open', 'progress', 'blocked')),
      'overdue', count(*) filter (where status in ('open', 'progress', 'blocked') and due < d0),
      'due_today', count(*) filter (where status in ('open', 'progress', 'blocked') and due = d0),
      'blocked', count(*) filter (where status = 'blocked'),
      'urgent_overdue', count(*) filter (where status in ('open', 'progress', 'blocked') and due < d0 and priority in ('urgent', 'high')),
      'done_month', count(*) filter (where status = 'done' and (done_at at time zone 'Asia/Kolkata')::date between ms and d0),
      'top', coalesce((select jsonb_agg(jsonb_build_object('no', t.no, 'title', left(t.title, 60), 'who', t.who, 'days', t.days) order by t.days desc)
                    from (select no, title, coalesce(nullif(assignee_name, ''), assignee, 'Not assigned') as who, d0 - due as days from console.tsk_tasks
                           where customer_id = p_cid and not sample and status in ('open', 'progress', 'blocked') and due < d0 order by due limit 5) t), '[]'))
      into r from console.tsk_tasks where customer_id = p_cid and not sample;
    res := res || jsonb_build_object('actions', r);
  end if;
  ok := coalesce((select a.ok from console.access_state('mom', p_cid) a), false);
  if ok and exists (select 1 from console.mom_points where customer_id = p_cid and not sample) then
    select jsonb_build_object('open', count(*) filter (where status in ('Open', 'In progress') and ptype in ('Action', 'Decision')),
      'overdue', count(*) filter (where status in ('Open', 'In progress') and ptype in ('Action', 'Decision') and when_on < d0))
      into r from console.mom_points where customer_id = p_cid and not sample;
    res := res || jsonb_build_object('meetings', r);
  end if;

  -- ---- internal audit findings
  ok := coalesce((select a.ok from console.access_state('aud', p_cid) a), false);
  if ok and exists (select 1 from console.aud_ncs where customer_id = p_cid and not sample) then
    select jsonb_build_object('open', count(*) filter (where status not in ('closed', 'cancelled')),
      'major_open', count(*) filter (where status not in ('closed', 'cancelled') and severity = 'Major'),
      'overdue', count(*) filter (where status not in ('closed', 'cancelled') and ((perm_due < d0 and perm_done_on is null) or (status = 'contain' and resp_due < d0 and contain_done_on is null))))
      into r from console.aud_ncs where customer_id = p_cid and not sample;
    res := res || jsonb_build_object('audit', r);
  end if;

  -- ---- invoicing
  ok := coalesce((select a.ok from console.access_state('inv', p_cid) a), false);
  if ok and exists (select 1 from console.inv_invoice where customer_id = p_cid) then
    select jsonb_build_object('month_count', count(*) filter (where status = 'issued' and inv_date between ms and d0), 'month_value', round(coalesce(sum(total) filter (where status = 'issued' and inv_date between ms and d0), 0)),
      'prev_value', round(coalesce(sum(total) filter (where status = 'issued' and inv_date >= pms and inv_date < ms), 0)),
      'last_date', max(inv_date) filter (where status = 'issued' and inv_date <= d0),
      'drafts_old', count(*) filter (where status = 'draft' and inv_date < d0 - 2))
      into r from console.inv_invoice where customer_id = p_cid;
    res := res || jsonb_build_object('invoicing', r);
  end if;
  -- ---- raw material planning (RMP): this month's weekly plan against what has been received, delays, stock below safety, open orders past due
  ok := coalesce((select a.ok from console.access_state('rmp', p_cid) a), false);
  if ok and exists (select 1 from console.rmp_plan_week where customer_id = p_cid and month = to_char(ms, 'YYYY-MM')) then
    -- week w covers days 7(w-1)+1 .. 7w of the month (week 5 runs to month end); a week is "elapsed" once its last day is before today
    with w as (
      select pw.material_code, pw.week, pw.planned_qty, pw.received_qty, st.rate, coalesce(st.unit, 'kg') as unit,
             case when pw.week >= 5 then (date_trunc('month', ms) + interval '1 month - 1 day')::date else (ms + 7 * pw.week - 1) end as wend2,
             pw.planned_qty * coalesce(st.rate, 0) as pv, coalesce(pw.cost_amt, pw.received_qty * coalesce(st.rate, 0)) as av
        from console.rmp_plan_week pw left join console.rmp_stock st on st.customer_id = pw.customer_id and st.material_code = pw.material_code
       where pw.customer_id = p_cid and pw.month = to_char(ms, 'YYYY-MM')),
    m as (select material_code, max(unit) as unit, max(rate) as rate, sum(planned_qty) as pq, sum(received_qty) as rq,
                 sum(planned_qty) filter (where wend2 < d0) as pq_e, sum(received_qty) filter (where wend2 < d0) as rq_e
            from w group by material_code)
    select jsonb_build_object('month', to_char(ms, 'YYYY-MM'), 'today', d0,
      'materials', (select count(*) from m where pq > 0 or rq > 0),
      'plan_qty', (select round(coalesce(sum(pq), 0)) from m), 'recv_qty', (select round(coalesce(sum(rq), 0)) from m),
      'plan_qty_td', (select round(coalesce(sum(pq_e), 0)) from m), 'recv_qty_td', (select round(coalesce(sum(rq_e), 0)) from m),
      'plan_lakh', (select round((coalesce(sum(pv), 0) / 100000.0)::numeric, 2) from w),
      'plan_lakh_td', (select round((coalesce(sum(pv) filter (where wend2 < d0), 0) / 100000.0)::numeric, 2) from w),
      'actual_lakh', (select round((coalesce(sum(av), 0) / 100000.0)::numeric, 2) from w),
      'actual_lakh_td', (select round((coalesce(sum(av) filter (where wend2 < d0), 0) / 100000.0)::numeric, 2) from w),
      'elapsed_weeks', (select count(distinct week) from w where wend2 < d0),
      'delayed', (select count(*) from m where coalesce(pq_e, 0) - coalesce(rq_e, 0) > 0.0001),
      'late', coalesce((select jsonb_agg(jsonb_build_object('code', t.material_code, 'unit', t.unit, 'plan', round(t.pq_e), 'recv', round(coalesce(t.rq_e, 0)), 'short', round(t.pq_e - coalesce(t.rq_e, 0)),
                          'pct', round((100.0 * coalesce(t.rq_e, 0) / nullif(t.pq_e, 0))::numeric)) order by (t.pq_e - coalesce(t.rq_e, 0)) * coalesce(t.rate, 1) desc)
                  from (select * from m where coalesce(pq_e, 0) - coalesce(rq_e, 0) > 0.0001 order by (pq_e - coalesce(rq_e, 0)) * coalesce(rate, 1) desc limit 5) t), '[]'),
      'no_rate', (select count(*) from m where (pq > 0 or rq > 0) and coalesce(rate, 0) = 0),
      'below_safety', (select count(*) from console.rmp_stock where customer_id = p_cid and not sample and safety_kg > 0 and on_hand_kg < safety_kg),
      'low', coalesce((select jsonb_agg(jsonb_build_object('code', t.material_code, 'on_hand', round(t.on_hand_kg), 'safety', round(t.safety_kg)) order by t.on_hand_kg / t.safety_kg)
                  from (select material_code, on_hand_kg, safety_kg from console.rmp_stock where customer_id = p_cid and not sample and safety_kg > 0 and on_hand_kg < safety_kg order by on_hand_kg / safety_kg limit 5) t), '[]'),
      'orders_open', (select count(*) from console.rmp_orders where customer_id = p_cid and not sample and status in ('planned', 'ordered')),
      'orders_late', (select count(*) from console.rmp_orders where customer_id = p_cid and not sample and status in ('planned', 'ordered') and due_date < d0),
      'orders_top', coalesce((select jsonb_agg(jsonb_build_object('code', t.material_code, 'po', t.po_no, 'days', d0 - t.due_date, 'qty', round(t.qty_kg)) order by t.due_date)
                  from (select material_code, po_no, due_date, qty_kg from console.rmp_orders where customer_id = p_cid and not sample and status in ('planned', 'ordered') and due_date < d0 order by due_date limit 5) t), '[]'),
      'updated_on', (select (max(updated_at) at time zone 'Asia/Kolkata')::date from console.rmp_plan_week where customer_id = p_cid and month = to_char(ms, 'YYYY-MM'))
    ) into r;
    res := res || jsonb_build_object('rmp', r);
  end if;
  return res;
end $$;
revoke all on function console.digest_kpis(uuid, jsonb) from public, anon, authenticated;

-- ---------- Administration screen: read / save the settings, and the figures for a test mail (company administrators only) ----------
create or replace function console.digest_admin(p_slug text) returns uuid language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or not console.is_customer_admin(cid) then raise exception 'Only your company''s administrators can use the daily management mail.'; end if;
  return cid;
end $$;
revoke all on function console.digest_admin(text) from public, anon, authenticated;

create or replace function public.kmr_digest_get(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.digest_admin(p_slug); s console.digest_settings;
begin
  select * into s from console.digest_settings where customer_id = cid;
  return jsonb_build_object('enabled', coalesce(s.enabled, false), 'recipients', coalesce(s.recipients, ''), 'include_users', coalesce(s.include_users, false),
    'send_days', coalesce(s.send_days, 'daily'), 'sections', coalesce(s.sections, '{}'), 'targets', coalesce(s.targets, '{}'), 'last_sent_on', s.last_sent_on,
    'apps', coalesce((select jsonb_agg(a.code order by a.code) from (select x.code from (values ('mmd'), ('sales'), ('dcg'), ('calib'), ('mnt'), ('hrms'), ('tsk'), ('mom'), ('aud'), ('inv'), ('rmp')) x(code)
                       where coalesce((select z.ok from console.access_state(x.code, cid) z), false)) a), '[]'),
    'admins', coalesce((select jsonb_agg(m.email order by m.email) from console.customer_members m where m.customer_id = cid and m.is_admin and m.email is not null), '[]'),
    'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
grant execute on function public.kmr_digest_get(text) to authenticated;

create or replace function public.kmr_digest_save(p_slug text, p jsonb) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.digest_admin(p_slug); en boolean := coalesce(p ->> 'enabled', '') in ('true', 't', '1'); iu boolean := coalesce(p ->> 'include_users', '') in ('true', 't', '1');
  rc text := lower(trim(coalesce(p ->> 'recipients', ''))); sd text := coalesce(nullif(p ->> 'send_days', ''), 'daily'); tg jsonb := coalesce(p -> 'targets', '{}'); k text; v numeric;
begin
  if sd not in ('daily', 'mon_sat') then raise exception 'Choose every day or Monday to Saturday.'; end if;
  if en and rc = '' and not iu then raise exception 'Add at least one e-mail address, or tick "all company administrators".'; end if;
  for k in select jsonb_object_keys(tg) loop
    if k not in ('eff_target', 'attendance_target', 'despatch_target', 'cal_days') then raise exception 'Unknown target %.', k; end if;
    v := nullif(tg ->> k, '')::numeric;
    if v is null or v < 0 or v > 365 or (k <> 'cal_days' and v > 100) then raise exception 'Target "%" is not a valid number.', k; end if;
  end loop;
  insert into console.digest_settings (customer_id, enabled, recipients, include_users, send_days, sections, targets, updated_at, updated_by)
  values (cid, en, rc, iu, sd, coalesce(p -> 'sections', '{}'), tg, now(), lower(coalesce(auth.jwt() ->> 'email', '')))
  on conflict (customer_id) do update set enabled = excluded.enabled, recipients = excluded.recipients, include_users = excluded.include_users, send_days = excluded.send_days,
    sections = excluded.sections, targets = excluded.targets, updated_at = now(), updated_by = excluded.updated_by;
  return 'ok';
end $$;
grant execute on function public.kmr_digest_save(text, jsonb) to authenticated;

-- the figures for the "Send test mail" button (nothing is marked as sent)
create or replace function public.kmr_digest_test(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.digest_admin(p_slug); s console.digest_settings; c console.customers;
begin
  select * into s from console.digest_settings where customer_id = cid; select * into c from console.customers where id = cid;
  return jsonb_build_object('customer_id', cid, 'slug', c.slug, 'company', c.name, 'brand', console.cal_brand(cid), 'sections', coalesce(s.sections, '{}'), 'targets', coalesce(s.targets, '{}'),
    'kpis', console.digest_kpis(cid, coalesce(s.targets, '{}')), 'me', lower(coalesce(auth.jwt() ->> 'email', '')));
end $$;
grant execute on function public.kmr_digest_test(text) to authenticated;

-- ---------- the morning run (service role only): every plant with the mail on, not yet mailed today ----------
create or replace function public.kmr_digest_scan() returns jsonb language plpgsql security definer set search_path = console, public as $$
declare d0 date := (now() at time zone 'Asia/Kolkata')::date; res jsonb := '[]'; s record; rcp text[];
begin
  for s in select a.customer_id, a.recipients, a.include_users, a.send_days, a.sections, a.targets, c.slug, c.name as company
             from console.digest_settings a join console.customers c on c.id = a.customer_id
            where a.enabled and (a.last_sent_on is null or a.last_sent_on < d0) loop
    if s.send_days = 'mon_sat' and extract(isodow from d0) = 7 then continue; end if;
    select coalesce(array_agg(distinct z.e), '{}') into rcp from (
      select lower(trim(x)) as e from regexp_split_to_table(coalesce(s.recipients, ''), '[,;[:space:]]+') as x
      union
      select m.email from console.customer_members m where s.include_users and m.customer_id = s.customer_id and m.is_admin and m.email is not null) z
     where z.e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$';
    continue when coalesce(array_length(rcp, 1), 0) = 0;
    res := res || jsonb_build_array(jsonb_build_object('customer_id', s.customer_id, 'slug', s.slug, 'company', s.company, 'brand', console.cal_brand(s.customer_id),
      'recipients', to_jsonb(rcp), 'sections', s.sections, 'targets', s.targets, 'kpis', console.digest_kpis(s.customer_id, s.targets)));
  end loop;
  return res;
end $$;
revoke all on function public.kmr_digest_scan() from public, anon, authenticated;
grant execute on function public.kmr_digest_scan() to service_role;

create or replace function public.kmr_digest_mark(p_cid uuid) returns void language sql security definer set search_path = console, public as $$
  update console.digest_settings set last_sent_on = (now() at time zone 'Asia/Kolkata')::date where customer_id = p_cid
$$;
revoke all on function public.kmr_digest_mark(uuid) from public, anon, authenticated;
grant execute on function public.kmr_digest_mark(uuid) to service_role;
