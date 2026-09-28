-- =====================================================================
-- KMR platform — company administrators (and the main contact) are admins in EVERY tool the customer has,
-- including tools switched on later. Fixes "Can't open this app" for the main contact. Safe to re-run.
-- =====================================================================
create or replace function console.grant_admins(p_customer uuid) returns void
language plpgsql security definer set search_path = console, public as $$
declare m record; l record; r jsonb;
begin
  -- the main contact is always a company administrator
  insert into console.customer_members (customer_id, email, full_name, is_admin, created_by)
  select c.id, lower(c.contact_email), c.contact_name, true, 'Contact person' from console.customers c
   where c.id = p_customer and coalesce(c.contact_email, '') <> ''
  on conflict (customer_id, email) do update set is_admin = true;
  for m in select * from console.customer_members where customer_id = p_customer and is_admin loop
    r := m.roles;
    for l in select product_code from console.licences where customer_id = p_customer and product_ref is not null loop
      if coalesce(r ->> l.product_code, '') = '' then
        r := r || jsonb_build_object(l.product_code, case when l.product_code = 'hrm' then 'company_admin' else 'admin' end);
      end if;
    end loop;
    if r <> m.roles then
      update console.customer_members set roles = r, updated_at = now() where customer_id = p_customer and email = m.email;
    end if;
    begin
      perform console.sync_member(p_customer, m.email);
    exception when others then
      raise notice 'Could not give % access in every tool: %', m.email, sqlerrm;   -- e.g. the email already uses another company's HRM
    end;
  end loop;
end $$;

create or replace function console.licence_grant_admins() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.product_ref is not null then perform console.grant_admins(new.customer_id); end if;
  return new;
end $$;
drop trigger if exists licences_grant_admins on console.licences;
create trigger licences_grant_admins after insert or update of product_ref, customer_id on console.licences
  for each row execute function console.licence_grant_admins();

-- apply to every existing customer now
do $$ declare c uuid; begin
  for c in select id from console.customers loop perform console.grant_admins(c); end loop;
end $$;
