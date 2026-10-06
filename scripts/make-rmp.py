#!/usr/bin/env python3
"""Generates supabase/migrations/0057_raw_material_planning.sql
The Raw Material Planning tables, functions and sample data are written below; the portal / data-master / grand-master functions are
re-created from their latest definition (0048, 0049) with the new app added, so nothing is hand-copied."""
import re, pathlib
M = pathlib.Path(__file__).resolve().parent.parent / 'supabase' / 'migrations'
src48 = (M / '0048_apqp_ppap.sql').read_text()
src49 = (M / '0049_demo_workspace.sql').read_text()

def block(src, header):
    i = src.index(header)
    j = src.index(' as $$', i); k = src.index('$$;', j + 6) + 3
    out = src[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    grants = [l for l in src.split('\n') if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

RMP_TABLES = "'rmp_bom','rmp_stock','rmp_demand','rmp_orders'"
GLOBAL = [
  ("('sales','calib','apqp','ppap')", "('sales','calib','apqp','ppap','rmp')"),
  ("array['sales','calib','apqp','ppap']", "array['sales','calib','apqp','ppap','rmp']"),
  ("in ('apqp', 'ppap')", "in ('apqp', 'ppap', 'rmp')"),
  ("'sf_lines','sf_actions','cal_instruments','apqp_projects','ppap_submissions'", "'sf_lines','sf_actions','cal_instruments','apqp_projects','ppap_submissions'," + RMP_TABLES),
]
SPECIFIC = {
 'public.kmr_portal(': [("             when 'ppap'     then console.qp_member(l.customer_id, em, 'ppap')",
                         "             when 'ppap'     then console.qp_member(l.customer_id, em, 'ppap')\n             when 'rmp'      then console.qp_member(l.customer_id, em, 'rmp')")],
 'public.kmr_portal_join(': [("    when 'ppap'     then console.qp_member(cid, em, 'ppap')",
                         "    when 'ppap'     then console.qp_member(cid, em, 'ppap')\n    when 'rmp'      then console.qp_member(cid, em, 'rmp')")],
 'console.app2_tables(': [("when 'ppap'  then array['ppap_submissions'] end",
                         "when 'ppap'  then array['ppap_submissions']\n                    when 'rmp'   then array['rmp_bom','rmp_stock','rmp_demand','rmp_orders'] end")],
 'console.app2_clear(': [("    delete from console.ppap_submissions where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  end if;",
                         "    delete from console.ppap_submissions where customer_id = p_cid and (not p_real_only or not sample); get diagnostics n = row_count;\n  elsif p_app = 'rmp' then\n    delete from console.rmp_orders where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n    delete from console.rmp_demand where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n    delete from console.rmp_bom where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n    delete from console.rmp_stock where customer_id = p_cid and (not p_real_only or not sample); get diagnostics k = row_count; n := n + k;\n  end if;")],
 'public.kmr_portal_stats(': [("  return out;\nend $$;",
                         "  select product_ref into ref from console.licences where customer_id = c and product_code = 'rmp';\n  if ref is not null then\n    out := out || jsonb_build_object('rmp', jsonb_build_object(\n      'Materials', (select count(*) from console.rmp_stock where customer_id = c),\n      'Orders placed', (select count(*) from console.rmp_orders where customer_id = c and status = 'ordered'),\n      'Planned orders', (select count(*) from console.rmp_orders where customer_id = c and status = 'planned')));\n  end if;\n  return out;\nend $$;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'rmp') then out := out || jsonb_build_object('rmp', console.rmp_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'ppap') then out := out || jsonb_build_object('ppap', console.ppap_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('ppap', n); smp := smp || jsonb_build_object('ppap', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('ppap', n); smp := smp || jsonb_build_object('ppap', k);\n  end if;\n  if console.has_app(cid, 'rmp') then\n    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.rmp_stock where customer_id = cid;\n    real_ := real_ || jsonb_build_object('rmp', n); smp := smp || jsonb_build_object('rmp', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('ppap', cid, true); out := out || jsonb_build_object('ppap', n);\n  end if;",
   "    perform console.app2_clear('ppap', cid, true); out := out || jsonb_build_object('ppap', n);\n  end if;\n  if console.has_app(cid, 'rmp') then\n    select count(*) into n from console.rmp_stock where customer_id = cid and not sample;\n    perform console.app2_clear('rmp', cid, true); out := out || jsonb_build_object('rmp', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.ppap_submissions where customer_id = cid and not sample; end if;",
   "    elsif t = 'ppap' then select count(*) into n from console.ppap_submissions where customer_id = cid and not sample;\n    else select count(*) into n from console.rmp_stock where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
regen = []
for h in REGEN:
    b = block(src48, 'create or replace function ' + h)
    for a, c in SPECIFIC.get(h, []):
        assert b.count(a) == 1, (h, a[:60], b.count(a))
        b = b.replace(a, c)
    for a, c in GLOBAL:
        b = b.replace(a, c)
    assert "'rmp'" in b or 'rmp_' in b or h in ('public.kmr_data_overview(',), h
    regen.append(b)
# the demo workspace switches the company-level apps on
demo = block(src49, 'create or replace function console.demo_refresh(')
assert demo.count("array['sales', 'calib', 'apqp', 'ppap']") == 1
demo = demo.replace("array['sales', 'calib', 'apqp', 'ppap']", "array['sales', 'calib', 'apqp', 'ppap', 'rmp']")

body = (pathlib.Path(__file__).resolve().parent / 'rmp-body.sql').read_text()
out = body.replace('--@@REGENERATED@@', '\n\n'.join(regen) + '\n\n-- the demo workspace switches Raw Material Planning on too\ndrop function if exists console.demo_refresh(uuid);\n' + demo)
(M / '0057_raw_material_planning.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
