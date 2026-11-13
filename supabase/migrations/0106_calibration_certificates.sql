-- Calibration Hub 0106 — calibration certificate scans / photos: one or many files (PDF or image) attached to a calibration record, taken from a file or the phone camera; they can be viewed and deleted.
-- Needs 0098. Safe to re-run. Files are private (customers/<customer id>/cal/<gauge id>/...), visible to anyone with Calibration Hub access, added / deleted by administrators and editors.
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-cal', 'kmr-cal', false, 15728640) on conflict (id) do update set file_size_limit = 15728640;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists kmr_cal_read on storage.objects';
    execute $p$create policy kmr_cal_read on storage.objects for select to authenticated using (
      bucket_id = 'kmr-cal' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.cal_role(((storage.foldername(name))[2])::uuid) is not null)$p$;
    execute 'drop policy if exists kmr_cal_write on storage.objects';
    execute $p$create policy kmr_cal_write on storage.objects for insert to authenticated with check (
      bucket_id = 'kmr-cal' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.cal_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
    execute 'drop policy if exists kmr_cal_delete on storage.objects';
    execute $p$create policy kmr_cal_delete on storage.objects for delete to authenticated using (
      bucket_id = 'kmr-cal' and (storage.foldername(name))[1] = 'customers' and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
      and console.cal_role(((storage.foldername(name))[2])::uuid) in ('admin','editor'))$p$;
  end if;
end $$;

create table if not exists console.cal_files (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references console.customers(id) on delete cascade,
  instrument_id uuid not null references console.cal_instruments(id) on delete cascade,
  record_id uuid not null references console.cal_records(id) on delete cascade,
  path text not null, file_name text not null, mime text, size_bytes integer,
  created_by text, created_at timestamptz not null default now());
create index if not exists cal_files_inst on console.cal_files (instrument_id);
create index if not exists cal_files_rec on console.cal_files (record_id);
alter table console.cal_files enable row level security;
drop policy if exists cal_files_staff on console.cal_files;
create policy cal_files_staff on console.cal_files for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- the screen needs the customer reference for the file path
create or replace function public.kmr_cal_context(p_slug text) returns jsonb language sql stable security definer set search_path = console, public as $$
  select case when console.cal_role(c.id) is null then null else jsonb_build_object('role', console.cal_role(c.id), 'company', c.name, 'customer_id', c.id) end from console.customers c where c.slug = lower(p_slug) $$;
grant execute on function public.kmr_cal_context(text) to authenticated;

create or replace function public.kmr_cal_files(p_slug text, p_instrument uuid default null, p_record uuid default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.cal_role(cid) is null then raise exception 'You have no access to Calibration Hub.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'instrument_id', f.instrument_id, 'record_id', f.record_id, 'path', f.path, 'file_name', f.file_name, 'mime', f.mime, 'size_bytes', f.size_bytes, 'created_by', f.created_by, 'created_at', f.created_at) order by f.created_at)
                     from console.cal_files f where f.customer_id = cid and (p_instrument is null or f.instrument_id = p_instrument) and (p_record is null or f.record_id = p_record)), '[]');
end $$;
grant execute on function public.kmr_cal_files(text, uuid, uuid) to authenticated;

create or replace function public.kmr_cal_add_file(p_slug text, p jsonb) returns uuid language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); rid uuid := (p ->> 'record_id')::uuid; iid uuid; fid uuid; pth text := coalesce(p ->> 'path', '');
begin
  select instrument_id into iid from console.cal_records where id = rid and customer_id = cid;
  if iid is null then raise exception 'Unknown calibration record.'; end if;
  if pth not like 'customers/' || cid::text || '/cal/%' then raise exception 'Wrong file location.'; end if;
  insert into console.cal_files (customer_id, instrument_id, record_id, path, file_name, mime, size_bytes, created_by)
  values (cid, iid, rid, pth, left(coalesce(nullif(p ->> 'file_name', ''), 'certificate'), 200), p ->> 'mime', nullif(p ->> 'size_bytes', '')::integer, lower(coalesce(auth.jwt() ->> 'email', ''))) returning id into fid;
  return fid;
end $$;
grant execute on function public.kmr_cal_add_file(text, jsonb) to authenticated;

-- removes the entry and returns the storage path (the screen then removes the file itself)
create or replace function public.kmr_cal_delete_file(p_slug text, p_id uuid) returns text language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.cal_edit(p_slug); pth text;
begin
  delete from console.cal_files where id = p_id and customer_id = cid returning path into pth;
  if pth is null then raise exception 'Unknown file.'; end if;
  return pth;
end $$;
grant execute on function public.kmr_cal_delete_file(text, uuid) to authenticated;
