-- HRM Suite — organisation chart: boxes entered directly (vacancies, people not in the employee list), reporting lines to those boxes,
-- the chart's document settings, and issued revisions (ISO 9001:2015 cl. 5.3, 7.5; IATF 16949:2016 cl. 5.3.1). Safe to re-run.

create table if not exists hrm.org_nodes (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references hrm.tenants(id) on delete cascade,
  title              text not null check (length(title) between 2 and 120),
  subtitle           text check (length(subtitle) <= 160),
  kind               text not null default 'person' check (kind in ('person','vacant','external')),
  parent_employee_id uuid references hrm.employees(id) on delete cascade,
  parent_node_id     uuid references hrm.org_nodes(id) on delete cascade,
  department_id      uuid references hrm.departments(id) on delete set null,
  sort_order         integer not null default 0,
  note               text check (length(note) <= 300),
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (parent_employee_id is null or parent_node_id is null),
  check (parent_node_id is distinct from id)
);
create index if not exists org_nodes_tenant on hrm.org_nodes (tenant_id);
create index if not exists org_nodes_parent_emp on hrm.org_nodes (parent_employee_id);
create index if not exists org_nodes_parent_node on hrm.org_nodes (parent_node_id);

-- an employee who reports to a direct-entry box (e.g. the Managing Director who is not in the employee list)
create table if not exists hrm.org_employee_links (
  employee_id    uuid primary key references hrm.employees(id) on delete cascade,
  tenant_id      uuid not null references hrm.tenants(id) on delete cascade,
  parent_node_id uuid not null references hrm.org_nodes(id) on delete cascade
);
create index if not exists org_links_tenant on hrm.org_employee_links (tenant_id);
create index if not exists org_links_parent on hrm.org_employee_links (parent_node_id);

create table if not exists hrm.org_chart_settings (
  tenant_id   uuid primary key references hrm.tenants(id) on delete cascade,
  title       text not null default 'Organisation Chart' check (length(title) between 2 and 80),
  doc_no      text not null default 'HR-ORG-01' check (length(doc_no) between 2 and 40),
  updated_at  timestamptz not null default now()
);

create table if not exists hrm.org_chart_issues (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references hrm.tenants(id) on delete cascade,
  rev_no       integer not null check (rev_no >= 0),
  issued_on    date not null,
  change_note  text check (length(change_note) <= 400),
  prepared_by  text check (length(prepared_by) <= 80),
  approved_by  text check (length(approved_by) <= 80),
  snapshot     jsonb not null,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  unique (tenant_id, rev_no)
);
create index if not exists org_issues_tenant on hrm.org_chart_issues (tenant_id, rev_no desc);

-- both parents of a box / link must belong to the same company
create or replace function hrm.org_guard() returns trigger language plpgsql set search_path = hrm, public as $$
begin
  if tg_table_name = 'org_nodes' then
    if new.parent_employee_id is not null and not exists (select 1 from hrm.employees e where e.id = new.parent_employee_id and e.tenant_id = new.tenant_id) then
      raise exception 'The person this box reports to is not in this company.';
    end if;
    if new.parent_node_id is not null and not exists (select 1 from hrm.org_nodes n where n.id = new.parent_node_id and n.tenant_id = new.tenant_id) then
      raise exception 'The box this box reports to is not in this company.';
    end if;
    if new.department_id is not null and not exists (select 1 from hrm.departments d where d.id = new.department_id and d.tenant_id = new.tenant_id) then
      raise exception 'Department not found.';
    end if;
    new.updated_at := now();
  else
    if not exists (select 1 from hrm.employees e where e.id = new.employee_id and e.tenant_id = new.tenant_id)
       or not exists (select 1 from hrm.org_nodes n where n.id = new.parent_node_id and n.tenant_id = new.tenant_id) then
      raise exception 'Person or box not found in this company.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists org_nodes_guard on hrm.org_nodes;
create trigger org_nodes_guard before insert or update on hrm.org_nodes for each row execute function hrm.org_guard();
drop trigger if exists org_links_guard on hrm.org_employee_links;
create trigger org_links_guard before insert or update on hrm.org_employee_links for each row execute function hrm.org_guard();

-- issued revisions are records: they are never changed or removed (ISO 9001:2015 cl. 7.5.3)
create or replace function hrm.org_issue_immutable() returns trigger language plpgsql set search_path = hrm, public as $$
begin
  -- only a company restore (company_import_safe, run as the database owner) or a removed company may delete issued revisions
  if current_user in ('postgres','supabase_admin') and (current_setting('hrm.restore', true) = 'on' or (tg_op = 'DELETE' and not exists (select 1 from hrm.tenants t where t.id = old.tenant_id))) then return coalesce(new, old); end if;
  raise exception 'An issued revision cannot be changed or deleted. Issue a new revision instead.';
end $$;
drop trigger if exists org_issues_no_change on hrm.org_chart_issues;
create trigger org_issues_no_change before update or delete on hrm.org_chart_issues for each row execute function hrm.org_issue_immutable();
revoke update, delete on hrm.org_chart_issues from anon, authenticated;

-- access: everyone in the company can read the chart; HR writes it
do $$ declare t text; begin
  foreach t in array array['org_nodes','org_employee_links','org_chart_settings','org_chart_issues'] loop
    execute format('alter table hrm.%I enable row level security', t);
    execute format('drop policy if exists %I on hrm.%I', t || '_read', t);
    execute format('create policy %I on hrm.%I for select to authenticated using (tenant_id = hrm.current_tenant_id())', t || '_read', t);
  end loop;
  foreach t in array array['org_nodes','org_employee_links','org_chart_settings'] loop
    execute format('drop policy if exists %I on hrm.%I', t || '_write', t);
    execute format('create policy %I on hrm.%I for all to authenticated using (tenant_id = hrm.current_tenant_id() and hrm.is_hr()) with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr())', t || '_write', t);
  end loop;
  drop policy if exists org_chart_issues_insert on hrm.org_chart_issues;
  create policy org_chart_issues_insert on hrm.org_chart_issues for insert to authenticated with check (tenant_id = hrm.current_tenant_id() and hrm.is_hr());
  foreach t in array array['org_nodes','org_employee_links','org_chart_settings','org_chart_issues'] loop
    execute format('drop trigger if exists %I on hrm.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on hrm.%I for each row execute function hrm.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- backup / restore: the chart is part of the company's backup ----------
create or replace function hrm.company_export_full(p_tenant uuid) returns jsonb
language plpgsql stable security definer set search_path = hrm, public as $fn$
declare out jsonb := hrm.company_export(p_tenant); t text; rows jsonb; tb jsonb := out->'tables';
begin
  foreach t in array array['org_nodes','org_employee_links','org_chart_settings','org_chart_issues'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from hrm.%I x where x.tenant_id = $1', t) into rows using p_tenant;
    tb := tb || jsonb_build_object(t, rows);
  end loop;
  return jsonb_set(jsonb_set(out, '{tables}', tb), '{version}', '9');
end $fn$;
revoke all on function hrm.company_export_full(uuid) from public, anon, authenticated;
grant execute on function hrm.company_export_full(uuid) to service_role;

-- restore (re-defined from 0014): same checks, then the organisation chart comes back too
create or replace function hrm.company_import_safe(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = hrm, public as $fn$
declare t text; bad int; ids uuid[]; counts jsonb; n int;
  skip text[] := array['employee_private'];
begin
  if coalesce(p_data->>'format', '') <> 'kmr-hrm-backup' then raise exception 'This file is not an HRM backup.'; end if;
  if (p_data->>'tenant_id')::uuid is distinct from p_tenant then raise exception 'This backup belongs to a different company.'; end if;
  for t in select jsonb_object_keys(coalesce(p_data->'tables', '{}'::jsonb)) loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    if t = any (skip) then continue; end if;
    select count(*) into bad from jsonb_array_elements(p_data->'tables'->t) r
     where coalesce(r->>'tenant_id', '') <> '' and (r->>'tenant_id') <> p_tenant::text;
    if bad > 0 then raise exception 'Backup rejected: % row(s) in "%" belong to another company.', bad, t; end if;
  end loop;
  select coalesce(array_agg((r->>'id')::uuid), '{}') into ids from jsonb_array_elements(coalesce(p_data->'tables'->'employees', '[]'::jsonb)) r;
  if jsonb_typeof(p_data->'tables'->'employee_private') = 'array' then
    select count(*) into bad from jsonb_array_elements(p_data->'tables'->'employee_private') r
     where not ((r->>'employee_id')::uuid = any (ids));
    if bad > 0 then raise exception 'Backup rejected: % private record(s) do not belong to an employee in this backup.', bad; end if;
  end if;
  counts := hrm.company_import(p_tenant, p_data);
  -- the chart: boxes first (a box may hang under another box), then links, settings and the issued revisions
  delete from hrm.org_employee_links where tenant_id = p_tenant;
  delete from hrm.org_nodes where tenant_id = p_tenant;
  delete from hrm.org_chart_settings where tenant_id = p_tenant;
  perform set_config('hrm.restore', 'on', true);
  delete from hrm.org_chart_issues where tenant_id = p_tenant;
  foreach t in array array['org_nodes','org_employee_links','org_chart_settings','org_chart_issues'] loop
    if jsonb_typeof(p_data->'tables'->t) <> 'array' then continue; end if;
    execute format('insert into hrm.%I select * from jsonb_populate_recordset(null::hrm.%I, $1)', t, t) using p_data->'tables'->t;
    get diagnostics n = row_count; counts := counts || jsonb_build_object(t, n);
  end loop;
  return counts;
end $fn$;
revoke all on function hrm.company_import_safe(uuid, jsonb) from public, anon, authenticated;
grant execute on function hrm.company_import_safe(uuid, jsonb) to service_role;
