-- =====================================================================
-- 0089 — Factory & Office Layout (a new KMR App)
--  • 1:1 scale factory machine shop and office layout generator
--  • Converts line concepts into lean cellular manufacturing layouts (Group Technology, U-Cells, Flow)
--  • Evaluates travel distance, WIP reduction, floor utilization, and aisle clearances
--  • Generates multiple 1:1 options with direct AutoCAD DXF export and KMR CAD integration
-- Safe to re-run.
-- =====================================================================

insert into console.products (code, name, description, app_path, seat_label, current_version, sort_order) values
  ('layout', 'Factory & Office Layout', '1:1 scale factory machine shop and office layout generator — converts line concepts into lean cellular layouts with DXF export', '/it/layout.html', 'users', '1.0.0', 135)
on conflict (code) do update set name = excluded.name, description = excluded.description, app_path = excluded.app_path;

insert into console.releases (product_code, version, notes) values
  ('layout', '1.0.0', 'Factory & Office Layout: 1:1 scale generator, line-to-cell transformation, U-cells, perimeter milling, office floor plans, DXF export, CAD integration')
on conflict do nothing;

insert into console.prices (product_code, period, currency, unit_amount, min_seats, active, note)
select v.code, v.period, 'INR', v.amt, 1, true, 'Starting price list (0089) — change in Console • Billing'
  from (values ('layout', 'month', 2000), ('layout', 'year', 20000)) v(code, period, amt)
on conflict (product_code, period, currency) do nothing;

insert into public.app_listings (code, name, tagline, features, sort_order, is_active) values
  ('layout', 'Factory & Office Layout', 'Transform factory machine lines and office floor plans into 1:1 scale lean cellular layouts.',
   E'1:1 metric scale layout engine\nLine concept to cellular manufacturing converter\nMulti-option generation with Lean KPIs and DXF export', 135, true)
on conflict (code) do update set name = excluded.name, tagline = coalesce(public.app_listings.tagline, excluded.tagline), features = coalesce(public.app_listings.features, excluded.features);

insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order) values
  ('layout', '1:1 Layout Engine & Options Generator', '1:1 metric layout generation, line-to-cell conversion, travel distance optimization, DXF export and KMR CAD link', true, 2000, 0, 10000, 10)
on conflict (product_code, name) do nothing;

-- Grant 'layout' licence to all active customers (including Esbee Precision Industries & Demo)
insert into console.licences (customer_id, product_code, status, valid_until, seats, notes)
select id, 'layout', 'active', null, 25, 'KMR Apps Suite licence'
  from console.customers
 where status = 'active'
on conflict (customer_id, product_code) do nothing;

create table if not exists console.layout_counters (
  customer_id uuid not null references console.customers(id) on delete cascade,
  key text not null,
  n bigint not null default 0,
  sample boolean not null default false,
  primary key (customer_id, key)
);

create table if not exists console.layout_projects (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  no text not null,
  title text not null,
  kind text not null default 'factory' check (kind in ('factory', 'office')),
  concept text not null default 'cellular-u' check (concept in ('cellular-u', 'cellular-heavy', 'straight-flow', 'office-ergonomic')),
  dimensions jsonb not null default '{"width": 20.0, "depth": 30.0, "hallDepth": 24.0, "qcDepth": 5.4, "aisle": 2.8, "opClearance": 1.2, "maintClearance": 1.5}'::jsonb,
  source_file text,
  machines jsonb not null default '[]'::jsonb,
  options jsonb not null default '[]'::jsonb,
  selected_option int not null default 1,
  status text not null default 'draft' check (status in ('draft', 'review', 'approved', 'superseded')),
  history jsonb not null default '[]'::jsonb,
  sample boolean not null default false,
  created_by text,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now(),
  unique (customer_id, no)
);

create index if not exists layout_proj_cid on console.layout_projects (customer_id, updated_at desc);

alter table console.layout_counters enable row level security;
alter table console.layout_projects enable row level security;
drop policy if exists layout_counters_staff on console.layout_counters;
create policy layout_counters_staff on console.layout_counters for all to authenticated using (console.is_staff()) with check (console.is_staff());
drop policy if exists layout_proj_staff on console.layout_projects;
create policy layout_proj_staff on console.layout_projects for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- ---------- helpers ----------
create or replace function console.layout_next(p_cid uuid, p_key text) returns bigint language sql security definer set search_path = console, public as $$
  insert into console.layout_counters (customer_id, key, n) values (p_cid, p_key, 1)
  on conflict (customer_id, key) do update set n = console.layout_counters.n + 1 returning n $$;
revoke all on function console.layout_next(uuid, text) from public, anon, authenticated;

-- ---------- API Functions ----------
create or replace function public.kmr_layout_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'layout');
begin
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id, 'no', p.no, 'title', p.title, 'kind', p.kind, 'concept', p.concept,
        'dimensions', p.dimensions, 'source_file', p.source_file,
        'machine_count', jsonb_array_length(p.machines),
        'options_count', jsonb_array_length(p.options),
        'selected_option', p.selected_option,
        'status', p.status, 'sample', p.sample,
        'created_by', p.created_by, 'created_at', p.created_at, 'updated_at', p.updated_at
      ) order by p.updated_at desc
    ) from console.layout_projects p where p.customer_id = cid
  ), '[]'::jsonb);
end $$;

create or replace function public.kmr_layout_get(p_slug text, p_id uuid) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'layout'); r jsonb;
begin
  select to_jsonb(p) - 'customer_id' into r from console.layout_projects p where p.id = p_id and p.customer_id = cid;
  if r is null then raise exception 'Layout project not found.'; end if;
  return r;
end $$;

create or replace function public.kmr_layout_save(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare
  cid uuid := console.qp_edit(p_slug, 'layout');
  pid uuid := nullif(p ->> 'id', '')::uuid;
  num text;
  now_t timestamptz := now();
  me text := lower(coalesce(auth.jwt() ->> 'email', ''));
  out_id uuid;
begin
  if pid is not null then
    update console.layout_projects
       set title = coalesce(p ->> 'title', title),
           kind = coalesce(p ->> 'kind', kind),
           concept = coalesce(p ->> 'concept', concept),
           dimensions = coalesce(p -> 'dimensions', dimensions),
           source_file = coalesce(p ->> 'source_file', source_file),
           machines = coalesce(p -> 'machines', machines),
           options = coalesce(p -> 'options', options),
           selected_option = coalesce((p ->> 'selected_option')::int, selected_option),
           updated_by = me,
           updated_at = now_t
     where id = pid and customer_id = cid
    returning id into out_id;
    if out_id is null then raise exception 'Layout project not found.'; end if;
    return jsonb_build_object('ok', true, 'id', out_id);
  else
    num := 'LAY-' || to_char(now_t, 'YYMM') || '-' || lpad(console.layout_next(cid, 'project')::text, 4, '0');
    insert into console.layout_projects (
      customer_id, no, title, kind, concept, dimensions, source_file, machines, options, selected_option, status, created_by, updated_by
    ) values (
      cid, num, coalesce(p ->> 'title', 'New Plant Layout'), coalesce(p ->> 'kind', 'factory'),
      coalesce(p ->> 'concept', 'cellular-u'), coalesce(p -> 'dimensions', '{"width": 20.0, "depth": 30.0, "hallDepth": 24.0, "qcDepth": 5.4}'::jsonb),
      p ->> 'source_file', coalesce(p -> 'machines', '[]'::jsonb), coalesce(p -> 'options', '[]'::jsonb),
      coalesce((p ->> 'selected_option')::int, 1), 'draft', me, me
    ) returning id into out_id;
    return jsonb_build_object('ok', true, 'id', out_id, 'no', num);
  end if;
end $$;

create or replace function public.kmr_layout_delete(p_slug text, p_id uuid) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'layout');
begin
  delete from console.layout_projects where id = p_id and customer_id = cid;
  return jsonb_build_object('ok', true);
end $$;

-- Populate EPI Factory Sample Layout (20m x 30m, 62 Machines)
create or replace function public.kmr_layout_sample(p_slug text) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare
  cid uuid := console.qp_edit(p_slug, 'layout');
  num text;
  now_t timestamptz := now();
  me text := lower(coalesce(auth.jwt() ->> 'email', ''));
  out_id uuid;
begin
  delete from console.layout_projects where customer_id = cid and sample = true;
  num := 'LAY-' || to_char(now_t, 'YYMM') || '-0001';
  insert into console.layout_projects (
    customer_id, no, title, kind, concept, dimensions, source_file, machines, options, selected_option, status, sample, created_by, updated_by
  ) values (
    cid, num, 'EPI Factory Machine Shop (20m × 30m Blueprint Re-Layout)', 'factory', 'cellular-u',
    '{"width": 20.0, "depth": 30.0, "hallDepth": 24.0, "qcDepth": 5.4, "aisle": 2.8, "opClearance": 1.2, "maintClearance": 1.5}'::jsonb,
    'EPI Factory Layout Working drawings_28.05.2026.pdf',
    '[
      {"id": "NEJ-04", "type": "cnc", "name": "NEJ-04", "w": 3.70, "h": 2.30, "cell": "CNC Turning"},
      {"id": "B-20", "type": "cnc", "name": "B-20", "w": 3.50, "h": 2.50, "cell": "CNC Turning"},
      {"id": "NEB-102", "type": "cnc", "name": "NEB 102", "w": 2.80, "h": 2.00, "cell": "CNC Turning"},
      {"id": "B-08", "type": "cnc", "name": "B-08", "w": 3.70, "h": 2.50, "cell": "CNC Turning"},
      {"id": "B-82", "type": "cnc", "name": "B-82", "w": 2.95, "h": 1.80, "cell": "CNC Turning"},
      {"id": "HMC", "type": "vmc", "name": "HMC NEJ-01", "w": 3.20, "h": 2.30, "cell": "VMC / HMC"},
      {"id": "B-02-1", "type": "vmc", "name": "VMC B-02 #1", "w": 3.20, "h": 2.30, "cell": "VMC / HMC"},
      {"id": "B-86", "type": "vmc", "name": "BED MILL B-86", "w": 6.00, "h": 2.20, "cell": "VMC / HMC"},
      {"id": "B-92", "type": "vmc", "name": "VMC B-92", "w": 4.00, "h": 2.20, "cell": "VMC / HMC"},
      {"id": "IC-STUD", "type": "msa", "name": "IC STUD 3 TABLE (CMM)", "w": 4.10, "h": 0.60, "cell": "Quality / MSA"},
      {"id": "2-TABLE", "type": "msa", "name": "2 TABLE (Air/Bore)", "w": 3.00, "h": 0.60, "cell": "Quality / MSA"},
      {"id": "ROTOR", "type": "finish", "name": "HOUSING & T-ROTOR ASSY", "w": 6.40, "h": 2.40, "cell": "Finish & Pack"}
    ]'::jsonb,
    '[
      {"name": "Option A: Dual U-Cells", "travel": 182, "util": 51.4, "score": "A+"},
      {"name": "Option B: Heavy Perimeter Machining", "travel": 210, "util": 54.2, "score": "A"},
      {"name": "Option C: Linear One-Piece Flow", "travel": 235, "util": 49.8, "score": "B+"}
    ]'::jsonb,
    1, 'approved', true, me, me
  ) returning id into out_id;
  return jsonb_build_object('ok', true, 'id', out_id, 'no', num);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_layout_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- Update demo workspace to activate 'layout' product and seed sample layout
drop function if exists console.demo_refresh(uuid, boolean);
create or replace function console.demo_refresh(p_cid uuid, p_full boolean default true) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cu console.customers%rowtype; pcode text; out jsonb;
begin
  select * into cu from console.customers where id = p_cid and kind = 'demo';
  if not found then raise exception 'This is not a demo workspace.'; end if;
  foreach pcode in array array['sales', 'calib', 'apqp', 'ppap', 'rmp', 'mmd', 'mnt', 'mom', 'cad', 'hrms', 'tsk', 'msa', 'spc', 'crm', 'd8', 'aud', 'off', 'layout'] loop
    insert into console.licences (customer_id, product_code, status, valid_until, seats, notes, product_ref, product_slug)
    select p_cid, pcode, 'active', null, 25, 'KMR demo data', p_cid, cu.slug where exists (select 1 from console.products pr where pr.code = pcode)
    on conflict (customer_id, product_code) do nothing;
  end loop;
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'email', lower(coalesce(cu.contact_email, ''))) ::text, true);
  if p_full then perform public.kmr_grand_sample(cu.slug, 'flush'); end if;
  out := public.kmr_grand_sample(cu.slug, 'load');
  -- load layout sample
  perform public.kmr_layout_sample(cu.slug);
  return out;
end $$;

revoke all on function console.demo_refresh(uuid, boolean), console.demo_refresh_all() from public, anon, authenticated;
grant execute on function console.demo_refresh(uuid, boolean), console.demo_refresh_all() to service_role;

