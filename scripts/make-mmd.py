#!/usr/bin/env python3
"""Generates supabase/migrations/0058_mmd.sql
Hand-written parts: mmd-body.sql (product, tables), mmd-core.sql (movement logic), mmd-api.sql (calls), mmd-sample.sql (sample data).
The portal / data-master / grand-master functions are re-created from their latest definition (the 0057 generation) with MMD added;
the Capacity Planner's two master reads are re-created without supplier processes (a supplier operation has no machine to load)."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
src57 = (M / '0057_raw_material_planning.sql').read_text()
src53 = (M / '0053_part_abc_class.sql').read_text()
src55 = (M / '0055_capacity_pull.sql').read_text()

def block(src, header):
    i = src.index(header)
    j = src.index(' as $$', i); k = src.index('$$;', j + 6) + 3
    out = src[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    grants = [l for l in src.split('\n') if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

MMD_T = "'mmd_counters','mmd_route_sheets','mmd_tags','mmd_dcs','mmd_entries','mmd_defects','mmd_grns','mmd_loss'"
GLOBAL = [
  ("'ppap','rmp'", "'ppap','rmp','mmd'"),
  ("'ppap', 'rmp'", "'ppap', 'rmp', 'mmd'"),
  ("'ppap_submissions','rmp_bom','rmp_stock','rmp_demand','rmp_orders'", "'ppap_submissions','rmp_bom','rmp_stock','rmp_demand','rmp_orders'," + MMD_T),
]
SPECIFIC = {
 'console.app2_tables(': [("                    when 'rmp'   then array['rmp_bom','rmp_stock','rmp_demand','rmp_orders'] end",
                           "                    when 'rmp'   then array['rmp_bom','rmp_stock','rmp_demand','rmp_orders']\n                    when 'mmd'   then array[" + MMD_T + "] end")],
 'console.app2_clear(': [("    delete from console.rmp_stock where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n  end if;",
   "    delete from console.rmp_stock where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n"
   "  elsif p_app = 'mmd' then\n"
   "    delete from console.mmd_loss where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mmd_route_sheets where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;   -- tags, entries, defects, DCs and GRNs go with their route sheet\n"
   "    if not p_real_only then delete from console.mmd_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("  return out;\nend $$;",
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'mmd';\n  if ref is not null then\n    out := out || jsonb_build_object('mmd', jsonb_build_object(\n"
   "      'Open route sheets', (select count(*) from console.mmd_route_sheets where customer_id = c and status = 'open'),\n"
   "      'Pieces in process', (select coalesce(sum(bal), 0) from console.mmd_tags where customer_id = c and status = 'open' and loc in ('op', 'rework')),\n"
   "      'Open DCs', (select count(*) from console.mmd_dcs where customer_id = c and status in ('open', 'part'))));\n  end if;\n  return out;\nend $$;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('rmp', n); smp := smp || jsonb_build_object('rmp', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('rmp', n); smp := smp || jsonb_build_object('rmp', k);\n  end if;\n  if console.has_app(cid, 'mmd') then\n    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.mmd_route_sheets where customer_id = cid;\n    real_ := real_ || jsonb_build_object('mmd', n); smp := smp || jsonb_build_object('mmd', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('rmp', cid, true); out := out || jsonb_build_object('rmp', n);\n  end if;",
   "    perform console.app2_clear('rmp', cid, true); out := out || jsonb_build_object('rmp', n);\n  end if;\n  if console.has_app(cid, 'mmd') then\n    select count(*) into n from console.mmd_route_sheets where customer_id = cid and not sample;\n    perform console.app2_clear('mmd', cid, true); out := out || jsonb_build_object('mmd', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.rmp_stock where customer_id = cid and not sample; end if;",
   "    elsif t = 'rmp' then select count(*) into n from console.rmp_stock where customer_id = cid and not sample;\n    else select count(*) into n from console.mmd_route_sheets where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
regen = []
for h in REGEN:
    b = block(src57, 'create or replace function ' + h)
    for a, c in SPECIFIC.get(h, []):
        assert b.count(a) == 1, (h, a[:70], b.count(a))
        b = b.replace(a, c)
    for a, c in GLOBAL:
        b = b.replace(a, c)
    # the portal's per-app membership lines: one more app next to the Raw Material Planning one
    b = re.sub(r"^(\s*)when 'rmp'(\s+)then console\.qp_member\((.*?), 'rmp'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'mmd'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'mmd')", b, flags=re.M)
    assert 'mmd' in b, h
    regen.append(b)
demo = block(src57, 'create or replace function console.demo_refresh(')
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'mmd'" in demo
# the Capacity Planner never loads a supplier operation onto a machine
cap1 = block(src53, 'create or replace function public.kmr_capacity_masters(')
cap2 = block(src55, 'create or replace function public.kmr_capacity_pull(')
for nm, b in (('cap1', cap1), ('cap2', cap2)):
    assert b.count("r.kind = 'cycle_times' and r.active") == 1, nm
cap1 = cap1.replace("r.kind = 'cycle_times' and r.active", "r.kind = 'cycle_times' and r.active and coalesce(r.data ->> 'op_type', '') not ilike 'supplier%'")
cap2 = cap2.replace("r.kind = 'cycle_times' and r.active", "r.kind = 'cycle_times' and r.active and coalesce(r.data ->> 'op_type', '') not ilike 'supplier%'")

body = (S / 'mmd-body.sql').read_text()
core = '\n'.join((S / f).read_text() for f in ('mmd-core.sql', 'mmd-api.sql', 'mmd-sample.sql'))
tail = """
-- the app's functions join the same execute grants as the other apps
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_mmd_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master, Grand Master and the Capacity Planner masters: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches MMD on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n\n' + cap1 + '\n\n' + cap2 + '\n' + tail)
(M / '0058_mmd.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
