-- =====================================================================
-- EXPORT_TOOL_SCHEMA.sql — read-only. Prints the CREATE statements of the Balloon Inspector (bi_*) and
-- Process Documents (pd_*) tables exactly as they exist in the live database (Capacity's cp_* tables and the
-- Console's licence functions are already in the kmr-console migrations, so they are left out),
-- so they can be saved in kmr-console/supabase/products/tools/0001_tool_tables.sql and a new customer's
-- database can be built from the repos alone.
-- Supabase -> SQL Editor -> paste -> Run -> copy the single "ddl" cell of the result and send it back.
-- Nothing is changed.
-- =====================================================================
with t as (
  select c.oid, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relname ~ '^(bi|pd)_'
),
cols as (
  select t.relname, string_agg(
           format('  %I %s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
                  case when a.attnotnull then ' not null' else '' end,
                  coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')),
           E',\n' order by a.attnum) body
    from t join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = t.oid and d.adnum = a.attnum
   group by t.relname
),
cons as (
  select t.relname, string_agg(format('  constraint %I %s', co.conname, pg_get_constraintdef(co.oid)), E',\n'
                               order by case co.contype when 'p' then 0 when 'u' then 1 when 'c' then 2 else 3 end, co.conname) body
    from t join pg_constraint co on co.conrelid = t.oid and co.contype <> 'f' group by t.relname
),
idx as (
  select string_agg(regexp_replace(regexp_replace(pg_get_indexdef(i.indexrelid), '^CREATE UNIQUE INDEX ', 'CREATE UNIQUE INDEX IF NOT EXISTS '), '^CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS ') || ';', E'\n' order by t.relname) body
    from t join pg_index i on i.indrelid = t.oid
   where not i.indisprimary and not exists (select 1 from pg_constraint co where co.conindid = i.indexrelid)
),
pol as (
  select string_agg(format('drop policy if exists %I on public.%I;%screate policy %I on public.%I as %s for %s to %s%s%s;', policyname, tablename, E'\n', policyname, tablename, permissive, cmd,
            array_to_string(roles, ', '), coalesce(' using (' || qual || ')', ''), coalesce(' with check (' || with_check || ')', '')), E'\n' order by tablename, policyname) body
    from pg_policies where schemaname = 'public' and tablename ~ '^(bi|pd)_'
),
fn as (   -- functions whose name starts bi_ / pd_ / cp_ (create or replace: safe to re-run)
  select string_agg(pg_get_functiondef(p.oid) || ';', E'\n\n' order by p.proname) body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname ~ '^(bi|pd)_' and p.prokind = 'f'
     and pg_get_functiondef(p.oid) !~* 'console\.'   -- the Console's own licence functions are already in its migrations
),
trg as (
  select string_agg(format('drop trigger if exists %I on public.%I;', tg.tgname, t.relname) || E'\n' || pg_get_triggerdef(tg.oid) || ';', E'\n' order by t.relname, tg.tgname) body
    from pg_trigger tg join t on t.oid = tg.tgrelid where not tg.tgisinternal
     and pg_get_functiondef(tg.tgfoid) !~* 'console\.'
),
seq as (  -- sequences behind serial defaults
  select string_agg(format('create sequence if not exists public.%I;', sq.relname), E'\n' order by sq.relname) body
    from pg_class sq join pg_namespace n on n.oid = sq.relnamespace
   where sq.relkind = 'S' and n.nspname = 'public' and sq.relname ~ '^(bi|pd)_'
),
fk as (   -- foreign keys after all tables, so they can be created in any order
  select string_agg(format('do $f$ begin alter table public.%I add constraint %I %s; exception when duplicate_object then null; end $f$;', t.relname, co.conname, pg_get_constraintdef(co.oid)), E'\n' order by t.relname, co.conname) body
    from t join pg_constraint co on co.conrelid = t.oid and co.contype = 'f'
),
tbl as (
  select string_agg(format(E'create table if not exists public.%I (\n%s%s\n);\nalter table public.%I enable row level security;', c.relname, c.body, coalesce(E',\n' || k.body, ''), c.relname), E'\n\n' order by c.relname) body
    from cols c left join cons k using (relname)
)
-- order: sequences, tables, foreign keys, indexes, functions, triggers, policies (policies may call the functions)
select concat_ws(E'\n\n', '-- tool tables exported ' || now()::text || ' — safe to run more than once',
         '-- sequences',   (select body from seq),
         '-- tables',      (select body from tbl),
         '-- foreign keys',(select body from fk),
         '-- indexes',     (select body from idx),
         '-- functions',   (select body from fn),
         '-- triggers',    (select body from trg),
         '-- policies',    (select body from pol)) as ddl;
