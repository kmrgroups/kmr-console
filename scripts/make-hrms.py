#!/usr/bin/env python3
"""Generates supabase/migrations/0072_hrm_suite.sql
Hand-written parts: hrms-body.sql (product, tables, move from the earlier HRM) and hrms-api.sql (calls, helpers, sample data).
The portal / data-master / grand-master functions are re-created from their latest definition (the 0069 generation) with HRM & Payroll added;
the Capacity Planner's masters function is re-created from 0058 so it reads working days from the new holiday calendar."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
src = (M / '0069_cad_draft.sql').read_text()

def block(header, source=None):
    source = source or src
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    out = source[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

HRMS_T = "'hrms_counters','hrms_settings','hrms_shifts','hrms_holidays','hrms_leave_types','hrms_devices','hrms_employees','hrms_punches','hrms_attendance','hrms_leaves','hrms_payroll_runs','hrms_payslips'"
GLOBAL = [
  ("'mom','cad'", "'mom','cad','hrms'"),
  ("'mom', 'cad'", "'mom', 'cad', 'hrms'"),
]
SPECIFIC = {
 'console.app2_tables(': [("when 'cad'   then array['cad_counters','cad_drawings'] end",
   "when 'cad'   then array['cad_counters','cad_drawings']\n                    when 'hrms'  then array[" + HRMS_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.cad_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.cad_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'hrms' then\n"
   "    delete from console.hrms_payslips where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_payroll_runs where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_leaves where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_attendance where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_punches where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_employees where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_devices where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_leave_types where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_holidays where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.hrms_shifts where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.hrms_settings where customer_id = p_cid; delete from console.hrms_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("      'In review', (select count(*) from console.cad_drawings where customer_id = c and status = 'review')));\n  end if;",
   "      'In review', (select count(*) from console.cad_drawings where customer_id = c and status = 'review')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'hrms';\n  if ref is not null then\n    out := out || jsonb_build_object('hrms', jsonb_build_object(\n"
   "      'Employees', (select count(*) from console.hrms_employees where customer_id = c and status = 'active'),\n"
   "      'Punched in today', (select count(distinct coalesce(employee_id::text, bio_id)) from console.hrms_punches where customer_id = c and punched_at >= ((now() at time zone console.hrms_tz(c))::date::timestamp at time zone console.hrms_tz(c))),\n"
   "      'Leave to approve', (select count(*) from console.hrms_leaves where customer_id = c and status = 'Pending')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'cad') then out := out || jsonb_build_object('cad', console.cad_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('cad', n); smp := smp || jsonb_build_object('cad', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('cad', n); smp := smp || jsonb_build_object('cad', k);\n  end if;\n  if console.has_app(cid, 'hrms') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.hrms_employees where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('hrms', n); smp := smp || jsonb_build_object('hrms', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('cad', cid, true); out := out || jsonb_build_object('cad', n);\n  end if;",
   "    perform console.app2_clear('cad', cid, true); out := out || jsonb_build_object('cad', n);\n  end if;\n  if console.has_app(cid, 'hrms') then\n"
   "    select count(*) into n from console.hrms_employees where customer_id = cid and not sample;\n    perform console.app2_clear('hrms', cid, true); out := out || jsonb_build_object('hrms', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.cad_drawings where customer_id = cid and not sample; end if;",
   "    elsif t = 'cad' then select count(*) into n from console.cad_drawings where customer_id = cid and not sample;\n    else select count(*) into n from console.hrms_employees where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
regen = []
for h in REGEN:
    b = block('create or replace function ' + h); orig = b
    for a, c in SPECIFIC.get(h, []):
        assert b.count(a) == 1, (h, a[:70], b.count(a))
        b = b.replace(a, c)
    for a, c in GLOBAL:
        b = b.replace(a, c)
    b = re.sub(r"^(\s*)when 'cad'(\s+)then console\.qp_member\((.*?), 'cad'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'hrms'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'hrms')", b, flags=re.M)
    if b == orig:   # nothing to add (the function is generic): not re-created
        print('unchanged:', h); continue
    assert "'hrms'" in b or 'hrms_' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(')
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'hrms'" in demo

# Capacity Planner masters: working days from the new holiday calendar
cap = block('create or replace function public.kmr_capacity_masters(', (M / '0058_mmd.sql').read_text())
old = ("  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrm' and product_ref is not null;\n"
       "  if hrm_ref is not null then\n"
       "    select coalesce(jsonb_agg(to_char(holiday_date, 'YYYY-MM-DD') order by holiday_date), '[]'), coalesce(jsonb_object_agg(to_char(holiday_date, 'YYYY-MM-DD'), name), '{}')\n"
       "      into hol, names from hrm.holidays where tenant_id = hrm_ref;\n  end if;")
new = ("  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrms' and product_ref is not null;   -- HRM & Payroll (0072)\n"
       "  if hrm_ref is not null then\n"
       "    select coalesce(jsonb_agg(to_char(hdate, 'YYYY-MM-DD') order by hdate), '[]'), coalesce(jsonb_object_agg(to_char(hdate, 'YYYY-MM-DD'), name), '{}')\n"
       "      into hol, names from console.hrms_holidays where customer_id = cid;\n  end if;")
assert cap.count(old) == 1
cap = cap.replace(old, new)

body = (S / 'hrms-body.sql').read_text()
core = (S / 'hrms-api.sql').read_text()
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_hrms_' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the Capacity Planner reads its holidays from the HRM & Payroll calendar\n' + cap
      + '\n\n-- the demo workspace switches HRM & Payroll on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0072_hrm_suite.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
