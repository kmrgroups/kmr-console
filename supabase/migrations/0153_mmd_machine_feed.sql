-- MMD machine capture: gateways (the program on the shop-floor PC), machine tag map, live feed, claim into production entries.
create table if not exists console.mmd_gateways(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  name text not null,
  location text,
  push_key text not null unique default substr(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),1,40),
  enabled boolean not null default true,
  last_seen timestamptz,
  rows_total bigint not null default 0,
  created_at timestamptz not null default now());

create table if not exists console.mmd_machine_map(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  machine_code text not null,
  protocol text not null default 'opcua',      -- opcua, s7, focas, mtconnect, modbus, mqtt, http
  address text,                                -- node id / data block address / register / topic / path
  kind text not null check (kind in ('good','reject','state','cycle')),
  scale numeric not null default 1,
  note text,
  unique (customer_id, machine_code, kind));

create table if not exists console.mmd_feed(
  id bigint generated always as identity primary key,
  customer_id uuid not null references console.customers(id) on delete cascade,
  machine_code text not null,
  captured_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  kind text not null check (kind in ('count','state')),
  good numeric not null default 0,
  rej numeric not null default 0,
  state text,                                  -- run, idle, alarm, off
  alarm text,
  cycle_s numeric,
  claimed_entry uuid references console.mmd_entries(id) on delete set null);
create index if not exists mmd_feed_m on console.mmd_feed(customer_id, machine_code, captured_at desc);
create index if not exists mmd_feed_open on console.mmd_feed(customer_id, machine_code) where claimed_entry is null and kind='count';

create table if not exists console.mmd_feed_last(
  customer_id uuid not null references console.customers(id) on delete cascade,
  machine_code text not null,
  last_good numeric, last_rej numeric,
  state text, state_at timestamptz, alarm text, last_at timestamptz,
  primary key (customer_id, machine_code));

alter table console.mmd_gateways enable row level security;
alter table console.mmd_machine_map enable row level security;
alter table console.mmd_feed enable row level security;
alter table console.mmd_feed_last enable row level security;

-- gateway sends {rows:[{machine, at?, good_total?, rej_total?, good?, rej?, state?, alarm?, cycle_s?}]}
-- *_total = cumulative counter read from the machine (resets are handled); good / rej = pieces since the last row.
create or replace function console.mmd_feed_ingest(p_key text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = console, public as $$
declare g console.mmd_gateways%rowtype; r jsonb; mc text; l console.mmd_feed_last%rowtype; found_l boolean;
  at timestamptz; gt numeric; rt numeric; dg numeric; dr numeric; st text; al text; n int := 0; unk text[] := '{}';
begin
  select * into g from console.mmd_gateways where push_key = coalesce(p_key,'') and enabled;
  if not found then return jsonb_build_object('ok', false, 'error', 'gateway not recognised'); end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]')) loop
    mc := upper(trim(coalesce(r->>'machine','')));
    if mc = '' then continue; end if;
    if not exists (select 1 from console.ops_records o where o.customer_id=g.customer_id and o.kind='machines' and upper(o.code)=mc) then
      if not (mc = any(unk)) then unk := unk || mc; end if; continue; end if;
    at := least(coalesce(nullif(r->>'at','')::timestamptz, now()), now() + interval '5 minutes');
    select * into l from console.mmd_feed_last where customer_id=g.customer_id and machine_code=mc; found_l := found;
    gt := nullif(r->>'good_total','')::numeric; rt := nullif(r->>'rej_total','')::numeric;
    dg := 0; dr := 0;
    if gt is not null then
      if found_l and l.last_good is not null then dg := case when gt >= l.last_good then gt - l.last_good else gt end; end if;
    else dg := greatest(0, coalesce(nullif(r->>'good','')::numeric, 0)); end if;
    if rt is not null then
      if found_l and l.last_rej is not null then dr := case when rt >= l.last_rej then rt - l.last_rej else rt end; end if;
    else dr := greatest(0, coalesce(nullif(r->>'rej','')::numeric, 0)); end if;
    st := lower(nullif(trim(coalesce(r->>'state','')),'')); if st is not null and st not in ('run','idle','alarm','off') then st := case when st in ('running','active','auto','1','true','on','cutting') then 'run' when st in ('stopped','ready','standby','interrupted','manual','0','false') then 'idle' when st in ('emergency','error','fault') then 'alarm' else 'idle' end; end if;
    al := nullif(left(coalesce(r->>'alarm',''),120),'');
    if dg > 0 or dr > 0 then
      insert into console.mmd_feed(customer_id, machine_code, captured_at, kind, good, rej, state, cycle_s)
      values (g.customer_id, mc, at, 'count', dg, dr, st, nullif(r->>'cycle_s','')::numeric); n := n + 1;
    end if;
    if st is not null and (not found_l or l.state is distinct from st or l.alarm is distinct from al) then
      insert into console.mmd_feed(customer_id, machine_code, captured_at, kind, state, alarm)
      values (g.customer_id, mc, at, 'state', st, al); n := n + 1;
    end if;
    insert into console.mmd_feed_last(customer_id, machine_code, last_good, last_rej, state, state_at, alarm, last_at)
    values (g.customer_id, mc, gt, rt, st, case when st is not null then at end, al, at)
    on conflict (customer_id, machine_code) do update set
      last_good = coalesce(excluded.last_good, console.mmd_feed_last.last_good),
      last_rej = coalesce(excluded.last_rej, console.mmd_feed_last.last_rej),
      state = coalesce(excluded.state, console.mmd_feed_last.state),
      state_at = case when excluded.state is not null and excluded.state is distinct from console.mmd_feed_last.state then excluded.state_at else console.mmd_feed_last.state_at end,
      alarm = case when excluded.state is not null then excluded.alarm else console.mmd_feed_last.alarm end,
      last_at = excluded.last_at;
  end loop;
  update console.mmd_gateways set last_seen = now(), rows_total = rows_total + n where id = g.id;
  return jsonb_build_object('ok', true, 'saved', n, 'unknown_machines', to_jsonb(unk), 'map', coalesce((select jsonb_agg(jsonb_build_object('machine',m.machine_code,'protocol',m.protocol,'address',m.address,'kind',m.kind,'scale',m.scale)) from console.mmd_machine_map m where m.customer_id=g.customer_id),'[]'));
end $$;
revoke all on function console.mmd_feed_ingest(text, jsonb) from public, anon, authenticated;
grant execute on function console.mmd_feed_ingest(text, jsonb) to service_role;
create or replace function public.mmd_feed_ingest(p_key text, p_rows jsonb) returns jsonb language sql security definer set search_path = console, public as $$ select console.mmd_feed_ingest(p_key, p_rows) $$;
revoke all on function public.mmd_feed_ingest(text, jsonb) from public, anon, authenticated;
grant execute on function public.mmd_feed_ingest(text, jsonb) to service_role;

-- screen data: live machines, unclaimed pieces, gateways, tag map
create or replace function public.kmr_mmd_feed_load(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug,'mmd'); ed boolean := coalesce(console.qp_role(cid,'mmd'),'') in ('admin','editor');
begin
  return jsonb_build_object('can_edit', ed,
   'gateways', coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'location',g.location,'enabled',g.enabled,'last_seen',g.last_seen,'rows_total',g.rows_total,'push_key',case when ed then g.push_key end) order by g.created_at) from console.mmd_gateways g where g.customer_id=cid),'[]'),
   'map', coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'machine_code',m.machine_code,'protocol',m.protocol,'address',m.address,'kind',m.kind,'scale',m.scale,'note',m.note) order by m.machine_code, m.kind) from console.mmd_machine_map m where m.customer_id=cid),'[]'),
   'live', coalesce((select jsonb_agg(jsonb_build_object('machine',l.machine_code,'state',l.state,'state_at',l.state_at,'alarm',l.alarm,'last_at',l.last_at,
        'good',coalesce((select sum(f.good) from console.mmd_feed f where f.customer_id=cid and f.machine_code=l.machine_code and f.kind='count' and f.claimed_entry is null),0),
        'rej',coalesce((select sum(f.rej) from console.mmd_feed f where f.customer_id=cid and f.machine_code=l.machine_code and f.kind='count' and f.claimed_entry is null),0),
        'upto',(select max(f.id) from console.mmd_feed f where f.customer_id=cid and f.machine_code=l.machine_code and f.kind='count'))) from console.mmd_feed_last l where l.customer_id=cid),'[]'));
end $$;
grant execute on function public.kmr_mmd_feed_load(text) to authenticated;

create or replace function public.kmr_mmd_gw_save(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug,'mmd'); gid uuid := nullif(p->>'id','')::uuid;
begin
  if coalesce((p->>'delete')::boolean,false) then delete from console.mmd_gateways where id=gid and customer_id=cid; return jsonb_build_object('ok',true); end if;
  if nullif(trim(coalesce(p->>'name','')),'') is null then raise exception 'Enter a name for the gateway (for example the PC or panel it runs on).'; end if;
  if gid is null then insert into console.mmd_gateways(customer_id,name,location) values (cid, trim(p->>'name'), nullif(p->>'location','')) returning id into gid;
  else update console.mmd_gateways set name=trim(p->>'name'), location=nullif(p->>'location',''), enabled=coalesce((p->>'enabled')::boolean,enabled) where id=gid and customer_id=cid; end if;
  return jsonb_build_object('ok',true,'id',gid);
end $$;
grant execute on function public.kmr_mmd_gw_save(text, jsonb) to authenticated;

create or replace function public.kmr_mmd_map_save(p_slug text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug,'mmd'); r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]')) loop
    if coalesce((r->>'delete')::boolean,false) then delete from console.mmd_machine_map where customer_id=cid and machine_code=upper(trim(r->>'machine_code')) and kind=r->>'kind'; continue; end if;
    if not exists (select 1 from console.ops_records o where o.customer_id=cid and o.kind='machines' and upper(o.code)=upper(trim(r->>'machine_code'))) then raise exception 'Machine % is not in the Operations Master.', r->>'machine_code'; end if;
    insert into console.mmd_machine_map(customer_id,machine_code,protocol,address,kind,scale,note)
    values (cid, upper(trim(r->>'machine_code')), coalesce(nullif(r->>'protocol',''),'opcua'), nullif(trim(coalesce(r->>'address','')),''), r->>'kind', coalesce(nullif(r->>'scale','')::numeric,1), nullif(r->>'note',''))
    on conflict (customer_id,machine_code,kind) do update set protocol=excluded.protocol, address=excluded.address, scale=excluded.scale, note=excluded.note;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok',true,'saved',n);
end $$;
grant execute on function public.kmr_mmd_map_save(text, jsonb) to authenticated;

-- production entry that also takes over the machine's counted pieces, so nothing is typed twice
create or replace function public.kmr_mmd_entry_feed(p_slug text, p jsonb) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug,'mmd'); res jsonb; ent uuid; mc text; upto bigint := nullif(p->>'feed_upto','')::bigint;
begin
  res := console.mmd_entry(cid, lower(coalesce(auth.jwt() ->> 'email','')), p);
  ent := (res->>'entry_id')::uuid;
  if upto is not null then
    select upper(machine) into mc from console.mmd_entries where id = ent;
    update console.mmd_feed set claimed_entry = ent where customer_id=cid and machine_code=mc and kind='count' and claimed_entry is null and id <= upto;
  end if;
  return res;
end $$;
grant execute on function public.kmr_mmd_entry_feed(text, jsonb) to authenticated;
