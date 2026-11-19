/* Budget (BUD) — sample data for the demo (?demo=1). Same answers as the database functions. */
(function () {
  "use strict";
  const HEADS = ["rm", "tool", "cons", "man", "pwr", "out", "mnt"];
  const plan = {}, rates = { "power:kw": 18, "power:tariff": 8.5 };
  const act = { rm: [420000, 380000, 455000], tool: [88000, 61000, 94000], cons: [42000, 39000, 47000], man: [610000, 615000, 620000], pwr: [250000, 240000, 262000], out: [76000, 52000, 81000], mnt: [18000, 0, 31000] };
  const mAdd = (ym, n) => { let y = +ym.slice(0, 4), m = +ym.slice(5, 7) - 1 + n; y += Math.floor(m / 12); m = ((m % 12) + 12) % 12; return y + "-" + String(m + 1).padStart(2, "0"); };
  const cur = new Date(Date.now() + 19800000).toISOString().slice(0, 7);
  window.QP_DEMO = {
    kmr_bud_context() { return { role: "admin", company: "Demo Engineering (sample data)" }; },
    kmr_bud_data(a) {
      const ms = []; for (let m = a.p_from; m <= a.p_to; m = mAdd(m, 1)) ms.push(m);
      const rows = []; ms.forEach((m) => { const k = Math.max(0, Math.min(2, 2 - (+cur.slice(5, 7) - +m.slice(5, 7) + 12) % 12)); HEADS.forEach((h) => { const v = m > cur ? 0 : act[h][k] || 0; rows.push({ head: h, month: m, intake: v ? Math.round(v * (h === "rm" ? 1.1 : 1)) : 0, outward: v, actual: v, basis: v ? (h === "man" ? "payroll" : h === "pwr" ? "run hours" : "bought") : "none", budget: (plan[m + h] || {}).amount || 0, note: (plan[m + h] || {}).note || null, assumed: h === "pwr" ? ["tariff Rs 8 per kWh"] : undefined, missing_rate: h === "tool" ? 2 : 0, qty: h === "rm" ? 5400 : h === "pwr" ? 31000 : 0, unit: h === "rm" ? "kg issued" : h === "pwr" ? "kWh" : undefined }); }); });
      return { months: ms, rows, rates };
    },
    kmr_bud_save(a) { (a.p_rows || []).forEach((r) => { plan[r.month + r.head] = { amount: +r.amount || 0, note: r.note }; }); return (a.p_rows || []).length; },
    kmr_bud_rates() { return { tools: [{ code: "T-101", rate: 420 }, { code: "T-205", rate: null }], cons: [{ code: "COOLANT-20L", rate: 3200 }, { code: "INSERT-CNMG", rate: null }], power: { kw: rates["power:kw"], tariff: rates["power:tariff"] }, dflt: {} }; },
    kmr_bud_rate_save(a) { return (a.p_rows || []).length; }
  };
})();
