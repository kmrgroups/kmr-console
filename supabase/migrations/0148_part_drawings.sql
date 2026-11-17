-- Shared customer drawings, kept against the part number (Operations Master → Parts).
-- Replaces the 8D-only drawing store (0147, never used). Files live in private bucket kmr-draw.
-- NOTE: applied to production through the Supabase tool; this file records it. Function bodies: see database.
drop function if exists public.kmr_d8_draw_list(text,uuid);
drop table if exists console.d8_drawings cascade;
create table if not exists console.part_drawings (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null, part_no text not null, part_key text not null,
  rev text, title text, kind text default 'Customer drawing', path text not null, file_name text, mime text, size_bytes bigint,
  created_by text, created_at timestamptz default now());
create index if not exists part_drawings_k on console.part_drawings (customer_id, part_key);
alter table console.part_drawings enable row level security;
create policy part_drawings_staff on console.part_drawings for all using (console.is_staff()) with check (console.is_staff());
insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-draw','kmr-draw',false,52428800) on conflict (id) do nothing;
-- storage policies kmr_draw_read / kmr_draw_write / kmr_draw_delete: customers/<customer_id>/draw/*, read = any product role, write/delete = ops admin/editor.
-- RPCs: kmr_part_draw_list(p_slug,p_part), kmr_part_draw_counts(p_slug), kmr_part_draw_add(p_slug,p), kmr_part_draw_save(p_slug,p_id,p), kmr_part_draw_delete(p_slug,p_id)
-- helpers: console.draw_role(cid), console.part_key(text)
