-- GRN app: PO types (rate contract / yearly / bulk) and monthly delivery schedules released against them.
alter table console.dcg_po add column if not exists po_type text not null default 'regular',
  add column if not exists valid_from date, add column if not exists valid_to date;
alter table console.dcg_po drop constraint if exists dcg_po_type_chk;
alter table console.dcg_po add constraint dcg_po_type_chk check (po_type in ('regular', 'rate_contract', 'yearly', 'bulk'));

create table if not exists console.dcg_sched (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  sched_no text not null, po_id uuid not null references console.dcg_po(id) on delete cascade, month text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  status text not null default 'draft' check (status in ('draft', 'released', 'closed', 'cancelled')),
  remarks text, released_at timestamptz, created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (customer_id, sched_no));
create table if not exists console.dcg_sched_lines (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references console.customers(id) on delete cascade,
  sched_id uuid not null references console.dcg_sched(id) on delete cascade, po_line_id uuid not null references console.dcg_po_lines(id) on delete cascade,
  sl int not null default 1, qty numeric not null check (qty > 0), due_date date, delivered_qty numeric not null default 0);
alter table console.dcg_grn_lines add column if not exists sched_line_id uuid references console.dcg_sched_lines(id) on delete set null;
create index if not exists dcg_sched_po on console.dcg_sched (po_id);
create index if not exists dcg_schedl_s on console.dcg_sched_lines (sched_id);
create index if not exists dcg_schedl_pl on console.dcg_sched_lines (po_line_id);
do $$ declare t text; begin
  foreach t in array array['dcg_sched', 'dcg_sched_lines'] loop
    execute format('alter table console.%I enable row level security', t);
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;

-- PO type and validity (called after kmr_dcg_po_save)
create or replace function public.kmr_dcg_po_type_save(p_slug text, p_id uuid, p_type text, p_from date, p_to date) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg');
begin
  if p_type not in ('regular', 'rate_contract', 'yearly', 'bulk') then raise exception 'Unknown PO type.'; end if;
  if p_from is not null and p_to is not null and p_to < p_from then raise exception 'Valid-to date is before valid-from.'; end if;
  update console.dcg_po set po_type = p_type, valid_from = p_from, valid_to = p_to, updated_at = now() where id = p_id and customer_id = cid;
  if not found then raise exception 'Unknown PO.'; end if;
  return p_type;
end $$;

-- save a schedule (p: id?, po_id, month, remarks, release bool, lines [{po_line_id, qty, due_date}])
create or replace function public.kmr_dcg_sched_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); me text := lower(coalesce(auth.jwt() ->> 'email', '')); sid uuid := nullif(p ->> 'id', '')::uuid; po console.dcg_po; s console.dcg_sched;
  ln jsonb; k int := 0; q numeric; pl console.dcg_po_lines; booked numeric; no text; rel boolean := coalesce((p ->> 'release')::boolean, false); kept uuid[] := '{}'; lid uuid;
begin
  select * into po from console.dcg_po where id = nullif(p ->> 'po_id', '')::uuid and customer_id = cid;
  if po.id is null then raise exception 'Choose the purchase order.'; end if;
  if po.status in ('closed', 'cancelled') then raise exception 'PO % is %; a schedule cannot be added.', po.po_no, po.status; end if;
  if coalesce(p ->> 'month', '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose the schedule month.'; end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' then raise exception 'Add at least one item.'; end if;
  if sid is not null then
    select * into s from console.dcg_sched where id = sid and customer_id = cid for update;
    if s.id is null then raise exception 'Unknown schedule.'; end if;
    if s.status in ('closed', 'cancelled') then raise exception 'A % schedule cannot be changed.', s.status; end if;
    update console.dcg_sched set month = p ->> 'month', remarks = nullif(trim(coalesce(p ->> 'remarks', '')), ''), updated_at = now() where id = sid;
  else
    no := console.dcg_next(cid, 'sch');
    insert into console.dcg_sched (customer_id, sched_no, po_id, month, remarks, created_by) values (cid, no, po.id, p ->> 'month', nullif(trim(coalesce(p ->> 'remarks', '')), ''), me) returning id into sid;
  end if;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    q := coalesce(nullif(ln ->> 'qty', '')::numeric, 0);
    if q <= 0 then continue; end if;
    k := k + 1;
    select * into pl from console.dcg_po_lines where id = nullif(ln ->> 'po_line_id', '')::uuid and po_id = po.id;
    if pl.id is null then raise exception 'Line %: unknown PO item.', k; end if;
    select coalesce(sum(sl2.qty), 0) into booked from console.dcg_sched_lines sl2 join console.dcg_sched s2 on s2.id = sl2.sched_id
     where sl2.po_line_id = pl.id and s2.status in ('draft', 'released') and s2.id <> sid;
    if booked + q > pl.qty + 0.0001 then raise exception 'Line %: % has % in the PO and % is already scheduled; only % is left to schedule.', k, pl.description, pl.qty, booked, greatest(0, pl.qty - booked); end if;
    select id into lid from console.dcg_sched_lines where sched_id = sid and po_line_id = pl.id;
    if lid is null then
      insert into console.dcg_sched_lines (customer_id, sched_id, po_line_id, sl, qty, due_date) values (cid, sid, pl.id, k, q, nullif(ln ->> 'due_date', '')::date) returning id into lid;
    else
      update console.dcg_sched_lines set sl = k, qty = q, due_date = nullif(ln ->> 'due_date', '')::date where id = lid;
    end if;
    kept := kept || lid;
  end loop;
  if k = 0 then raise exception 'Enter a quantity for at least one item.'; end if;
  if exists (select 1 from console.dcg_sched_lines where sched_id = sid and id <> all (kept) and delivered_qty > 0) then raise exception 'An item that already has deliveries cannot be removed.'; end if;
  delete from console.dcg_sched_lines where sched_id = sid and id <> all (kept);
  if rel then update console.dcg_sched set status = 'released', released_at = coalesce(released_at, now()) where id = sid and status = 'draft'; end if;
  return jsonb_build_object('id', sid, 'sched_no', (select sched_no from console.dcg_sched where id = sid));
end $$;

create or replace function public.kmr_dcg_sched_status(p_slug text, p_id uuid, p_status text) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'dcg'); s console.dcg_sched;
begin
  select * into s from console.dcg_sched where id = p_id and customer_id = cid for update;
  if s.id is null then raise exception 'Unknown schedule.'; end if;
  if p_status not in ('released', 'closed', 'cancelled', 'delete') then raise exception 'Unknown status.'; end if;
  if p_status = 'delete' then
    if s.status <> 'draft' then raise exception 'Only a draft can be deleted; cancel a released schedule instead.'; end if;
    delete from console.dcg_sched where id = s.id; return 'deleted';
  end if;
  if p_status = 'cancelled' and exists (select 1 from console.dcg_sched_lines where sched_id = s.id and delivered_qty > 0) then raise exception 'This schedule already has deliveries; close it instead.'; end if;
  if p_status = 'released' and s.status <> 'draft' then raise exception 'Already %.', s.status; end if;
  update console.dcg_sched set status = p_status, released_at = case when p_status = 'released' then now() else released_at end, updated_at = now() where id = s.id;
  return p_status;
end $$;

-- patch load, GRN save and GRN cancel from their live definitions
do $do$
declare def text; a text;
begin
  -- load: add schedules
  def := pg_get_functiondef('public.kmr_dcg_load(text)'::regprocedure);
  if position('''scheds''' in def) = 0 then
    a := '''dcs'', coalesce(';
    if position(a in def) = 0 then raise exception 'load anchor'; end if;
    def := replace(def, a, '''scheds'', coalesce((select jsonb_agg(to_jsonb(s) - ''customer_id'' || jsonb_build_object(''lines'', coalesce((select jsonb_agg(to_jsonb(l) - ''customer_id'' order by l.sl) from console.dcg_sched_lines l where l.sched_id = s.id), ''[]''::jsonb)) order by s.month desc, s.created_at desc) from console.dcg_sched s where s.customer_id = cid), ''[]''::jsonb),' || chr(10) || '    ' || a);
    execute def;
  end if;
  -- grn save
  def := pg_get_functiondef('public.kmr_dcg_grn_save(text,jsonb)'::regprocedure);
  if position('sched_line_id' in def) = 0 then
    a := 'update console.dcg_po_lines set received_qty = received_qty + rq where id = pl.id;';
    if position(a in def) = 0 then raise exception 'grn anchor 1'; end if;
    def := replace(def, a, a || chr(10) || '      if nullif(ln ->> ''sched_line_id'', '''') is not null then update console.dcg_sched_lines set delivered_qty = delivered_qty + rq where id = (ln ->> ''sched_line_id'')::uuid and po_line_id = pl.id and customer_id = cid; if not found then raise exception ''Line %: unknown schedule item.'', k; end if; end if;');
    a := E'  end loop;\n  if k = 0 then raise exception';
    if position(a in def) = 0 then raise exception 'grn anchor 2'; end if;
    def := replace(def, a, E'    if gt = ''po_receipt'' and nullif(ln ->> ''sched_line_id'', '''') is not null then update console.dcg_grn_lines set sched_line_id = (ln ->> ''sched_line_id'')::uuid where grn_id = gid and sl = k; end if;\n' || a);
    a := E'  return jsonb_build_object(''id'', gid, ''grn_no'', no,';
    if position(a in def) = 0 then raise exception 'grn anchor 3'; end if;
    def := replace(def, a, E'  update console.dcg_sched s set status = ''closed'', updated_at = now() where s.customer_id = cid and s.status = ''released'' and exists (select 1 from console.dcg_sched_lines x where x.sched_id = s.id and x.id in (select sched_line_id from console.dcg_grn_lines where grn_id = gid))\n    and not exists (select 1 from console.dcg_sched_lines x where x.sched_id = s.id and x.delivered_qty < x.qty - 0.0001);\n' || a);
    execute def;
  end if;
  -- grn cancel
  def := pg_get_functiondef('public.kmr_dcg_grn_cancel(text,uuid,text)'::regprocedure);
  if position('sched_line_id' in def) = 0 then
    a := E'    if l.cal_record_id is not null then kept := kept + 1; end if;';
    if position(a in def) = 0 then raise exception 'cancel anchor'; end if;
    def := replace(def, a, a || E'\n    if l.sched_line_id is not null then update console.dcg_sched_lines set delivered_qty = greatest(0, delivered_qty - l.received_qty) where id = l.sched_line_id; update console.dcg_sched set status = ''released'' where status = ''closed'' and id = (select sched_id from console.dcg_sched_lines where id = l.sched_line_id); end if;');
    execute def;
  end if;
  -- backup lists
  def := pg_get_functiondef('console.bk_app_tables(uuid,text)'::regprocedure);
  if position('dcg_sched' in def) = 0 then
    a := 'when ''calib'' then array[''cal_files''] else';
    if position(a in def) = 0 then raise exception 'bk anchor'; end if;
    def := replace(def, a, 'when ''calib'' then array[''cal_files''] when ''dcg'' then array[''dcg_sched'', ''dcg_sched_lines''] else');
    def := replace(def, '''rmp_partstock'', ''rmp_plan_week'', ''rmp_settings''', '''rmp_partstock'', ''rmp_plan_week'', ''rmp_settings'', ''rmp_grn_alias''');
    execute def;
  end if;
end $do$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_dcg_(po_type|sched)' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
