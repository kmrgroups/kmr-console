#!/usr/bin/env python3
"""Generates supabase/migrations/0066_minutes_of_meetings.sql
Hand-written parts: mom-body.sql (product, tables) and mom-api.sql (calls, helpers, sample data).
The portal / data-master / grand-master functions are re-created from their latest definition (the 0059 generation) with Minutes Of Meetings added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
src = (M / '0059_maintenance.sql').read_text()

def block(header):
    i = src.index(header)
    j = src.index(' as $$', i); k = src.index('$$;', j + 6) + 3
    out = src[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    grants = [l for l in src.split('\n') if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

MOM_T = "'mom_counters','mom_meetings','mom_points','mom_segments'"
GLOBAL = [
  ("'mmd','mnt'", "'mmd','mnt','mom'"),
  ("'mmd', 'mnt'", "'mmd', 'mnt', 'mom'"),
  ("'mnt_events')", "'mnt_events'," + MOM_T + ")"),
]
SPECIFIC = {
 'console.app2_tables(': [("'mnt_events'] end", "'mnt_events']\n                    when 'mom'   then array[" + MOM_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.mnt_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.mnt_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'mom' then\n"
   "    delete from console.mom_segments where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mom_points where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.mom_meetings where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.mom_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("'Breakdowns (30 days)', (select count(*) from console.mnt_breakdowns where customer_id = c and status <> 'void' and started_at >= now() - interval '30 days')));\n  end if;",
   "'Breakdowns (30 days)', (select count(*) from console.mnt_breakdowns where customer_id = c and status <> 'void' and started_at >= now() - interval '30 days')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'mom';\n  if ref is not null then\n    out := out || jsonb_build_object('mom', jsonb_build_object(\n"
   "      'Meetings (30 days)', (select count(*) from console.mom_meetings where customer_id = c and status <> 'void' and meeting_date >= (now() at time zone 'Asia/Kolkata')::date - 30),\n"
   "      'Open actions', (select count(*) from console.mom_points p join console.mom_meetings m on m.id = p.meeting_id where p.customer_id = c and m.status <> 'void' and p.status in ('Open', 'In progress') and p.ptype in ('Action', 'Decision', 'Risk / concern', 'Query')),\n"
   "      'Overdue actions', (select count(*) from console.mom_points p join console.mom_meetings m on m.id = p.meeting_id where p.customer_id = c and m.status <> 'void' and p.status in ('Open', 'In progress') and p.when_on < (now() at time zone 'Asia/Kolkata')::date)));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'mom') then out := out || jsonb_build_object('mom', console.mom_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'mnt') then out := out || jsonb_build_object('mnt', console.mnt_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('mnt', n); smp := smp || jsonb_build_object('mnt', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('mnt', n); smp := smp || jsonb_build_object('mnt', k);\n  end if;\n  if console.has_app(cid, 'mom') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.mom_meetings where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('mom', n); smp := smp || jsonb_build_object('mom', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('mnt', cid, true); out := out || jsonb_build_object('mnt', n);\n  end if;",
   "    perform console.app2_clear('mnt', cid, true); out := out || jsonb_build_object('mnt', n);\n  end if;\n  if console.has_app(cid, 'mom') then\n"
   "    select count(*) into n from console.mom_meetings where customer_id = cid and not sample;\n    perform console.app2_clear('mom', cid, true); out := out || jsonb_build_object('mom', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.mnt_breakdowns where customer_id = cid and not sample; end if;",
   "    elsif t = 'mnt' then select count(*) into n from console.mnt_breakdowns where customer_id = cid and not sample;\n    else select count(*) into n from console.mom_meetings where customer_id = cid and not sample; end if;")],
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
    b = re.sub(r"^(\s*)when 'mnt'(\s+)then console\.qp_member\((.*?), 'mnt'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'mom'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'mom')", b, flags=re.M)
    assert "'mom'" in b or 'mom_' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(')
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'mom'" in demo

body = (S / 'mom-body.sql').read_text()
core = (S / 'mom-api.sql').read_text()
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_mom_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches Minutes Of Meetings on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0066_minutes_of_meetings.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
