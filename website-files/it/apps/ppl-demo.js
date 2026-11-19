/* Production plan (PPL) — sample data for the demo (?demo=1). Same answers as the database functions. */
(function () {
  "use strict";
  const st = { ps: { DEMO100: { safety: 1000, rrs: 500, fg: 800, fi: 200, wip: 0, wip2: 0, inc: 300, sup: 0 } }, stock: [], manual: [], cfg: {} };
  const rt = (m) => [{ seq: 1, name: "CNC TURNING", type: "in", op_no: 10, ct_sec: 40, machine: m[0] }, { seq: 2, name: "GRINDING", type: "in", op_no: 20, ct_sec: 60, machine: m[1] }, { seq: 3, name: "HEAT TREATMENT", type: "supplier", op_no: 30, ct_sec: null, machine: "", supplier: "Sample Heat Treaters" }, { seq: 4, name: "FINAL INSPECTION", type: "in", op_no: 40, ct_sec: 20, machine: m[2] }];
  const parts = () => [
    { part: "DEMO-100", name: "Sample drive shaft", demand: 12000, despatched: 4000, due: null, src: "Sales Flow", route: rt(["CNC-01", "GR-01", "INS-01"]), erp: { "CNC TURNING": 9000, GRINDING: 6500 }, erp_mc: {} },
    { part: "DEMO-200", name: "Sample spacer", demand: 8000, despatched: 8000, due: null, src: "Sales Flow", route: rt(["CNC-02", "GR-01", "INS-01"]), erp: {}, erp_mc: {} },
    { part: "DEMO-300", name: "Sample pin (no route yet)", demand: 3000, despatched: 0, due: null, src: "Sales Flow", route: [], erp: {}, erp_mc: {} }
  ].concat(st.manual.map((m) => ({ part: m.part, name: m.name, demand: +m.qty, despatched: 0, due: m.due, src: "Manual", route: rt(["CNC-02", "GR-01", "INS-01"]), erp: {}, erp_mc: {} })));
  const data = (a) => ({ month: a.p_month, parts: parts(), ps: st.ps, stock: st.stock, manual: st.manual, cfg: st.cfg, last: null });
  window.QP_DEMO = {
    kmr_ppl_context() { return { role: "admin", company: "Demo Engineering (sample data)" }; },
    kmr_ppl_data: data,
    kmr_ppl_save(a) { if (a.p_ps) a.p_ps.forEach((r) => { const k = String(r.part).toUpperCase().replace(/[^A-Z0-9]/g, ""); st.ps[k] = st.ps[k] || {}; Object.keys(r).forEach((f) => { if (f !== "part") st.ps[k][f] = +r[f]; }); }); if (a.p_stock) st.stock = a.p_stock.map((r) => ({ part: r.part, seq: +r.seq, qty: +r.qty })); if (a.p_demand) st.manual = a.p_demand.map((r) => ({ part: r.part, name: r.name, qty: +r.qty, due: r.due, note: r.note })); if (a.p_cfg) Object.keys(a.p_cfg).forEach((k) => (st.cfg[k] = +a.p_cfg[k])); return data(a); },
    kmr_ppl_publish() { return { version: 1 }; },
    kmr_ppl_latest() { return null; }
  };
})();
