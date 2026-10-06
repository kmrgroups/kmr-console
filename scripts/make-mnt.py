#!/usr/bin/env python3
"""Generates supabase/migrations/0059_maintenance.sql
Hand-written parts: mnt-body.sql (product, tables) and mnt-api.sql (calls, helpers, sample data).
The portal / data-master / grand-master functions are re-created from their latest definition (the 0058 generation) with Maintenance added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
src = (M / '0058_mmd.sql').read_text()

def block(header):
    i = src.index(header)
    j = src.index(' as $$', i); k = src.index('$$;', j + 6) + 3
    out = src[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    grants = [l for l in src.split('\n') if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

MNT_T = "'mnt_counters','mnt_breakdowns','mnt_pm_plans','mnt_pm_log','mnt_events'"
GLOBAL = [
  ("'rmp','mmd'", "'rmp','mmd','mnt'"),
  ("'rmp', 'mmd'", "'rmp', 'mmd', 'mnt'"),
  ("'mmd_grns','mmd_loss')", "'mmd_grns','mmd_loss'," + MNT_T + ")"),
]
SPECIFIC = {
 'console.app2_tables(': [("'mmd_grns','mmd_loss'] end", "'mmd_grns','mmd_loss']\n                    when 'mnt'   then array[" + MNT_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.mmd_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.mmd_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'mnt' then\n"
   "    delete from console.mmd_loss where customer_id = p_cid and ref is not null and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mnt_pm_log where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mnt_pm_plans where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mnt_events where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mnt_breakdowns where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.mnt_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("'Open DCs', (select count(*) from console.mmd_dcs where customer_id = c and status in ('open', 'part'))));\n  end if;",
   "'Open DCs', (select count(*) from console.mmd_dcs where customer_id = c and status in ('open', 'part'))));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'mnt';\n  if ref is not null then\n    out := out || jsonb_build_object('mnt', jsonb_build_object(\n"
   "      'Open breakdowns', (select count(*) from console.mnt_breakdowns where customer_id = c and status in ('open', 'attended')),\n"
   "      'PM overdue', (select count(*) from console.mnt_pm_plans where customer_id = c and active and next_due < (now() at time zone 'Asia/Kolkata')::date),\n"
   "      'Breakdowns (30 days)', (select count(*) from console.mnt_breakdowns where customer_id = c and status <> 'void' and started_at >= now() - interval '30 days')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'mmd') then out := out || jsonb_build_object('mmd', console.mmd_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('mmd', n); smp := smp || jsonb_build_object('mmd', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('mmd', n); smp := smp || jsonb_build_object('mmd', k);\n  end if;\n  if console.has_app(cid, 'mnt') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.mnt_breakdowns where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('mnt', n); smp := smp || jsonb_build_object('mnt', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('mmd', cid, true); out := out || jsonb_build_object('mmd', n);\n  end if;",
   "    perform console.app2_clear('mmd', cid, true); out := out || jsonb_build_object('mmd', n);\n  end if;\n  if console.has_app(cid, 'mnt') then\n"
   "    select count(*) into n from console.mnt_breakdowns where customer_id = cid and not sample;\n    perform console.app2_clear('mnt', cid, true); out := out || jsonb_build_object('mnt', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.mmd_route_sheets where customer_id = cid and not sample; end if;",
   "    elsif t = 'mmd' then select count(*) into n from console.mmd_route_sheets where customer_id = cid and not sample;\n    else select count(*) into n from console.mnt_breakdowns where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
regen = []
for h in REGEN:
    b = block('create or replace function ' + h)
    for a, c in SPECIFIC.get(h, []):
        assert b.count(a) == 1, (h, a[:70], b.count(a))
        b = b.replace(a, c)
    for a, c in GLOBAL:
        b = b.replace(a, c)
    b = re.sub(r"^(\s*)when 'mmd'(\s+)then console\.qp_member\((.*?), 'mmd'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'mnt'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'mnt')", b, flags=re.M)
    assert 'mnt' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(')
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'mnt'" in demo

body = (S / 'mnt-body.sql').read_text()
core = (S / 'mnt-api.sql').read_text()
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_mnt_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches Maintenance on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0059_maintenance.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
