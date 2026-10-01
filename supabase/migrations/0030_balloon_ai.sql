-- =====================================================================
-- Balloon Inspector — "Read with AI". The website reads the drawing with Claude (the API key stays on the website's
-- server); before every read it asks the database whether the signed-in person may use it, and logs each read here.
-- Safe to re-run.
-- =====================================================================
create table if not exists console.ai_usage (
  id            bigserial primary key,
  at            timestamptz not null default now(),
  product       text not null,
  org_id        uuid,
  customer_id   uuid,
  user_email    text,
  model         text,
  input_tokens  integer,
  output_tokens integer,
  ok            boolean not null default true,
  error         text
);
create index if not exists ai_usage_org_at on console.ai_usage (product, org_id, at desc);
alter table console.ai_usage enable row level security;
drop policy if exists ai_usage_staff on console.ai_usage;
create policy ai_usage_staff on console.ai_usage for select to authenticated using (console.is_staff());

-- May the signed-in person read drawings with AI in this Balloon workspace? Returns their role, the company and
-- how many AI reads the workspace used today (India time). Editors and administrators only; licence must be active.
create or replace function public.kmr_bi_ai_check(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare em text := lower(coalesce(auth.jwt() ->> 'email', '')); r text; n bigint; cid uuid;
begin
  if em = '' then raise exception 'Please sign in again.'; end if;
  select m.role into r from public.bi_members m where m.org_id = p_org and lower(m.email) = em limit 1;
  if r is null and exists (select 1 from public.bi_platform_admins a where a.user_id = auth.uid()) then r := 'admin'; end if;
  if r is null or r not in ('admin', 'editor') then raise exception 'Only editors and administrators can read drawings with AI.'; end if;
  if not console.product_ok('balloon', p_org) then raise exception 'Your company''s Balloon Inspector licence is not active.'; end if;
  select customer_id into cid from console.licences where product_code = 'balloon' and product_ref = p_org limit 1;
  select count(*) into n from console.ai_usage
   where product = 'balloon' and org_id = p_org and ok and at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata');
  return jsonb_build_object('role', r, 'customer_id', cid, 'used_today', n, 'email', em);
end $$;
revoke all on function public.kmr_bi_ai_check(uuid) from public, anon;
grant execute on function public.kmr_bi_ai_check(uuid) to authenticated;

-- Console: AI reads per company in the last 30 days
create or replace view console.ai_usage_30d with (security_invoker = true) as
select u.product, c.name as company, count(*) filter (where u.ok) as reads, count(*) filter (where not u.ok) as failed,
       sum(u.input_tokens) as input_tokens, sum(u.output_tokens) as output_tokens, max(u.at) as last_read
  from console.ai_usage u left join console.customers c on c.id = u.customer_id
 where u.at >= now() - interval '30 days'
 group by u.product, c.name;
