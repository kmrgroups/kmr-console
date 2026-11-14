import { Tables, rows, num, trim, r2, pySum } from "./common";

/** ERP invoicemaster + invoicedetail + customer  ->  { invoices: [...] } for kmr_inv_import (same rules as the one-time loader). */
export function buildInvoices(t: Tables) {
  const M = rows(t.invoicemaster), D = rows(t.invoicedetail), C = rows(t.customer);
  const cust = new Map<string, Record<string, string>>(); for (const c of C) cust.set(trim(c.custcode).toUpperCase(), c);
  const lines = new Map<string, Record<string, string>[]>(); for (const l of D) { const k = trim(l.invno); if (!lines.has(k)) lines.set(k, []); lines.get(k)!.push(l); }
  const res: Record<string, unknown>[] = [];
  for (const m of M) {
    const no = trim(m.invno); if (!no) continue;
    const c = cust.get(trim(m.custcode).toUpperCase()) || {};
    const ls = (lines.get(no) || []).slice().sort((a, b) => num(a.LINENO) - num(b.LINENO));
    const outL = ls.map((l) => ({
      code: trim(l.prodcode), desc: trim(l.Desc1), hsn: trim(l.Hsncode), uom: trim(l.uom1) || "Nos", qty: num(l.qty), rate: num(l.rate), discount: num(l.Discounta),
      gst: num(l.CGSTAMT) ? num(l.CGSTTAX) * 2 : num(l.IGSTTAX), taxable: num(l.Taxablev) || num(l.value), cgst: num(l.CGSTAMT), sgst: num(l.SGSTAMT), igst: num(l.IGSTAMT), packing: trim(l.packing),
    }));
    const tx = pySum(outL.map((x) => x.taxable)), cg = num(m.CGSTAMT), sg = num(m.SGSTAMT), ig = num(m.IGSTAMT), tcs = num(m.TcsAmt), tot = num(m.gtotal);
    const gst = trim(c.Billgstno).toUpperCase(), country = trim(c.Country1).toUpperCase();
    const supply = gst.length === 15 ? "B2B" : (country !== "" && country !== "INDIA" ? "EXPWOP" : "B2B");
    const d = r2(tot - (tx + cg + sg + ig + tcs));
    res.push({
      no, date: m.invdate, po_no: trim(m.pono), po_date: m.podate || "", buyer_code: trim(m.custcode), buyer_name: trim(c.custname || m.custcode), gstin: gst.length === 15 ? gst : "",
      addr: trim(c.address), loc: trim(c.CITY), pin: trim(c.billpin), state: trim(c.Statecode || gst.slice(0, 2)), supply, dc_no: trim(m.dcno), dc_date: m.dcdate || "",
      vehicle: trim(m.transth), mode: trim(m.transmode), terms: trim(m.Deliverytrm), pay_days: trim(m.Paytrm), remarks: trim(m.Remarks),
      taxable: r2(tx), cgst: cg, sgst: sg, igst: ig, tcs, round_off: Math.abs(d) <= 1 ? d : 0, total: tot, cancelled: (trim(m.CANCELL || "NO")).toUpperCase() === "YES", lines: outL,
    });
  }
  res.sort((a, b) => { const x = String(a.date) + "\u0000" + String(a.no), y = String(b.date) + "\u0000" + String(b.no); return x < y ? -1 : x > y ? 1 : 0; });
  return { invoices: res };
}
