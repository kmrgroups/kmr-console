#!/usr/bin/env python3
"""Generates supabase/migrations/0069_cad_draft.sql
Hand-written parts: cad-body.sql (product, tables) and cad-api.sql (calls, helpers, sample data); cad-sample.json (sample drawings).
The portal / data-master / grand-master functions are re-created from their latest definition (the 0066 generation) with KMR CAD Draft added."""
import re, json, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
src = (M / '0066_minutes_of_meetings.sql').read_text()

def block(header):
    i = src.index(header)
    j = src.index(' as $$', i); k = src.index('$$;', j + 6) + 3
    out = src[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = src[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

CAD_T = "'cad_counters','cad_drawings'"
GLOBAL = [
  ("'mnt','mom'", "'mnt','mom','cad'"),
  ("'mnt', 'mom'", "'mnt', 'mom', 'cad'"),
  ("'mom_segments')", "'mom_segments'," + CAD_T + ")"),
]
SPECIFIC = {
 'console.app2_tables(': [("when 'mom'   then array['mom_counters','mom_meetings','mom_points','mom_segments'] end",
   "when 'mom'   then array['mom_counters','mom_meetings','mom_points','mom_segments']\n                    when 'cad'   then array[" + CAD_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.mom_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.mom_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'cad' then\n"
   "    delete from console.cad_drawings where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.cad_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("and p.when_on < (now() at time zone 'Asia/Kolkata')::date)));\n  end if;",
   "and p.when_on < (now() at time zone 'Asia/Kolkata')::date)));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'cad';\n  if ref is not null then\n    out := out || jsonb_build_object('cad', jsonb_build_object(\n"
   "      'Drawings', (select count(distinct number) from console.cad_drawings where customer_id = c and status <> 'obsolete'),\n"
   "      'Released', (select count(*) from console.cad_drawings where customer_id = c and status = 'released'),\n"
   "      'In review', (select count(*) from console.cad_drawings where customer_id = c and status = 'review')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('mom', n); smp := smp || jsonb_build_object('mom', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('mom', n); smp := smp || jsonb_build_object('mom', k);\n  end if;\n  if console.has_app(cid, 'cad') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.cad_drawings where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('cad', n); smp := smp || jsonb_build_object('cad', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('mom', cid, true); out := out || jsonb_build_object('mom', n);\n  end if;",
   "    perform console.app2_clear('mom', cid, true); out := out || jsonb_build_object('mom', n);\n  end if;\n  if console.has_app(cid, 'cad') then\n"
   "    select count(*) into n from console.cad_drawings where customer_id = cid and not sample;\n    perform console.app2_clear('cad', cid, true); out := out || jsonb_build_object('cad', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.mom_meetings where customer_id = cid and not sample; end if;",
   "    elsif t = 'mom' then select count(*) into n from console.mom_meetings where customer_id = cid and not sample;\n    else select count(*) into n from console.cad_drawings where customer_id = cid and not sample; end if;")],
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
    b = re.sub(r"^(\s*)when 'mom'(\s+)then console\.qp_member\((.*?), 'mom'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'cad'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'cad')", b, flags=re.M)
    assert "'cad'" in b or 'cad_' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(')
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'cad'" in demo

sample = json.loads((S / 'cad-sample.json').read_text())
sj = json.dumps(sample, separators=(',', ':'), ensure_ascii=False)
assert '$json$' not in sj
body = (S / 'cad-body.sql').read_text()
core = (S / 'cad-api.sql').read_text().replace('--@@SAMPLE@@', sj)
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_cad_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches KMR CAD Draft on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0069_cad_draft.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
