-- WhatsApp Cloud API credentials kept server-side (Vercel env WA_TOKEN / WA_PHONE_ID still win when set). Applied live as "wa_creds".
create table if not exists console.wa_creds (
  id int primary key default 1 check (id = 1),
  token text, phone_id text, template text, waba_id text, updated_at timestamptz default now()
);
alter table console.wa_creds enable row level security;
revoke all on console.wa_creds from anon, authenticated;
create or replace function public.kmr_wa_creds() returns jsonb language sql security definer set search_path = console, public as $$
  select coalesce((select jsonb_build_object('token', token, 'phone_id', phone_id, 'template', template, 'waba_id', waba_id) from console.wa_creds where id = 1), '{}'::jsonb)
$$;
revoke all on function public.kmr_wa_creds() from public, anon, authenticated;
grant execute on function public.kmr_wa_creds() to service_role;
