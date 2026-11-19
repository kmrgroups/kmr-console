/* Machine loading plan (MLP): finite-capacity loading of the Production plan on a monthly calendar.
   Every machine has a fixed number of hours per working day (plant standards: hours per day x OEE; weekly off and HRM holidays are not working days).
   Parts are loaded in due-date order, process by process, from today. The result says, part by part, whether the customer due date can be met.
   When it cannot, "balanced" loading moves or splits operations to other machines that have run the same process (or are listed as alternates in the cycle-time master),
   and what is still late is turned into a number of extra machines. Same ideas as the Capacity Planner (alternates, levelling, weekly off, holidays). */
(function () {
  "use strict";
  const { $, esc, say, call } = QP;
  const { calc } = window.PPLCalc;
  const S = { go: null, month: "", d: null, c: null, scen: "plan", R: null };
  const DAY = 86400000, HZ = 150;
  const td = () => new Date(Date.now() + 19800000).toISOString().slice(0, 10);
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], DOW = "SMTWTFS";
  const mlong = (ym) => MON[+ym.slice(5, 7) - 1] + " " + ym.slice(0, 4);
  const n0 = (v) => (v == null || v === "" ? "–" : Math.round(+v).toLocaleString("en-IN"));
  const n1 = (v) => (v == null ? "–" : (+v).toLocaleString("en-IN", { maximumFractionDigits: 1 }));
  const canEdit = () => QP.canEdit;
  const hashGo = () => { const m = location.hash.match(/go=([a-z]+)/); return m ? m[1] : "std"; };
  const T = (html) => '<div class="sc">' + html + "</div>";
  const rep = (title, no) => { if (window.KMRReport) window.KMRReport.set({ title, doc: "", format: "KMR/MLP/F-" + no, rev: "01", date: "2026-11-19" }); };
  const tms = (s) => new Date(s + "T00:00:00Z").getTime(), iso = (t) => new Date(t).toISOString().slice(0, 10);
  const dd = (t) => { const x = new Date(t); return String(x.getUTCDate()).padStart(2, "0") + " " + MON[x.getUTCMonth()]; };
  const chip = (t, c) => '<span class="chip ' + c + '">' + t + "</span>";
  const tile = (l, v, c, sub) => '<div class="tile" style="--c:' + c + '"><small class="mut">' + l + "</small><b style='display:block;font-size:22px'>" + v + "</b>" + (sub ? "<small class='mut'>" + sub + "</small>" : "") + "</div>";
  const nm = (r) => "<b>" + esc(r.part) + "</b><br><small class='mut'>" + esc(r.name || "") + "</small>";
  const hue = (s) => { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360; return "hsl(" + h + ",58%,42%)"; };
  const nk = (c) => String(c || "").toUpperCase().replace(/[^A-Z0-9]/g, "");

  (function () {
    const top = $("#top"), cb = $("#ahc"); let on = true; try { on = localStorage.getItem("mlp-ah") !== "0"; } catch (e) { /* ignore */ }
    const apply = () => { document.body.classList.toggle("ah", on); cb.checked = on; top.classList.remove("show"); };
    const show = () => top.classList.add("show");
    $("#rev").addEventListener("mouseenter", show); $("#pill").addEventListener("click", show);
    top.addEventListener("mouseleave", () => { if (document.body.classList.contains("ah")) setTimeout(() => { if (!top.matches(":hover")) top.classList.remove("show"); }, 250); });
    document.addEventListener("click", (e) => { if (document.body.classList.contains("ah") && !top.contains(e.target) && e.target.id !== "pill") top.classList.remove("show"); });
    top.addEventListener("click", (e) => { if (e.target.closest(".tab") && document.body.classList.contains("ah")) setTimeout(() => top.classList.remove("show"), 150); });
    cb.addEventListener("change", () => { on = cb.checked; try { localStorage.setItem("mlp-ah", on ? "1" : "0"); } catch (e) { /* ignore */ } apply(); });
    apply();
  })();

  /* ------------------------------------------------------------------ finite-capacity loading */
  function params(d) {
    const cfg = d.cfg || {}, sd = d.std || {};
    const hpd = +cfg.hpd || +sd.hoursPerDay || 16, eff = +cfg.eff || +sd.oee || 85;
    let woff = cfg.woff != null ? +cfg.woff : (/^none$/i.test(String(sd.weeklyOff || "")) ? -1 : DOW.length ? ({ sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 }[String(sd.weeklyOff || "sunday").toLowerCase()] ?? 0) : 0);
    return { hpd, eff, cap: hpd * eff / 100, woff, lag: cfg.wait != null ? +cfg.wait : 1, supd: cfg.supd != null ? +cfg.supd : 5 };
  }
  function load(d, C, scen) {
    const P = params(d), ym = S.month, m0 = tms(ym + "-01"), y = +ym.slice(0, 4), mo = +ym.slice(5, 7), dim = new Date(Date.UTC(y, mo, 0)).getUTCDate();
    const today = tms(d.today || td()), i0 = Math.max(0, Math.min(HZ - 1, Math.round((today - m0) / DAY))), hol = new Set(d.holidays || []);
    const work = [], cap = [];
    for (let i = 0; i < HZ; i++) { const t = m0 + i * DAY, dw = new Date(t).getUTCDay(); const w = i >= i0 && dw !== P.woff && !hol.has(iso(t)); work.push(w); cap.push(w ? P.cap : 0); }
    const used = {}, U = (m) => used[m] || (used[m] = new Array(HZ).fill(0));
    const alts = {}; (d.alts || []).forEach((a) => { alts[nk(a.part) + "|" + a.process] = a.alts || []; });
    const trial = (m, ready, hrs) => { const u = U(m); let rem = hrs, i = Math.max(ready, 0), start = -1; while (rem > 1e-9 && i < HZ) { const f = cap[i] - u[i]; if (f > 1e-9) { if (start < 0) start = i; rem -= Math.min(f, rem); } i++; } return { start: start < 0 ? Math.max(ready, 0) : start, end: rem > 1e-9 ? HZ : i - 1 }; };
    const commit = (m, ready, hrs) => { const u = U(m), segs = []; let rem = hrs, i = Math.max(ready, 0), start = -1; while (rem > 1e-9 && i < HZ) { const f = cap[i] - u[i]; if (f > 1e-9) { const t = Math.min(f, rem); u[i] += t; rem -= t; segs.push([i, t]); if (start < 0) start = i; } i++; } return { start: start < 0 ? Math.max(ready, 0) : start, end: rem > 1e-9 ? HZ : i - 1, segs }; };
    const byP = {}; C.rows.filter((r) => r.make > 0).forEach((r) => (byP[r.part] = byP[r.part] || []).push(r));
    const dueIdx = (r) => (r.due ? Math.round((tms(String(r.due).slice(0, 10)) - m0) / DAY) : dim - 1);
    const plist = Object.keys(byP).map((pc) => { const st = byP[pc].sort((a, b) => a.seq - b.seq); return { pc, st, due: dueIdx(st[0]), hrs: st.reduce((a, r) => a + r.hrs, 0) }; }).sort((a, b) => a.due - b.due || b.hrs - a.hrs);
    const ops = [], parts = [];
    plist.forEach((p) => {
      let ready = i0, prevStart = i0, prevEnd = i0, prevSup = false; const items = [];
      p.st.forEach((r) => {
        let o;
        if (r.type === "supplier") { const s = Math.max(ready, prevEnd + 1); o = { ...r, mach: r.machine, start: s, end: s + Math.max(1, Math.round(P.supd)), segs: [], moved: false, sup: true }; ready = o.end + 1; prevSup = true; }
        else {
          const rd = prevSup ? ready : Math.max(ready, i0), prim = r.machine || "Unassigned";
          let pick = [{ m: prim, h: r.hrs }], moved = false;
          if (scen === "bal" && r.hrs > 0) {
            const cand = [prim].concat(alts[nk(r.part) + "|" + String(r.stage).toUpperCase()] || [], (d.cand || {})[String(r.stage).toUpperCase()] || []).filter((x, i, a) => x && a.indexOf(x) === i).slice(0, 14);
            const pe = trial(prim, rd, r.hrs).end;
            if (pe > p.due && cand.length > 1) {
              let best = { end: pe, pick }, tr = cand.map((m) => ({ m, e: trial(m, rd, r.hrs).end })).sort((a, b) => a.e - b.e);
              if (tr[0].e < best.end) best = { end: tr[0].e, pick: [{ m: tr[0].m, h: r.hrs }] };
              [2, 3].forEach((k) => { const ts = cand.map((m) => ({ m, e: trial(m, rd, r.hrs / k).end })).sort((a, b) => a.e - b.e).slice(0, k); if (ts.length === k && ts[k - 1].e < best.end) best = { end: ts[k - 1].e, pick: ts.map((x) => ({ m: x.m, h: r.hrs / k })) }; });
              pick = best.pick; moved = pick.length > 1 || pick[0].m !== prim;
            }
          }
          let s = HZ, e = 0; const segs = [];
          pick.forEach((x) => { const c = commit(x.m, rd, x.h); s = Math.min(s, c.start); e = Math.max(e, c.end); c.segs.forEach((g) => segs.push([x.m, g[0], g[1]])); });
          if (e < prevEnd + 1 && items.length) e = Math.min(HZ, prevEnd + 1);
          o = { ...r, mach: pick.map((x) => x.m).join(" + "), start: s, end: e, segs, moved, prim, pick, sup: false };
          ready = Math.max(i0, s + Math.round(P.lag)); prevSup = false;
        }
        prevStart = o.start; prevEnd = o.end; items.push(o);
      });
      const first = items[0].start, last = Math.max(...items.map((x) => x.end)), lateD = last - p.due;
      items.forEach((o) => { o.dueIdx = p.due; o.over = o.segs.filter((g) => (g[1]) > p.due).reduce((a, g) => a + g[2], 0); ops.push(o); });
      parts.push({ part: p.pc, name: p.st[0].name, due: p.due, first, last, tpt: last - first + 1, late: Math.max(0, lateD), hrs: p.hrs, items, qty: p.st[p.st.length - 1].make });
    });
    // machines
    const mach = Object.keys(used).map((m) => { const u = used[m], tot = u.reduce((a, b) => a + b, 0), lastD = Math.max(...ops.filter((o) => o.segs.some((g) => g[0] === m)).map((o) => o.dueIdx), i0), avail = cap.slice(0, lastD + 1).reduce((a, b) => a + b, 0), need = ops.reduce((a, o) => a + o.segs.filter((g) => g[0] === m).reduce((b, g) => b + g[2], 0), 0); return { m, u, tot, avail, need, load: avail > 0 ? 100 * need / avail : 0 }; }).filter((x) => x.tot > 0).sort((a, b) => b.load - a.load);
    // extra machines needed for what is still late (per process)
    const extra = {};
    ops.filter((o) => !o.sup && o.over > 0.01).forEach((o) => { const k = String(o.stage).toUpperCase(), x = extra[k] || (extra[k] = { stage: o.stage, hrs: 0, due: 0, parts: new Set() }); x.hrs += o.over; x.due = Math.max(x.due, o.dueIdx); x.parts.add(o.part); });
    const sugg = Object.values(extra).map((x) => { const days = Math.max(1, cap.slice(0, x.due + 1).filter((c) => c > 0).length); return { stage: x.stage, hrs: x.hrs, parts: [...x.parts], machines: Math.max(1, Math.ceil(x.hrs / (P.cap * days))) }; }).sort((a, b) => b.hrs - a.hrs);
    return { P, m0, dim, i0, work, cap, ops, parts, mach, sugg, scen, late: parts.filter((p) => p.late > 0) };
  }
  const run = () => { S.R = { plan: load(S.d, S.c, "plan"), bal: load(S.d, S.c, "bal") }; };
  const cur = () => S.R[S.scen];

  /* ------------------------------------------------------------------ screens */
  function topBar(pub) {
    return '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button>' +
      '<span class="seg2" id="scen"><button data-s="plan" class="' + (S.scen === "plan" ? "on" : "") + '">As planned (route machines)</button><button data-s="bal" class="' + (S.scen === "bal" ? "on" : "") + '">Balanced (use other machines)</button></span><span class="grow"></span>' +
      (pub && canEdit() ? '<button class="btn sm" id="ppub">Publish this plan</button>' : "") + '<button class="btn o sm" id="ppr">Print report</button></div><div id="pmsg"></div>';
  }
  function bindBar(title, no) {
    const Rt = $("#" + S.go), q = (id) => Rt.querySelector(id);
    q("#pgo").onclick = () => { const v = q("#pm").value; if (!v) { say("Choose a month."); return; } S.month = v; route(); };
    q("#ppr").onclick = () => { rep(title, no); window.print(); };
    Rt.querySelectorAll("#scen button").forEach((b) => (b.onclick = () => { S.scen = b.dataset.s; draw(); }));
    const pb = q("#ppub");
    if (pb) pb.onclick = async () => {
      const R = cur(), m0 = R.m0, rows = R.ops.map((o) => ({ part: o.part, name: o.name, seq: o.seq, stage: o.stage, machine: o.mach, qty: Math.round(o.make), hours: +o.hrs.toFixed(2), start: iso(m0 + o.start * DAY), finish: iso(m0 + o.end * DAY), due: iso(m0 + o.dueIdx * DAY), type: o.type }));
      const tp = R.parts, sm = { scenario: S.scen, parts: tp.length, late_parts: R.late.length, avg_tpt_days: tp.length ? +(tp.reduce((a, p) => a + p.tpt, 0) / tp.length).toFixed(1) : 0, max_tpt_days: tp.length ? Math.max(...tp.map((p) => p.tpt)) : 0, make_hours: +R.ops.reduce((a, o) => a + (o.sup ? 0 : o.hrs), 0).toFixed(1), machines: R.mach.length, extra_machines: R.sugg.reduce((a, s) => a + s.machines, 0) };
      try { const r = await call("kmr_mlp_publish", { p_month: S.month, p_rows: rows, p_summary: sm }); q("#pmsg").innerHTML = '<div class="msg ok">Published as version ' + r.version + " (" + (S.scen === "bal" ? "balanced" : "as planned") + "). Capacity, manpower, overtime, tools, consumables and electricity plans can now read it.</div>"; } catch (e) { say(e.message); }
    };
  }
  const head = (R) => { let h = '<th class="t" style="width:11%">Part</th><th class="t" style="width:11%">Process</th><th class="t" style="width:11%">Machine</th>'; for (let i = 0; i < R.dim; i++) { const t = R.m0 + i * DAY, dw = new Date(t).getUTCDay(); h += '<th class="' + (R.work[i] || i < R.i0 ? "" : "off") + '">' + (i + 1) + "<br>" + DOW[dw] + "</th>"; } return h; };

  function drawDash() {
    const A = S.R.plan, B = S.R.bal, R = cur(), n = A.parts.length, noR = S.c.parts.filter((p) => p.noRoute), ok = (x) => x.parts.length - x.late.length;
    const verdict = (x, label) => { const l = x.late.length; return '<div class="verdict" style="--c:' + (l ? "var(--r)" : "var(--g)") + '"><b>' + label + ": " + (l ? "NO - " + l + " of " + x.parts.length + " parts miss the due date" : "YES - all " + x.parts.length + " parts finish by the due date") + "</b>" + (l ? "<div class='note'>Latest: " + x.late.slice().sort((a, b) => b.late - a.late).slice(0, 5).map((p) => esc(p.part) + " (+" + p.late + " d)").join(", ") + "</div>" : "") + "</div>"; };
    const sg = B.sugg.length ? "<ul>" + B.sugg.map((s) => "<li><b>Add " + s.machines + " machine(s) for " + esc(s.stage) + "</b>: about " + n0(s.hrs) + " h cannot be done by the due date even after using every other machine that has run this process (" + s.parts.slice(0, 4).map(esc).join(", ") + (s.parts.length > 4 ? " …" : "") + "). Or work overtime.</li>").join("") + "</ul>" : "<p>Nothing more is needed after balancing.</p>";
    const mv = B.ops.filter((o) => o.moved).length;
    $("#dash").innerHTML = topBar(false) + '<h3 style="margin:4px 0">' + mlong(S.month) + ": can the production plan be achieved by the customer due dates?</h3>" + verdict(A, "As planned (each process on its route machine)") + verdict(B, "Balanced (load moved to other machines)") +
      '<div class="tiles">' + tile("Parts in the plan", n, "#2563eb", "scheduled in Sales Flow") + tile("On time as planned", ok(A), "#16a34a", "of " + n) + tile("On time after balancing", ok(B), ok(B) === n ? "#16a34a" : "#ea580c", mv + " operation(s) moved or split") +
      tile("Average throughput time", n1(R.parts.reduce((a, p) => a + p.tpt, 0) / Math.max(1, n)) + " days", "#7c3aed", "first start to last finish") + tile("Machines used", R.mach.length, "#0d9488", "busiest " + (R.mach[0] ? esc(R.mach[0].m) + " " + R.mach[0].load.toFixed(0) + "%" : "–")) +
      tile("Extra machines needed", B.sugg.reduce((a, s) => a + s.machines, 0), B.sugg.length ? "#dc2626" : "#16a34a", "after balancing") + "</div>" +
      '<div class="cd wide"><h3>What to do to meet the due dates</h3>' + (A.late.length ? "<p>Open <b>Balance the load</b> to see which operations move to which machine. " + (B.late.length ? "Parts still late after balancing need more machine hours:" : "After moving them, every part is on time.") + "</p>" + (B.late.length ? sg : "") : "<p>The plan can be met on the route machines. No balancing is needed.</p>") + "</div>" +
      '<div class="cd wide"><h3>Working time used</h3><p class="note">' + n1(R.P.hpd) + " h per day × " + n1(R.P.eff) + "% OEE (overall equipment effectiveness) = " + n1(R.P.cap) + " h per machine per working day. Weekly off: " + (R.P.woff < 0 ? "none" : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][R.P.woff]) + "; holidays: " + (S.d.holidays || []).length + " from HRM. Loading starts today (" + dd(R.m0 + R.i0 * DAY) + "). Change on the Entry screen.</p>" +
      (noR.length ? "<p class='note'>" + noR.length + " scheduled part(s) have no route and are not loaded: " + noR.slice(0, 8).map((p) => esc(p.part)).join(", ") + "</p>" : "") + "</div>" +
      '<p class="note">Published: ' + (S.d.mlast ? "version " + S.d.mlast.version + " on " + String(S.d.mlast.at).slice(0, 10) : "not yet for this month") + ".</p>";
    bindBar("Machine loading dashboard", 1);
  }

  function drawCal() {
    const R = cur(), q = S.fpart || "", lateOnly = !!S.flate, rows = [];
    R.parts.filter((p) => (!q || p.part === q) && (!lateOnly || p.late > 0)).forEach((p) => p.items.forEach((o) => rows.push({ p, o })));
    const col = (pc) => hue(pc);
    const body = rows.map(({ p, o }, i) => {
      let cells = ""; for (let d = 0; d < R.dim; d++) { const on = d >= o.start && d <= o.end, isDue = d === p.due, off = !R.work[d] && !on; cells += '<td class="dy ' + (off ? "off " : "") + (isDue ? "due" : "") + (on ? " bar" : "") + '"' + (on ? ' style="background:' + (o.sup ? "#94a3b8" : col(p.part)) + '" title="' + esc(p.part + " " + o.stage + " " + o.mach + " " + dd(R.m0 + o.start * DAY) + " to " + dd(R.m0 + o.end * DAY)) + '"' : "") + ">" + (on && d === o.start ? "▸" : on && d === o.end && o.end > R.dim - 1 ? "" : "") + "</td>"; }
      const lateOp = o.end > p.due;
      return "<tr><td class='t'>" + (o === p.items[0] ? nm(p) : '<span class="mut">' + esc(p.part) + "</span>") + "</td><td class='t'>" + o.seq + ". " + esc(o.stage) + (o.moved ? " " + chip("moved", "a") : "") + "</td><td class='t'>" + esc(o.mach) + "</td>" + cells + "</tr>";
    }).join("");
    $("#cal").innerHTML = topBar(true) + '<div class="row"><label>Part <select id="fp" style="width:auto"><option value="">All parts</option>' + R.parts.map((p) => '<option value="' + esc(p.part) + '"' + (p.part === q ? " selected" : "") + ">" + esc(p.part) + (p.late ? " (late)" : "") + "</option>").join("") + '</select></label><label style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="fl" style="width:auto"' + (lateOnly ? " checked" : "") + "> Late parts only</label></div>" +
      '<p class="note">Each bar runs from the day the process starts to the day it finishes on its machine (loaded from today, working days only). Red outline = customer due date. Grey cells = weekly off or holiday. A bar that reaches the last day of the month continues into the next month.</p>' +
      '<div class="sc" style="max-height:calc(100vh - 360px)"><table class="cal" data-nofilter="1"><thead><tr>' + head(R) + "</tr></thead><tbody>" + (body || '<tr><td class="t" colspan=' + (R.dim + 3) + ">Nothing to show.</td></tr>") + "</tbody></table></div>" +
      '<h3 style="margin:12px 0 4px">Start, finish and due date</h3>' + T('<table><thead><tr><th>S.No</th><th>Part</th><th class="num">Quantity</th><th>First process starts</th><th>Last process finishes</th><th>Due date</th><th class="num">Throughput (days)</th><th>Status</th></tr></thead><tbody>' +
        R.parts.filter((p) => (!q || p.part === q) && (!lateOnly || p.late > 0)).map((p, i) => "<tr><td>" + (i + 1) + "</td><td>" + nm(p) + '</td><td class="num">' + n0(p.qty) + "</td><td>" + dd(R.m0 + p.first * DAY) + "</td><td>" + dd(R.m0 + p.last * DAY) + "</td><td>" + dd(R.m0 + p.due * DAY) + '</td><td class="num">' + p.tpt + "</td><td>" + (p.late ? chip("late " + p.late + " d", "r") : chip("on time", "g")) + "</td></tr>").join("") + "</tbody></table>");
    bindBar("Machine loading - part and process calendar", 2);
    $("#cal").querySelector("#fp").onchange = (e) => { S.fpart = e.target.value; drawCal(); };
    $("#cal").querySelector("#fl").onchange = (e) => { S.flate = e.target.checked; drawCal(); };
  }

  function drawMach() {
    const R = cur(), cp = R.P.cap;
    const body = R.mach.map((m, i) => {
      let cells = ""; for (let d = 0; d < R.dim; d++) { const h = m.u[d], pc = cp ? 100 * h / cp : 0, off = !R.work[d]; const who = [...new Set(R.ops.filter((o) => o.segs.some((g) => g[0] === m.m && g[1] === d)).map((o) => o.part + " " + o.stage))].join(", "); cells += '<td class="' + (off ? "off" : "") + '" style="' + (h > 0 ? "background:" + (pc > 99 ? "#fca5a5" : pc > 85 ? "#fde68a" : "#bbf7d0") : "") + '" title="' + esc(who) + '">' + (h > 0 ? Math.round(h) : "") + "</td>"; }
      return "<tr><td class='t'><b>" + esc(m.m) + "</b></td><td class='t num'>" + n0(m.need) + " / " + n0(m.avail) + "</td><td class='t num'><b style='color:" + (m.load > 100 ? "var(--r)" : m.load > 85 ? "var(--a)" : "var(--g)") + "'>" + m.load.toFixed(0) + "%</b></td>" + cells + "</tr>";
    }).join("");
    let h = '<th class="t" style="width:9%">Machine</th><th class="t" style="width:8%">Need / available h to due</th><th class="t" style="width:5%">Load</th>'; for (let i = 0; i < R.dim; i++) { const t = R.m0 + i * DAY; h += '<th class="' + (R.work[i] ? "" : "off") + '">' + (i + 1) + "<br>" + DOW[new Date(t).getUTCDay()] + "</th>"; }
    $("#mach").innerHTML = topBar(true) + '<p class="note">Hours loaded on each machine each day (a full day is ' + n1(cp) + " h). Green up to 85%, amber up to 99%, red = full day. Load = hours the machine must run for its parts / hours it has until the latest due date of those parts. Over 100% means those parts cannot all be finished on that machine in time. Point at a cell to see the parts.</p>" +
      '<div class="sc" style="max-height:calc(100vh - 340px)"><table class="cal" data-nofilter="1"><thead><tr>' + h + "</tr></thead><tbody>" + (body || '<tr><td class="t" colspan=' + (R.dim + 3) + ">No machine load.</td></tr>") + "</tbody></table></div>";
    bindBar("Machine loading - machine calendar", 3);
  }

  function drawBal() {
    const A = S.R.plan, B = S.R.bal, over = A.mach.filter((m) => m.load > 100);
    const moves = B.ops.filter((o) => o.moved).map((o) => ({ o, free: o.pick.map((x) => { const m = B.mach.find((y) => y.m === x.m); return m ? Math.max(0, m.avail - m.need) : null; }) }));
    const spare = B.mach.filter((m) => m.load < 70).sort((a, b) => (b.avail - b.need) - (a.avail - a.need)).slice(0, 12);
    $("#bal").innerHTML = topBar(true) + '<div class="verdict" style="--c:' + (B.late.length ? "var(--r)" : "var(--g)") + '"><b>' + (A.late.length ? A.late.length + " part(s) are late as planned. After balancing: " + (B.late.length ? B.late.length + " still late" : "all on time") : "All parts are on time on their route machines") + "</b></div>" +
      '<h3 style="margin:8px 0 4px">1. Overloaded machines (as planned)</h3>' + T('<table><thead><tr><th>S.No</th><th>Machine</th><th class="num">Hours needed</th><th class="num">Hours available to due date</th><th class="num">Load %</th></tr></thead><tbody>' + (over.map((m, i) => "<tr><td>" + (i + 1) + "</td><td><b>" + esc(m.m) + '</b></td><td class="num">' + n0(m.need) + '</td><td class="num">' + n0(m.avail) + '</td><td class="num"><b style="color:var(--r)">' + m.load.toFixed(0) + "%</b></td></tr>").join("") || '<tr><td colspan=5 class="mut">No machine is over 100%.</td></tr>') + "</tbody></table>") +
      '<h3 style="margin:12px 0 4px">2. Move the load: which operation goes to which machine</h3>' + T('<table><thead><tr><th>S.No</th><th>Part</th><th>Process</th><th>From machine</th><th>To machine(s)</th><th class="num">Hours</th><th>New start</th><th>New finish</th><th>Due</th><th>Result</th></tr></thead><tbody>' +
        (moves.map(({ o }, i) => "<tr><td>" + (i + 1) + "</td><td>" + nm(o) + "</td><td>" + o.seq + ". " + esc(o.stage) + "</td><td>" + esc(o.prim) + "</td><td><b>" + esc(o.mach) + '</b></td><td class="num">' + n1(o.hrs) + "</td><td>" + dd(B.m0 + o.start * DAY) + "</td><td>" + dd(B.m0 + o.end * DAY) + "</td><td>" + dd(B.m0 + o.dueIdx * DAY) + "</td><td>" + (o.end > o.dueIdx ? chip("still late", "r") : chip("on time", "g")) + "</td></tr>").join("") || '<tr><td colspan=10 class="mut">No operation needs to move.</td></tr>') + "</tbody></table>") +
      '<h3 style="margin:12px 0 4px">3. Machines with spare hours (to take more load)</h3>' + T('<table><thead><tr><th>S.No</th><th>Machine</th><th class="num">Load %</th><th class="num">Spare hours to the latest due date</th></tr></thead><tbody>' + (spare.map((m, i) => "<tr><td>" + (i + 1) + "</td><td><b>" + esc(m.m) + '</b></td><td class="num">' + m.load.toFixed(0) + '%</td><td class="num">' + n0(m.avail - m.need) + "</td></tr>").join("") || '<tr><td colspan=4 class="mut">None.</td></tr>') + "</tbody></table>") +
      '<h3 style="margin:12px 0 4px">4. Still late after balancing: add machines</h3>' + T('<table><thead><tr><th>S.No</th><th>Process</th><th class="num">Hours that miss the due date</th><th class="num">Extra machines needed</th><th>Parts</th></tr></thead><tbody>' + (B.sugg.map((s, i) => "<tr><td>" + (i + 1) + "</td><td><b>" + esc(s.stage) + '</b></td><td class="num">' + n0(s.hrs) + '</td><td class="num"><b>' + s.machines + "</b></td><td>" + s.parts.slice(0, 6).map(esc).join(", ") + (s.parts.length > 6 ? " …" : "") + "</td></tr>").join("") || '<tr><td colspan=5 class="mut">Nothing more is needed.</td></tr>') + "</tbody></table>") +
      '<p class="note">Candidate machines for a process are the alternates in the cycle-time master and every machine that has run the same process in the last 180 days (ERP). Switch the view at the top to "Balanced" to see the new calendar and to publish it.</p>';
    bindBar("Machine loading - balance the load", 4);
  }

  function drawEntry() {
    const P = params(S.d), ed = canEdit() ? "" : "disabled", WD = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    $("#entry").innerHTML = '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button></div><div id="pmsg"></div>' +
      '<p class="note">Quantities, routes, cycle times, machines and due dates come from the Production plan, Sales Flow and the Operations Master; holidays from HRM. Only the working-time settings are typed here. They start from the Plant standards and are shared with the Production plan.</p>' +
      '<div class="box"><h3>Working time</h3><div class="frm"><div><label>Hours per machine per day (plant standards: ' + (S.d.std && S.d.std.hoursPerDay || "–") + ')</label><input class="n" id="chpd" type="number" min="1" max="24" value="' + P.hpd + '" ' + ed + '></div><div><label>OEE % (overall equipment effectiveness)</label><input class="n" id="ceff" type="number" min="1" max="100" value="' + P.eff + '" ' + ed + '></div>' +
      '<div><label>Weekly off</label><select id="cwoff" ' + ed + '><option value="-1"' + (P.woff < 0 ? " selected" : "") + ">None</option>" + WD.map((w, i) => '<option value="' + i + '"' + (P.woff === i ? " selected" : "") + ">" + w + "</option>").join("") + "</select></div>" +
      '<div><label>Days after a process starts before the next process can start</label><input class="n" id="cwait" type="number" min="0" step="1" value="' + P.lag + '" ' + ed + '></div><div><label>Outside (supplier) process time (days)</label><input class="n" id="csupd" type="number" min="0" step="1" value="' + P.supd + '" ' + ed + "></div></div>" +
      '<p class="note">"Days after a process starts" is the batch transfer: the next process can begin on parts already finished, so a part does not wait for its whole lot.</p></div>' + (canEdit() ? '<div class="row"><button class="btn" id="psv">Save</button><span id="pmsg2" class="mut"></span></div>' : "");
    const Rt = $("#entry"); Rt.querySelector("#pgo").onclick = () => { const x = Rt.querySelector("#pm").value; if (x) { S.month = x; route(); } };
    if (!canEdit()) return;
    Rt.querySelector("#psv").onclick = async () => { try { await call("kmr_mlp_save", { p_month: S.month, p_cfg: { hpd: Rt.querySelector("#chpd").value, eff: Rt.querySelector("#ceff").value, woff: Rt.querySelector("#cwoff").value, wait: Rt.querySelector("#cwait").value, supd: Rt.querySelector("#csupd").value } }); Rt.querySelector("#pmsg2").textContent = "Saved."; setTimeout(route, 400); } catch (e) { say(e.message); } };
  }

  const DRAW = { dash: drawDash, cal: drawCal, mach: drawMach, bal: drawBal, entry: drawEntry };
  function draw() { const f = DRAW[S.go]; if (f) f(); }
  async function route() {
    const go = hashGo(); S.go = go;
    if (!S.month) S.month = td().slice(0, 7);
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go));
    ["std", "dash", "cal", "mach", "bal", "entry"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go));
    window.scrollTo(0, 0);
    if (go === "std") { KMRStd.draw($("#std"), "mlp"); return; }
    try { S.d = await call("kmr_mlp_data", { p_month: S.month }); S.c = calc(S.d); run(); draw(); } catch (e) { say(e.message); }
  }
  document.addEventListener("click", (e) => { const a = e.target.closest('a[href^="#go="]'); if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; e.preventDefault(); history.replaceState(null, "", location.pathname + location.search + a.getAttribute("href")); route(); });
  window.addEventListener("hashchange", route);
  window.MLP = { load };
  (async () => { try { await QP.init("mlp", "kmr_mlp_context"); if (!QP.ctx) return; await route(); } catch (e) { say(e.message); } })();
})();
