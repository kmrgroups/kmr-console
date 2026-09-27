-- =====================================================================
-- KMR Console — Milestone 3: service layer.
--   tickets + ticket_messages  support requests raised from inside the products, answered in the Console
--   leads                      pilot / demo requests from the website
-- Products write through the service key (after checking their own user); nothing here is open to the public.
-- Safe to re-run.
-- =====================================================================
create sequence if not exists console.ticket_no;
create table if not exists console.tickets (
  id              uuid primary key default gen_random_uuid(),
  number          text not null unique default ('T-' || lpad(nextval('console.ticket_no')::text, 5, '0')),
  customer_id     uuid references console.customers(id) on delete set null,
  product_code    text not null references console.products(code),
  product_ref     uuid,                       -- the customer's company / workspace inside the product
  raised_by_email text not null,
  raised_by_name  text not null,
  subject         text not null check (length(subject) between 3 and 150),
  priority        text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status          text not null default 'open' check (status in ('open','in_progress','waiting_on_customer','resolved','closed')),
  page_url        text,
  app_version     text,
  assigned_to     uuid references console.staff(user_id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  first_reply_at  timestamptz,
  resolved_at     timestamptz
);
create index if not exists tickets_status on console.tickets (status, created_at desc);
create index if not exists tickets_ref on console.tickets (product_code, product_ref, created_at desc);

create table if not exists console.ticket_messages (
  id           bigserial primary key,
  ticket_id    uuid not null references console.tickets(id) on delete cascade,
  author_kind  text not null check (author_kind in ('customer','kmr')),
  author_name  text not null,
  body         text not null check (length(body) between 1 and 5000),
  created_at   timestamptz not null default now()
);
create index if not exists ticket_messages_ticket on console.ticket_messages (ticket_id, created_at);

-- first KMR reply and resolution times feed the Console's response-time figures
create or replace function console.ticket_touch() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  update console.tickets set updated_at = now(),
         first_reply_at = case when new.author_kind = 'kmr' and first_reply_at is null then now() else first_reply_at end,
         status = case when new.author_kind = 'customer' and status in ('waiting_on_customer','resolved') then 'open' else status end
   where id = new.ticket_id;
  return new;
end $$;
drop trigger if exists ticket_messages_touch on console.ticket_messages;
create trigger ticket_messages_touch after insert on console.ticket_messages for each row execute function console.ticket_touch();

create table if not exists console.leads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(name) between 2 and 100),
  company     text not null check (length(company) between 2 and 150),
  email       text not null,
  phone       text,
  country     text,
  products    text[] not null default '{}',
  message     text,
  status      text not null default 'new' check (status in ('new','contacted','converted','dropped')),
  customer_id uuid references console.customers(id) on delete set null,
  source      text not null default 'website',
  created_at  timestamptz not null default now()
);
create index if not exists leads_status on console.leads (status, created_at desc);

-- Link a ticket to its Console customer automatically (from the product's licence)
create or replace function console.ticket_customer() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if new.customer_id is null and new.product_ref is not null then
    select customer_id into new.customer_id from console.licences where product_code = new.product_code and product_ref = new.product_ref;
  end if;
  return new;
end $$;
drop trigger if exists tickets_customer on console.tickets;
create trigger tickets_customer before insert on console.tickets for each row execute function console.ticket_customer();

alter table console.tickets         enable row level security;
alter table console.ticket_messages enable row level security;
alter table console.leads           enable row level security;
do $$
declare t text;
begin
  foreach t in array array['tickets','ticket_messages','leads'] loop
    execute format('drop policy if exists %I on console.%I', t || '_staff', t);
    execute format('create policy %I on console.%I for all to authenticated using (console.is_staff()) with check (console.is_staff())', t || '_staff', t);
  end loop;
end $$;
revoke all on console.tickets, console.ticket_messages, console.leads from anon;
