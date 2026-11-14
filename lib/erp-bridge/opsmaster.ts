import { Tables, rows, trim } from "./common";

type Rec = { kind: string; code: string; name: string; active: boolean; data: Record<string, unknown> };
const nzd = (d: Record<string, unknown>) => { const o: Record<string, unknown> = {}; for (const [k, v] of Object.entries(d)) if (v !== "" && v !== null && v !== undefined) o[k] = v; return o; };
const numN = (v: unknown): number | null => { const s = trim(v); if (s === "") return null; const n = Number(s); return Number.isFinite(n) ? n : null; };
const T = (v: unknown, n: number) => trim(v).slice(0, n);
const mtype = (t0: string) => { const t = trim(t0).toUpperCase(); if (t.includes("HMC")) return "HMC"; if (t.includes("VMC")) return "VMC"; if (t.includes("TURN")) return "CNC Turning"; if (t.includes("GRIND")) return "Grinding"; if (t.includes("PRESS")) return "Press"; if (t.startsWith("MSA")) return "Assembly"; return "Other"; };
function dedupe(R: Rec[]) { const cc = new Map<string, number>(); for (const r of R) { const n = (cc.get(r.code) || 0) + 1; cc.set(r.code, n); if (n > 1) r.code = r.code.slice(0, 74) + ` #${n}`; } }

/** ERP customer, product, machine, supplier, raw material, cycle time and customer PO tables -> Operations Master rows for kmr_ops_bulk. */
export function buildOpsMaster(t: Tables, today: string) {
  const out: Rec[] = [];
  const cust = rows(t.customer); const cname = new Map<string, string>(); for (const x of cust) cname.set(trim(x.custcode), trim(x.custname));
  for (const x of cust) {
    const cn = trim(x.contactno), em = cn.includes("@") ? cn : "", ph = cn.includes("@") ? "" : cn;
    out.push({ kind: "customers", code: T(x.custcode, 80), name: T(x.custname, 200), active: trim(x.HIDE1).toUpperCase() !== "YES", data: nzd({
      gstin: trim(x.Billgstno) || trim(x.kstcst), city: trim(x.CITY), country: trim(x.Country1), email: em, phone: ph, supplier_code: trim(x.vendorcode) !== "0" ? trim(x.vendorcode) : "", address: trim(x.address) }) });
  }
  // parts
  const po = rows(t.pomaster), tpo = rows(t.tpomaster); const pocust = new Map<string, string>(), povalid = new Map<string, string>();
  for (const x of po) { pocust.set(trim(x.pono), trim(x.custcode)); povalid.set(trim(x.pono), x.validdate); }
  const pc = new Map<string, string[]>(), lastpo = new Map<string, string>();
  const addc = (p: string, c: string) => { if (!pc.has(p)) pc.set(p, []); if (c && !pc.get(p)!.includes(c)) pc.get(p)!.push(c); };
  for (const x of rows(t.tcustprod)) addc(trim(x.PRODCODE), trim(x.CUSTCODE));
  for (const x of tpo) { const p = trim(x.prodcode), c = pocust.get(trim(x.pono)) || ""; addc(p, c); const v = povalid.get(trim(x.pono)) || ""; const o = lastpo.get(p) || ""; lastpo.set(p, v > o ? v : o); }
  const activeSince = (parseInt(today.slice(0, 4), 10) - 1) + "-01-01";   // active when a customer PO valid on or after 1 Jan of last year exists
  const parts: Rec[] = [];
  for (const x of rows(t.product)) {
    const p = trim(x.prodcode); if (!p) continue;
    const cs = (pc.get(p) || []).map((c) => cname.get(c) || c);
    let rm = trim(x.rmcode); if (["NIL", "NA", "N/A", "0"].includes(rm.toUpperCase())) rm = "";
    const w = numN(x.wtreq);
    parts.push({ kind: "parts", code: T(p, 80), name: T(x.prodname, 200), active: (lastpo.get(p) || "") >= activeSince, data: nzd({ customer: cs.join(", "), drawing_no: !["1", "0"].includes(trim(x.drgno)) ? trim(x.drgno) : "", revision: trim(x.drgrevision), material: rm, weight_kg: w || null }) });
  }
  out.push(...parts);
  // suppliers
  const sub = new Set(rows(t.subcontractor).map((x) => trim(x.subcontcode))); const suppliers: Rec[] = [];
  for (const x of rows(t.supplier)) {
    const c = trim(x.suppcode); if (!c) continue;
    const cat = sub.has(c) ? "Outsourced process" : (trim(x.vtype) === "M" ? "Raw material" : "Services");
    const cn = trim(x.contactno); let em = cn.includes("@") ? cn : ""; em = em || (trim(x.kstcst).includes("@") ? trim(x.kstcst) : "");
    suppliers.push({ kind: "suppliers", code: T(c, 80), name: T(x.suppname, 200), active: trim(x.HIDE1).toUpperCase() !== "YES", data: nzd({ category: cat, gstin: trim(x.GSTNO), city: trim(x.City1), contact: trim(x.contactperson), email: em, phone: cn.includes("@") ? "" : cn }) });
  }
  out.push(...suppliers);
  // machines
  for (const x of rows(t.machine)) {
    const c = trim(x.machineno); if (!c) continue; const hid = trim(x.HIDE1).toUpperCase() === "YES";
    const eff = numN(x.EFFCY);
    const rem = "ERP type: " + trim(x.mctype) + (eff ? " · ERP efficiency " + trim(x.EFFCY) + "%" : "") + (trim(x.mslno) ? " · S/N " + trim(x.mslno) : "");
    out.push({ kind: "machines", code: T(c, 80), name: T(x.machinename, 200), active: !hid, data: nzd({ type: mtype(x.mctype), cell: trim(x.location), status: hid ? "Scrapped" : "Running", remarks: rem }) });
  }
  // raw materials with latest rate / supplier
  const rates = new Map<string, [string, number | null, string]>();
  for (const x of rows(t.trawmaterial)) {
    if (trim(x.HIDE1).toUpperCase() === "YES") continue;
    const k = trim(x.rmcode); let d = trim(x.DATE2) || trim(x.DATE1); const m = d.match(/^(\d{4})\/(\d\d)\/(\d\d)$/); d = m ? `${m[1]}-${m[2]}-${m[3]}` : "0000-" + d;
    const cur = rates.get(k); if (!cur || d >= cur[0]) rates.set(k, [d, numN(x.rate), trim(x.suppcode)]);
  }
  const sname = new Map(suppliers.map((x) => [x.code, x.name])); 
  for (const x of rows(t.rawmaterial)) {
    const c = trim(x.rmcode); if (!c) continue; const r = rates.get(c);
    out.push({ kind: "raw_materials", code: T(c, 80), name: T(x.rmname, 200), active: trim(x.hide1).toUpperCase() !== "YES", data: nzd({ grade: trim(x.tolerence), specification: trim(x.ordspec), form: ["Bar", "Forging", "Casting", "Sheet", "Tube"].includes(trim(x.rmform)) ? trim(x.rmform) : "", size: trim(x.rmsize), supplier: r ? (sname.get(r[2]) || r[2]) : "", rate_per_kg: r && r[1] ? r[1] : null }) });
  }
  // cycle times: part + operation sequence
  const partIdx = new Map(parts.map((x) => [x.code, x])); const seen = new Map<string, number>(); const ct: Rec[] = [];
  for (const x of rows(t.tproduct)) {
    const p = trim(x.prodcode), op = trim(x.process), c = numN(x.cycletime);
    if (!p || !op || !partIdx.has(p) || !c) continue;
    seen.set(p, (seen.get(p) || 0) + 1); const rk = numN(x.RANK); const seq = Math.trunc(rk || seen.get(p)!);
    ct.push({ kind: "cycle_times", code: T(`${p} / OP${String(seq).padStart(2, "0")} ${op}`, 80), name: T(op, 200), active: partIdx.get(p)!.active, data: nzd({ part_no: p, cycle_time_sec: c }) });
  }
  dedupe(ct); out.push(...ct);
  // rate contracts: customer PO lines
  const pod = new Map(po.map((x) => [trim(x.pono), x])); const rc: Rec[] = [];
  for (const x of tpo) {
    const pn = trim(x.pono), h = pod.get(pn), rt = numN(x.rate); if (!h || !rt) continue;
    const ord = numN(x.ordqty), pay = numN(h.payterms);
    rc.push({ kind: "rate_contracts", code: T(`${pn} / ${trim(x.lineno)}`, 80), name: T(cname.get(trim(h.custcode)) || trim(h.custcode), 200), active: h.validdate >= today,
      data: nzd({ party_type: "Customer", item: trim(x.prodcode), rate: rt, valid_from: h.podate, valid_to: h.validdate, terms: (pay ? "Payment " + trim(h.payterms) + " days" : "") + (ord ? " · PO qty " + trim(x.ordqty) : "") }) });
  }
  dedupe(rc); out.push(...rc);
  return out;
}
