/* Raw Material Planning — monthly plan and budget (the "RM planning" Excel sheets). Calculation only, kept apart from the screen so it can be tested.
   For each part line (part + material from the bill of material):
     schedule      = Sales Flow schedule of this plant for the month; if Sales Flow has none, the quantity typed by the plant in-charge
     balance (pcs) = schedule + safety stock + super-market (RRS) qty − despatched so far (Sales Flow) − WIP − WIP stage 2
     material qty  = balance × kg (or pieces) per piece
   For each material:
     needed   = sum of the material qty of its parts            available = stock on hand
     balance  = needed − available                               to buy    = max(0, balance)
     planned  = sum of the weekly planned quantities             received  = sum of the weekly received quantities
     net      = planned × rate / 1,00,000 (₹ lakh)               gross     = net × (1 + GST %)
     actual   = received × rate / 1,00,000 (and gross)
   A company adds up its plants. */
(function (g) {
  "use strict";
  const n = (v) => { const x = Number(v); return isFinite(x) ? x : 0; };
  const LAKH = 100000;

  function plant(p) {
    const lines = (p.lines || []).map((l, idx) => {
      const hasSales = l.sales !== null && l.sales !== undefined;
      const sched = hasSales ? n(l.sales) : n(l.manual);
      const bal = sched + n(l.safety) + n(l.rrs) - n(l.despatched) - n(l.wip) - n(l.wip2);
      return Object.assign({}, l, { idx, src: hasSales ? "sales" : (l.manual !== null && l.manual !== undefined ? "typed" : "none"), sched, bal, qty: bal * n(l.factor) });
    });
    const mats = (p.materials || []).map((m) => {
      const mine = lines.filter((l) => l.material_code === m.code);
      const need = mine.reduce((a, l) => a + l.qty, 0);
      const wk = [1, 2, 3, 4, 5].map((w) => { const x = (m.weeks || []).find((y) => y.w === w); return { w, p: x ? n(x.p) : 0, r: x ? n(x.r) : 0 }; });
      const planned = wk.reduce((a, x) => a + x.p, 0), received = wk.reduce((a, x) => a + x.r, 0);
      const rate = m.rate === null || m.rate === undefined ? null : n(m.rate), gst = n(m.gst);
      const balance = need - n(m.on_hand), toBuy = Math.max(0, balance);
      const net = planned * n(rate) / LAKH, aNet = received * n(rate) / LAKH;
      return Object.assign({}, m, { parts: mine, need, balance, toBuy, wk, planned, received, gap: toBuy - planned, net, gross: net * (1 + gst / 100), aNet, aGross: aNet * (1 + gst / 100), noRate: rate === null && (planned > 0 || toBuy > 0) });
    });
    const t = mats.reduce((a, m) => ({ net: a.net + m.net, gross: a.gross + m.gross, aNet: a.aNet + m.aNet, aGross: a.aGross + m.aGross, short: a.short + (m.toBuy > 0 && m.gap > 0.5 ? 1 : 0), buy: a.buy + (m.toBuy > 0 ? 1 : 0), norate: a.norate + (m.noRate ? 1 : 0) }), { net: 0, gross: 0, aNet: 0, aGross: 0, short: 0, buy: 0, norate: 0 });
    return Object.assign({ id: p.id, name: p.name, code: p.code, lines, mats, parts: new Set(lines.map((l) => l.part_code)).size, noSales: lines.filter((l) => l.src !== "sales" && l.sched > 0).length }, t);
  }
  function company(plants) {
    return plants.reduce((a, p) => ({ net: a.net + p.net, gross: a.gross + p.gross, aNet: a.aNet + p.aNet, aGross: a.aGross + p.aGross, buy: a.buy + p.buy, short: a.short + p.short, parts: a.parts + p.parts }), { net: 0, gross: 0, aNet: 0, aGross: 0, buy: 0, short: 0, parts: 0 });
  }
  g.RMPMonth = { plant, company };
  if (typeof module !== "undefined") module.exports = g.RMPMonth;
})(typeof window !== "undefined" ? window : globalThis);
