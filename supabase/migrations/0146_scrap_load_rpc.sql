-- Applied via the Supabase connector 2026-11-17. Read access for the 8D app's Scrap register tab (same role check as the 8D app).
create or replace function public.kmr_scrap_load(p_slug text) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'd8');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('d', s.scrap_date, 'c', s.customer_name, 'p', s.part_label, 'pn', s.part_cell, 'sec', s.section, 'df', s.defect, 'q', s.qty) order by s.scrap_date, s.id)
    from console.scrap_daily s where s.customer_id = cid), '[]'::jsonb);
end $$;
grant execute on function public.kmr_scrap_load(text) to authenticated;
