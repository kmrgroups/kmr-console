#!/usr/bin/env python3
"""Generates supabase/migrations/0081_qms_learning.sql (QMS Learning Guide: a company-level app with no data tables, content is in the website).
Portal / access functions are re-created from 0080 with the new app 'qms' added."""
import re, pathlib
S = pathlib.Path(__file__).resolve().parent; M = S.parent / 'supabase' / 'migrations'
SRC = (M / '0080_d8_problem_solving.sql').read_text()
def block(header):
    i = SRC.index(header); j = SRC.index(' as $$', i); k = SRC.index('$$;', j + 6) + 3
    name = re.search(r'function ([\w.]+)\(', header).group(1)
    tail = SRC[k:k + 2000].split('\n'); grants = [l for l in tail if re.match(r'^(revoke|grant) .*function ' + re.escape(name) + r'\(', l)]
    return SRC[i:k] + '\n' + '\n'.join(grants)
out = []
for h in ['public.kmr_qp_context(', 'public.kmr_portal(', 'public.kmr_portal_join(']:
    b = block('create or replace function ' + h)
    b = b.replace("'crm', 'd8')", "'crm', 'd8', 'qms')")
    b = re.sub(r"^(\s*)when 'd8'(\s+)then console\.qp_member\((.*?), 'd8'\)$", lambda m: m.group(0) + "\n" + m.group(1) + "when 'qms'" + m.group(2) + "then console.qp_member(" + m.group(3) + ", 'qms')", b, flags=re.M)
    assert "'qms'" in b, h; out.append(b)
body = (S / 'qms-body.sql').read_text()
(M / '0081_qms_learning.sql').write_text(body.replace('--@@REGENERATED@@', '\n\n'.join(out)) + '\n')
print('ok', len(out))
