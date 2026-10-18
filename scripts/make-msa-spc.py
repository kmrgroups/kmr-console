#!/usr/bin/env python3
"""Generates supabase/migrations/0077_msa_spc.sql (MSA Studies + SPC Charts, two stand-alone apps).
Hand-written: msa-spc-body.sql (products, tables) and msa-spc-api.sql (calls, sample data).
Portal / Data Master / Grand Master functions are re-created from their latest definition (0076) with the two apps added."""
import re, json, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
SRC = (M / '0076_actiontrack.sql').read_text()

def block(header, source):
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    out = source[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

MSA_T = "'msa_counters','msa_studies'"; SPC_T = "'spc_counters','spc_charts','spc_points'"
GLOBAL = [("'hrms','tsk'", "'hrms','tsk','msa','spc'"), ("'hrms', 'tsk'", "'hrms', 'tsk', 'msa', 'spc'")]
SPECIFIC = {
 'console.app2_tables(': [("'tsk_push_subs'] end", "'tsk_push_subs']\n                    when 'msa'   then array[" + MSA_T + "]\n                    when 'spc'   then array[" + SPC_T + "] end")],
 'console.app2_clear(': [("delete from console.tsk_counters where customer_id = p_cid; end if;\n  end if;",
   "delete from console.tsk_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'msa' then\n"
   "    delete from console.msa_studies where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.msa_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'spc' then\n"
   "    delete from console.spc_points where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.spc_charts where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.spc_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("'Done this week', (select count(*) from console.tsk_tasks where customer_id = c and status = 'done' and done_at >= now() - interval '7 days')));\n  end if;",
   "'Done this week', (select count(*) from console.tsk_tasks where customer_id = c and status = 'done' and done_at >= now() - interval '7 days')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'msa';\n  if ref is not null then\n    out := out || jsonb_build_object('msa', jsonb_build_object(\n"
   "      'Studies', (select count(*) from console.msa_studies where customer_id = c),\n"
   "      'Not acceptable', (select count(*) from console.msa_studies where customer_id = c and decision = 'Not acceptable'),\n"
   "      'Drafts', (select count(*) from console.msa_studies where customer_id = c and status = 'draft')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'spc';\n  if ref is not null then\n    out := out || jsonb_build_object('spc', jsonb_build_object(\n"
   "      'Active charts', (select count(*) from console.spc_charts where customer_id = c and status = 'active'),\n"
   "      'With signals', (select count(*) from console.spc_charts where customer_id = c and status = 'active' and coalesce((summary ->> 'signals')::int, 0) > 0)));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'load')); end if;\n"
    "    if console.has_app(cid, 'msa') then out := out || jsonb_build_object('msa', console.msa_sample(cid, 'load')); end if;\n"
    "    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'msa') then out := out || jsonb_build_object('msa', console.msa_sample(cid, 'flush')); end if;\n"
    "    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'flush')); end if;\n"
    "    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('tsk', n); smp := smp || jsonb_build_object('tsk', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('tsk', n); smp := smp || jsonb_build_object('tsk', k);\n  end if;\n"
   "  if console.has_app(cid, 'msa') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.msa_studies where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('msa', n); smp := smp || jsonb_build_object('msa', k);\n  end if;\n"
   "  if console.has_app(cid, 'spc') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.spc_charts where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('spc', n); smp := smp || jsonb_build_object('spc', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('tsk', cid, true); out := out || jsonb_build_object('tsk', n);\n  end if;",
   "    perform console.app2_clear('tsk', cid, true); out := out || jsonb_build_object('tsk', n);\n  end if;\n"
   "  if console.has_app(cid, 'msa') then\n    select count(*) into n from console.msa_studies where customer_id = cid and not sample;\n    perform console.app2_clear('msa', cid, true); out := out || jsonb_build_object('msa', n);\n  end if;\n"
   "  if console.has_app(cid, 'spc') then\n    select count(*) into n from console.spc_charts where customer_id = cid and not sample;\n    perform console.app2_clear('spc', cid, true); out := out || jsonb_build_object('spc', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.tsk_tasks where customer_id = cid and not sample; end if;",
   "    elsif t = 'tsk' then select count(*) into n from console.tsk_tasks where customer_id = cid and not sample;\n"
   "    elsif t = 'msa' then select count(*) into n from console.msa_studies where customer_id = cid and not sample;\n"
   "    else select count(*) into n from console.spc_charts where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
def addsub(b, a, c):
    assert b.count(a) == 1, (a[:70], b.count(a))
    return b.replace(a, c)
regen = []
for h in REGEN:
    if 'create or replace function ' + h not in SRC: print('not in latest source (generic):', h); continue
    b = block('create or replace function ' + h, SRC); orig = b
    for a, c in SPECIFIC.get(h, []): b = addsub(b, a, c)
    for a, c in GLOBAL: b = b.replace(a, c)
    b = re.sub(r"^(\s*)when 'tsk'(\s+)then console\.qp_member\((.*?), 'tsk'\)$",
               lambda m: m.group(0) + "".join("\n" + m.group(1) + "when '" + a + "'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", '" + a + "')" for a in ('msa', 'spc')), b, flags=re.M)
    if b == orig: print('unchanged:', h); continue
    assert "'msa'" in b or 'msa_' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(', SRC)
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'msa'" in demo

# AIAG Gage R&R example, parts-major: d[appraiser][part][trial]
A = [[.29, -.56, 1.34, .47, -.80, .02, .59, -.31, 2.26, -1.36], [.41, -.68, 1.17, .50, -.92, -.11, .75, -.20, 1.99, -1.25], [.64, -.58, 1.27, .64, -.84, -.21, .66, -.17, 2.01, -1.31]]
B = [[.08, -.47, 1.19, .01, -.56, -.20, .47, -.63, 1.80, -1.68], [.25, -1.22, .94, 1.03, -1.20, .22, .55, .08, 2.12, -1.62], [.07, -.68, 1.34, .20, -1.28, .06, .83, -.34, 2.19, -1.50]]
C = [[.04, -1.38, .88, .14, -1.46, -.29, .02, -.46, 1.77, -1.49], [-.11, -1.13, 1.09, .20, -1.07, -.67, .01, -.56, 1.45, -1.77], [-.15, -.96, .67, .11, -1.45, -.49, .21, -.49, 1.87, -2.16]]
grr = json.dumps([[[X[t][p] for t in range(3)] for p in range(10)] for X in (A, B, C)], separators=(',', ':'))

body = (S / 'msa-spc-body.sql').read_text(); core = (S / 'msa-spc-api.sql').read_text().replace('@@GRR_D@@', grr)
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_(msa|spc)_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches the two new apps on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0077_msa_spc.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
