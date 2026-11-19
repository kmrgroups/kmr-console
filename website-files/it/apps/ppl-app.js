/* Production plan (PPL): customer schedule + supermarket quantity - stage stock, netted back stage by stage through the route.
   Auto-pulled: Sales Flow (schedule, despatched), MMD / ERP (route, cycle times, stage stock, machines), RMP (supermarket qty). Every figure can also be typed in. */
(function () {
  "use strict";
  const { $, esc, say, call } = QP;
  const S = { go: null, month: "", d: null, plan: null };
  const td = () => new Date(Date.now() + 19800000).toISOString().slice(0, 10);
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const mlong = (ym) => MON[+ym.slice(5, 7) - 1] + " " + ym.slice(0, 4);
  const n0 = (v) => (v == null || v === "" ? "–" : Math.round(+v).toLocaleString("en-IN"));
  const n1 = (v) => (v == null ? "–" : (+v).toLocaleString("en-IN", { maximumFractionDigits: 1 }));
  const canEdit = () => QP.canEdit;
  const hashGo = () => { const m = location.hash.match(/go=([a-z]+)/); return m ? m[1] : "std"; };
  const T = (html) => '<div class="sc">' + html + "</div>";
  const rep = (title, no) => { if (window.KMRReport) window.KMRReport.set({ title, doc: "", format: "KMR/PPL/F-" + no, rev: "01", date: "2026-11-19" }); };

  /* ---- auto-hide menu (remembered on this device) ---- */
  (function () {
    const top = $("#top"), cb = $("#ahc"); let on = true; try { on = localStorage.getItem("ppl-ah") !== "0"; } catch (e) { /* ignore */ }
    const apply = () => { document.body.classList.toggle("ah", on); cb.checked = on; top.classList.remove("show"); };
    const show = () => top.classList.add("show");
    $("#rev").addEventListener("mouseenter", show); $("#pill").addEventListener("click", show);
    top.addEventListener("mouseleave", () => { if (document.body.classList.contains("ah")) setTimeout(() => { if (!top.matches(":hover")) top.classList.remove("show"); }, 250); });
    document.addEventListener("click", (e) => { if (document.body.classList.contains("ah") && !top.contains(e.target) && e.target.id !== "pill") top.classList.remove("show"); });
    top.addEventListener("click", (e) => { if (e.target.closest(".tab") && document.body.classList.contains("ah")) setTimeout(() => top.classList.remove("show"), 150); });
    cb.addEventListener("change", () => { on = cb.checked; try { localStorage.setItem("ppl-ah", on ? "1" : "0"); } catch (e) { /* ignore */ } apply(); });
    apply();
  })();

  const { calc, nk } = window.PPLCalc;
  const nm = (r) => '<b>' + esc(r.part) + "</b><br><small class='mut'>" + esc(r.name || "") + "</small>";
  const tile = (l, v, c, sub) => '<div class="tile" style="--c:' + c + '"><small class="mut">' + l + "</small><b style='display:block;font-size:22px'>" + v + "</b>" + (sub ? "<small class='mut'>" + sub + "</small>" : "") + "</div>";
  const chip = (t, c) => '<span class="chip ' + c + '">' + t + "</span>";

  function monthBar(no, title) {
    return '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button><span class="grow"></span>' +
      (S.go === "plan" && canEdit() ? '<button class="btn sm" id="ppub">Publish this plan</button>' : "") + '<button class="btn o sm" id="ppr">Print report</button></div><div id="pmsg"></div>';
  }
  function bindBar(title, no) {
    const R = $("#" + S.go), q = (id) => R.querySelector(id);
    q("#pgo").onclick = () => { const v = q("#pm").value; if (!v) { say("Choose a month."); return; } S.month = v; route(); };
    q("#ppr").onclick = () => { rep(title, no); window.print(); };
    const pb = q("#ppub");
    if (pb) pb.onclick = async () => {
      const C = S.c, rows = C.rows.filter((r) => r.make > 0 || r.req > 0).map((r) => ({ part: r.part, name: r.name, seq: r.seq, stage: r.stage, machine: r.machine, ct_sec: r.ct, qty: Math.round(r.make), hours: +r.hrs.toFixed(2), due: r.due, type: r.type }));
      const sm = { parts: C.parts.length, make_hours: +C.mach.reduce((a, m) => a + m.hrs, 0).toFixed(1), machines: C.mach.length, hpd: C.cfg.hpd, eff: C.cfg.eff, days: C.cfg.days };
      try { const r = await call("kmr_ppl_publish", { p_month: S.month, p_rows: rows, p_summary: sm }); q("#pmsg").innerHTML = '<div class="msg ok">Published as version ' + r.version + ". Machine loading plan, Raw material plan, Capacity and the budgets can now read it.</div>"; } catch (e) { say(e.message); }
    };
  }

  async function load() { S.d = await call("kmr_ppl_data", { p_month: S.month }); S.c = calc(S.d); }

  async function route() {
    const go = hashGo(); S.go = go;
    if (!S.month) S.month = td().slice(0, 7);
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go));
    ["std", "dash", "plan", "mach", "entry"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go));
    window.scrollTo(0, 0);
    if (go === "std") { KMRStd.draw($("#std"), "ppl"); return; }
    try { await load(); ({ dash: drawDash, plan: drawPlan, mach: drawMach, entry: drawEntry })[go](); } catch (e) { say(e.message); }
  }
  document.addEventListener("click", (e) => { const a = e.target.closest('a[href^="#go="]'); if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; e.preventDefault(); history.replaceState(null, "", location.pathname + location.search + a.getAttribute("href")); route(); });
  window.addEventListener("hashchange", route);

  /* ---------- Dashboard ---------- */
  function drawDash() {
    const C = S.c, P = C.parts, tot = (k) => P.reduce((a, p) => a + p[k], 0), make = C.rows.filter((r) => r.type !== "supplier").reduce((a, r) => a + r.make, 0), hrs = C.mach.reduce((a, m) => a + m.hrs, 0);
    const noR = P.filter((p) => p.noRoute), noC = P.filter((p) => !p.noRoute && p.noCt), unass = C.rows.filter((r) => r.machine === "Unassigned" && r.make > 0).length, over = C.mach.filter((m) => m.load > 100);
    const top = C.mach.slice(0, 10), mx = Math.max(1, ...top.map((m) => m.load));
    $("#dash").innerHTML = monthBar() +
      '<h3 style="margin:4px 0">' + mlong(S.month) + ' production plan</h3><div class="tiles">' +
      tile("Parts in the plan", P.length, "#2563eb", "from Sales Flow and manual lines") + tile("Schedule still to deliver", n0(tot("net")), "#7c3aed", "pieces, after despatched") +
      tile("Stock held (FG, FI, WIP, incoming, supplier)", n0(tot("held")), "#0d9488", "from the Raw Material Plan work sheet") + tile("Final need (pieces)", n0(tot("final")), "#ea580c", "after all stock and buffers") + tile("Pieces to make (all processes)", n0(make), "#f97316", "sum over every process") + tile("Machine hours needed", n1(hrs), "#eab308", C.mach.length + " machines") +
      tile("Machines over 100% load", over.length, over.length ? "#dc2626" : "#16a34a", "load = hours needed / hours available") + "</div>" +
      '<div class="cd wide"><h3>Machine load this month (% of available hours)</h3>' + (top.length ? top.map((m) => '<div class="bl"><span>' + esc(m.machine) + '</span><div class="bt"><i style="width:' + Math.min(100, 100 * m.load / Math.max(100, mx)) + "%;background:" + (m.load > 100 ? "var(--r)" : m.load > 85 ? "var(--a)" : "var(--g)") + '"></i></div><b>' + m.load.toFixed(0) + "%</b></div>").join("") : '<p class="mut">No quantity to make.</p>') +
      '<p class="note">Available hours = hours per day × efficiency × working days (' + C.cfg.hpd + " h × " + C.cfg.eff.toFixed(0) + "% × " + C.cfg.days + " days). Change them on the Entry screen.</p></div>" +
      '<div class="cd wide"><h3>Gaps to close before this plan can be trusted</h3><ul>' +
      (noR.length ? "<li>" + noR.length + " part(s) have no route, so they are not netted: " + noR.slice(0, 8).map((p) => esc(p.part)).join(", ") + (noR.length > 8 ? " …" : "") + " (add the route and cycle times in Process Documents or Parts master)</li>" : "") +
      (noC.length ? "<li>" + noC.length + " part(s) have a stage without a cycle time, so machine hours are understated: " + noC.slice(0, 8).map((p) => esc(p.part)).join(", ") + "</li>" : "") +
      (unass ? "<li>" + unass + " stage(s) have no machine linked: they show as Unassigned in the Machine wise screen</li>" : "") +
      (!noR.length && !noC.length && !unass ? "<li>None. Every part has a route, cycle times and a machine.</li>" : "") + "</ul></div>" +
      '<p class="note">Published: ' + (S.d.last ? "version " + S.d.last.version + " on " + String(S.d.last.at).slice(0, 10) : "not yet for this month") + ". Next: Machine loading plan reads the published plan, back-schedules to the first operation and shows throughput time.</p>";
    bindBar("Production plan dashboard", 1);
  }

  /* ---------- Part & process wise ---------- */
  function drawPlan() {
    const C = S.c, P = C.parts, nz = (v) => (v ? n0(v) : '<span class="mut">0</span>');
    const t1 = P.map((p, i) => "<tr><td>" + (i + 1) + "</td><td>" + nm(p) + '</td><td class="num">' + n0(p.demand) + '</td><td class="num">' + n0(p.despatched) + '</td><td class="num">' + n0(p.net) + '</td><td class="num">' + nz(p.safety) + '</td><td class="num">' + nz(p.sup) + '</td><td class="num">' + nz(p.fg) + '</td><td class="num">' + nz(p.fi) + '</td><td class="num">' + nz(p.wip) + '</td><td class="num">' + nz(p.wip2) + '</td><td class="num">' + nz(p.inc) + '</td><td class="num">' + nz(p.supl) + '</td><td class="num"><b>' + n0(p.final) + "</b></td><td>" + (p.noRoute ? chip("no route", "r") : p.noCt ? chip("cycle time missing", "a") : p.final > 0 ? chip("to make", "b") : chip("enough stock", "g")) + "</td></tr>").join("");
    const rs = C.rows.filter((r) => r.req > 0 || r.make > 0), t2 = rs.map((r, i) => "<tr><td>" + (i + 1) + "</td><td>" + nm(r) + "</td><td>" + r.seq + ". " + esc(r.stage) + "</td><td>" + esc(r.machine) + '</td><td class="num">' + n0(r.req) + '</td><td class="num">' + (r.ssrc === "none" ? '<span class="mut">0</span>' : n0(r.stock) + " <small class='mut'>" + r.ssrc + "</small>") + '</td><td class="num"><b>' + n0(r.make) + '</b></td><td class="num">' + (r.ct || "–") + '</td><td class="num">' + (r.type === "supplier" ? "–" : n1(r.hrs)) + "</td><td>" + (r.due ? esc(String(r.due)) : "") + "</td></tr>").join("");
    $("#plan").innerHTML = monthBar() + '<p class="note">Only parts with a customer schedule for the month are planned (' + P.length + '). Stocks are the same numbers as the Raw Material Plan work sheet; change them on the Entry screen. Final need = still to deliver + minimum stock + supermarket - all stock held.</p>' +
      '<h3 style="margin:8px 0 4px">1. Part wise: schedule, stocks and quantity to make</h3>' +
      T('<table><thead><tr><th>S.No</th><th>Part</th><th class="num">Schedule</th><th class="num">Despatched</th><th class="num">Still to deliver</th><th class="num">Min. stock</th><th class="num">Super-market</th><th class="num">FG</th><th class="num">FI</th><th class="num">WIP</th><th class="num">WIP-2</th><th class="num">Incom-ing</th><th class="num">Supp-lier</th><th class="num">Final need</th><th>Status</th></tr></thead><tbody>' + (t1 || '<tr><td colspan=15 class="mut">No part has a schedule for this month. Load the schedule in Sales Flow, or add a line on the Entry screen.</td></tr>') + "</tbody></table>") +
      '<h3 style="margin:14px 0 4px">2. Process wise: what each process must make</h3>' +
      T('<table><thead><tr><th>S.No</th><th>Part</th><th>Process</th><th>Machine</th><th class="num">Need</th><th class="num">Stock after process</th><th class="num">Make</th><th class="num">Cycle (sec)</th><th class="num">Hours</th><th>Due</th></tr></thead><tbody>' + (t2 || '<tr><td colspan=10 class="mut">Nothing to make.</td></tr>') + "</tbody></table>");
    bindBar("Production plan - part and process wise", 2);
  }

  /* ---------- Machine wise ---------- */
  function drawMach() {
    const C = S.c;
    $("#mach").innerHTML = monthBar() + '<p class="note">Every machine with the parts and processes it must run this month, the quantity and the hours. Machines come from the route; where the route has none, from the machine last used in the ERP.</p>' +
      (C.mach.length ? C.mach.map((m, i) => '<div class="ph"><h3>' + (i + 1) + ". " + esc(m.machine) + " " + chip(m.load.toFixed(0) + "% load", m.load > 100 ? "r" : m.load > 85 ? "a" : "g") + '<span class="grow"></span><small class="mut">' + n0(m.qty) + " pcs · " + n1(m.hrs) + " h · " + n1(m.days) + " days</small></h3>" +
        T('<table><thead><tr><th>S.No</th><th>Part</th><th>Process</th><th class="num">Quantity</th><th class="num">Cycle (sec)</th><th class="num">Hours</th><th>Due</th></tr></thead><tbody>' + (m.items.length ? m.items.map((r, j) => "<tr><td>" + (j + 1) + "</td><td>" + nm(r) + "</td><td>" + esc(r.stage) + '</td><td class="num">' + n0(r.make) + '</td><td class="num">' + (r.ct || "–") + '</td><td class="num">' + n1(r.hrs) + "</td><td>" + (r.due ? esc(String(r.due)) : "") + "</td></tr>").join("") : '<tr><td colspan=7 class="mut">Nothing to make.</td></tr>') + "</tbody></table>") + "</div>").join("") : '<p class="mut">Nothing to make this month.</p>');
    bindBar("Production plan - machine wise", 3);
  }

  /* ---------- Entry (manual): stage stocks (shared with Raw Material Plan), extra demand lines, process stock, working time ---------- */
  const PSF = [["safety", "Minimum stock"], ["rrs", "Supermarket"], ["fg", "FG"], ["fi", "FI"], ["wip", "WIP"], ["wip2", "WIP stage 2"], ["inc", "Incoming"], ["sup", "Supplier"]];
  function drawEntry() {
    const d = S.d, ed = canEdit() ? "" : "disabled", C = S.c, cfg = C.cfg, stk = {}; (d.stock || []).forEach((s) => { stk[s.part + "|" + s.seq] = s.qty; });
    const prows = C.parts.map((p, i) => { const b = (d.ps || {})[nk(p.part)] || {}; return '<tr data-p="' + esc(p.part) + '"><td>' + (i + 1) + "</td><td>" + nm(p) + "</td>" + PSF.map((f) => '<td><input class="n ps" data-f="' + f[0] + '" type="number" min="0" value="' + (b[f[0]] ? b[f[0]] : "") + '" placeholder="0" ' + ed + "></td>").join("") + "</tr>"; }).join("");
    const srows = C.rows.filter((r) => r.type !== "supplier").map((r, i) => '<tr data-p="' + esc(r.part) + '" data-s="' + r.seq + '"><td>' + (i + 1) + "</td><td>" + nm(r) + "</td><td>" + r.seq + ". " + esc(r.stage) + '</td><td><input class="n st" type="number" min="0" value="' + (stk[r.part + "|" + r.seq] != null ? stk[r.part + "|" + r.seq] : "") + '" placeholder="' + (r.ssrc === "ERP" ? Math.round(r.stock) + " (ERP)" : "0") + '" ' + ed + "></td></tr>").join("");
    const mrows = (d.manual || []).map((m, i) => manualRow(m, i)).join("");
    $("#entry").innerHTML = '<div class="row"><label>Month <input type="month" id="pm" value="' + S.month + '" style="width:auto"></label><button class="btn sm" id="pgo">Show</button></div><div id="pmsg"></div>' +
      '<p class="note">The stock boxes are the same numbers as the Raw Material Plan work sheet: a change here shows there, and the other way round. Process stock is optional and used only when no WIP is entered (then the ERP production history fills it).</p>' +
      '<div class="box"><h3>Working time (used for machine hours available)</h3><div class="frm"><div><label>Hours per machine per day</label><input class="n" id="chpd" type="number" min="1" max="24" value="' + cfg.hpd + '" ' + ed + '></div><div><label>Efficiency %</label><input class="n" id="ceff" type="number" min="1" max="100" value="' + cfg.eff + '" ' + ed + '></div><div><label>Working days in the month</label><input class="n" id="cdays" type="number" min="1" max="31" value="' + cfg.days + '" ' + ed + "></div></div></div>" +
      '<div class="box"><h3>Extra demand lines (parts not in Sales Flow)</h3>' + T('<table id="mt"><thead><tr><th>S.No</th><th>Part code</th><th>Part name</th><th class="num">Quantity</th><th>Due date</th><th>Note</th><th></th></tr></thead><tbody>' + mrows + "</tbody></table>") + (canEdit() ? '<button class="btn o sm" id="madd">+ Add line</button>' : "") + "</div>" +
      '<div class="box"><h3>Stage stocks per part (pieces)</h3>' + T('<table id="spt"><thead><tr><th>S.No</th><th>Part</th>' + PSF.map((f) => '<th class="num">' + f[1] + "</th>").join("") + "</tr></thead><tbody>" + (prows || '<tr><td colspan=10 class="mut">No parts have a schedule.</td></tr>') + "</tbody></table>") + "</div>" +
      '<div class="box"><h3>Stock after each process (pieces waiting for the next process)</h3>' + T('<table id="stt"><thead><tr><th>S.No</th><th>Part</th><th>Process</th><th class="num">Stock</th></tr></thead><tbody>' + (srows || '<tr><td colspan=4 class="mut">No routes.</td></tr>') + "</tbody></table>") + "</div>" +
      (canEdit() ? '<div class="row"><button class="btn" id="psv">Save</button><span id="pmsg2" class="mut"></span></div>' : "");
    const R = $("#entry"); R.querySelector("#pgo").onclick = () => { const v = R.querySelector("#pm").value; if (v) { S.month = v; route(); } };
    if (!canEdit()) return;
    R.querySelector("#madd").onclick = () => { R.querySelector("#mt tbody").insertAdjacentHTML("beforeend", manualRow({}, R.querySelectorAll("#mt tbody tr").length)); };
    R.querySelector("#mt").addEventListener("click", (e) => { const b = e.target.closest(".mdel"); if (b) b.closest("tr").remove(); });
    R.querySelector("#psv").onclick = async () => {
      const v = (el) => el.value.trim();
      const p_ps = [...R.querySelectorAll("#spt tbody tr[data-p]")].map((tr) => { const o = { part: tr.dataset.p }; tr.querySelectorAll("input.ps").forEach((i) => { o[i.dataset.f] = v(i) === "" ? "0" : v(i); }); return o; });
      const p_stock = [...R.querySelectorAll("#stt tbody tr[data-p]")].filter((tr) => v(tr.querySelector("input")) !== "").map((tr) => ({ part: tr.dataset.p, seq: tr.dataset.s, qty: v(tr.querySelector("input")) }));
      const p_demand = [...R.querySelectorAll("#mt tbody tr")].map((tr) => { const i = tr.querySelectorAll("input"); return { part: v(i[0]), name: v(i[1]), qty: v(i[2]), due: v(i[3]), note: v(i[4]) }; }).filter((x) => x.part);
      const p_cfg = { hpd: R.querySelector("#chpd").value, eff: R.querySelector("#ceff").value, days: R.querySelector("#cdays").value };
      try { await call("kmr_ppl_save", { p_month: S.month, p_ps, p_stock, p_demand, p_cfg }); R.querySelector("#pmsg2").textContent = "Saved."; setTimeout(route, 400); } catch (e) { say(e.message); }
    };
  }
  function manualRow(m, i) {
    return "<tr><td>" + (i + 1) + '</td><td><input value="' + esc(m.part || "") + '"></td><td><input value="' + esc(m.name || "") + '"></td><td><input class="n" type="number" min="0" value="' + (m.qty == null ? "" : m.qty) + '"></td><td><input type="date" value="' + esc(m.due ? String(m.due).slice(0, 10) : "") + '"></td><td><input value="' + esc(m.note || "") + '"></td><td><button class="btn o sm mdel" type="button">Remove</button></td></tr>';
  }

  window.PPL = { calc };
  (async () => { try { await QP.init("ppl", "kmr_ppl_context"); if (!QP.ctx) return; await route(); } catch (e) { say(e.message); } })();
})();
