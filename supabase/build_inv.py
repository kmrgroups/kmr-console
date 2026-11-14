import csv,json,gzip,sys,glob,os
d=sys.argv[1]; out=sys.argv[2]
def rd(n):
    f=glob.glob(os.path.join(d,'*_'+n+'.csv'))
    return list(csv.DictReader(open(f[0],encoding='utf-8-sig'))) if f else []
def num(x):
    try: return float(str(x).replace(',','') or 0)
    except: return 0.0
M=rd('invoicemaster') or rd('invoicemaster_last'); D=rd('invoicedetail') or rd('invoicedetail_last'); C=rd('customer') or rd('customer_gst')
cust={c['custcode'].strip().upper():c for c in C}
lines={}
for l in D: lines.setdefault(l['invno'].strip(),[]).append(l)
res=[]
for m in M:
    no=m['invno'].strip(); c=cust.get(m['custcode'].strip().upper(),{})
    ls=lines.get(no,[])
    out_l=[]
    for l in sorted(ls,key=lambda x:num(x.get('LINENO'))):
        g=num(l['CGSTTAX'])*2 if num(l['CGSTAMT']) else num(l['IGSTTAX'])
        out_l.append(dict(code=l['prodcode'].strip(),desc=l.get('Desc1','').strip(),hsn=l.get('Hsncode','').strip(),uom=l.get('uom1','').strip() or 'Nos',qty=num(l['qty']),rate=num(l['rate']),discount=num(l.get('Discounta')),gst=g,
            taxable=num(l.get('Taxablev')) or num(l['value']),cgst=num(l['CGSTAMT']),sgst=num(l['SGSTAMT']),igst=num(l['IGSTAMT']),packing=l.get('packing','').strip()))
    tx=sum(x['taxable'] for x in out_l); cg=num(m['CGSTAMT']); sg=num(m['SGSTAMT']); ig=num(m['IGSTAMT']); tcs=num(m.get('TcsAmt')); tot=num(m['gtotal'])
    gst=(c.get('Billgstno') or '').strip().upper()
    country=(c.get('Country1') or '').strip().upper()
    sup='B2B' if len(gst)==15 else ('EXPWOP' if country not in ('','INDIA') else 'B2B')
    res.append(dict(no=no,date=m['invdate'],po_no=m.get('pono','').strip(),po_date=m.get('podate',''),buyer_code=m['custcode'].strip(),buyer_name=(c.get('custname') or m['custcode']).strip(),gstin=gst if len(gst)==15 else '',
        addr=(c.get('address') or '').strip(),loc=(c.get('CITY') or '').strip(),pin=(c.get('billpin') or '').strip(),state=(c.get('Statecode') or gst[:2]).strip(),supply=sup,dc_no=m.get('dcno','').strip(),dc_date=m.get('dcdate',''),
        vehicle=m.get('transth','').strip(),mode=m.get('transmode','').strip(),terms=m.get('Deliverytrm','').strip(),pay_days=m.get('Paytrm','').strip(),remarks=m.get('Remarks','').strip(),
        taxable=round(tx,2),cgst=cg,sgst=sg,igst=ig,tcs=tcs,round_off=round(tot-(tx+cg+sg+ig+tcs),2),total=tot,cancelled=(m.get('CANCELL','NO').strip().upper()=='YES'),lines=out_l))
res.sort(key=lambda x:(x['date'],x['no']))
js=json.dumps({'invoices':res},separators=(',',':'))
open(out,'wb').write(gzip.compress(js.encode())) if out.endswith('.gz') else open(out,'w').write(js)
print(len(res),'invoices',sum(len(r['lines']) for r in res),'lines',len(js)//1024,'KB')
