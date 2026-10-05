-- =====================================================================
-- 0047 — a quotation can be drafted against a website enquiry (Console › Leads › Quote, or "Against an enquiry"
-- in the quotation screen). The quotation remembers its enquiry; saving it marks the enquiry "quoted".
-- Needs 0045. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.quotes') is null then raise exception 'Run 0045_media_costing_quotes.sql first.'; end if;
end $$;
alter table console.quotes add column if not exists lead_id uuid references console.leads(id) on delete set null;
create index if not exists quotes_lead on console.quotes (lead_id) where lead_id is not null;
