import { Tables, rows, num, cl, nz, trim, pyRoundN } from "./common";

/** ERP toolchanging (+ toolchangingold) + product -> production history rows for kmr_mmd_hist_import (same columns as the one-time loader). */
export function buildProduction(t: Tables) {
  const pname = new Map<string, string>(); for (const p of rows(t.product)) pname.set(nz(p.prodcode), cl(p.prodname));
  const H: unknown[][] = [];
  for (const [src, tag] of [["toolchanging", "n"], ["toolchangingold", "o"]] as const) {
    for (const r of rows(t[src])) {
      const d = (r.refdate || "").slice(0, 10); if (!d) continue;
      const pc = cl(r.prodcode), idle = pc.toUpperCase().startsWith("NILL");
      const codes = Array.from(new Set([1, 2, 3, 4, 5, 6, 7].map((i) => r["drea" + i]).filter((v) => v !== undefined && !["", "0", "NILL1"].includes(v)))).sort().join(",");
      const sh = trim(r.shift).toUpperCase().startsWith("NILL") ? "" : cl(r.shift);
      const op = cl(r.operatorno).toUpperCase().startsWith("NILL") ? "" : cl(r.operatorno);
      H.push([tag + r.refno, d, sh, cl(r.machineno), op, idle ? "" : pc, idle ? "" : (pname.get(nz(pc)) || ""), idle ? "No production" : cl(r.process), idle ? "" : cl(r.rmcode), idle ? "" : cl(r.batchno),
        num(r.hours), num(r.qtyprod), num(r.cycletime), num(r.barsused), num(r.scrap), pyRoundN(num(r.EFFCY1), 1), num(r.totalidlehrs), num(r.totalmchrs), num(r.plannedhrs), codes, cl(r.reasons)]);
    }
  }
  return H;
}
