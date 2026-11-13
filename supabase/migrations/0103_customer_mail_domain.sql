-- 0103 — each customer can send its notification mails from its own domain (e.g. dont-reply@nerigroup.in). Set in Console › customer › Mail sending address.
-- A plant uses its company's domain. Until the domain is verified at the mail provider, mails go out from the standard KMR address with the customer's name.
alter table console.customers add column if not exists mail_domain text;
alter table console.customers add column if not exists mail_local text not null default 'dont-reply';
alter table console.customers add column if not exists mail_domain_id text;
alter table console.customers add column if not exists mail_domain_status text;
alter table console.customers add column if not exists mail_dns jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_mail_domain_format') then
    alter table console.customers add constraint customers_mail_domain_format check (mail_domain is null or mail_domain ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_mail_local_format') then
    alter table console.customers add constraint customers_mail_local_format check (mail_local ~ '^[a-z0-9._-]{1,40}$');
  end if;
end $$;
