-- =====================================================================
-- HRM — each customer company sends its HR emails from ITS OWN mailbox (Gmail / Google Workspace,
-- Microsoft 365 / Outlook, Zoho Mail, GoDaddy, Hostinger or any mail server). No KMR address is used.
-- Until a company connects its mailbox, HRM emails are not sent (WhatsApp and in-app still work).
-- The mailbox password is stored encrypted by the server; this table is never readable from the browser.
-- Safe to re-run.
-- =====================================================================
create table if not exists hrm.tenant_mail (
  tenant_id     uuid primary key references hrm.tenants(id) on delete cascade,
  from_email    text not null,
  from_name     text,
  host          text not null,
  port          integer not null default 587 check (port between 1 and 65535),
  secure        boolean not null default false,      -- true = SSL on connect (port 465); false = STARTTLS (587)
  username      text not null,
  password_enc  text not null,                        -- AES-256-GCM, encrypted by the HRM server
  verified_at   timestamptz,
  last_error    text,
  updated_at    timestamptz not null default now(),
  updated_by    uuid
);
alter table hrm.tenant_mail enable row level security;
-- no policies: only the server (service role) reads or writes it
revoke all on hrm.tenant_mail from anon, authenticated;
