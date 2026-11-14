-- 0117 — Delivery Challan & GRN: items and parties for the challan / purchase order screens come from the Operations Master
-- (gauges, tools, parts, raw materials, consumables; suppliers and customers). Needs 0113. Safe to re-run.
create or replace function public.kmr_dcg_items(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'dcg');
begin
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'code', r.code, 'name', r.name,
              'uom', coalesce(nullif(r.data ->> 'uom', ''), nullif(r.data ->> 'unit', ''), 'Nos'), 'hsn', coalesce(r.data ->> 'hsn', r.data ->> 'hsn_code', ''),
              'info', concat_ws(' · ', nullif(r.data ->> 'make', ''), nullif(r.data ->> 'range', ''), nullif(r.data ->> 'material', ''), nullif(r.data ->> 'grade', ''), nullif(r.data ->> 'type', ''))) order by r.kind, r.code)
            from console.ops_records r where r.customer_id = cid and r.active and r.kind in ('gauges', 'tools', 'parts', 'raw_materials', 'consumables')), '[]'::jsonb),
    'parties', coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'code', r.code, 'name', r.name, 'gstin', coalesce(r.data ->> 'gstin', ''),
              'addr', concat_ws(', ', nullif(r.data ->> 'address', ''), nullif(r.data ->> 'city', ''))) order by r.name)
            from console.ops_records r where r.customer_id = cid and r.active and r.kind in ('suppliers', 'customers')), '[]'::jsonb));
end $$;
revoke all on function public.kmr_dcg_items(text) from public, anon;
grant execute on function public.kmr_dcg_items(text) to authenticated;
