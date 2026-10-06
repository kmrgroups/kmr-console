-- =====================================================================
-- 0056 — Server-side feature lock for Sales Flow and Calibration Hub.
--   A company that did not buy a feature (console.licences.features, set by a paid invoice — see 0051) can no longer use it
--   by calling the database directly; the apps already lock the screens. NULL features = no list set = everything open.
--   Re-run this file after any later migration that redefines one of the functions below.
-- Needs 0051 and the Sales Flow / Calibration migrations. Safe to re-run.
-- =====================================================================
create or replace function console.require_feature(p_slug text, p_product text, p_key text) returns void
language plpgsql stable security definer set search_path = console, public as $$
declare feats text[]; has_row boolean;
begin
  select true, l.features into has_row, feats
    from console.licences l join console.customers c on c.id = l.customer_id
   where c.slug = lower(p_slug) and l.product_code = p_product limit 1;
  if has_row and feats is not null and not (p_key = any (feats)) then
    raise exception '% is not part of your company''s subscription. To add it, contact KMR Group of Companies - www.kmr-groups.com/contact.',
      coalesce((select name from console.app_features where key = p_key), 'This feature');
  end if;
end $$;
revoke all on function console.require_feature(text, text, text) from public, anon, authenticated;

-- put the check at the start of each function body
do $$
declare m record; def text; n int := 0;
begin
  for m in select * from (values
    ('kmr_sf_save_despatch', 'sales', 'sales.daily-despatch-abc-analysis'),
    ('kmr_sf_save_loss',     'sales', 'sales.loss-reasons-action-plans'),
    ('kmr_sf_actions',       'sales', 'sales.loss-reasons-action-plans'),
    ('kmr_sf_save_action',   'sales', 'sales.loss-reasons-action-plans'),
    ('kmr_sf_delete_action', 'sales', 'sales.loss-reasons-action-plans'),
    ('kmr_cal_save_msa',     'calib', 'calib.gauge-r-r-msa'),
    ('kmr_cal_delete_msa',   'calib', 'calib.gauge-r-r-msa'),
    ('kmr_cal_close_oot',    'calib', 'calib.out-of-tolerance-cases'),
    ('kmr_cal_delete_oot',   'calib', 'calib.out-of-tolerance-cases'),
    ('kmr_cal_save_record',  'calib', 'calib.due-alerts-certificates'),
    ('kmr_cal_update_record','calib', 'calib.due-alerts-certificates'),
    ('kmr_cal_delete_record','calib', 'calib.due-alerts-certificates')
  ) v(fn, product, key) loop
    for def in select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                where s.nspname = 'public' and p.proname = m.fn and p.prokind = 'f' loop
      if def like '%require_feature%' or def !~* E'language plpgsql' then continue; end if;
      def := regexp_replace(def, E'(\\mbegin\\M)', E'\\1\n  perform console.require_feature(p_slug, ''' || m.product || ''', ''' || m.key || ''');', 'i');   -- first begin only
      execute def; n := n + 1;
    end loop;
  end loop;
  raise notice 'feature check added to % functions', n;
end $$;
