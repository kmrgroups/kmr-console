#!/usr/bin/env python3
"""Generates supabase/migrations/0080_d8_problem_solving.sql (8D Problem Solving, one new company-level app).
Hand-written: d8-body.sql (products, tables) and d8-api.sql (calls, step rules, sample data).
Portal / Data Master / Grand Master / developer sample button are re-created from their latest definitions (0079) with the new app added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
SRC = (M / '0079_crm_rfq.sql').read_text()

def block(header, source):
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    out = source[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

D8_T = "'d8_counters','d8_settings','d8_reports','d8_actions','d8_log'"
GLOBAL = [("'spc','crm'", "'spc','crm','d8'"), ("'spc', 'crm'", "'spc', 'crm', 'd8'")]
SPECIFIC = {
 'console.app2_tables(': [("'crm_quotes','crm_activities'] end", "'crm_quotes','crm_activities']\n                    when 'd8'    then array[" + D8_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.crm_settings where customer_id = p_cid; delete from console.crm_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.crm_settings where customer_id = p_cid; delete from console.crm_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'd8' then\n"
   "    delete from console.d8_log where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.d8_actions where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.d8_reports where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.d8_settings where customer_id = p_cid; delete from console.d8_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("      'Quotes out', (select count(*) from console.crm_quotes where customer_id = c and status = 'sent')));\n  end if;",
   "      'Quotes out', (select count(*) from console.crm_quotes where customer_id = c and status = 'sent')));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'd8';\n  if ref is not null then\n    out := out || jsonb_build_object('d8', jsonb_build_object(\n"
   "      'Open 8Ds', (select count(*) from console.d8_reports where customer_id = c and status = 'open'),\n"
   "      'Overdue', (select count(*) from console.d8_reports where customer_id = c and status = 'open' and due_on is not null and due_on < console.d8_today()),\n"
   "      'Actions open', (select count(*) from console.d8_actions a join console.d8_reports r on r.id = a.report_id where a.customer_id = c and a.status = 'open' and r.status = 'open')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'load')); end if;\n"
    "    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'flush')); end if;\n"
    "    if console.has_app(cid, 'd8') then out := out || jsonb_build_object('d8', console.d8_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('crm', n); smp := smp || jsonb_build_object('crm', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('crm', n); smp := smp || jsonb_build_object('crm', k);\n  end if;\n"
   "  if console.has_app(cid, 'd8') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.d8_reports where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('d8', n); smp := smp || jsonb_build_object('d8', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('crm', cid, true); out := out || jsonb_build_object('crm', n);\n  end if;",
   "    perform console.app2_clear('crm', cid, true); out := out || jsonb_build_object('crm', n);\n  end if;\n"
   "  if console.has_app(cid, 'd8') then\n    select count(*) into n from console.d8_reports where customer_id = cid and not sample;\n    perform console.app2_clear('d8', cid, true); out := out || jsonb_build_object('d8', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.crm_parties where customer_id = cid and not sample; end if;",
   "    elsif t = 'crm' then select count(*) into n from console.crm_parties where customer_id = cid and not sample;\n"
   "    else select count(*) into n from console.d8_reports where customer_id = cid and not sample; end if;")],
}
REGEN = ['console.data_target(', 'console.app2_tables(', 'console.app2_clear(',
         'public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(', 'public.kmr_portal_stats(', 'public.kmr_data_overview(', 'public.kmr_data_export(',
         'public.kmr_data_flush(', 'public.kmr_data_import(', 'public.kmr_grand_sample(', 'public.kmr_grand_overview(',
         'public.kmr_grand_real_export(', 'public.kmr_grand_real_flush(', 'public.kmr_grand_real_import(']
def addsub(b, a, c):
    assert b.count(a) == 1, (a[:70], b.count(a))
    return b.replace(a, c)
regen = []
for h in REGEN:
    assert 'create or replace function ' + h in SRC, h
    b = block('create or replace function ' + h, SRC); orig = b
    for a, c in SPECIFIC.get(h, []): b = addsub(b, a, c)
    for a, c in GLOBAL: b = b.replace(a, c)
    b = re.sub(r"^(\s*)when 'crm'(\s+)then console\.qp_member\((.*?), 'crm'\)$",
               lambda m: m.group(0) + "\n" + m.group(1) + "when 'd8'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'd8')", b, flags=re.M)
    if b == orig: print('unchanged:', h); continue
    assert "'d8'" in b or 'd8_' in b, h
    regen.append(b)

exp = block('create or replace function console.app2_export(', SRC)
exp = addsub(exp, "or t like 'crm\\_%' then null", "or t like 'crm\\_%' or t like 'd8\\_%' then null")
regen.append(exp)

demo = block('create or replace function console.demo_refresh(', SRC)
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'d8'" in demo

smp = block('create or replace function public.kmr_app_sample(', SRC)
smp = addsub(smp, "  elsif p_app = 'crm' then out := jsonb_build_object('crm', console.crm_sample(cid, p_action));",
             "  elsif p_app = 'crm' then out := jsonb_build_object('crm', console.crm_sample(cid, p_action));\n  elsif p_app = 'd8' then out := jsonb_build_object('d8', console.d8_sample(cid, p_action));")

body = (S / 'd8-body.sql').read_text(); core = (S / 'd8-api.sql').read_text()
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the developer sample-data button knows the new app\n' + smp
      + '\n\n-- the demo workspace switches the new app on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n')
(M / '0080_d8_problem_solving.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
