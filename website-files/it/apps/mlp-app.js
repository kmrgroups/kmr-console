/* Machine loading plan (MLP): the due date is worked back to the first operation using the cycle times of the Production plan, so the throughput time of every part
   and the load on every machine are known. Auto-pulled: Production plan quantities (same calculation), routes, cycle times, machines, due dates from Sales Flow. */
(function () {
  "use strict";
  const { $, esc, say, call } = QP;
  const { calc } = window.PPLCalc;
  const S = { go: null, month: "", d: null, c: null, p: null };
  const DAY = 86400000;
  const td = () => new Date(Date.now() + 19800000).toISOString().slice(0, 10);
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const mlong = (ym) => MON[+ym.slice(5, 7) - 1] + " " + ym.slice(0, 4);
  const n0 = (v) => (v == null || v === "" ? "–" : Math.round(+v).toLocaleString("en-IN"));
  const n1 = (v) => (v == null ? "–" : (+v).toLocaleString("en-IN", { maximumFractionDigits: 1 }));
  const canEdit = () => QP.canEdit;
  const hashGo = () => { const m = location.hash.match(/go=([a-z]+)/); return m ? m[1] : "std"; };
  const T = (html) => '<div class="sc">' + html + "</div>";
  const rep = (title, no) => { if (window.KMRReport) window.KMRReport.set({ title, doc: "", format: "KMR/MLP/F-" + no, rev: "01", date: "2026-11-19" }); };
  const tms = (iso) => new Date(iso + "T00:00:00Z").getTime(), iso = (t) => new Date(t).toISOString().slice(0, 10);
  const dd = (t) => { const d = new Date(t); return String(d.getUTCDate()).padStart(2, "0") + " " + MON[d.getUTCMonth()]; };
  const chip = (t, c) => '<span class="chip ' + c + '">' + t + "</span>";
  const tile = (l, v, c, sub) => '<div class="tile" style="--c:' + c + '"><small class="mut">' + l + "</small><b style='display:block;font-size:22px'>" + v + "</b>" + (sub ? "<small class='mut'>" + sub + "</small>" : "") + "</div>";
  const nm = (r) => "<b>" + esc(r.part) + "</b><br><small class='mut'>" + esc(r.name || "") + "</small>";

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

  /* ---- back-scheduling: finish of the last process = due date; each earlier process finishes when the next one starts, less the wait between processes ---- */
  function schedule(d, C) {
    const cfg = d.cfg || {}, wait = cfg.wait != null ? +cfg.wait : 0.5, supd = cfg.supd != null ? +cfg.supd : 5;
    const ym = S.month, y = +ym.slice(0, 4), mo = +ym.slice(5, 7), dim = new Date(Date.UTC(y, mo, 0)).getUTCDate(), cal = dim / Math.max(1, C.cfg.days);
    const avail = C.cfg.hpd * C.cfg.eff / 100, today = tms(d.today || td()), mend = Date.UTC(y, mo, 0), out = [], parts = [];
    const byP = {}; C.rows.filter((r) => r.make > 0).forEach((r) => (byP[r.part] = byP[r.part] || []).push(r));
    Object.keys(byP).forEach((pc) => {
      const st = byP[pc].sort((a, b) => a.seq - b.seq), due = st[0].due ? tms(String(st[0].due).slice(0, 10)) : mend;
      let end = due; const items = [];
      for (let i = st.length - 1; i >= 0; i--) {
        const r = st[i], wd = r.type === "supplier" ? supd : Math.max(0.1, r.hrs / avail), days = wd * (r.type === "supplier" ? 1 : cal), start = end - days * DAY;
        items[i] = { ...r, days, start, end }; end = start - wait * cal * DAY;
      }
      const first = items[0].start, last = items[items.length - 1].end, tpt = (last - first) / DAY, late = Math.ceil((today - first) / DAY);
      items.forEach((x) => out.push(x));
      parts.push({ part: pc, name: st[0].name, due, first, last, tpt, late: late > 0 ? late : 0, stages: items.length, qty: items[items.length - 1].make });
    });
    parts.sort((a, b) => b.tpt - a.tpt);
    // weekly machine load
    const wk = [], t0 = out.length ? Math.min(...out.map((x) => x.start)) : tms(ym + "-01"), t1 = out.length ? Math.max(...out.map((x) => x.end)) : mend;
    const mon = (t) => { const x = new Date(t), dow = (x.getUTCDay() + 6) % 7; return Date.UTC(x.getUTCFullYear(), x.getUTCMonth(), x.getUTCDate() - dow); };
    for (let w = mon(t0); w <= t1 && wk.length < 14; w += 7 * DAY) wk.push(w);
    const perWeekAvail = avail * (C.cfg.days / dim) * 7, mm = {};
    out.filter((x) => x.type !== "supplier" && x.hrs > 0).forEach((x) => {
      const m = mm[x.machine] || (mm[x.machine] = { machine: x.machine, w: wk.map(() => 0) }), span = Math.max(DAY * 0.5, x.end - x.start);
      wk.forEach((w, i) => { const o = Math.min(x.end, w + 7 * DAY) - Math.max(x.start, w); if (o > 0) m.w[i] += x.hrs * o / span; });
    });
    const mach = Object.values(mm).map((m) => ({ ...m, peak: Math.max(...m.w) / perWeekAvail * 100, total: m.w.reduce((a, b) => a + b, 0) })).sort((a, b) => b.peak - a.peak);
    return { items: out, parts, wk, mach, perWeekAvail, wait, supd, today };
  }

  function bar(i, r, t0, span) { const l = 100 * (r.start - t0) / span, w = Math.max(1.2, 100 * (r.end - r.start) / span); return '<div style="position:relative;height:14px;background:var(--line);border-radius:4px;min-width:160px"><i style="position:absolute;top:0;bottom:0;left:' + l.toFixed(1) + "%;width:" + w.toFixed(1) + "%;background:" + (r.type === "supplier" ? "#94a3b8" : "var(--b1)") + ';border-radius:4px"></i></div>'; }
  function monthBar() {
    return '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button><span class="grow"></span>' +
      (S.go === "sched" && canEdit() ? '<button class="btn sm" id="ppub">Publish this plan</button>' : "") + '<button class="btn o sm" id="ppr">Print report</button></div><div id="pmsg"></div>';
  }
  function bindBar(title, no) {
    const R = $("#" + S.go), q = (id) => R.querySelector(id);
    q("#pgo").onclick = () => { const v = q("#pm").value; if (!v) { say("Choose a month."); return; } S.month = v; route(); };
    q("#ppr").onclick = () => { rep(title, no); window.print(); };
    const pb = q("#ppub");
    if (pb) pb.onclick = async () => {
      const P = S.p, rows = P.items.map((r) => ({ part: r.part, name: r.name, seq: r.seq, stage: r.stage, machine: r.machine, qty: Math.round(r.make), hours: +r.hrs.toFixed(2), start: iso(r.start), finish: iso(r.end), type: r.type }));
      const tp = P.parts, sm = { parts: tp.length, avg_tpt_days: tp.length ? +(tp.reduce((a, p) => a + p.tpt, 0) / tp.length).toFixed(1) : 0, max_tpt_days: tp.length ? +tp[0].tpt.toFixed(1) : 0, late_parts: tp.filter((p) => p.late).length, make_hours: +P.items.reduce((a, r) => a + r.hrs, 0).toFixed(1), machines: P.mach.length };
      try { const r = await call("kmr_mlp_publish", { p_month: S.month, p_rows: rows, p_summary: sm }); q("#pmsg").innerHTML = '<div class="msg ok">Published as version ' + r.version + ". Capacity, manpower, overtime, tools, consumables and electricity plans can now read it.</div>"; } catch (e) { say(e.message); }
    };
  }

  async function route() {
    const go = hashGo(); S.go = go;
    if (!S.month) S.month = td().slice(0, 7);
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go));
    ["std", "dash", "sched", "load", "entry"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go));
    window.scrollTo(0, 0);
    if (go === "std") { KMRStd.draw($("#std"), "mlp"); return; }
    try { S.d = await call("kmr_mlp_data", { p_month: S.month }); S.c = calc(S.d); S.p = schedule(S.d, S.c); ({ dash: drawDash, sched: drawSched, load: drawLoad, entry: drawEntry })[go](); } catch (e) { say(e.message); }
  }
  document.addEventListener("click", (e) => { const a = e.target.closest('a[href^="#go="]'); if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; e.preventDefault(); history.replaceState(null, "", location.pathname + location.search + a.getAttribute("href")); route(); });
  window.addEventListener("hashchange", route);

  function drawDash() {
    const P = S.p, tp = P.parts, avg = tp.length ? tp.reduce((a, p) => a + p.tpt, 0) / tp.length : 0, late = tp.filter((p) => p.late), over = P.mach.filter((m) => m.peak > 100), noR = S.c.parts.filter((p) => p.noRoute), mx = Math.max(1, ...tp.slice(0, 10).map((p) => p.tpt));
    $("#dash").innerHTML = monthBar() + '<h3 style="margin:4px 0">' + mlong(S.month) + ' machine loading</h3><div class="tiles">' +
      tile("Parts scheduled", tp.length, "#2563eb", "with quantity to make") + tile("Average throughput time", n1(avg) + " days", "#7c3aed", "first operation start to last finish") + tile("Longest throughput time", tp.length ? n1(tp[0].tpt) + " days" : "–", "#ea580c", tp.length ? esc(tp[0].part) : "") +
      tile("Parts that should have started", late.length, late.length ? "#dc2626" : "#16a34a", "start date already passed") + tile("Machines over 100% in a week", over.length, over.length ? "#dc2626" : "#16a34a", "peak week load") + "</div>" +
      '<div class="cd wide"><h3>Throughput time by part (days) - longest first</h3>' + (tp.length ? tp.slice(0, 10).map((p) => '<div class="bl"><span>' + esc(p.part) + '</span><div class="bt"><i style="width:' + (100 * p.tpt / mx).toFixed(1) + '%;background:' + (p.late ? "var(--r)" : "var(--b1)") + '"></i></div><b>' + n1(p.tpt) + "</b></div>").join("") : '<p class="mut">Nothing to make this month. Check the Production plan.</p>') +
      '<p class="note">Throughput time = time for the part to go through all its processes: the machine time of every process plus the wait of ' + P.wait + " day(s) between processes and " + P.supd + " day(s) for outside (supplier) processes. Change these on the Entry screen. Red = the first operation should already have started.</p></div>" +
      '<div class="cd wide"><h3>Gaps</h3><ul>' + (noR.length ? "<li>" + noR.length + " scheduled part(s) have no route, so they cannot be loaded: " + noR.slice(0, 8).map((p) => esc(p.part)).join(", ") + "</li>" : "") + (late.length ? "<li>" + late.length + " part(s) must start before today to meet the due date: " + late.slice(0, 6).map((p) => esc(p.part) + " (" + p.late + " d)").join(", ") + "</li>" : "") + (!noR.length && !late.length ? "<li>None.</li>" : "") + "</ul></div>" +
      '<p class="note">Published: ' + (S.d.mlast ? "version " + S.d.mlast.version + " on " + String(S.d.mlast.at).slice(0, 10) : "not yet for this month") + ".</p>";
    bindBar("Machine loading dashboard", 1);
  }

  function drawSched() {
    const P = S.p, it = P.items, t0 = it.length ? Math.min(...it.map((x) => x.start)) : 0, t1 = it.length ? Math.max(...it.map((x) => x.end)) : 1, span = Math.max(DAY, t1 - t0);
    const body = it.sort((a, b) => (a.part < b.part ? -1 : a.part > b.part ? 1 : a.seq - b.seq)).map((r, i) => "<tr><td>" + (i + 1) + "</td><td>" + nm(r) + "</td><td>" + r.seq + ". " + esc(r.stage) + "</td><td>" + esc(r.machine) + '</td><td class="num">' + n0(r.make) + '</td><td class="num">' + (r.type === "supplier" ? "–" : n1(r.hrs)) + "</td><td>" + dd(r.start) + (r.start < P.today ? " " + chip("late", "r") : "") + "</td><td>" + dd(r.end) + "</td><td>" + bar(i, r, t0, span) + "</td></tr>").join("");
    $("#sched").innerHTML = monthBar() + '<p class="note">Start and finish of every process, worked back from the due date (Sales Flow date; month end when the schedule has no date). The bar covers ' + (it.length ? dd(t0) + " to " + dd(t1) : "–") + ". Grey = outside (supplier) process.</p>" +
      T('<table><thead><tr><th>S.No</th><th>Part</th><th>Process</th><th>Machine</th><th class="num">Quantity</th><th class="num">Hours</th><th>Start</th><th>Finish</th><th style="min-width:200px">Timeline</th></tr></thead><tbody>' + (body || '<tr><td colspan=9 class="mut">Nothing to make this month.</td></tr>') + "</tbody></table>");
    bindBar("Machine loading - schedule", 2);
  }

  function drawLoad() {
    const P = S.p, col = (v) => (v > 100 ? "#fecaca" : v > 85 ? "#fde68a" : v > 0 ? "#bbf7d0" : "transparent");
    $("#load").innerHTML = monthBar() + '<p class="note">Hours placed on each machine in each week as a % of the hours available in a week (' + n1(P.perWeekAvail) + " h). Red above 100%, amber above 85%.</p>" +
      T('<table><thead><tr><th>S.No</th><th>Machine</th>' + P.wk.map((w) => '<th class="num">' + dd(w) + "</th>").join("") + '<th class="num">Peak %</th></tr></thead><tbody>' +
        (P.mach.map((m, i) => "<tr><td>" + (i + 1) + "</td><td><b>" + esc(m.machine) + "</b></td>" + m.w.map((h) => { const v = 100 * h / P.perWeekAvail; return '<td class="num" style="background:' + col(v) + '">' + (h > 0 ? v.toFixed(0) + "%" : "") + "</td>"; }).join("") + '<td class="num"><b>' + m.peak.toFixed(0) + "%</b></td></tr>").join("") || '<tr><td colspan=3 class="mut">No machine load.</td></tr>') + "</tbody></table>");
    bindBar("Machine loading - load by week", 3);
  }

  function drawEntry() {
    const d = S.d, C = S.c, cfg = d.cfg || {}, ed = canEdit() ? "" : "disabled", v = (k, df) => (cfg[k] != null ? cfg[k] : df);
    $("#entry").innerHTML = '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button></div><div id="pmsg"></div>' +
      '<p class="note">Quantities, cycle times, machines and due dates come from the Production plan, Sales Flow and the part routes. Only the planning parameters are typed here (shared with the Production plan).</p>' +
      '<div class="box"><h3>Planning parameters</h3><div class="frm"><div><label>Hours per machine per day</label><input class="n" id="chpd" type="number" min="1" max="24" value="' + C.cfg.hpd + '" ' + ed + '></div><div><label>Efficiency %</label><input class="n" id="ceff" type="number" min="1" max="100" value="' + C.cfg.eff + '" ' + ed + '></div><div><label>Working days in the month</label><input class="n" id="cdays" type="number" min="1" max="31" value="' + C.cfg.days + '" ' + ed +
      '></div><div><label>Wait between two processes (days)</label><input class="n" id="cwait" type="number" min="0" step="0.1" value="' + v("wait", 0.5) + '" ' + ed + '></div><div><label>Outside (supplier) process time (days)</label><input class="n" id="csupd" type="number" min="0" step="0.5" value="' + v("supd", 5) + '" ' + ed + "></div></div></div>" + (canEdit() ? '<div class="row"><button class="btn" id="psv">Save</button><span id="pmsg2" class="mut"></span></div>' : "");
    const R = $("#entry"); R.querySelector("#pgo").onclick = () => { const x = R.querySelector("#pm").value; if (x) { S.month = x; route(); } };
    if (!canEdit()) return;
    R.querySelector("#psv").onclick = async () => { try { await call("kmr_mlp_save", { p_month: S.month, p_cfg: { hpd: R.querySelector("#chpd").value, eff: R.querySelector("#ceff").value, days: R.querySelector("#cdays").value, wait: R.querySelector("#cwait").value, supd: R.querySelector("#csupd").value } }); R.querySelector("#pmsg2").textContent = "Saved."; setTimeout(route, 400); } catch (e) { say(e.message); } };
  }

  window.MLP = { schedule };
  (async () => { try { await QP.init("mlp", "kmr_mlp_context"); if (!QP.ctx) return; await route(); } catch (e) { say(e.message); } })();
})();
