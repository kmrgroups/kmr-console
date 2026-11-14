import { Tables, rows, cl, nz, trim } from "./common";

const SER: Record<string, string> = { CTS: "Tools (cutting tools)", GAU: "Gauges & instruments", RM: "Raw materials", CONS: "Consumables", OIL: "Consumables", PAC: "Packing material", LC: "Job-work components", SM: "Job-work components", "R&M": "Repairs & maintenance", "P&M": "Repairs & maintenance", "C&F": "Services (clearing & forwarding)" };
const GA = /gauge|gage|micrometer|vernier|caliper|dial indicator|height gauge|plug|snap|thread ring/i;
const TO = /drill|insert|cutter|end ?mill|\btap\b|\btaps\b|reamer|boring|holder|collet|carbide|tnmg|cnmg|dnmg|vnmg|ccmt|dcmt|grinding wheel|\bhss\b|jaws|chuck|broach|punch|\bbit\b|parting|groov|threading|turning tool|milling|\bdie\b|tool/i;
const CO = /grease|oil|coolant|cotton|waste|\bfile\b|emery|paper|glove|tape|brush|cloth|welding|lubric|cleaner|thinner|paint|adhesive|loctite|wd.?40|spray|marker|chalk|soap|detergent|filter|belt|hose|broom|mop|bag|ink|rubber/i;
const SC: Record<string, string> = { "Raw materials": "Raw material", "Tools (cutting tools)": "Tooling", Consumables: "Consumables", "Packing material": "Consumables", "Gauges & instruments": "Gauges & calibration", "Job-work components": "Outsourced process", "Repairs & maintenance": "Services", "Services (clearing & forwarding)": "Services" };
const TT: [string, RegExp][] = [["Insert", /insert|tnmg|cnmg|dnmg|vnmg|ccmt|dcmt|apkt|wnmg|tpmt/i], ["Drill", /drill/i], ["Tap", /\btap/i], ["Reamer", /reamer/i], ["End mill", /end ?mill|milling/i], ["Boring bar", /boring/i]];
const ttype = (t: string) => { for (const [n, p] of TT) if (p.test(t)) return n; return "Other"; };
const Fn = (x: string) => (/^-?[\d,]*\.?\d+$/.test(trim(x)) ? Number(trim(x).replace(/,/g, "")) : 0);
function category(pono: string, rmcode: string): string {
  const m = (pono || "").match(/EPI\/[A-Z]+\/([A-Z&]+)\//); const s = m ? m[1] : "";
  if (s && SER[s]) return SER[s];
  const t = rmcode || "";
  if (GA.test(t)) return "Gauges & instruments"; if (TO.test(t)) return "Tools (cutting tools)"; if (CO.test(t)) return "Consumables"; return "General / others";
}

/** ERP grn + suppliercm -> supplier, tool, consumable and raw-material master rows for kmr_ops_bulk (same rules as the one-time loader). */
export function buildMasters(t: Tables) {
  const g = rows(t.grn).map((r) => ({ c: category(r.PONO, r.RMCODE), grn: r.GRN, date: r.GRNDATE, sup: trim(r.SUPPLIER || r.SUPPCODE), item: trim(r.RMCODE), rate: Fn(r.RATE) }));
  g.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : (a.grn < b.grn ? -1 : a.grn > b.grn ? 1 : 0)));
  const out: { kind: string; code: string; name: string; data: Record<string, unknown>; active: boolean }[] = [];
  const add = (kind: string, code: string, name: string, data: Record<string, unknown>, active = true) => {
    const c = cl(code).slice(0, 80); if (!c) return;
    const d: Record<string, unknown> = {}; for (const [k, v] of Object.entries(data)) if (v !== "" && v !== null && v !== undefined) d[k] = v;
    out.push({ kind, code: c, name: cl(name || c).slice(0, 200), data: d, active });
  };
  const cnt = new Map<string, Map<string, number>>();
  for (const x of g) { const k = nz(x.sup); if (!cnt.has(k)) cnt.set(k, new Map()); const m = cnt.get(k)!; const c = SC[x.c] || ""; m.set(c, (m.get(c) || 0) + 1); }
  const seen = new Set<string>();
  for (const s of rows(t.suppliercm)) {
    const k = nz(s.suppname || s.suppcode); if (seen.has(k)) continue; seen.add(k);
    let cat = ""; const c = cnt.get(k) || cnt.get(nz(s.suppcode));
    if (c) { const e = Array.from(c.entries()).filter(([a]) => a); if (e.length) { let best = e[0]; for (const x of e) if (x[1] > best[1]) best = x; cat = best[0]; } }
    const ph = cl(s.contactno);
    add("suppliers", s.suppcode, s.suppname, { category: cat, address: cl(s.address), contact: cl(s.contactperson), phone: ph.includes("@") ? "" : ph, email: ph.includes("@") ? ph : "", pan: cl(s.panno) }, trim(s.HIDE1 || "NO").toUpperCase() !== "YES");
  }
  const last = new Map<string, (typeof g)[number]>();
  for (const x of g) if (["Tools (cutting tools)", "Consumables", "Packing material", "Raw materials"].includes(x.c) && x.item) last.set(x.c + "|" + nz(x.item), x);
  for (const x of last.values()) {
    const it = cl(x.item);
    if (x.c === "Tools (cutting tools)") add("tools", it, it, { type: ttype(it), source: x.sup, rate: x.rate || "", erp_last_grn: x.date });
    else if (x.c === "Consumables" || x.c === "Packing material") add("consumables", it, it, { supplier: x.sup, rate: x.rate || "", category: x.c === "Packing material" ? "Packing material" : "Consumables", erp_last_grn: x.date });
    else add("raw_materials", it, it, { supplier: x.sup, erp_last_grn: x.date });
  }
  const seen2 = new Set<string>(); return out.filter((r) => { const k = r.kind + "|" + nz(r.code); if (seen2.has(k)) return false; seen2.add(k); return true; });
}
