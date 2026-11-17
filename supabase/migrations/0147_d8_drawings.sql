-- 8D 0147 — customer drawings: private files (PDF or image) kept per workspace, listed by customer group and part, opened on screen, renamed, deleted or added by editors.
-- Files are private (customers/<customer id>/draw/...). Anyone with 8D access can view; administrators and editors add, change and delete.
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-draw', 'kmr-draw', false, 52428800) on conflict (id) do update set file_size_limit = 52428800;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_draw_read on storage.objects';
    execute $p$create policy kmr_draw_read on storage.objects for select to authenticated using (
      bucket_id = 'kmr-draw' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.qp_role(((storage.foldername(name))[2])::uuid, 'd8') is not null)$p$;
    execute 'drop policy if exists kmr_draw_write on storage.objects';
    execute $p$create policy kmr_draw_write on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-draw' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.qp_role(((storage.foldername(name))[2])::uuid, 'd8') in ('admin','editor'))$p$;
    execute 'drop policy if exists kmr_draw_delete on storage.objects';
    execute $p$create policy kmr_draw_delete on storage.objects for delete to authenticated using (
      bucket_id = 'kmr-draw' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.qp_role(((storage.foldername(name))[2])::uuid, 'd8') in ('admin','editor'))$p$;
  end if;
end $$;

create table if not exists console.d8_drawings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  grp text not null default '', part_no text, title text not null, path text not null, file_name text not null, mime text, size_bytes bigint,
  created_by text, created_at timestamptz not null default now());
create index if not exists d8_drawings_c on console.d8_drawings (customer_id, grp);
alter table console.d8_drawings enable row level security;
drop policy if exists d8_drawings_staff on console.d8_drawings;
create policy d8_drawings_staff on console.d8_drawings for all to authenticated using (console.is_staff()) with check (console.is_staff());

create or replace function public.kmr_d8_draw_list(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.qp_role(cid, 'd8') is null then raise exception 'You have no access to 8D.'; end if;
  return jsonb_build_object('customer_id', cid, 'items', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'grp', d.grp, 'part_no', d.part_no, 'title', d.title, 'path', d.path, 'file_name', d.file_name, 'mime', d.mime, 'size_bytes', d.size_bytes, 'created_at', d.created_at) order by d.grp, d.title) from console.d8_drawings d where d.customer_id = cid), '[]'));
end $$;
grant execute on function public.kmr_d8_draw_list(text) to authenticated;

create or replace function public.kmr_d8_draw_add(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); fid uuid; pth text := coalesce(p ->> 'path', '');
begin
  if pth not like 'customers/' || cid::text || '/draw/%' then raise exception 'Wrong file location.'; end if;
  insert into console.d8_drawings (customer_id, grp, part_no, title, path, file_name, mime, size_bytes, created_by)
  values (cid, left(coalesce(p ->> 'grp', ''), 120), left(nullif(p ->> 'part_no', ''), 80), left(coalesce(nullif(p ->> 'title', ''), 'Drawing'), 200), pth, left(coalesce(nullif(p ->> 'file_name', ''), 'drawing'), 200), p ->> 'mime', nullif(p ->> 'size_bytes', '')::bigint, lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into fid;
  return fid;
end $$;
grant execute on function public.kmr_d8_draw_add(text, jsonb) to authenticated;

create or replace function public.kmr_d8_draw_save(p_slug text, p_id uuid, p jsonb) returns void language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8');
begin
  update console.d8_drawings set grp = left(coalesce(p ->> 'grp', grp), 120), part_no = left(nullif(p ->> 'part_no', ''), 80), title = left(coalesce(nullif(p ->> 'title', ''), title), 200) where id = p_id and customer_id = cid;
  if not found then raise exception 'Unknown drawing.'; end if;
end $$;
grant execute on function public.kmr_d8_draw_save(text, uuid, jsonb) to authenticated;

create or replace function public.kmr_d8_draw_delete(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'd8'); pth text;
begin
  delete from console.d8_drawings where id = p_id and customer_id = cid returning path into pth;
  if pth is null then raise exception 'Unknown drawing.'; end if;
  return pth;
end $$;
grant execute on function public.kmr_d8_draw_delete(text, uuid) to authenticated;
