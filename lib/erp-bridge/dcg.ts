import { Tables, rows, F, trim, isoDate, pyTitle, isUpper } from "./common";

const BADPO = new Set(["", "VERBAL", "NIL", "-", "0", "NA", "N/A", "NO", "NONE"]);
const validpo = (p: string) => { const s = trim(p); return !!s && !BADPO.has(s.toUpperCase()) && !s.toUpperCase().startsWith("VERBAL"); };
const DT = (s: unknown) => isoDate(s, 1995, 2027);
const title = (s: unknown) => { const t = trim(s); return isUpper(t) ? pyTitle(t) : t; };
const uniq = <T,>(a: T[]) => Array.from(new Set(a));

/** ERP dc + grn + grnno + grndc -> { pos, dcs, grns } for kmr_dcg_import (same rules as the one-time loader). */
export function buildDcg(t: Tables) {
  const dc = rows(t.dc), grn = rows(t.grn), gdc = rows(t.grndc);
  const hdr = new Map<string, Record<string, string>>(); for (const r of rows(t.grnno)) hdr.set(r.GRNNO, r);
  // ---- delivery challans
  const by = new Map<string, Record<string, string>[]>(); for (const r of dc) { const k = trim(r.DCNO); if (!by.has(k)) by.set(k, []); by.get(k)!.push(r); }
  const dcs: Record<string, unknown>[] = [], dcset = new Set<string>(); const posDc = new Map<string, { supplier: string; date: string }>();
  for (const [no, rs] of by) {
    const d0 = rs.map((r) => DT(r.DCDATE)).find((x) => x) || null;
    if (!no || !d0) continue;
    const r0 = rs[0];
    const ret = rs.some((r) => trim(r.DESCP11).toLowerCase().startsWith("ret"));
    const lines: Record<string, unknown>[] = []; let rets = 0, tot = 0;
    for (const r of rs) {
      const q = F(r.QTY); if (!q || q <= 0) continue;
      const code = trim(r.DRGNO), desc = trim(r.DRGNO1) || trim(r.drgnodc) || code;
      const rem = uniq([r.DESCP, r.REMARKS].map(trim).filter((x) => x)).join(" · ");
      const bal = F(r.DCBAL);
      const returned = (!ret || trim(r.DCBAL) === "" || bal === null) ? q : Math.max(0, Math.min(q, q - bal));
      rets += returned; tot += q;
      const v = F(r.Value1) || ((F(r.Rate1) || 0) * q || null);
      lines.push({ sl: lines.length + 1, item_code: code, description: desc, uom: pyTitle(trim(r.unit1) || "Nos") || "Nos", qty: q, hsn: trim(r.HSNCode), value: v, returned_qty: returned, remarks: rem });
    }
    if (!lines.length) continue;
    const text = rs.map((r) => `${r.DESCP} ${r.REMARKS} ${r.DRGNO1} ${r.DRGNO}`).join(" ").toLowerCase();
    const pur = (text.includes("calib") || text.includes("-ins-")) ? "calibration" : text.includes("repair") ? "repair" : (text.includes("rework") || text.includes("re-work")) ? "rework" : text.includes("sample") ? "sample" : text.includes("scrap") ? "scrap" : ret ? "job_work" : "other";
    const status = ret ? (tot - rets <= 1e-9 ? "closed" : (rets > 0 ? "part_returned" : "issued")) : "issued";
    let er: string | null = null;
    if (ret) { const m = trim(r0.DRGNO11).match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})/); if (m) er = DT(`${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`); }
    const po = validpo(r0.PONO) ? trim(r0.PONO) : "";
    const party = trim(r0.SUPPNAME || r0.SUPPCODE);
    dcs.push({ dc_no: no, dc_date: d0, kind: ret ? "returnable" : "non_returnable", purpose: pur, party_name: party, party_addr: trim(r0.SUPPADD), party_gstin: trim(r0.GSTNo || r0.TIN), vehicle_no: trim(r0.vichicleno), mode: trim(r0.modeofdsp),
      expected_return: er, po_no: po, remarks: "Imported from ERP", status, lines });
    dcset.add(no);
    if (po && !posDc.has(po)) posDc.set(po, { supplier: party, date: DT(r0.PODATE) || d0 });
  }
  // ---- GRNs
  const link = new Map<string, string>(); for (const r of gdc) { if (trim(r.GRNNO) && dcset.has(trim(r.DCNO)) && !link.has(trim(r.GRNNO))) link.set(trim(r.GRNNO), trim(r.DCNO)); }
  const gb = new Map<string, Record<string, string>[]>(); for (const r of grn) { const k = trim(r.INVNO); if (!gb.has(k)) gb.set(k, []); gb.get(k)!.push(r); }
  const dates = new Map<string, Set<string>>(); for (const [k, v] of gb) dates.set(k, new Set(v.map((r) => r.GRNDATE)));
  const grns: Record<string, unknown>[] = []; const poLines = new Map<string, Map<string, { description: string; qty: number; rate: number | null; received: number; bal: number | null }>>(); const poMeta = new Map<string, { supplier: string; date: string }>();
  for (const [no, rs] of gb) {
    if (!no) continue;
    const d0 = rs.map((r) => DT(r.GRNDATE)).find((x) => x) || DT((hdr.get(no) || {}).GRNDATE); if (!d0) continue;
    const key = (dates.get(no)!.size <= 1) ? no : `${no} (${d0})`;
    const h = hdr.get(no) || {}; const r0 = rs[0];
    const po = (rs.find((r) => validpo(r.PONO)) || { PONO: "" }).PONO.trim();
    const dcn = link.get(no) || "";
    const lines: Record<string, unknown>[] = [];
    for (const r of rs) {
      const q = F(r.QTY); if (!q || q <= 0) continue;
      const rej = F(r.REJQTY) || 0, acc = F(r.ACCQTY) || 0, accepted = acc > 0 ? acc : Math.max(0, q - rej);
      const nm = trim(r.rmname), desc = nm && nm !== "-" ? nm : trim(r.RMCODE);
      const rate = F(r.RATE);
      const rem = [rate ? "Rate " + String(r.RATE).replace(/0+$/, "").replace(/\.$/, "") : "", trim(r.BATCH) ? "Batch " + trim(r.BATCH) : "", trim(r.RMTYPE)].filter((x) => x).join(" · ");
      lines.push({ sl: lines.length + 1, item_code: "", description: desc.slice(0, 300), uom: "Nos", received_qty: q, accepted_qty: accepted, rejected_qty: rej, reject_reason: rej > 0 ? trim(r.REASONREJ) : "", remarks: rem });
      if (po) {
        if (!poLines.has(po)) poLines.set(po, new Map());
        const pl = poLines.get(po)!; const k = desc.slice(0, 300);
        if (!pl.has(k)) pl.set(k, { description: k, qty: 0, rate, received: 0, bal: null, });
        const e = pl.get(k)!; e.qty = Math.max(e.qty, F(r.poqty) || q); e.received += q; e.bal = F(r.pobal); e.rate = rate || e.rate;
      }
    }
    if (!lines.length) continue;
    const sup = trim(r0.SUPPLIER || r0.SUPPCODE);
    if (po && !poMeta.has(po)) poMeta.set(po, { supplier: sup, date: d0 });
    const inv = trim(h.SINVNO || h.INVNO || "");
    const st = trim(h.GRNSTATUS || r0.grnstatus || "");
    grns.push({ grn_no: key, grn_date: d0, gtype: dcn ? "dc_return" : (po ? "po_receipt" : "other"), party_name: sup, po_no: po, dc_no: dcn, party_doc_no: inv, party_doc_date: DT(h.invdate), remarks: "Imported from ERP" + (st ? " · status " + st : ""), lines });
  }
  // ---- purchase orders (from GRN lines and challans)
  const pos: Record<string, unknown>[] = [];
  for (const [po, m] of poMeta) {
    const L: Record<string, unknown>[] = []; const es = Array.from(poLines.get(po)!.values());
    for (const e of es) L.push({ sl: L.length + 1, item_code: "", description: e.description, uom: "Nos", qty: Math.max(e.qty, e.received), rate: e.rate, received_qty: e.received });
    const openq = es.some((e) => (e.bal || 0) > 0), rec = es.some((e) => e.received > 0);
    pos.push({ po_no: po, po_date: m.date, supplier_name: m.supplier, status: openq && rec ? "part_received" : "closed", remarks: "Imported from ERP (date = first receipt)", lines: L });
  }
  const have = new Set(pos.map((p) => p.po_no));
  for (const [po, m] of posDc) if (!have.has(po)) pos.push({ po_no: po, po_date: m.date, supplier_name: m.supplier, status: "closed", remarks: "Imported from ERP (from challan)", lines: [] });
  return { pos, dcs, grns };
}
