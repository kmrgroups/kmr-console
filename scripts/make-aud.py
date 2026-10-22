#!/usr/bin/env python3
"""Generates supabase/migrations/0082_internal_audit.sql (Internal Audit, one new company-level app).
Hand-written: aud-body.sql (products, tables) and aud-api.sql (calls, rules, sample data).
Portal / Data Master / Grand Master / developer sample button are re-created from their latest definitions with 'aud' added
(0081 for context/portal/portal_join, 0080 for the rest)."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
S80 = (M / '0080_d8_problem_solving.sql').read_text(); S81 = (M / '0081_qms_learning.sql').read_text()

def block(header, source):
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return source[i:k] + '\n' + '\n'.join(grants)
def addsub(b, a, c):
    assert b.count(a) == 1, (a[:70], b.count(a))
    return b.replace(a, c)

AUD_T = "'aud_counters','aud_settings','aud_audits','aud_actions','aud_log'"
SPECIFIC = {
 'console.app2_tables(': [("                    when 'd8'    then array['d8_counters','d8_settings','d8_reports','d8_actions','d8_log'] end",
   "                    when 'd8'    then array['d8_counters','d8_settings','d8_reports','d8_actions','d8_log']\n                    when 'aud'   then array[" + AUD_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.d8_settings where customer_id = p_cid; delete from console.d8_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.d8_settings where customer_id = p_cid; delete from console.d8_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'aud' then\n"
   "    delete from console.aud_log where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.aud_actions where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.aud_audits where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.aud_settings where customer_id = p_cid; delete from console.aud_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("a.status = 'open' and r.status = 'open')));\n  end if;",
   "a.status = 'open' and r.status = 'open')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'aud';\n  if ref is not null then\n    out := out || jsonb_build_object('aud', jsonb_build_object(\n"
   "      'Audits planned', (select count(*) from console.aud_audits where customer_id = c and status = 'planned'),\n"
   "      'Late audits', (select count(*) from console.aud_audits where customer_id = c and status = 'planned' and planned_on is not null and planned_on < console.aud_today()),\n"
   "      'Actions open', (select count(*) from console.aud_actions a join console.aud_audits r on r.id = a.audit_id where a.customer_id = c and a.status = 'open' and r.status <> 'cancelled')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'load')); end if;\n"
    "    if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'flush')); end if;\n"
    "    if console.has_app(cid, 'aud') then out := out || jsonb_build_object('aud', console.aud_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('d8', n); smp := smp || jsonb_build_object('d8', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('d8', n); smp := smp || jsonb_build_object('d8', k);\n  end if;\n"
   "  if console.has_app(cid, 'aud') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.aud_audits where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('aud', n); smp := smp || jsonb_build_object('aud', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('d8', cid, true); out := out || jsonb_build_object('d8', n);\n  end if;",
   "    perform console.app2_clear('d8', cid, true); out := out || jsonb_build_object('d8', n);\n  end if;\n"
   "  if console.has_app(cid, 'aud') then\n    select count(*) into n from console.aud_audits where customer_id = cid and not sample;\n    perform console.app2_clear('aud', cid, true); out := out || jsonb_build_object('aud', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.d8_reports where customer_id = cid and not sample; end if;",
   "    elsif t = 'd8' then select count(*) into n from console.d8_reports where customer_id = cid and not sample;\n"
   "    else select count(*) into n from console.aud_audits where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_clear(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
LATEST81 = {'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join('}

def lists(b):
    b = re.sub(r"'d8'(,\s*)'qms'(?=\s*\))", lambda m: "'d8'" + m.group(1) + "'qms'" + m.group(1) + "'aud'", b)
    b = re.sub(r"'d8'(?=\s*[\])])", lambda m: "'d8','aud'" if False else "'d8'", b)  # placeholder (no-op), handled below
    def pl(m):
        txt = m.group(0)
        if "'aud'" in txt: return txt
        sep = ', ' if "', '" in txt else ','
        return txt[:-1] + sep + "'aud'" + txt[-1]
    # list ending right after 'd8'  e.g. ('apqp',... 'd8')  or [... 'd8']
    b = re.sub(r"[\[(]'sales'.*?'d8'[\])]|[\[(]'apqp'.*?'d8'[\])]", pl, b)
    return b

regen = []
for h in REGEN:
    src = S81 if h in LATEST81 else S80
    assert 'create or replace function ' + h in src, h
    b = block('create or replace function ' + h, src); orig = b
    for a, c in SPECIFIC.get(h, []): b = addsub(b, a, c)
    b = lists(b)
    b = re.sub(r"^(\s*)when 'd8'(\s+)then console\.qp_member\((.*?), 'd8'\)$",
               lambda m: m.group(0) + "\n" + m.group(1) + "when 'aud'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'aud')", b, flags=re.M)
    if b == orig: print('unchanged:', h); continue
    assert "'aud'" in b or 'aud_' in b, h
    regen.append(b)

exp = block('create or replace function console.app2_export(', S80)
exp = addsub(exp, "or t like 'd8\\_%' then null", "or t like 'd8\\_%' or t like 'aud\\_%' then null")
regen.append(exp)
demo = block('create or replace function console.demo_refresh(', S80); demo = lists(demo)
assert "'aud'" in demo
smp = block('create or replace function public.kmr_app_sample(', S80)
smp = addsub(smp, "  elsif p_app = 'd8' then out := jsonb_build_object('d8', console.d8_sample(cid, p_action));",
             "  elsif p_app = 'd8' then out := jsonb_build_object('d8', console.d8_sample(cid, p_action));\n  elsif p_app = 'aud' then out := jsonb_build_object('aud', console.aud_sample(cid, p_action));")

body = (S / 'aud-body.sql').read_text(); core = (S / 'aud-api.sql').read_text()
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the developer sample-data button knows the new app\n' + smp
      + '\n\n-- the demo workspace switches the new app on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n')
(M / '0082_internal_audit.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
