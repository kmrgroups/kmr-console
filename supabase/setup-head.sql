-- =====================================================================
-- KMR PLATFORM SETUP — run ONCE in the KMR Supabase project (dehlcusptkzfhqvpfyjh).
-- Adds two new sections next to the website's and the quality tools' tables:
--   console  KMR Console: staff, customers, products, licences, releases
--            + licences for Balloon Inspector / Process Documents (existing workspaces adopted as pilots)
--   hrm      HRM Suite for all customer companies
-- Nothing existing is changed or deleted (website tables, bi_* and pd_* tool tables, the "media" bucket).
--
-- BEFORE RUNNING
--   1. Take a backup: Database -> Backups (or Project Settings -> Database -> download a backup).
--   2. Set YOUR KMR CONSOLE OWNER below to your existing login email (e.g. the website admin login).
--   3. SQL Editor -> New query -> paste this whole file -> Run.  It ends with: KMR PLATFORM READY
-- AFTER RUNNING
--   4. Project Settings -> Data API -> Exposed schemas: add  hrm  and  console  -> Save.
-- =====================================================================

-- ------------------- YOUR KMR CONSOLE OWNER --------------------------
create temp table kmr_setup as select
  'info@kmr-groups.com'   ::text as owner_email,   -- an EXISTING login (Authentication -> Users)
  'Rajavelu R'            ::text as owner_name;
-- ---------------------------------------------------------------------

do $$
declare s record;
begin
  select * into s from kmr_setup;
  if to_regclass('console.staff') is not null or to_regclass('hrm.tenants') is not null then
    raise exception 'The KMR platform is already set up in this project. Nothing was changed.';
  end if;
  if not exists (select 1 from auth.users where lower(email) = lower(s.owner_email)) then
    raise exception 'No login found for %. Put an existing login email in owner_email (Authentication -> Users), then run again.', s.owner_email;
  end if;
end $$;
