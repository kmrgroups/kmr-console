import csv,re,json,gzip,collections,sys
P='/tmp/pr/ERP_ESBEE_%s.csv'; G='/tmp/dg/ERP_ESBEE_%s.csv'
def rd(f,n): return list(csv.DictReader(open(f%n,encoding='utf-8-sig')))
nz=lambda s:re.sub(r'[^a-z0-9]','',str(s or '').lower())
cl=lambda s:re.sub(r'\s+',' ',str(s or '')).strip()
def num(x):
    try: return float(str(x).replace(',',''))
    except: return 0.0
rows=[]
def add(kind,code,name,data=None,active=True):
    code=cl(code)[:80]
    if not code: return
    d={k:v for k,v in (data or {}).items() if v not in ('',None)}
    rows.append(dict(kind=kind,code=code,name=cl(name or code)[:200],data=d,active=active))
# ---- GRN categories (same rules as the Excel)
src=open('/home/claude/po-grn-xl/build_xl.py').read().split("rows.sort")[0].replace("/tmp/dg/ERP_ESBEE_grn.csv","/tmp/dg/ERP_ESBEE_grn.csv")
ns={}; exec(src,ns); grn=ns['rows']
grn.sort(key=lambda x:(x['date'],x['grn']))
# ---- customers
for c in rd(P,'customer'):
    add('customers',c['custcode'],c['custname'],dict(address=cl(c['address']),city=cl(c['CITY']),state=cl(c['STATE']),state_code=cl(c['Statecode']),gstin=cl(c['Billgstno']).upper() if len(cl(c['Billgstno']))==15 else '',pin=cl(c['billpin']),contact=cl(c['contactperson']),email=cl(c['contactno']) if '@' in c['contactno'] else '',phone='' if '@' in c['contactno'] else cl(c['contactno'])),active=c.get('HIDE1','NO').upper()!='YES')
# ---- suppliers: dominant purchase category
SC={'Raw materials':'Raw material','Tools (cutting tools)':'Tooling','Consumables':'Consumables','Packing material':'Consumables','Gauges & instruments':'Gauges & calibration','Job-work components':'Outsourced process','Repairs & maintenance':'Services','Services (clearing & forwarding)':'Services'}
cnt=collections.defaultdict(collections.Counter)
for x in grn: cnt[nz(x['sup'])][SC.get(x['c'],'')]+=1
seen=set()
for s in rd(P,'suppliercm'):
    k=nz(s['suppname'] or s['suppcode']); 
    if k in seen: continue
    seen.add(k)
    cat=''; 
    c=cnt.get(k) or cnt.get(nz(s['suppcode']))
    if c:
        c=collections.Counter({a:b for a,b in c.items() if a}); cat=c.most_common(1)[0][0] if c else ''
    ph=cl(s['contactno'])
    add('suppliers',s['suppcode'],s['suppname'],dict(category=cat,address=cl(s['address']),contact=cl(s['contactperson']),phone=ph if '@' not in ph else '',email=ph if '@' in ph else '',pan=cl(s['panno'])),active=s.get('HIDE1','NO').upper()!='YES')
# ---- machines
mt={r['MCTYPE']:r['MCTYPE1'] for r in rd(P,'mctype')}
def mtype(t):
    t=(t or '').upper()
    if 'TURN' in t or t in('CNC','TURNING'): return 'CNC Turning'
    if 'VMC' in t: return 'VMC'
    if 'GRIND' in t: return 'Grinding'
    if 'PRESS' in t: return 'Press'
    if 'WELD' in t: return 'Welding'
    return 'Other'
for m in rd(P,'machine'):
    add('machines',m['machineno'],m['machinename'],dict(type=mtype(m['mctype']),erp_type=cl(m['mctype']),make=cl(m['SUPPCODE']),year=cl(m['YMANF']),location=cl(m['location']),serial_no=cl(m['mslno']),efficiency_pct=cl(m['EFFCY']) if num(m['EFFCY']) else '',monitored=cl(m['MONITORED'])),active=m['HIDE1'].upper()!='YES')
# ---- parts
for p in rd(P,'product'):
    add('parts',p['prodcode'],p['prodname'] or p['prodcode'],dict(drawing_no=cl(p['drgno']),revision=cl(p['drgrevision']),material=cl(p['rmcode']),weight_kg=num(p['wtreq']) or '',rate=num(p['rate']) or '',hsn=cl(p['HSNCode']),moq=num(p['moq']) or ''))
# ---- cycle times: the latest entry for each part + process
ct={}
for r in sorted(rd(P,'cycletime1'),key=lambda r:num(r['refno'])):
    if not cl(r['product']) or not cl(r['process']) or num(r['mastercycletime'])<=0: continue
    ct[(cl(r['product']),cl(r['process']))]=r
for (pc,pr),r in ct.items():
    add('cycle_times',pc+' | '+pr,pr,dict(part_no=pc,op_type='In-house',cycle_time_sec=num(r['mastercycletime']),tool_cycle_sec=num(r['tcycletime']) or ''))
# ---- tools, consumables, raw materials from the purchases (one record per distinct item, latest supplier and rate)
last={}
for x in grn:
    if x['c'] in('Tools (cutting tools)','Consumables','Packing material','Raw materials') and x['item']:
        last[(x['c'],nz(x['item']))]=x
TT=[('Insert',r'insert|tnmg|cnmg|dnmg|vnmg|ccmt|dcmt|apkt|wnmg|tpmt'),('Drill',r'drill'),('Tap',r'\btap'),('Reamer',r'reamer'),('End mill',r'end ?mill|milling'),('Boring bar',r'boring')]
def ttype(t):
    for n,p in TT:
        if re.search(p,t,re.I): return n
    return 'Other'
for (c,k),x in last.items():
    it=cl(x['item'])
    if c=='Tools (cutting tools)': add('tools',it,it,dict(type=ttype(it),source=x['sup'],rate=x['rate'] or '',erp_last_grn=x['date']))
    elif c in('Consumables','Packing material'): add('consumables',it,it,dict(supplier=x['sup'],rate=x['rate'] or '',category='Packing material' if c=='Packing material' else 'Consumables',erp_last_grn=x['date']))
    elif c=='Raw materials': add('raw_materials',it,it,dict(supplier=x['sup'],erp_last_grn=x['date']))
# duplicates inside the file (same kind and same normalised code) are dropped, keeping the first
seen=set();out=[]
for r in rows:
    k=(r['kind'],nz(r['code']))
    if k in seen: continue
    seen.add(k); out.append(r)
out=[r for r in out if r['kind'] in ('suppliers','tools','consumables','raw_materials')]   # customers, machines, parts and cycle times were loaded earlier from the ERP
print(collections.Counter(r['kind'] for r in out),len(rows)-len(out),'dropped')
open('Unit-2_ERP_Masters.json.gz','wb').write(gzip.compress(json.dumps({'rows':out},separators=(',',':')).encode()))
# ---- production history
pname={nz(p['prodcode']):cl(p['prodname']) for p in rd(P,'product')}
H=[]
for srcn,tag in (('toolchanging','n'),('toolchangingold','o')):
    for r in rd(P,srcn):
        d=r['refdate'][:10]
        if not d: continue
        pc=cl(r['prodcode']); idle=pc.upper().startswith('NILL')
        codes=','.join(sorted({r['drea%d'%i] for i in range(1,8) if r.get('drea%d'%i,'0') not in('','0','NILL1')}))
        H.append([tag+r['refno'],d,'' if r['shift'].upper().startswith('NILL') else cl(r['shift']),cl(r['machineno']),'' if cl(r['operatorno']).upper().startswith('NILL') else cl(r['operatorno']),'' if idle else pc,'' if idle else pname.get(nz(pc),''),'No production' if idle else cl(r['process']),cl(r['rmcode']) if not idle else '',cl(r['batchno']) if not idle else '',num(r['hours']),num(r['qtyprod']),num(r['cycletime']),num(r['barsused']),num(r['scrap']),round(num(r['EFFCY1']),1),num(r['totalidlehrs']),num(r['totalmchrs']),num(r['plannedhrs']),codes,cl(r['reasons'])])
print(len(H),'production history rows')
open('Unit-2_ERP_Production.json.gz','wb').write(gzip.compress(json.dumps({'rows':H},separators=(',',':')).encode()))
