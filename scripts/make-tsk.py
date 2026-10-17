#!/usr/bin/env python3
"""Generates supabase/migrations/0076_actiontrack.sql (ActionTrack — Task Management).
Hand-written: tsk-body.sql (product, tables) and tsk-api.sql (calls, helpers, sample data).
The portal / data-master / grand-master functions are re-created from their latest definition (0072; portal 0074; portal join 0075) with ActionTrack added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
SRC = {'default': (M / '0072_hrm_suite.sql').read_text(),
       'public.kmr_portal(': (M / '0074_staff_portal_access.sql').read_text(),
       'public.kmr_portal_join(': (M / '0075_staff_admin_everywhere.sql').read_text()}

def block(header, source):
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    out = source[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

TSK_T = "'tsk_counters','tsk_tasks','tsk_comments','tsk_notifications','tsk_push_subs'"
GLOBAL = [("'cad','hrms'", "'cad','hrms','tsk'"), ("'cad', 'hrms'", "'cad', 'hrms', 'tsk'")]
SPECIFIC = {
 'console.app2_tables(': [(re.compile(r"(when 'hrms'\s+then array\[[^\]]*\])( end)"), r"\1\n                    when 'tsk'   then array[" + TSK_T + r"]\2")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.hrms_settings where customer_id = p_cid; delete from console.hrms_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.hrms_settings where customer_id = p_cid; delete from console.hrms_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'tsk' then\n"
   "    delete from console.tsk_notifications where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.tsk_comments where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.tsk_tasks where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.tsk_push_subs where customer_id = p_cid; delete from console.tsk_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("      'Leave to approve', (select count(*) from console.hrms_leaves where customer_id = c and status = 'Pending')));\n  end if;",
   "      'Leave to approve', (select count(*) from console.hrms_leaves where customer_id = c and status = 'Pending')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'tsk';\n  if ref is not null then\n    out := out || jsonb_build_object('tsk', jsonb_build_object(\n"
   "      'Open tasks', (select count(*) from console.tsk_tasks where customer_id = c and status in ('open', 'progress', 'blocked')),\n"
   "      'Overdue', (select count(*) from console.tsk_tasks where customer_id = c and status in ('open', 'progress', 'blocked') and due < (now() at time zone 'Asia/Kolkata')::date),\n"
   "      'Done this week', (select count(*) from console.tsk_tasks where customer_id = c and status = 'done' and done_at >= now() - interval '7 days')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'load')); end if;\n    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'tsk') then out := out || jsonb_build_object('tsk', console.tsk_sample(cid, 'flush')); end if;\n    if console.has_app(cid, 'hrms') then out := out || jsonb_build_object('hrms', console.hrms_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('hrms', n); smp := smp || jsonb_build_object('hrms', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('hrms', n); smp := smp || jsonb_build_object('hrms', k);\n  end if;\n  if console.has_app(cid, 'tsk') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.tsk_tasks where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('tsk', n); smp := smp || jsonb_build_object('tsk', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('hrms', cid, true); out := out || jsonb_build_object('hrms', n);\n  end if;",
   "    perform console.app2_clear('hrms', cid, true); out := out || jsonb_build_object('hrms', n);\n  end if;\n  if console.has_app(cid, 'tsk') then\n"
   "    select count(*) into n from console.tsk_tasks where customer_id = cid and not sample;\n    perform console.app2_clear('tsk', cid, true); out := out || jsonb_build_object('tsk', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.hrms_employees where customer_id = cid and not sample; end if;",
   "    elsif t = 'hrms' then select count(*) into n from console.hrms_employees where customer_id = cid and not sample;\n    else select count(*) into n from console.tsk_tasks where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_export(', 'console.app2_clear(', 'console.app2_restore(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
def addsub(b, a, c):
    if hasattr(a, 'sub'):
        assert a.search(b), a.pattern
        return a.sub(c, b)
    assert b.count(a) == 1, (a[:70], b.count(a))
    return b.replace(a, c)
regen = []
for h in REGEN:
    srcx = SRC.get(h, SRC['default'])
    if 'create or replace function ' + h not in srcx: print('not in latest source (generic):', h); continue
    b = block('create or replace function ' + h, srcx); orig = b
    for a, c in SPECIFIC.get(h, []): b = addsub(b, a, c)
    for a, c in GLOBAL: b = b.replace(a, c)
    b = re.sub(r"^(\s*)when 'hrms'(\s+)then console\.qp_member\((.*?), 'hrms'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'tsk'" + m.group(2) + "  then console.qp_member(" + m.group(3) + ", 'tsk')", b, flags=re.M)
    if b == orig: print('unchanged:', h); continue
    assert "'tsk'" in b or 'tsk_' in b, h
    regen.append(b)
demo = block('create or replace function console.demo_refresh(', SRC['default'])
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'tsk'" in demo

body = (S / 'tsk-body.sql').read_text(); core = (S / 'tsk-api.sql').read_text()
tail = """
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^kmr_tsk_' and p.proname not in ('kmr_tsk_due_scan', 'kmr_tsk_push_take', 'kmr_tsk_push_drop') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
"""
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the demo workspace switches ActionTrack on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n' + tail)
(M / '0076_actiontrack.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
