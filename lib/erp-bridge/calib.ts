import { Tables, rows, num, trim, low, isoDate, pyTitle, isUpper, isLower, dayDiff, addDays } from "./common";

const D = (s: unknown) => isoDate(s);
const title = (s: unknown) => { const t = trim(s); return isUpper(t) || isLower(t) ? pyTitle(t) : t; };
const pyRound = (x: number) => { const f = Math.floor(x), d = x - f; return d < 0.5 ? f : d > 0.5 ? f + 1 : (f % 2 === 0 ? f : f + 1); };
const test = (re: RegExp, s: string) => re.test(s);

function catInst(d0: string): string | null {
  const d = low(d0);
  if (/height/.test(d)) return "height";
  if (/master|air gauge|assembl|assly|position|distance|symmetry|carbide|special|wear check|bush/.test(d)) return null;
  if (/thread plug|tpg|wear check thread/.test(d)) return "tplug";
  if (/thread ring|trg/.test(d)) return "tring";
  if (/snap|gagu/.test(d)) return "snap";
  if (/flush|flesh|flu pin/.test(d)) return "flush";
  if (/width/.test(d)) return "width";
  if (/plain ring|ring gauge|go ring|^ring$/.test(d)) return "ring";
  if (/plug|pluge/.test(d)) return "plug";
  if (/micromet|micmetr|micrmt|ext mic/.test(d)) return "mic";
  if (/vernier|caliper|calliper|calli/.test(d)) return "vernier";
  if (/dial|plunger|millimess|zentimess|lever/.test(d)) return "dial";
  return null;
}
function catGrn(t0: string): string | null {
  const t = low(t0);
  if (/^0~150 mm$|^0~200 mm$|vernier|caliper|calli|^25~50 mm$|^50~75 mm$/.test(t)) return "vernier";
  if (/thread plug/.test(t)) return "tplug";
  if (/thread ring/.test(t)) return "tring";
  if (/snap/.test(t)) return "snap";
  if (/flush|flu pin/.test(t)) return "flush";
  if (/width/.test(t)) return "width";
  if (/plain ring|ring gauge/.test(t)) return "ring";
  if (/plain pl|plain pg|plug/.test(t)) return "plug";
  if (/micrometer|micromet|micmetr|micrmt|ext micro/.test(t)) return "mic";
  if (/dial|plunge|millimess|zentimess|lever|inter test/.test(t)) return "dial";
  if (/height/.test(t)) return "height";
  return null;
}
void test;
type Rec = { cal_date: string; next_due: string; lab?: string; kind?: string; cost?: number; remarks?: string; cert_no?: string };
type Rcp = { d: string; lab: string; cost: number | null; grn: string | null; tag?: string };

/** ERP instruments + calibstock + receiptcalib + inhousecalib + historycard + grn + supplier + subcontractor -> gauge rows for kmr_cal_import_erp. */
export function buildCalibration(t: Tables, unit: string) {
  const ins = rows(t.instruments), cs = rows(t.calibstock), rc = rows(t.receiptcalib), ih = rows(t.inhousecalib), hc = rows(t.historycard), grn = rows(t.grn);
  const sub = new Map<string, string>(); for (const r of rows(t.subcontractor)) sub.set(low(r.subcontcode), trim(r.subcontname));
  const sup = new Map<string, string>(); for (const r of rows(t.supplier)) sup.set(low(r.suppcode), trim(r.suppname));
  const labname = (code: string) => sup.get(low(code)) || sub.get(low(code)) || trim(code);
  const tags = new Map<string, Record<string, string>>(); for (const r of ins) if (trim(r.INSTCODE)) tags.set(trim(r.INSTCODE), r);
  const tcat = new Map<string, string | null>(); for (const [k, r] of tags) tcat.set(k, catInst(r.DESCP));
  const rcs = new Map<string, Rcp[]>();
  for (const r of rc) { const k = trim(r.INSTCODE), d = D(r.ISSDATE); if (tags.has(k) && d && trim(r.SUBCONTCODE)) { if (!rcs.has(k)) rcs.set(k, []); rcs.get(k)!.push({ d, lab: trim(r.SUBCONTCODE), cost: null, grn: null }); } }
  const labl = new Set<string>(); for (const v of rcs.values()) for (const x of v) labl.add(low(x.lab));
  const glines = grn.filter((r) => labl.has(low(r.SUPPCODE)) && D(r.GRNDATE) && num(r.RATE) > 0 && num(r.QTY) > 0).sort((a, b) => (a.GRNDATE < b.GRNDATE ? -1 : a.GRNDATE > b.GRNDATE ? 1 : 0));
  const pool = new Map<string, Rcp[]>();
  for (const [k, v] of rcs) for (const x of v) { x.tag = k; const p = low(x.lab); if (!pool.has(p)) pool.set(p, []); pool.get(p)!.push(x); }
  for (const v of pool.values()) v.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0));
  for (const g of glines) {
    const c = catGrn(g.RMCODE); if (!c) continue;
    const gd = D(g.GRNDATE)!, q = pyRound(num(g.QTY)), rate = num(g.RATE);
    const cand = (pool.get(low(g.SUPPCODE)) || []).filter((x) => x.cost === null && tcat.get(x.tag!) === c && addDays(gd, -45) <= x.d && x.d <= addDays(gd, 3));
    cand.sort((a, b) => Math.abs(dayDiff(gd, a.d)) - Math.abs(dayDiff(gd, b.d)));
    for (const x of cand.slice(0, Math.max(0, q))) { x.cost = rate; x.grn = g.GRN; }
  }
  // ---- history records
  const hist = new Map<string, Map<string, Rec>>(); const H = (k: string) => { if (!hist.has(k)) hist.set(k, new Map()); return hist.get(k)!; };
  for (const r of cs) { const k = trim(r.instcode), cd = D(r.calibdate); if (tags.has(k) && cd) { const h = H(k); if (!h.has(cd)) h.set(cd, { cal_date: cd, next_due: D(r.duedate) || "" }); } }
  for (const [k, r] of tags) { const cd = D(r.calibdate); if (cd && !H(k).has(cd)) H(k).set(cd, { cal_date: cd, next_due: D(r.duedate) || "" }); }
  const inh = new Map<string, string[]>(); for (const r of ih) { const k = trim(r.INSTCODE), d = D(r.ISSDATE); if (tags.has(k) && d) { if (!inh.has(k)) inh.set(k, []); inh.get(k)!.push(d); } }
  const certs = new Map<string, [string, string, string][]>(); for (const r of hc) { const k = trim(r.instcode), d = D(r.recfromcalib) || D(r.instdate); if (tags.has(k) && d) { if (!certs.has(k)) certs.set(k, []); certs.get(k)!.push([d, trim(r.certificateno), trim(r.remarks)]); } }
  for (const [k, h] of hist) {
    const recs = rcs.get(k) || [];
    for (const [cd, rec] of h) {
      let best: [number, number] | null = null;
      recs.forEach((x, i) => { const dd = Math.abs(dayDiff(x.d, cd)); if (dd <= 10 && (best === null || dd < best[0])) best = [dd, i]; });
      if (best) {
        const x = recs[(best as [number, number])[1]]; rec.lab = labname(x.lab); rec.kind = "External";
        if (x.cost !== null) { rec.cost = x.cost; rec.remarks = `Cost from GRN ${x.grn} (rate per piece)`; }
      } else if ((inh.get(k) || []).some((d) => Math.abs(dayDiff(d, cd)) <= 10)) { rec.lab = "In-house"; rec.kind = "Internal"; }
      for (const [d, cn, rm] of certs.get(k) || []) if (Math.abs(dayDiff(d, cd)) <= 5) { rec.cert_no = cn; rec.remarks = ((rec.remarks || "") + " " + rm).trim(); }
    }
  }
  // ---- supplier from GRN via PO
  const supby = new Map<string, string>();
  if (ins.length && "PONO" in ins[0]) {
    const bypo = new Map<string, Record<string, string>[]>(); for (const g of grn) if (trim(g.PONO)) { const p = trim(g.PONO).toLowerCase(); if (!bypo.has(p)) bypo.set(p, []); bypo.get(p)!.push(g); }
    for (const [k, r] of tags) { const p = trim(r.PONO).toLowerCase(); if (p && bypo.has(p)) supby.set(k, labname(bypo.get(p)!.slice().sort((a, b) => (a.GRNDATE < b.GRNDATE ? -1 : a.GRNDATE > b.GRNDATE ? 1 : 0))[0].SUPPCODE)); }
  }
  const out: Record<string, unknown>[] = [];
  for (const k of Array.from(tags.keys()).sort()) {
    const r = tags.get(k)!; const w = num(r.CALIBRATION1);
    const fm = w > 0 ? Math.max(1, pyRound(w * 7 / 30.4)) : 12;
    const scrap = trim(r.SCRAP1).toUpperCase() === "YES", ist = trim(r.INSTSTATUS).toUpperCase();
    const status = scrap ? "Scrapped" : (ist === "ONHOLD" ? "Out of service" : "In use");
    const loc = ["production", "quality"].includes(trim(r.LOCATION1).toLowerCase()) ? title(r.LOCATION1) : "";
    const recsl = Array.from(H(k).values()).sort((a, b) => (a.cal_date < b.cal_date ? -1 : a.cal_date > b.cal_date ? 1 : 0));
    const lastlab = [...recsl].reverse().find((x) => x.lab)?.lab || "";
    const notes = ["Imported from " + unit + " ERP"]; if (ist) notes.push("ERP status: " + ist);
    if (trim(r.CUSTCODE)) notes.push("ERP owner code: " + trim(r.CUSTCODE));
    const pd = D(r.PURDATE); if (pd && Number(pd.slice(0, 4)) >= 1990) notes.push("Purchased: " + r.PURDATE);
    if (trim(r.REFNO) && trim(r.REFNO) !== "0") notes.push("Ref no: " + trim(r.REFNO));
    const row: Record<string, unknown> = { tag: k, name: title(r.DESCP) || k, itype: title(r.DESCP), make: title(r.MAKE1), serial_no: trim(r.IDSLNO), range_text: trim(r.RANGE1), least_count: trim(r.LEASTCOUNT1), location: loc,
      freq_months: fm, lab: lastlab, supplier: supby.get(k) || lastlab, status, notes: notes.join(" | "), last_cal: r.calibdate, next_due: r.duedate, history: recsl };
    if (scrap) { const sd = D(r.SCRAPDATE); row.scrapped_on = sd && Number(sd.slice(0, 4)) >= 1990 ? sd : ""; row.scrap_reason = "Scrapped in ERP"; }
    out.push(row);
  }
  return out;
}
