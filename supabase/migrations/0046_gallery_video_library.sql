-- =====================================================================
-- 0046 — the Gallery is the video library.
-- Every promo video saved on a KMR App listing, a business vertical, or a shop item / programme / service is
-- added to the Gallery (Website CMS › About us › Gallery) with its thumbnail and a caption saying where it is
-- used, and any Gallery video can be picked for those cards. Needs 0045. Safe to re-run.
-- =====================================================================
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'app_listings' and column_name = 'video_url')
  then raise exception 'Run 0045_media_costing_quotes.sql first.'; end if;
end $$;

do $outer$ begin
  if to_regclass('public.gallery_items') is null then
    raise notice '0046 skipped: the website Gallery table (gallery_items) is not in this project yet. Run the website SQL, then run this file again.';
    return;
  end if;
  execute $body$
-- the video columns of the cards (normally added by 0045; added here too so the order the files were run in does not matter)
do $$ declare t text; begin foreach t in array array['verticals', 'products'] loop
  if to_regclass('public.' || t) is not null then
    execute format('alter table public.%I add column if not exists video_url text', t);
    execute format('alter table public.%I add column if not exists video_poster text', t);
  end if;
end loop; end $$;
alter table public.gallery_items add column if not exists used_for text;           -- e.g. "KMR Apps · Sales Flow"
create index if not exists gallery_items_media on public.gallery_items (media_url);

-- add (or refresh) one Gallery video; the same file is never added twice
create or replace function public.kmr_gallery_keep_video(p_url text, p_poster text, p_title text, p_used_for text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(p_url), '') = '' then return; end if;
  update public.gallery_items
     set thumbnail_url = coalesce(nullif(thumbnail_url, ''), nullif(p_poster, '')),
         used_for = case when coalesce(used_for, '') = '' then p_used_for
                         when position(p_used_for in used_for) > 0 then used_for
                         else left(used_for || ' · ' || p_used_for, 300) end
   where media_url = p_url;
  if not found then
    insert into public.gallery_items (title, media_type, media_url, thumbnail_url, sort_order, is_active, used_for)
    values (left(coalesce(nullif(p_title, ''), 'Promo video'), 200), 'video', p_url, nullif(p_poster, ''),
            coalesce((select max(sort_order) from public.gallery_items), 0) + 10, true, p_used_for);
  end if;
end $$;
revoke all on function public.kmr_gallery_keep_video(text, text, text, text) from public, anon, authenticated;

create or replace function public.kmr_gallery_from_card() returns trigger language plpgsql security definer set search_path = public as $$
declare title text; used text;
begin
  if coalesce(new.video_url, '') = '' then return new; end if;
  if tg_op = 'UPDATE' and new.video_url is not distinct from old.video_url and new.video_poster is not distinct from old.video_poster then return new; end if;
  if tg_table_name = 'app_listings' then title := new.name; used := 'KMR Apps · ' || new.name;
  elsif tg_table_name = 'verticals' then title := (to_jsonb(new) ->> 'title'); used := 'Business · ' || coalesce(to_jsonb(new) ->> 'title', '');
  else title := (to_jsonb(new) ->> 'name');
       used := initcap(replace(coalesce(to_jsonb(new) ->> 'business', 'shop'), '_', ' ')) || ' · ' || coalesce(to_jsonb(new) ->> 'name', '');
  end if;
  perform public.kmr_gallery_keep_video(new.video_url, new.video_poster, title, used);
  return new;
end $$;

do $$ declare t text; begin
  foreach t in array array['app_listings', 'verticals', 'products'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop trigger if exists %I on public.%I', t || '_gallery', t);
    execute format('create trigger %I after insert or update of video_url, video_poster on public.%I for each row execute function public.kmr_gallery_from_card()', t || '_gallery', t);
  end loop;
end $$;

-- videos already saved before this migration go into the Gallery once
do $$ declare r record; begin
  for r in select video_url, video_poster, name as title, 'KMR Apps · ' || name as used from public.app_listings where coalesce(video_url, '') <> '' loop
    perform public.kmr_gallery_keep_video(r.video_url, r.video_poster, r.title, r.used); end loop;
  if to_regclass('public.verticals') is not null then
    for r in select video_url, video_poster, title, 'Business · ' || title as used from public.verticals where coalesce(video_url, '') <> '' loop
      perform public.kmr_gallery_keep_video(r.video_url, r.video_poster, r.title, r.used); end loop;
  end if;
  if to_regclass('public.products') is not null then
    for r in select video_url, video_poster, name as title, initcap(replace(coalesce(business, 'shop'), '_', ' ')) || ' · ' || name as used from public.products where coalesce(video_url, '') <> '' loop
      perform public.kmr_gallery_keep_video(r.video_url, r.video_poster, r.title, r.used); end loop;
  end if;
end $$;

  $body$;
end $outer$;
