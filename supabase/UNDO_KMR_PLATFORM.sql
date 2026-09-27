-- =====================================================================
-- UNDO the KMR platform setup — removes ONLY what KMR_PLATFORM_SETUP.sql added:
--   the "console" and "hrm" schemas (Console + HRM data!), the licence rules added to the
--   Balloon Inspector / Process Documents tables, public.kmr_access, and the hrm-* storage buckets.
-- The website's tables and the tools' own tables and data are NOT touched.
-- WARNING: all Console customers/licences and all HRM companies, employees and attendance are deleted.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['bi_reports','pd_projects','pd_masters'] loop
    if to_regclass('public.' || t) is not null then execute format('drop policy if exists kmr_licence on public.%I', t); end if;
  end loop;
  foreach t in array array['bi_orgs','pd_orgs'] loop
    if to_regclass('public.' || t) is not null then execute format('drop trigger if exists kmr_auto_trial on public.%I', t); end if;
  end loop;
  foreach t in array array['bi_members','pd_members'] loop
    if to_regclass('public.' || t) is not null then execute format('drop trigger if exists kmr_member_limit on public.%I', t); end if;
  end loop;
end $$;
drop function if exists public.kmr_access(text);
do $$ begin
  execute 'delete from storage.objects where bucket_id in (''hrm-branding'',''hrm-docs'')';
  execute 'delete from storage.buckets where id in (''hrm-branding'',''hrm-docs'')';
exception when others then
  raise notice 'Could not remove the hrm-branding / hrm-docs storage buckets here (%). Delete them under Storage in the dashboard.', sqlerrm;
end $$;
drop schema if exists hrm cascade;
drop schema if exists console cascade;
select 'KMR PLATFORM REMOVED — website and tool data untouched' as result;
