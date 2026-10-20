#!/usr/bin/env python3
"""Generates supabase/migrations/0079_crm_rfq.sql (CRM & RFQ, one new company-level app).
Hand-written: crm-body.sql (products, tables) and crm-api.sql (calls, costing arithmetic, sample data).
Portal / Data Master / Grand Master / developer sample button are re-created from their latest definitions (0077, 0078, 0069) with the new app added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent
M = S.parent / 'supabase' / 'migrations'
SRC = (M / '0077_msa_spc.sql').read_text()
SRC78 = (M / '0078_dev_sample_button.sql').read_text()
SRC69 = (M / '0069_cad_draft.sql').read_text()

def block(header, source):
    i = source.index(header)
    j = source.index(' as $$', i); k = source.index('$$;', j + 6) + 3
    out = source[i:k]
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = source[k:k + 2000].split('\n')
    grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return out + '\n' + '\n'.join(grants)

CRM_T = "'crm_counters','crm_settings','crm_parties','crm_contacts','crm_leads','crm_rfqs','crm_rfq_items','crm_supplier_quotes','crm_quotes','crm_activities'"
GLOBAL = [("'tsk','msa','spc'", "'tsk','msa','spc','crm'"), ("'tsk', 'msa', 'spc'", "'tsk', 'msa', 'spc', 'crm'")]
SPECIFIC = {
 'console.app2_tables(': [("when 'spc'   then array['spc_counters','spc_charts','spc_points'] end",
                           "when 'spc'   then array['spc_counters','spc_charts','spc_points']\n                    when 'crm'   then array[" + CRM_T + "] end")],
 'console.app2_clear(': [("    if not p_real_only then delete from console.spc_counters where customer_id = p_cid; end if;\n  end if;",
   "    if not p_real_only then delete from console.spc_counters where customer_id = p_cid; end if;\n"
   "  elsif p_app = 'crm' then\n"
   "    delete from console.crm_activities where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_quotes where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_supplier_quotes where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_rfq_items where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_rfqs where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_leads where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_contacts where customer_id = p_cid and (not p_real_only or sample); get diagnostics k = row_count; n := n + k;\n"
   "    delete from console.crm_parties y where y.customer_id = p_cid and (not p_real_only or y.sample) and (not p_real_only or (not exists (select 1 from console.crm_rfqs r where r.party_id = y.id) and not exists (select 1 from console.crm_quotes z where z.party_id = y.id) and not exists (select 1 from console.crm_supplier_quotes q where q.supplier_id = y.id))); get diagnostics k = row_count; n := n + k;\n"
   "    if not p_real_only then delete from console.crm_settings where customer_id = p_cid; delete from console.crm_counters where customer_id = p_cid; end if;\n  end if;")],
 'public.kmr_portal_stats(': [("      'With signals', (select count(*) from console.spc_charts where customer_id = c and status = 'active' and coalesce((summary ->> 'signals')::int, 0) > 0)));\n  end if;",
   "      'With signals', (select count(*) from console.spc_charts where customer_id = c and status = 'active' and coalesce((summary ->> 'signals')::int, 0) > 0)));\n  end if;\n"
   "  select product_ref into ref from console.licences where customer_id = c and product_code = 'crm';\n  if ref is not null then\n    out := out || jsonb_build_object('crm', jsonb_build_object(\n"
   "      'Open leads', (select count(*) from console.crm_leads where customer_id = c and stage not in ('Won', 'Lost')),\n"
   "      'RFQs to quote', (select count(*) from console.crm_rfqs where customer_id = c and status in ('Received', 'Costing')),\n"
   "      'Quotes out', (select count(*) from console.crm_quotes where customer_id = c and status = 'sent')));\n  end if;")],
 'public.kmr_grand_sample(': [
   ("    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'load')); end if;",
    "    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'load')); end if;\n"
    "    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'load')); end if;"),
   ("    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'flush')); end if;",
    "    if console.has_app(cid, 'spc') then out := out || jsonb_build_object('spc', console.spc_sample(cid, 'flush')); end if;\n"
    "    if console.has_app(cid, 'crm') then out := out || jsonb_build_object('crm', console.crm_sample(cid, 'flush')); end if;")],
 'public.kmr_grand_overview(': [("    real_ := real_ || jsonb_build_object('spc', n); smp := smp || jsonb_build_object('spc', k);\n  end if;",
   "    real_ := real_ || jsonb_build_object('spc', n); smp := smp || jsonb_build_object('spc', k);\n  end if;\n"
   "  if console.has_app(cid, 'crm') then\n"
   "    select count(*) filter (where not sample), count(*) filter (where sample) into n, k from console.crm_parties where customer_id = cid;\n"
   "    real_ := real_ || jsonb_build_object('crm', n); smp := smp || jsonb_build_object('crm', k);\n  end if;")],
 'public.kmr_grand_real_flush(': [("    perform console.app2_clear('spc', cid, true); out := out || jsonb_build_object('spc', n);\n  end if;",
   "    perform console.app2_clear('spc', cid, true); out := out || jsonb_build_object('spc', n);\n  end if;\n"
   "  if console.has_app(cid, 'crm') then\n    select count(*) into n from console.crm_parties where customer_id = cid and not sample;\n    perform console.app2_clear('crm', cid, true); out := out || jsonb_build_object('crm', n);\n  end if;")],
 'public.kmr_grand_real_import(': [("    else select count(*) into n from console.spc_charts where customer_id = cid and not sample; end if;",
   "    elsif t = 'spc' then select count(*) into n from console.spc_charts where customer_id = cid and not sample;\n"
   "    else select count(*) into n from console.crm_parties where customer_id = cid and not sample; end if;")],
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
    b = re.sub(r"^(\s*)when 'spc'(\s+)then console\.qp_member\((.*?), 'spc'\)$",
               lambda m: m.group(0) + "\n" + m.group(1) + "when 'crm'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'crm')", b, flags=re.M)
    if b == orig: print('unchanged:', h); continue
    assert "'crm'" in b or 'crm_' in b, h
    regen.append(b)

# the export function: the CRM tables all carry their own sample flag, so the "real data only" export reads them directly
exp = block('create or replace function console.app2_export(', SRC69)
exp = addsub(exp, "'cad_drawings') then null", "'cad_drawings') or t like 'crm\\_%' then null")
regen.append(exp)

demo = block('create or replace function console.demo_refresh(', SRC)
for a, c in GLOBAL: demo = demo.replace(a, c)
assert "'crm'" in demo

smp = block('create or replace function public.kmr_app_sample(', SRC78)
smp = addsub(smp, "  elsif p_app = 'spc' then out := jsonb_build_object('spc', console.spc_sample(cid, p_action));",
             "  elsif p_app = 'spc' then out := jsonb_build_object('spc', console.spc_sample(cid, p_action));\n  elsif p_app = 'crm' then out := jsonb_build_object('crm', console.crm_sample(cid, p_action));")

body = (S / 'crm-body.sql').read_text(); core = (S / 'crm-api.sql').read_text()
out = body.replace('--@@CORE@@', core).replace('--@@REGENERATED@@',
      '-- ---------- portal, access, Data Master and Grand Master: re-created from their latest version ----------\n' + '\n\n'.join(regen)
      + '\n\n-- the developer sample-data button knows the new app\n' + smp
      + '\n\n-- the demo workspace switches the new app on too\ndrop function if exists console.demo_refresh(uuid, boolean);\n' + demo + '\n')
(M / '0079_crm_rfq.sql').write_text(out)
print('written', len(out), 'bytes;', len(regen), 'functions regenerated')
