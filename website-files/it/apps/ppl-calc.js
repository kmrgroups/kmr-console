/* Production plan calculation, shared by Production plan and Machine loading plan. */
(function () {
  "use strict";
  /* ---- the netting. Same stage stocks as the Raw Material Plan work sheet (minimum stock, supermarket, FG, FI, WIP, WIP stage 2, incoming, supplier).
     Final need = schedule still to deliver + minimum stock + supermarket - (FG + FI + WIP + WIP2 + incoming + supplier); then worked back process by process,
     taking off the stock held after each process (typed in, or from ERP production when no WIP is entered). ---- */
  const nk = (c) => String(c || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  function calc(d) {
    const cfg = d.cfg || {}, hpd = +cfg.hpd || 16, eff = (+cfg.eff || 85) / 100, days = +cfg.days || 26;
    const man = {}; (d.stock || []).forEach((s) => { man[s.part + "|" + s.seq] = +s.qty; });
    const rows = [], parts = [];
    (d.parts || []).forEach((p) => {
      const net = Math.max(0, (+p.demand || 0) - (+p.despatched || 0)), b = (d.ps || {})[nk(p.part)] || {}, v = (k) => +b[k] || 0;
      const held = v("fg") + v("fi") + v("wip") + v("wip2") + v("inc") + v("sup"), want = net + v("safety") + v("rrs");
      const final = Math.max(0, want - held), bucketWip = v("wip") + v("wip2") > 0;
      const rt = p.route || [], erp = p.erp || {};
      const stock = rt.map((o, i) => {
        const k = p.part + "|" + o.seq;
        if (i === rt.length - 1) return { q: 0, src: "none" };
        if (man[k] != null) return { q: man[k], src: "Entered" };
        const a = erp[(o.name || "").toUpperCase()], c = erp[(rt[i + 1].name || "").toUpperCase()];
        if (!bucketWip && a != null) return { q: Math.max(0, a - (c || 0)), src: "ERP" };
        return { q: 0, src: "none" };
      });
      let need = final; const out = [];
      for (let i = rt.length - 1; i >= 0; i--) {
        const have = stock[i].q, mk = Math.max(0, need - have), o = rt[i], ct = +o.ct_sec || 0;
        out[i] = { part: p.part, name: p.name, seq: o.seq, stage: o.name, type: o.type, ct, req: need, stock: have, ssrc: stock[i].src, make: mk,
          hrs: o.type === "supplier" ? 0 : mk * ct / 3600, machine: o.type === "supplier" ? "Supplier" + (o.supplier ? ": " + o.supplier : "") : (o.machine || (p.erp_mc || {})[(o.name || "").toUpperCase()] || "Unassigned"), due: p.due };
        need = mk;
      }
      out.forEach((r) => rows.push(r));
      const blanks = out.length ? Math.max(0, out[0].make - v("inc")) : 0;
      parts.push({ part: p.part, name: p.name, demand: +p.demand || 0, despatched: +p.despatched || 0, net, safety: v("safety"), sup: v("rrs"), fg: v("fg"), fi: v("fi"), wip: v("wip"), wip2: v("wip2"), inc: v("inc"), supl: v("sup"), held, want, final, blanks,
        src: p.src, due: p.due, stages: out.length, noRoute: !rt.length, noCt: rt.some((o) => o.type !== "supplier" && !(+o.ct_sec > 0)), first: out[0], last: out[out.length - 1] });
    });
    const mc = {};
    rows.forEach((r) => { if (r.type === "supplier") return; const m = mc[r.machine] || (mc[r.machine] = { machine: r.machine, qty: 0, hrs: 0, items: [] }); m.qty += r.make; m.hrs += r.hrs; if (r.make > 0) m.items.push(r); });
    const mach = Object.values(mc).filter((m) => m.hrs > 0 || m.items.length).sort((a, b) => b.hrs - a.hrs).map((m) => ({ ...m, days: m.hrs / (hpd * eff), cap: hpd * eff * days, load: 100 * m.hrs / (hpd * eff * days) }));
    return { cfg: { hpd, eff: eff * 100, days }, rows, parts, mach };
  }
  window.PPLCalc = { calc, nk };
})();
