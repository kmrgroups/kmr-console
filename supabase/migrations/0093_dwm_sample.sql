-- =====================================================================
-- 0093 — Daily Work Management: developer sample data (the "Sample data" button in the footer, KMR staff only)
--  • Load adds 3 sample employees with their DWM sheet for the current month; Remove deletes exactly that sample data
--  • documents keep a sample flag so real data is never touched
-- Needs 0091 and 0092. Safe to re-run.
-- =====================================================================
alter table console.dwm_docs add column if not exists sample boolean not null default false;

-- 31 characters, one per day: O plan, – off  (same rule as apps/dwm-core.js: Daily = every day except the weekly-off days)
create or replace function console.dwm_cells(p_mode text, p_wd int[], p_dates int[], p_month date, p_off int[]) returns text
language plpgsql immutable as $$
declare n int := extract(day from (date_trunc('month', p_month) + interval '1 month - 1 day'))::int; out text := ''; d int; dw int; on_ boolean;
begin
  for d in 1..31 loop
    on_ := false;
    if d <= n then
      dw := extract(dow from p_month + (d - 1))::int;
      if p_mode = 'daily' then on_ := not (dw = any (p_off));
      elsif p_mode = 'weekly' then on_ := dw = any (p_wd);
      elsif p_mode = 'dates' then on_ := d = any (p_dates);
      end if;
    end if;
    out := out || case when on_ then 'O' else '–' end;
  end loop;
  return out;
end $$;

create or replace function console.dwm_sample(p_cid uuid, p_action text) returns bigint language plpgsql security definer set search_path = console, public as $$
declare n bigint := 0; me text := lower(coalesce(auth.jwt() ->> 'email', 'sample')); mon date := date_trunc('month', (now() at time zone 'Asia/Kolkata')::date)::date;
        today_d int := extract(day from (now() at time zone 'Asia/Kolkata')::date)::int; mkey text := to_char(mon, 'YYYY-MM');
        st jsonb; emps jsonb; e record; acts jsonb; a record; cells text; chars text[]; d int; k int := 0; sheet jsonb; i int;
begin
  -- remove the earlier sample (documents and employees)
  delete from console.dwm_docs where customer_id = p_cid and sample;
  get diagnostics n = row_count;
  select doc into st from console.dwm_docs where customer_id = p_cid and doc_key = 'staff';
  if st is not null then
    emps := coalesce((select jsonb_agg(x) from jsonb_array_elements(st -> 'emps') x where coalesce((x ->> 'sample')::boolean, false) = false), '[]'::jsonb);
    update console.dwm_docs set doc = jsonb_build_object('emps', emps) where customer_id = p_cid and doc_key = 'staff';
  end if;
  if p_action = 'flush' then return n; end if;

  emps := coalesce((select doc -> 'emps' from console.dwm_docs where customer_id = p_cid and doc_key = 'staff'), '[]'::jsonb);
  for e in select * from (values ('smp1', 'Ravi Kumar', 'Plant Head', 'Plant Operations'), ('smp2', 'Anita Rao', 'Quality Head', 'Quality'), ('smp3', 'Suresh Patil', 'Production Manager', 'Production')) v(id, nm, ds, dp) loop
    emps := emps || jsonb_build_array(jsonb_build_object('id', e.id, 'name', e.nm, 'desig', e.ds, 'dept', e.dp, 'sample', true));
    acts := '[]'::jsonb; i := 0;
    for a in select * from (values
        ('Daily line walk — 5S and machine status', 'daily', '{}'::int[], '{}'::int[], '30 min'),
        ('Daily meeting with incharges', 'daily', '{}'::int[], '{}'::int[], '30 min'),
        ('Weekly business review', 'weekly', '{1}'::int[], '{}'::int[], '45 min'),
        ('Stock and quality review', 'weekly', '{2,4}'::int[], '{}'::int[], '30 min'),
        ('Month-end review and sign-off', 'dates', '{}'::int[], '{15,28}'::int[], '45 min')) v(t, m, wd, dt, du) loop
      i := i + 1; k := k + 1;
      cells := console.dwm_cells(a.m, a.wd, a.dt, mon, array[0]);
      chars := regexp_split_to_array(cells, '');
      for d in 1..least(today_d - 1, 31) loop            -- past planned days: mostly completed, a few missed or conceded
        if chars[d] = 'O' then
          chars[d] := case when (d * 7 + k * 3) % 17 = 0 then 'X' when (d * 5 + k) % 19 = 0 then 'E' else 'C' end;
        end if;
      end loop;
      acts := acts || jsonb_build_array(jsonb_build_object('id', e.id || 'a' || i, 'activity', a.t, 'resp', e.ds, 'mode', a.m, 'wd', to_jsonb(a.wd), 'dates', to_jsonb(a.dt), 'dur', a.du, 'cells', array_to_string(chars, '')));
    end loop;
    sheet := jsonb_build_object('target', 98, 'off', jsonb_build_array(0), 'section', 'Sample reviews', 'reviewed', '', 'approved', '', 'date', '', 'acts', acts, 'log', '{}'::jsonb);
    insert into console.dwm_docs (customer_id, doc_key, doc, updated_by, sample) values (p_cid, 'dwm:' || mkey || ':' || e.id, sheet, me, true)
    on conflict (customer_id, doc_key) do update set doc = excluded.doc, sample = true;
    n := n + 1;
  end loop;
  insert into console.dwm_docs (customer_id, doc_key, doc, updated_by) values (p_cid, 'staff', jsonb_build_object('emps', emps), me)
  on conflict (customer_id, doc_key) do update set doc = excluded.doc, updated_by = excluded.updated_by, updated_at = now();
  return n;
end $$;
revoke all on function console.dwm_sample(uuid, text), console.dwm_cells(text, int[], int[], date, int[]) from public, anon, authenticated;

-- the app clear (Data Master) also removes sample only when asked for real-only = false / true correctly
do $wrap$ begin
  if to_regprocedure('public.kmr_app_sample_dwm_base(text,text,text)') is null then
    alter function public.kmr_app_sample(text, text, text) rename to kmr_app_sample_dwm_base;
    create function public.kmr_app_sample(p_slug text, p_app text, p_action text) returns jsonb language plpgsql security definer set search_path = console, public as $f$
    declare cid uuid;
    begin
      if p_app = 'dwm' then
        if not coalesce(console.is_staff(), false) then raise exception 'Only the KMR developer login can load or remove sample data here.'; end if;
        if p_action not in ('load', 'flush') then raise exception 'Unknown action.'; end if;
        select id into cid from console.customers where slug = lower(p_slug);
        if cid is null then raise exception 'Unknown company link.'; end if;
        if not console.has_app(cid, 'dwm') then raise exception 'This company does not have that app.'; end if;
        return jsonb_build_object('dwm', console.dwm_sample(cid, p_action));
      end if;
      return public.kmr_app_sample_dwm_base(p_slug, p_app, p_action);
    end $f$;
    revoke all on function public.kmr_app_sample(text, text, text) from public, anon;
    grant execute on function public.kmr_app_sample(text, text, text) to authenticated;
    revoke all on function public.kmr_app_sample_dwm_base(text, text, text) from public, anon, authenticated;
  end if;
end $wrap$;

-- the Data Master "clear" for DWM (replaces the 0091 version): sample-only clear removes just the sample; a full clear removes everything
create or replace function console.app2_clear(p_app text, p_cid uuid, p_real_only boolean) returns bigint language plpgsql security definer set search_path = console, public as $f$
declare n bigint;
begin
  if p_app = 'dwm' then
    if p_real_only then return console.dwm_sample(p_cid, 'flush'); end if;
    delete from console.dwm_docs where customer_id = p_cid; get diagnostics n = row_count; return n;
  end if;
  return console.app2_clear_dwm_base(p_app, p_cid, p_real_only);
end $f$;
revoke all on function console.app2_clear(text, uuid, boolean) from public, anon, authenticated;
