/* Budget (BUD) screens: dashboard, budget vs actual, set budget & actuals, receipts & issues, rates. */
(function () {
  "use strict";
  const { $, esc, say, call } = QP;
  const HEADS = [
    ["rm", "Raw material", "#2563eb", "rmp", "Raw material bought on GRN (valued at the PO rate) or received in Raw Material Planning; issued = kg on route sheets x rate"],
    ["tool", "Tooling", "#7c3aed", "dcg", "Inserts, drills, end mills, holders bought on GRN; used = tool changes recorded in Material Movement x tool rate"],
    ["cons", "Consumables", "#0d9488", "dcg", "Coolant, oils, grease, gloves, blades bought on GRN; used = consumable issues in Material Movement x rate"],
    ["man", "Manpower", "#ea580c", "hrms", "HRM payroll, final runs (gross pay)"],
    ["pwr", "Electricity", "#eab308", "mmd", "Electricity bill entered by you; if none is entered, an estimate = machine run hours x kW x tariff"],
    ["out", "Outside processing", "#db2777", "dcg", "Heat treatment, plating, grinding and other job work received on GRN"],
    ["mnt", "Maintenance & spares", "#64748b", "mnt", "Repairs, servicing and spares on GRN plus the Maintenance log"],
    ["oth", "Gauges, fixtures & other", "#94a3b8", "dcg", "Gauges, fixtures, machines and everything on GRN that fits no other head"]
  ];
  const HN = Object.fromEntries(HEADS.map((h) => [h[0], h[1]])), HC = Object.fromEntries(HEADS.map((h) => [h[0], h[2]]));
  const S = { go: null, from: "", to: "", d: null, rates: null };
  const td = () => new Date(Date.now() + 19800000).toISOString().slice(0, 10);
  const inr = (v) => (v == null ? "–" : (v < 0 ? "−" : "") + "₹" + Math.abs(Math.round(v)).toLocaleString("en-IN"));
  const lk = (v) => (v == null ? "–" : Math.abs(v) >= 1e7 ? (v / 1e7).toFixed(2) + " Cr" : Math.abs(v) >= 1e5 ? (v / 1e5).toFixed(2) + " L" : Math.round(v).toLocaleString("en-IN"));
  const mAdd = (ym, n) => { let y = +ym.slice(0, 4), m = +ym.slice(5, 7) - 1 + n; y += Math.floor(m / 12); m = ((m % 12) + 12) % 12; return y + "-" + String(m + 1).padStart(2, "0"); };
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const mlab = (ym) => MON[+ym.slice(5, 7) - 1] + " " + ym.slice(2, 4);
  const mlong = (ym) => MON[+ym.slice(5, 7) - 1] + " " + ym.slice(0, 4);
  const canEdit = () => QP.canEdit;
  const sum = (rows, k) => rows.reduce((a, r) => a + (+r[k] || 0), 0);
  const hashGo = () => { const m = location.hash.match(/go=([a-z]+)/); return m ? m[1] : "std"; };
  const rep = (title, no) => { if (window.KMRReport) window.KMRReport.set({ title, doc: "", format: "KMR/BUD/F-" + no, rev: "01", date: "2026-11-19" }); };
  const appUrl = (p) => p + "?" + new URLSearchParams(location.search).toString();
  const T = (html) => '<div class="sc">' + html + "</div>";
  const tone = (p) => (p > 100 ? "var(--r)" : p > 85 ? "var(--a)" : "var(--g)");

  /* ---- auto-hide menu (remembered on this device) ---- */
  (function () {
    const top = $("#top"), cb = $("#ahc"); let on = true; try { on = localStorage.getItem("bud-ah") !== "0"; } catch (e) { /* ignore */ }
    const apply = () => { document.body.classList.toggle("ah", on); cb.checked = on; top.classList.remove("show"); };
    const show = () => top.classList.add("show"), hide = () => { if (!top.contains(document.activeElement) || !top.matches(":hover")) top.classList.remove("show"); };
    $("#rev").addEventListener("mouseenter", show); $("#pill").addEventListener("click", show);
    top.addEventListener("mouseleave", () => { if (document.body.classList.contains("ah")) setTimeout(() => { if (!top.matches(":hover")) top.classList.remove("show"); }, 250); });
    document.addEventListener("click", (e) => { if (document.body.classList.contains("ah") && !top.contains(e.target) && e.target.id !== "pill") top.classList.remove("show"); });
    top.addEventListener("click", (e) => { if (e.target.closest(".tab") && document.body.classList.contains("ah")) setTimeout(() => top.classList.remove("show"), 150); });
    cb.addEventListener("change", () => { on = cb.checked; try { localStorage.setItem("bud-ah", on ? "1" : "0"); } catch (e) { /* ignore */ } apply(); });
    apply();
  })();

  function months() { if (!S.from) { const cur = td().slice(0, 7); S.to = cur; S.from = mAdd(cur, -5); } return [S.from, S.to]; }
  async function load() { const [f, t] = months(); S.d = await call("kmr_bud_data", { p_from: f, p_to: t }); }
  function pickBar(title) {
    const [f, t] = months();
    return '<div class="row"><label>From <input type="month" id="mf" value="' + f + '" style="width:auto"></label><label>To <input type="month" id="mt" value="' + t + '" style="width:auto"></label><button class="btn sm" id="mgo">Show</button><span class="grow"></span><button class="btn o sm" id="mpr">Print report</button></div>';
  }
  function bindBar(title, no) {
    const R = $("#" + S.go) || document, q = (id) => R.querySelector(id);   // every screen has its own From / To boxes: use the ones on this screen
    q("#mgo").onclick = () => { const f = q("#mf").value, t = q("#mt").value; if (!f || !t || f > t) { say("Choose the From month and a To month that is not earlier."); return; } S.from = f; S.to = t; route(); };
    q("#mpr").onclick = () => { rep(title, no); window.print(); };
  }
  function pbar(used, bud) { if (!bud) return '<span class="mut">no budget</span>'; const p = 100 * used / bud; return '<div class="pb"><i class="' + (p > 100 ? "r" : p > 85 ? "a" : "") + '" style="width:' + Math.min(100, p) + '%"></i></div><small class="mut">' + p.toFixed(0) + "% used</small>"; }

  async function route() {
    const go = hashGo(); S.go = go;
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go));
    ["std", "dash", "stat", "plan", "flow", "rate"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go));
    window.scrollTo(0, 0);
    if (go === "std") { KMRStd.draw($("#std"), "bud"); return; }
    try {
      if (go === "rate") { S.rates = await call("kmr_bud_rates", {}); drawRate(); return; }
      await load(); ({ dash: drawDash, stat: drawStat, plan: drawPlan, flow: drawFlow })[go]();
    } catch (e) { say(e.message); }
  }
  document.addEventListener("click", (e) => { const a = e.target.closest('a[href^="#go="]'); if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; e.preventDefault(); history.replaceState(null, "", location.pathname + location.search + a.getAttribute("href")); route(); });
  window.addEventListener("hashchange", route);

  /* per head totals for the chosen months */
  function byHead(R) { return HEADS.map((h) => { const r = R.filter((x) => x.head === h[0]); return { k: h[0], n: h[1], c: h[2], b: sum(r, "budget"), a: sum(r, "actual"), i: sum(r, "intake"), o: sum(r, "outward"), basis: [...new Set(r.map((x) => x.basis).filter((x) => x !== "none"))].join(", ") || "no data yet", ass: r.some((x) => (x.assumed || []).length), miss: r.reduce((a, x) => a + (+x.missing_rate || 0), 0), est: r.some((x) => x.basis && x.basis.indexOf("estimate") === 0), n_grn: sum(r, "grn_lines") }; }); }
  const monthTot = (R, ms) => ms.map((m) => { const r = R.filter((x) => x.month === m); return { m, b: sum(r, "budget"), a: sum(r, "actual"), pcs: (r[0] || {}).pieces || 0 }; });

  /* ---------- svg helpers ---------- */
  function donut(items, size) {
    const tot = items.reduce((a, x) => a + x.v, 0); if (!tot) return '<p class="note">No spend recorded for these months.</p>';
    const R = 70, r = 42, c = 90; let ang = -Math.PI / 2, out = "";
    items.filter((x) => x.v > 0).forEach((x) => {
      const a2 = ang + 2 * Math.PI * x.v / tot, big = a2 - ang > Math.PI ? 1 : 0;
      const p = (rad, a) => (c + rad * Math.cos(a)).toFixed(1) + " " + (c + rad * Math.sin(a)).toFixed(1);
      out += '<path d="M' + p(R, ang) + " A" + R + " " + R + " 0 " + big + " 1 " + p(R, a2 - 0.0001) + " L" + p(r, a2 - 0.0001) + " A" + r + " " + r + " 0 " + big + " 0 " + p(r, ang) + 'Z" fill="' + x.c + '"><title>' + esc(x.n) + ": " + inr(x.v) + " (" + (100 * x.v / tot).toFixed(1) + "%)</title></path>"; ang = a2;
    });
    return '<div style="display:flex;gap:14px;align-items:center;flex-wrap:wrap"><svg viewBox="0 0 180 180" width="170" height="170" role="img" aria-label="Share of spend by head">' + out + '<text x="90" y="86" text-anchor="middle" font-size="11" fill="currentColor" opacity=".6">Total</text><text x="90" y="104" text-anchor="middle" font-size="14" font-weight="700" fill="currentColor">' + lk(tot) + "</text></svg><div style=\"font-size:12px;flex:1;min-width:150px\">" +
      items.filter((x) => x.v > 0).sort((a, b) => b.v - a.v).map((x) => '<div style="display:flex;justify-content:space-between;gap:8px;margin:3px 0"><span><i style="display:inline-block;width:10px;height:10px;border-radius:3px;background:' + x.c + ';margin-right:5px"></i>' + esc(x.n) + "</span><b>" + (100 * x.v / tot).toFixed(1) + "%</b></div>").join("") + "</div></div>";
  }
  function trend(tm) {
    const W = 560, H = 220, pl = 44, pr = 40, pt = 14, pb = 26, n = tm.length, mx = Math.max(1, ...tm.map((x) => Math.max(x.b, x.a))) * 1.1, bw = (W - pl - pr) / n;
    const y = (v) => pt + (H - pt - pb) * (1 - v / mx); let o = "";
    for (let i = 0; i <= 4; i++) { const v = mx * i / 4, yy = y(v); o += '<line x1="' + pl + '" x2="' + (W - pr) + '" y1="' + yy + '" y2="' + yy + '" stroke="currentColor" opacity=".12"/><text x="' + (pl - 4) + '" y="' + (yy + 3) + '" text-anchor="end" font-size="9" fill="currentColor" opacity=".65">' + lk(v) + "</text>"; }
    let pts = [];
    tm.forEach((x, i) => {
      const x0 = pl + i * bw + bw * 0.15, w = bw * 0.33;
      o += '<rect x="' + x0 + '" y="' + y(x.b) + '" width="' + w + '" height="' + (H - pb - y(x.b)) + '" fill="#94a3b8" rx="2"><title>Budget ' + mlong(x.m) + ": " + inr(x.b) + "</title></rect>";
      o += '<rect x="' + (x0 + w + 2) + '" y="' + y(x.a) + '" width="' + w + '" height="' + (H - pb - y(x.a)) + '" fill="' + (x.b && x.a > x.b ? "#dc2626" : "#2563eb") + '" rx="2"><title>Actual ' + mlong(x.m) + ": " + inr(x.a) + "</title></rect>";
      o += '<text x="' + (pl + i * bw + bw / 2) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="10" fill="currentColor" opacity=".75">' + mlab(x.m) + "</text>";
      if (x.b) pts.push([pl + i * bw + bw / 2, pt + (H - pt - pb) * (1 - Math.min(150, 100 * x.a / x.b) / 150), 100 * x.a / x.b, x.m]);
    });
    if (pts.length) { o += '<polyline fill="none" stroke="#ea580c" stroke-width="2" points="' + pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ") + '"/>' + pts.map((p) => '<circle cx="' + p[0].toFixed(1) + '" cy="' + p[1].toFixed(1) + '" r="3.5" fill="#ea580c"><title>' + mlong(p[3]) + ": " + p[2].toFixed(0) + "% of budget used</title></circle>").join(""); }
    return '<svg viewBox="0 0 ' + W + " " + H + '" style="width:100%;height:auto;max-height:290px" role="img" aria-label="Budget and actual by month">' + o + '</svg><div class="lg"><span><i style="background:#94a3b8"></i>Budget</span><span><i style="background:#2563eb"></i>Actual</span><span><i style="background:#dc2626"></i>Actual above budget</span><span><i style="background:#ea580c"></i>% of budget used (right line)</span></div>';
  }
  function spark(vals, color) {
    if (vals.length < 2) return ""; const mx = Math.max(1, ...vals), W = 100, H = 24;
    return '<svg class="sp" viewBox="0 0 ' + W + " " + H + '" width="100%" height="24" preserveAspectRatio="none"><polyline fill="none" stroke="' + color + '" stroke-width="2" points="' + vals.map((v, i) => (i * W / (vals.length - 1)).toFixed(1) + "," + (H - 2 - (H - 4) * v / mx).toFixed(1)).join(" ") + '"/></svg>';
  }

  /* ---------- Dashboard ---------- */
  function drawDash() {
    const R = S.d.rows, ms = S.d.months, tm = monthTot(R, ms), H = byHead(R), tb = sum(R, "budget"), ta = sum(R, "actual"), pcs = sum(tm, "pcs"), cur = S.d.today.slice(0, 7);
    const over = H.filter((x) => x.b && x.a > x.b), nob = H.filter((x) => !x.b && x.a > 0);
    const per = ms.length > 1 ? mlong(ms[0]) + " to " + mlong(ms[ms.length - 1]) : mlong(ms[0]);
    /* month-end projection for the running month (purchases come in lumps, so this is a guide only) */
    const dN = +S.d.today.slice(8, 10), dT = new Date(+cur.slice(0, 4), +cur.slice(5, 7), 0).getDate(), cm = R.filter((x) => x.month === cur);
    const proj = cm.length ? sum(cm, "actual") * dT / Math.max(1, dN) : null, cb = cm.length ? sum(cm, "budget") : 0;
    const pw = R.filter((x) => x.head === "pwr"), eEnt = pw.filter((x) => x.entered), eGap = eEnt.length ? { b: sum(eEnt, "actual"), e: sum(eEnt, "estimate") } : null;
    const cpp = pcs > 0 ? ta / pcs : null;
    const used = tb ? 100 * ta / tb : null;
    const kp = (label, val, sub, c, extra) => '<div class="kpi" style="--c:' + c + '"><span>' + label + "</span><b>" + val + "</b><small class=\"mut\">" + (sub || "") + "</small>" + (extra || "") + "</div>";
    let h = pickBar() + '<div class="kpis">' +
      kp("Budget · " + esc(per), tb ? inr(tb) : "Not set", tb ? "" : "Open Set budget & actuals", "var(--b1)", spark(tm.map((x) => x.b), "#94a3b8")) +
      kp("Actual spend", inr(ta), used != null ? used.toFixed(0) + "% of budget" : "", used != null ? tone(used) : "var(--b1)", spark(tm.map((x) => x.a), "#2563eb")) +
      kp(tb && ta > tb ? "Over budget by" : "Left in budget", tb ? inr(Math.abs(tb - ta)) : "–", "", tb && ta > tb ? "var(--r)" : "var(--g)") +
      kp("Heads over budget", over.length, nob.length ? nob.length + " spending with no budget" : "", over.length ? "var(--a)" : "var(--g)") +
      (proj != null ? kp("Projected " + mlab(cur) + " month-end", inr(proj), cb ? (100 * proj / cb).toFixed(0) + "% of its budget (day " + dN + " of " + dT + ")" : "day " + dN + " of " + dT, cb ? tone(100 * proj / cb) : "var(--b1)") : "") +
      kp("Cost per piece made", cpp != null ? "₹" + cpp.toFixed(2) : "–", cpp != null ? Math.round(pcs).toLocaleString("en-IN") + " pieces (ERP history)" : "no production quantity", "var(--b2)") + "</div>";
    h += '<div class="grid">';
    h += '<div class="cd"><h3>1 · Budget used by head</h3>' + (tb ? "" : '<p class="note">No budget set; bars show spend only.</p>') + H.filter((x) => x.b || x.a).map((x) => {
      const mx = Math.max(x.b, x.a) * 1.12 || 1, p = x.b ? 100 * x.a / x.b : null;
      return '<div class="bl"><span>' + esc(x.n) + '</span><div class="bt"><i style="width:' + (100 * x.a / mx).toFixed(1) + "%;background:" + (p == null ? x.c : tone(p)) + '"></i>' + (x.b ? '<b style="left:' + (100 * x.b / mx).toFixed(1) + '%" title="Budget"></b>' : "") + '</div><span class="num">' + (p != null ? p.toFixed(0) + "%" : lk(x.a)) + "</span></div>";
    }).join("") + '<div class="lg"><span><i style="background:var(--g)"></i>up to 85%</span><span><i style="background:var(--a)"></i>85–100%</span><span><i style="background:var(--r)"></i>over budget</span><span>│ black line = budget</span></div></div>';
    h += '<div class="cd"><h3>2 · Where the money goes</h3>' + donut(H.map((x) => ({ n: x.n, c: x.c, v: x.a }))) + "</div>";
    h += '<div class="cd wide"><h3>3 · Month by month — budget, actual and % used</h3>' + trend(tm) + "</div>";
    h += '<div class="cd"><h3>4 · Over / under budget by head</h3>' + (tb ? (() => { const mx = Math.max(1, ...H.filter((x) => x.b).map((x) => Math.abs(x.b - x.a))); return H.filter((x) => x.b).map((x) => { const d = x.b - x.a, w = 50 * Math.abs(d) / mx; return '<div class="dv"><span>' + esc(x.n) + '</span><div class="t"><i style="' + (d >= 0 ? "left:50%;" : "right:50%;") + "width:" + w.toFixed(1) + "%;background:" + (d >= 0 ? "var(--g)" : "var(--r)") + '" title="' + (d >= 0 ? "under " : "over ") + inr(Math.abs(d)) + '"></i></div></div><div class="num mut" style="font-size:11px;margin:-4px 0 4px">' + (d >= 0 ? "under " : "over ") + inr(Math.abs(d)) + "</div>"; }).join(""); })() + '<div class="lg"><span><i style="background:var(--g)"></i>under budget (right)</span><span><i style="background:var(--r)"></i>over budget (left)</span></div>' : '<p class="note">Set a budget to see this.</p>') + "</div>";
    h += '<div class="cd wide"><h3>5 · Heat map — % of budget used, head by month</h3>' + T('<table class="hm"><thead><tr><th>Head</th>' + ms.map((m) => "<th>" + mlab(m) + "</th>").join("") + "</tr></thead><tbody>" + HEADS.map((hd) => "<tr><td style=\"text-align:left;color:inherit;font-weight:600\">" + hd[1] + "</td>" + ms.map((m) => { const r = R.find((x) => x.head === hd[0] && x.month === m) || {}; if (!r.budget) return '<td style="background:var(--bg);color:var(--mut);font-weight:400" title="Actual ' + inr(r.actual) + '">' + (r.actual ? lk(r.actual) : "–") + "</td>"; const p = 100 * r.actual / r.budget; return '<td style="background:' + (p > 100 ? "#fca5a5" : p > 85 ? "#fde68a" : "#bbf7d0") + '" title="Actual ' + inr(r.actual) + " of " + inr(r.budget) + '">' + p.toFixed(0) + "%</td>"; }).join("") + "</tr>").join("") + "</tbody></table>") + '<div class="lg"><span>Grey = no budget (amount shown is the actual)</span></div></div>';
    h += '<div class="cd"><h3>6 · Cost per piece by month</h3>' + (tm.some((x) => x.pcs > 0) ? (() => { const v = tm.map((x) => (x.pcs ? x.a / x.pcs : 0)), mx = Math.max(1, ...v); return tm.map((x, i) => '<div class="bl"><span>' + mlab(x.m) + '</span><div class="bt"><i style="width:' + (100 * v[i] / mx).toFixed(1) + '%;background:#7c3aed"></i></div><span class="num">₹' + v[i].toFixed(2) + "</span></div>").join(""); })() : '<p class="note">No production quantity in the ERP history for these months.</p>') + "</div>";
    h += '<div class="cd"><h3>7 · Electricity check</h3>' + (pw.some((x) => x.actual || x.estimate) ? pw.map((x) => '<div class="bl"><span>' + mlab(x.month) + '</span><div class="bt"><i style="width:' + Math.min(100, 100 * (x.estimate || 0) / (Math.max(x.estimate, x.actual) || 1)).toFixed(0) + '%;background:#eab308"></i></div><span class="num">' + (x.entered ? "bill " + lk(x.actual) : "est. " + lk(x.estimate)) + "</span></div>").join("") + '<p class="note">' + (eGap ? "Where a bill is entered, it replaces the estimate. Entered bills are " + (100 * (eGap.b - eGap.e) / Math.max(1, eGap.e)).toFixed(0) + "% " + (eGap.b >= eGap.e ? "above" : "below") + " the run-hours estimate: use it to correct the kW and tariff on the Rates screen." : "No electricity bill entered yet, so these are estimates (run hours × kW × tariff). Enter the bill under Set budget & actuals.") + "</p>" : '<p class="note">No machine run hours or bills for these months.</p>') + "</div>";
    h += '<div class="cd wide"><h3>8 · Biggest movers</h3>' + (() => { const rows = H.filter((x) => x.a > 0).sort((a, b) => b.a - a.a).slice(0, 4); return rows.length ? T('<table><thead><tr><th>Head</th><th class="num">Actual</th><th class="num">Share</th><th>Where it comes from</th></tr></thead><tbody>' + rows.map((x) => "<tr><td><b>" + esc(x.n) + '</b></td><td class="num">' + inr(x.a) + '</td><td class="num">' + (100 * x.a / ta).toFixed(1) + "%</td><td class=\"mut\" style=\"font-size:12px\">" + esc(x.basis) + "</td></tr>").join("") + "</tbody></table>") : '<p class="note">Nothing yet.</p>'; })() + "</div>";
    h += "</div>";
    $("#dash").innerHTML = h; bindBar("Budget dashboard", 1);
  }

  /* ---------- Budget vs actual ---------- */
  function drawStat() {
    const R = S.d.rows, ms = S.d.months, H = byHead(R), tb = sum(R, "budget"), ta = sum(R, "actual");
    const per = ms.length > 1 ? mlong(ms[0]) + " to " + mlong(ms[ms.length - 1]) : mlong(ms[0]);
    $("#stat").innerHTML = pickBar() + '<p class="note">Period: ' + esc(per) + ". Actual = what was bought on GRN (valued at the PO rate) or the figure you entered; where nothing was bought, the value used is shown, and the last column says which.</p>" +
      T('<table><thead><tr><th>Head</th><th class="num">Budget</th><th class="num">Actual</th><th class="num">Difference</th><th>Used</th><th>Where the actual comes from</th></tr></thead><tbody>' +
        H.map((x) => { const d = x.b - x.a; return '<tr><td><b>' + esc(x.n) + '</b></td><td class="num">' + inr(x.b) + '</td><td class="num">' + inr(x.a) + '</td><td class="num ' + (x.b && d < 0 ? "over" : "") + '">' + (x.b ? (d < 0 ? "over " : "under ") + inr(Math.abs(d)) : "–") + "</td><td>" + pbar(x.a, x.b) + '</td><td class="mut" style="font-size:12px">' + esc(x.basis) + (x.est ? ' <span class="chip a" title="Enter the electricity bill under Set budget & actuals">estimate</span>' : "") + (x.ass ? ' <span class="chip a" title="Set the real kW and tariff on the Rates screen">assumed rates</span>' : "") + (x.miss ? ' <span class="chip a" title="Enter the rate on the Rates screen">' + x.miss + " without a rate</span>" : "") + "</td></tr>"; }).join("") +
        '<tr style="font-weight:700;background:var(--bg)"><td>Total</td><td class="num">' + inr(tb) + '</td><td class="num">' + inr(ta) + '</td><td class="num ' + (tb && ta > tb ? "over" : "") + '">' + (tb ? (ta > tb ? "over " : "under ") + inr(Math.abs(tb - ta)) : "–") + "</td><td>" + pbar(ta, tb) + "</td><td></td></tr></tbody></table>") +
      (ms.length > 1 ? '<h3 style="margin:14px 0 4px">Month by month</h3>' + T('<table><thead><tr><th>Month</th><th class="num">Budget</th><th class="num">Actual</th><th class="num">Difference</th><th>Used</th></tr></thead><tbody>' + monthTot(R, ms).map((x) => "<tr><td>" + mlong(x.m) + '</td><td class="num">' + inr(x.b) + '</td><td class="num">' + inr(x.a) + '</td><td class="num ' + (x.b && x.a > x.b ? "over" : "") + '">' + (x.b ? (x.a > x.b ? "over " : "under ") + inr(Math.abs(x.b - x.a)) : "–") + "</td><td>" + pbar(x.a, x.b) + "</td></tr>").join("") + "</tbody></table>") : "") +
      (tb ? "" : '<p class="note">No budget has been set for these months. Open <b>Set budget &amp; actuals</b>.</p>');
    bindBar("Budget vs actual", 1);
  }

  /* ---------- Set budget & actuals ---------- */
  function drawPlan() {
    const R = S.d.rows, ms = S.d.months, ed = canEdit() ? "" : "disabled";
    const cell = (h, m) => {
      const r = R.find((x) => x.head === h && x.month === m) || {};
      return '<td><label class="mut" style="font-size:10px;margin:0">Budget</label><input class="n" data-h="' + h + '" data-m="' + m + '" data-t="b" type="number" min="0" step="1000" value="' + (r.budget || "") + '" placeholder="0" ' + ed + '>' +
        '<label class="mut" style="font-size:10px;margin:4px 0 0">Actual (type to override)</label><input class="n" data-h="' + h + '" data-m="' + m + '" data-t="a" data-was="' + (r.entered ? 1 : 0) + '" type="number" min="0" step="100" value="' + (r.entered ? r.actual : "") + '" placeholder="' + Math.round(r.actual || 0) + '" ' + ed + ">" +
        (h === "pwr" ? '<label class="mut" style="font-size:10px;margin:4px 0 0">Units on the bill (kWh)</label><input class="n" data-h="pwr" data-m="' + m + '" data-t="u" type="number" min="0" step="1" value="' + (r.units || "") + '" ' + ed + ">" : "") + "</td>";
    };
    $("#plan").innerHTML = pickBar() + '<p class="note"><b>Budget</b> = what you plan to spend. <b>Actual</b> is filled from the other apps; type a figure only where the apps do not hold it, such as the <b>electricity bill</b> (and its kWh units). A typed actual replaces the app figure for that month; clear it to go back to the app figure. The grey number inside the box is the figure the apps give now.</p>' +
      T('<table><thead><tr><th>Head</th>' + ms.map((m) => '<th class="num">' + mlong(m) + "</th>").join("") + "</tr></thead><tbody>" + HEADS.map((h) => "<tr><td><b>" + h[1] + "</b></td>" + ms.map((m) => cell(h[0], m)).join("") + "</tr>").join("") + "</tbody></table>") +
      (canEdit() ? '<div class="row" style="margin-top:12px"><button class="btn" id="bsv">Save</button><button class="btn o" id="bavg">Fill empty budget cells with the average of the 3 months before</button><span id="bmsg" class="mut"></span></div>' : '<p class="note">You can view but not change.</p>');
    bindBar("Set budget and actuals", 1);
    if (!canEdit()) return;
    $("#bsv").onclick = async () => {
      const inp = [...document.querySelectorAll("#plan input.n")], bud = [], act = [], un = {};
      inp.filter((i) => i.dataset.t === "u").forEach((i) => { un[i.dataset.m] = i.value; });
      inp.forEach((i) => {
        if (i.dataset.t === "b") bud.push({ month: i.dataset.m, head: i.dataset.h, amount: i.value === "" ? 0 : +i.value });
        else if (i.dataset.t === "a" && (i.value !== "" || i.dataset.was === "1")) act.push({ month: i.dataset.m, head: i.dataset.h, amount: i.value, units: i.dataset.h === "pwr" ? un[i.dataset.m] : "" });
      });
      try { await call("kmr_bud_save", { p_rows: bud }); await call("kmr_bud_actual_save", { p_rows: act }); $("#bmsg").textContent = "Saved."; await load(); drawPlan(); $("#bmsg").textContent = "Saved."; } catch (e) { say(e.message); }
    };
    $("#bavg").onclick = async () => {
      try {
        const f = mAdd(S.from, -3), t = mAdd(S.from, -1), p = await call("kmr_bud_data", { p_from: f, p_to: t }); let n = 0;
        document.querySelectorAll('#plan input.n[data-t="b"]').forEach((i) => { if (i.value !== "") return; const v = p.rows.filter((x) => x.head === i.dataset.h && x.actual > 0).map((x) => x.actual); if (v.length) { i.value = Math.round(v.reduce((a, b) => a + b, 0) / v.length); n++; } });
        $("#bmsg").textContent = n ? n + " cells filled. Check them, then press Save." : "There was no spend in the 3 months before to average.";
      } catch (e) { say(e.message); }
    };
  }

  /* ---------- Receipts & issues ---------- */
  function drawFlow() {
    const R = S.d.rows, ms = S.d.months, H = byHead(R), tr = sum(H, "i"), to = sum(H, "o");
    const per = ms.length > 1 ? mlong(ms[0]) + " to " + mlong(ms[ms.length - 1]) : mlong(ms[0]);
    $("#flow").innerHTML = pickBar() +
      '<div class="box"><h3>What this screen shows</h3><p class="note" style="margin:0">The stores way of looking at it: <b>Opening stock + Receipts − Issues = Closing stock</b>.<br><b>Receipts</b> = goods that came in on a <b>GRN</b> (Goods Receipt Note), valued at the purchase-order rate. <b>Issues</b> = what left stores for the shop floor or was consumed (material issued on route sheets, tool changes, consumables issued). <b>Net</b> = Receipts − Issues: positive means stock is building up, negative means stock is being run down. Period: ' + esc(per) + ".</p></div>" +
      T('<table><thead><tr><th>Head</th><th class="num">Receipts (GRN)</th><th class="num">Issues</th><th class="num">Net (Receipts − Issues)</th><th class="num">GRN lines</th><th>How issues are measured</th><th></th></tr></thead><tbody>' +
        HEADS.map((hd, i) => { const x = H[i], flow = hd[0] === "rm" || hd[0] === "tool" || hd[0] === "cons"; return "<tr><td><b>" + hd[1] + '</b></td><td class="num">' + inr(x.i) + '</td><td class="num">' + (flow ? (x.o ? inr(x.o) : '<span class="mut" title="Not recorded yet in Material Movement">not recorded</span>') : '<span class="mut">same as receipts</span>') + '</td><td class="num ' + (flow && x.o && x.i < x.o ? "over" : "") + '">' + (flow && x.o ? inr(x.i - x.o) : "–") + '</td><td class="num">' + (x.n_grn || "–") + '</td><td style="font-size:12px" class="mut">' + esc(hd[4]) + '</td><td><button class="btn o sm" data-it="' + hd[0] + '">GRN lines</button> <a class="btn o sm" href="' + appUrl("/it/" + ({ rmp: "rmp", dcg: "dcg", hrms: "hrm", mmd: "mmd", mnt: "mnt" })[hd[3]] + ".html") + '">Open app</a></td></tr>'; }).join("") +
        '<tr style="font-weight:700;background:var(--bg)"><td>Total</td><td class="num">' + inr(tr) + '</td><td class="num">' + inr(to) + "</td><td></td><td></td><td></td><td></td></tr></tbody></table>") +
      '<div id="itm"></div><p class="note">Part-wise, lot-wise and heat-code-wise movement of material is in Material Movement → Traceability. GRN lines are sorted into heads by item words (for example “insert”, “coolant”, “heat treatment”); an item that fits no word lands in “Gauges, fixtures &amp; other”.</p>';
    bindBar("Receipts and issues", 2);
    document.querySelectorAll("[data-it]").forEach((b) => (b.onclick = async () => {
      const k = b.dataset.it; $("#itm").innerHTML = '<p class="note">Loading…</p>';
      try {
        const L = await call("kmr_bud_items", { p_from: S.from, p_to: S.to, p_head: k });
        $("#itm").innerHTML = '<h3 style="margin:12px 0 4px">' + HN[k] + " · GRN lines" + (L.length >= 300 ? " (largest 300)" : "") + "</h3>" + (L.length ? T('<table><thead><tr><th>GRN no</th><th>Date</th><th>Supplier</th><th>Item</th><th class="num">Qty</th><th>Unit</th><th class="num">Rate</th><th class="num">Value</th></tr></thead><tbody>' + L.map((x) => "<tr><td>" + esc(x.grn_no) + "</td><td>" + String(x.grn_date).slice(0, 10).split("-").reverse().join("/") + "</td><td>" + esc(x.supplier || "") + "</td><td>" + esc(x.descr || "") + '</td><td class="num">' + (+x.qty || 0).toLocaleString("en-IN") + "</td><td>" + esc(x.uom || "") + '</td><td class="num">' + (x.rate == null ? '<span class="mut">no PO rate</span>' : inr(x.rate)) + '</td><td class="num">' + inr(x.val) + "</td></tr>").join("") + "</tbody></table>") : '<p class="note">No GRN lines for this head in these months.</p>');
        $("#itm").scrollIntoView({ behavior: "smooth", block: "start" });
      } catch (e) { say(e.message); }
    }));
  }

  /* ---------- Rates ---------- */
  function drawRate() {
    const R = S.rates, P = R.power || {}, D = R.dflt || {}, ed = canEdit() ? "" : "disabled";
    const tbl = (kind, list, title) => '<div class="box"><h3>' + title + "</h3>" + (list.length ? T('<table><thead><tr><th>Code</th><th class="num">Rate (₹ per change / unit)</th></tr></thead><tbody>' + list.map((x) => "<tr><td>" + esc(x.code) + '</td><td class="num"><input class="n rt" data-k="' + kind + '" data-c="' + esc(x.code) + '" type="number" min="0" step="0.01" value="' + (x.rate == null ? "" : x.rate) + '" ' + ed + "></td></tr>").join("") + "</tbody></table>") : '<p class="note">Nothing here yet. Add items in Material Movement (tools / consumables) and they will appear.</p>') + "</div>";
    $("#rate").innerHTML = '<p class="note">These rates turn tool changes, consumable issues and machine run hours into rupees (used when no bill is entered). Leave a rate empty if you do not know it; Budget vs actual then says which rates are missing.</p>' +
      '<div class="box"><h3>Electricity estimate</h3><div class="frm"><div><label>Average load per running machine (kW = kilowatt)</label><input class="n rt" data-k="power" data-c="kw" type="number" min="0" step="0.1" value="' + (P.kw == null ? "" : P.kw) + '" placeholder="15 (assumed)" ' + ed + '></div><div><label>Tariff (₹ per kWh = kilowatt-hour)</label><input class="n rt" data-k="power" data-c="tariff" type="number" min="0" step="0.01" value="' + (P.tariff == null ? "" : P.tariff) + '" placeholder="8 (assumed)" ' + ed + '></div></div><p class="note">Tip: enter the real bill under Set budget &amp; actuals, then adjust kW until the estimate matches the bill.</p></div>' +
      '<div class="box"><h3>Rate when a tool or consumable has no rate of its own</h3><div class="frm"><div><label>Tool, per tool change (₹)</label><input class="n rt" data-k="tool" data-c="*" type="number" min="0" step="0.01" value="' + (D.tool == null ? "" : D.tool) + '" ' + ed + '></div><div><label>Consumable, per unit (₹)</label><input class="n rt" data-k="cons" data-c="*" type="number" min="0" step="0.01" value="' + (D.cons == null ? "" : D.cons) + '" ' + ed + "></div></div></div>" +
      tbl("tool", R.tools || [], "Tools") + tbl("cons", R.cons || [], "Consumables") + (canEdit() ? '<div class="row"><button class="btn" id="rsv">Save rates</button><span id="rmsg" class="mut"></span></div>' : "");
    if (!canEdit()) return;
    $("#rsv").onclick = async () => { const rows = [...document.querySelectorAll("#rate input.rt")].map((i) => ({ kind: i.dataset.k, code: i.dataset.c, rate: i.value })); try { await call("kmr_bud_rate_save", { p_rows: rows }); $("#rmsg").textContent = "Saved."; } catch (e) { say(e.message); } };
  }

  (async () => { try { await QP.init("bud", "kmr_bud_context"); if (!QP.ctx) return; await route(); } catch (e) { say(e.message); } })();
})();
