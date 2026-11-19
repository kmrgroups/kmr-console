/* Material Movement — WIP part map with throughput-time alerts, and the dashboards
   (production efficiency, OEE, capacity utilisation, rejection & rework rate, Pareto five ways, loss hours).
   Everything is worked out from the entries, tags and loss hours already recorded — nothing is typed again. */
(function () {
  "use strict";
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const N = (v, d) => (v == null || isNaN(v) ? "—" : Number(v).toLocaleString("en-IN", { maximumFractionDigits: d == null ? 0 : d }));
  const pc = (v) => (v == null || !isFinite(v) ? "—" : (v * 100).toFixed(1) + "%");
  const D = (v) => (v ? new Date(v).toLocaleDateString("en-IN", { day: "2-digit", month: "short" }) : "—");
  const plant = (m) => { const p = (m && m.plant) || {}; return { H: +p.hoursPerDay > 0 ? +p.hoursPerDay : 16, lag: p.transferLagHours != null && p.transferLagHours !== "" ? +p.transferLagHours : 4, oee: +p.oee > 0 ? +p.oee / 100 : 0.8, off: p.weeklyOff || "Sunday", set: !!m.plant }; };
  const age = (iso, now) => Math.max(0, (now - new Date(iso).getTime()) / 36e5);
  const ctOf = (m, part, seq) => { const r = (m.routes || {})[part]; return r && r[seq - 1] ? +r[seq - 1].ct_sec || 0 : 0; };

  /* ---------- throughput: how long should a lot sit at an operation? transfer time + its run time at the OEE target ---------- */
  function expectH(m, P, part, seq, qty) { const ct = ctOf(m, part, seq); return P.lag + (qty * ct) / 3600 / P.oee; }

  function wip(m, x) {
    const P = plant(m), now = new Date(x.now).getTime(), today = x.today;
    const items = [];
    x.tags.filter((t) => t.status === "open" && t.bal > 0 && ((["RM", "OK"].includes(t.kind) && t.loc === "op") || t.kind === "REW")).forEach((t) => {
      const wh = age(t.created_at, now) * (P.H / 24), ex = expectH(m, P, t.part_code, t.seq, t.bal), ratio = wh / ex;
      items.push({ tag: t, kind: t.kind === "REW" ? "rework" : t.op_type === "supplier" ? "send" : "wait", where: t.op_name, qty: t.bal, since: t.created_at, hrs: age(t.created_at, now), exp: ex, ratio, st: ratio > 2 ? "stuck" : ratio > 1 ? "slow" : "ok" });
    });
    x.dcs.filter((d) => ["open", "part"].includes(d.status)).forEach((d) => {
      const late = d.expected_date && d.expected_date < today, h = age(d.dispatch_at, now), over = d.expected_date ? Math.max(0, (now - new Date(d.expected_date + "T23:59:59").getTime()) / 864e5) : 0;
      items.push({ dc: d, kind: "supplier", where: d.op_name + " — " + (d.supplier_name || d.supplier_code), qty: d.qty - d.received_qty, since: d.dispatch_at, hrs: h, exp: null, ratio: late ? 1 + over : h / 24 > 10 ? 1.5 : 0, st: late ? (over > 2 ? "stuck" : "slow") : (!d.expected_date && h / 24 > 10 ? "slow" : "ok"), part_code: d.part_code, rs_no: d.rs_no, part_name: d.part_name });
    });
    items.forEach((i) => { if (i.tag) { i.part_code = i.tag.part_code; i.rs_no = i.tag.rs_no; i.part_name = i.tag.part_name; } });
    // due-date risk per open route sheet: the working time still needed, from where the lots are now, against the days left
    const risk = [];
    x.rs.filter((r) => r.status === "open").forEach((r) => {
      let need = 0;
      items.filter((i) => i.rs_no === r.rs_no).forEach((i) => {
        if (i.tag) { const from = i.tag.seq, ops = (m.routes || {})[r.part_code] || []; for (let s = from; s <= ops.length; s++) need += s === from && i.kind === "rework" ? P.lag : expectH(m, P, r.part_code, s, i.qty); }
        else if (i.dc) { const ops = (m.routes || {})[r.part_code] || []; for (let s = i.dc.seq + 1; s <= ops.length; s++) need += expectH(m, P, r.part_code, s, i.qty); need += 24 * 2 * (P.H / 24); }
      });
      if (!r.due_date || !need) return;
      const days = Math.ceil(need / P.H * 7 / 6), left = Math.round((new Date(r.due_date + "T00:00:00") - new Date(today + "T00:00:00")) / 864e5);
      if (days > left) risk.push({ r, need, days, left, late: left < 0 });
    });
    return { P, items, risk };
  }

  function wipHtml(m, x) {
    const w = wip(m, x), P = w.P, st = { stuck: ["Not moving", "r"], slow: ["Slow", "a"], ok: ["Moving", "g"] }, ord = { stuck: 0, slow: 1, ok: 2 };
    const k = (n, l, c) => `<div class="kpi" style="--c:${c}"><b>${n}</b><span>${l}</span></div>`, cnt = (s) => w.items.filter((i) => i.st === s).length;
    const pcs = (s) => w.items.filter((i) => i.st === s).reduce((a, i) => a + i.qty, 0);
    const alerts = w.items.filter((i) => i.st !== "ok").sort((a, b) => ord[a.st] - ord[b.st] || b.ratio - a.ratio);
    // part map: for every part, where its pieces lie now
    const parts = {};
    w.items.forEach((i) => { (parts[i.part_code] = parts[i.part_code] || { name: i.part_name, at: {}, fg: 0, rew: 0 }); });
    x.tags.filter((t) => t.loc === "fg" && t.status === "open" && t.bal > 0).forEach((t) => { (parts[t.part_code] = parts[t.part_code] || { name: t.part_name, at: {}, fg: 0, rew: 0 }).fg += t.bal; });
    w.items.forEach((i) => { const p = parts[i.part_code], key = i.tag ? i.tag.seq : i.dc.seq; const c = p.at[key] = p.at[key] || { w: 0, rw: 0, sp: 0, st: "ok" }; if (i.kind === "rework") c.rw += i.qty; else if (i.kind === "supplier") c.sp += i.qty; else c.w += i.qty; if (ord[i.st] < ord[c.st]) c.st = i.st; });
    const map = Object.keys(parts).sort().map((code) => {
      const p = parts[code], ops = (m.routes || {})[code] || [], tot = Object.values(p.at).reduce((a, c) => a + c.w + c.rw + c.sp, 0) + p.fg;
      return `<div class="card"><div class="row" style="margin:0 0 6px"><b>${esc(code)}</b><span class="mut grow">${esc(p.name || "")}</span><span class="chip b">${N(tot)} pcs in the plant</span></div><div style="display:flex;gap:6px;overflow-x:auto;padding-bottom:4px">${ops.map((o) => {
        const c = p.at[o.seq], on = c && (c.w + c.rw + c.sp > 0), col = on ? { ok: "var(--g)", slow: "var(--a)", stuck: "var(--r)" }[c.st] : "var(--line)";
        return `<div style="flex:1;min-width:104px;border:2px solid ${col};border-radius:10px;padding:6px 8px;${on ? "" : "opacity:.55"}"><div style="font-size:11px;font-weight:700">${o.seq}. ${esc(o.name)}${o.type === "supplier" ? " ⚑" : ""}</div><div style="font-size:18px;font-weight:800">${on ? N(c.w + c.rw + c.sp) : "·"}</div>${on ? `<div class="mut" style="font-size:11px">${c.sp ? N(c.sp) + " at supplier " : ""}${c.w ? N(c.w) + " waiting " : ""}${c.rw ? N(c.rw) + " rework" : ""}</div>` : ""}</div>`;
      }).join("")}<div style="flex:1;min-width:90px;border:2px solid ${p.fg ? "var(--g)" : "var(--line)"};border-radius:10px;padding:6px 8px;${p.fg ? "" : "opacity:.55"}"><div style="font-size:11px;font-weight:700">Finished goods</div><div style="font-size:18px;font-weight:800">${p.fg ? N(p.fg) : "·"}</div></div></div></div>`;
    }).join("") || '<p class="note">No material on the floor.</p>';
    return `<p class="note">An operation is expected to take its <b>transfer time (${N(P.lag, 1)} h)</b> plus the <b>run time at the OEE target (${N(P.oee * 100)}%)</b>, counted in working hours (${N(P.H, 1)} h a day)${P.set ? "" : " — Plant standards are not filled in yet, so these defaults are used (Operations Master › Plant standards)"}. A lot that has waited longer than that is <b>slow</b>; more than twice that, <b>not moving</b>. Supplier lots follow the expected-back date on the DC.</p>
    <div class="kpis">${k(N(pcs("stuck")), "pcs not moving (" + cnt("stuck") + " lots)", "var(--r)")}${k(N(pcs("slow")), "pcs moving slowly (" + cnt("slow") + " lots)", "var(--a)")}${k(N(pcs("ok")), "pcs moving as planned", "var(--g)")}${k(w.risk.length, "route sheets at risk of missing the due date", w.risk.length ? "var(--r)" : "var(--g)")}</div>
    ${w.risk.length ? `<div class="card" style="border-left:4px solid var(--r)"><h3>Delivery at risk</h3><table style="min-width:520px"><thead><tr><th>Route sheet</th><th>Part</th><th>Due</th><th class="n">Days left</th><th class="n">Days still needed</th></tr></thead><tbody>${w.risk.map((q) => `<tr><td><b>${esc(q.r.rs_no)}</b></td><td>${esc(q.r.part_code)} <span class="mut">${esc(q.r.part_name || "")}</span></td><td>${D(q.r.due_date)}</td><td class="n ${q.left < 0 ? "late" : ""}">${q.left}</td><td class="n"><b>${q.days}</b></td></tr>`).join("")}</tbody></table></div>` : ""}
    <b>Lots that are not moving</b><table><thead><tr><th>Lot</th><th>Part</th><th>Where</th><th class="n">Qty</th><th>Waiting since</th><th class="n">Waiting (h)</th><th class="n">Expected (h)</th><th>Status</th></tr></thead><tbody>${alerts.map((i) => `<tr><td><b>${esc(i.tag ? i.tag.tag_no : i.dc.dc_no)}</b><div class="mut">${esc(i.rs_no)}</div></td><td>${esc(i.part_code)}<div class="mut">${esc(i.part_name || "")}</div></td><td>${esc(i.where)}${i.kind === "rework" ? ' <span class="chip a">rework</span>' : i.kind === "supplier" ? ' <span class="chip a">supplier</span>' : ""}</td><td class="n">${N(i.qty)}</td><td>${D(i.since)}</td><td class="n">${N(i.hrs, 0)}</td><td class="n">${i.exp != null ? N(i.exp, 1) : i.dc.expected_date ? "back " + D(i.dc.expected_date) : "—"}</td><td><span class="chip ${st[i.st][1]}">${st[i.st][0]}</span></td></tr>`).join("") || '<tr><td colspan="8" class="mut">Everything is moving as planned.</td></tr>'}</tbody></table>
    <div style="height:16px"></div><b>Where every part lies</b><div style="height:8px"></div>${map}`;
  }

  /* ---------- dashboards ---------- */
  function pareto(title, rows, unit, note) {
    const L = rows.filter((r) => r.v > 0).sort((a, b) => b.v - a.v), tot = L.reduce((a, r) => a + r.v, 0), top = L.slice(0, 10);
    let cum = 0; const mx = top.length ? top[0].v : 1;
    return `<div class="card"><h3>${esc(title)}</h3>${note ? `<div class="mut" style="font-size:11px;margin:-4px 0 6px">${esc(note)}</div>` : ""}${top.length ? `<table style="min-width:0"><tbody>${top.map((r) => { const before = cum / tot; cum += r.v; return `<tr><td style="width:34%;word-break:break-word">${esc(r.l)}</td><td style="width:40%"><div style="height:10px;border-radius:5px;background:var(--line)"><div style="height:10px;border-radius:5px;width:${Math.max(3, r.v / mx * 100)}%;background:${before < 0.8 ? "var(--r)" : "#94a3b8"}"></div></div></td><td class="n" style="white-space:nowrap">${N(r.v, unit === "h" ? 1 : 0)}${unit ? " " + unit : ""}</td><td class="n mut" style="white-space:nowrap">${(cum / tot * 100).toFixed(0)}%</td></tr>`; }).join("")}</tbody></table><div class="mut" style="font-size:11px">Red = the “vital few” that make up the first 80%. Total ${N(tot, unit === "h" ? 1 : 0)}${unit ? " " + unit : ""}.</div>` : '<p class="note">Nothing recorded in this period.</p>'}</div>`;
  }
  const group = (arr, keyf, valf) => { const o = {}; arr.forEach((a) => { const k = keyf(a) || "—"; o[k] = (o[k] || 0) + valf(a); }); return Object.keys(o).map((k) => ({ l: k, v: o[k] })); };

  /* ERP production history -> the same shape as the app's own entries and loss rows, so every dashboard works from one source.
     Machine-days that already have app entries are left out on the server. Time a machine neither ran nor logged a reason for is a loss ("not scheduled"). */
  const PLANNED = /holiday|sunday|no (load|plan|order|schedule|work)|not scheduled|planned|festival|lock ?out/i;
  function mergeErp(m, x, E, days) {
    if (!E || !E.prod) return x;
    const P = plant(m), since = new Date(x.today + "T00:00:00").getTime() - (days - 1) * 864e5; let wd = 0;
    for (let i = 0; i < days; i++) { const dow = new Date(since + i * 864e5).getDay(); const off = P.off === "Sunday" ? dow === 0 : P.off === "Saturday & Sunday" ? dow === 0 || dow === 6 : P.off === "Friday" ? dow === 5 : false; if (!off) wd++; }
    /* A day counts only if the ERP really has that day (at least a third as many machines reported as on the busiest day, and not in the future). Days the ERP was not loaded are left out, not counted as lost time. */
    const cnt = {}; E.prod.forEach((r) => { (cnt[r[0]] = cnt[r[0]] || new Set()).add(r[1]); });
    const mxm = Math.max(0, ...Object.keys(cnt).filter((d) => d <= x.today).map((d) => cnt[d].size)), okDay = (d) => d <= x.today && cnt[d] && cnt[d].size >= Math.max(1, 0.3 * mxm); let wdL = 0, loaded = 0;
    for (let i = 0; i < days; i++) { const dt = new Date(since + i * 864e5), iso = dt.toISOString().slice(0, 10), dow = dt.getDay(); const off = P.off === "Sunday" ? dow === 0 : P.off === "Saturday & Sunday" ? dow === 0 || dow === 6 : P.off === "Friday" ? dow === 5 : false; if (okDay(iso)) { loaded++; if (!off) wdL++; } }
    E = Object.assign({}, E, { prod: E.prod.filter((r) => okDay(r[0])), idle: E.idle.filter((r) => okDay(r[0])) }); wd = wdL;
    const entries = (x.entries || []).slice(), loss = (x.loss || []).slice(), mc = {};
    const M = (c) => (mc[c] = mc[c] || { op: 0, idle: 0, plan: 0 });
    E.prod.forEach((r) => { const q = +r[2], sh = +r[4]; M(r[1]).op += +r[5]; entries.push({ id: "erp", kind: "process", status: "ok", machine: r[1], ok_qty: q, rej_qty: +r[3], rew_qty: 0, ct_sec: q ? sh * 3600 / q : 0, entry_at: r[0] + "T12:00:00", src: "erp", part_code: "", rs_no: "ERP history" }); });
    E.idle.forEach((r) => { const pl = PLANNED.test(r[2]), h = +r[3]; if (pl) M(r[1]).plan += h; else M(r[1]).idle += h; loss.push({ machine_code: r[1], d_code: pl ? "ERP-P" : "ERP", d_name: r[2], minutes: h * 60, loss_date: r[0], status: "ok", src: "erp" }); });
    Object.keys(mc).forEach((c) => { const a = mc[c], ns = P.H * wd - Math.min(a.plan, P.H * wd) - a.op - a.idle; if (ns > 0.5) loss.push({ machine_code: c, d_code: "ERP", d_name: "NOT SCHEDULED / NO ENTRY", minutes: ns * 60, loss_date: x.today, status: "ok", src: "erp" }); });
    const lcs = (m.loss_codes || []).concat([{ code: "ERP-P", name: "ERP planned stop", planned: "Yes" }]);
    return Object.assign({}, x, { entries, loss, erp_rows: E.rows || 0, erp_last: E.last, _lc: lcs, _wd: wdL, _erpdays: { loaded, total: days } });
  }
  function dash(m, x, days, kind) {
    const P = plant(m), since = new Date(x.today + "T00:00:00").getTime() - (days - 1) * 864e5, inWin = (iso) => new Date(String(iso).slice(0, 10) + "T00:00:00").getTime() >= since;
    // working days in the window (weekly off removed)
    let wd = 0; for (let i = 0; i < days; i++) { const dd = new Date(since + i * 864e5), dow = dd.getDay(); const off = P.off === "Sunday" ? dow === 0 : P.off === "Saturday & Sunday" ? dow === 0 || dow === 6 : P.off === "Friday" ? dow === 5 : false; if (!off) wd++; }
    if (x._wd != null) wd = x._wd;
    const lc = {}; (x._lc || m.loss_codes || []).forEach((l) => (lc[l.code] = l));
    const pe = x.entries.filter((e) => e.status === "ok" && e.kind === "process" && inWin(e.entry_at) && e.machine), loss = x.loss.filter((l) => inWin(l.loss_date));
    const mach = {}; const M = (c) => (mach[c] = mach[c] || { c, ok: 0, rej: 0, rew: 0, std: 0, std_ok: 0, loss: 0, plan: 0 });
    pe.forEach((e) => { const r = M(e.machine); r.ok += +e.ok_qty; r.rej += +e.rej_qty; r.rew += +e.rew_qty; const ct = +e.ct_sec || 0; r.std += (ct * (+e.ok_qty + +e.rej_qty + +e.rew_qty)) / 3600; r.std_ok += (ct * +e.ok_qty) / 3600; });
    loss.forEach((l) => { const r = M(l.machine_code), pl = (lc[l.d_code] || {}).planned === "Yes"; if (pl) r.plan += +l.minutes / 60; else r.loss += +l.minutes / 60; });
    const R = Object.values(mach).sort((a, b) => a.c.localeCompare(b.c)).map((r) => {
      const avail = P.H * wd - r.plan, op = Math.max(0.01, avail - r.loss), A = avail > 0 ? op / avail : 0, tot = r.ok + r.rej + r.rew, Pf = r.std ? Math.min(1, r.std / op) : null, Q = tot ? r.ok / tot : null;
      return Object.assign(r, { avail, op, A, Pf, Q, oee: Pf != null && Q != null ? A * Pf * Q : null, eff: r.std_ok ? r.std_ok / op : null, util: avail > 0 && r.std ? r.std / avail : null, tot });
    });
    const T = R.reduce((a, r) => { ["ok", "rej", "rew", "std", "std_ok", "loss", "plan", "avail", "op"].forEach((k) => (a[k] += r[k])); return a; }, { ok: 0, rej: 0, rew: 0, std: 0, std_ok: 0, loss: 0, plan: 0, avail: 0, op: 0 });
    const tot = T.ok + T.rej + T.rew, TA = T.avail > 0 ? T.op / T.avail : null, TP = T.std ? Math.min(1, T.std / Math.max(0.01, T.op)) : null, TQ = tot ? T.ok / tot : null, TO = TA != null && TP != null && TQ != null ? TA * TP * TQ : null;
    const col = (v, tg) => (v == null ? "x" : v >= tg ? "g" : v >= tg * 0.85 ? "a" : "r"), tg = P.oee;
    const k = (v, l, c, s) => `<div class="kpi" style="--c:var(--${c})"><b>${v}</b><span>${l}${s ? `<br><i>${s}</i>` : ""}</span></div>`;
    const df = x.defects.filter((d) => inWin(d.entry_at) && d.kind === kind), q = (f) => group(df, f, (d) => +d.qty);
    // daily rejection and rework rate
    const day = {}; pe.forEach((e) => { const d = String(e.entry_at).slice(0, 10), r = (day[d] = day[d] || { ok: 0, rej: 0, rew: 0 }); r.ok += +e.ok_qty; r.rej += +e.rej_qty; r.rew += +e.rew_qty; });
    const dk = Object.keys(day).sort().slice(-30), mxr = Math.max(0.01, ...dk.map((d) => (day[d].rej + day[d].rew) / Math.max(1, day[d].ok + day[d].rej + day[d].rew)));
    const lossBy = (f) => group(loss, f, (l) => +l.minutes / 60);
    return `<div class="note">Period: last ${days} days · ${wd} working days × ${N(P.H, 1)} h = ${N(P.H * wd)} h available per machine${P.set ? "" : " (Plant standards not filled in — default hours used)"}. Targets from Operations Master › Plant standards (OEE ${N(tg * 100)}%).${x.erp_rows ? ` <b>${N(x.erp_rows)} ERP production records</b> (to ${esc(String(x.erp_last || "").slice(0, 10))}) are included with this app's own entries. The ERP has no rejection data, so quality counts only entries made here.${x._erpdays && x._erpdays.loaded < x._erpdays.total ? ` <b>The ERP has ${x._erpdays.loaded} of these ${x._erpdays.total} days loaded;</b> the other days are left out of the figures (not counted as lost time), so the percentages describe the loaded days only.` : ""}` : ""}</div>
    <div class="kpis">${k(pc(TO), "OEE", col(TO, tg), "target " + N(tg * 100) + "%")}${k(pc(TA), "Availability", col(TA, 0.9))}${k(pc(TP), "Performance", col(TP, 0.9))}${k(pc(TQ), "Quality (first pass OK)", col(TQ, 0.97))}${k(pc(T.std_ok && T.op ? T.std_ok / T.op : null), "Production efficiency", "b", "earned hours ÷ operating hours")}${k(pc(T.avail && T.std ? T.std / T.avail : null), "Capacity utilisation", "b", "standard hours ÷ available hours")}${k(pc(tot ? T.rej / tot : null), "Rejection rate", tot && T.rej / tot > 0.02 ? "r" : "g", N(T.rej) + " of " + N(tot) + " pcs")}${k(pc(tot ? T.rew / tot : null), "Rework rate", tot && T.rew / tot > 0.03 ? "a" : "g", N(T.rew) + " pcs")}</div>
    <b>Machine wise</b><div style="overflow-x:auto"><table><thead><tr><th>Machine</th><th class="n">Available h</th><th class="n">Loss h</th><th class="n">Availability</th><th class="n">Performance</th><th class="n">Quality</th><th class="n">OEE</th><th class="n">Efficiency</th><th class="n">Utilisation</th><th class="n">Rej %</th><th class="n">Rew %</th></tr></thead><tbody>${R.map((r) => `<tr><td><b>${esc(r.c)}</b></td><td class="n">${N(r.avail, 0)}</td><td class="n">${N(r.loss, 1)}</td><td class="n">${pc(r.A)}</td><td class="n">${pc(r.Pf)}</td><td class="n">${pc(r.Q)}</td><td class="n"><span class="chip ${col(r.oee, tg)}">${pc(r.oee)}</span></td><td class="n">${pc(r.eff)}</td><td class="n">${pc(r.util)}</td><td class="n">${pc(r.tot ? r.rej / r.tot : null)}</td><td class="n">${pc(r.tot ? r.rew / r.tot : null)}</td></tr>`).join("") || '<tr><td colspan="11" class="mut">No entries in this period.</td></tr>'}</tbody></table></div>
    <p class="note"><b>How it is worked out.</b> Availability = (available hours − unplanned loss hours) ÷ available hours; planned-stop D codes are taken off the available hours. Performance = standard hours of everything made (cycle time from Operations Master × pieces) ÷ operating hours, capped at 100%. Quality = OK ÷ (OK + rejected + rework). OEE = A × P × Q. Efficiency = standard hours of OK pieces ÷ operating hours. Utilisation = standard hours of everything made ÷ available hours. Enter every loss in <i>Loss hours</i> for the figures to be right.</p>
    <div class="row" style="margin-top:14px"><b class="grow">Pareto — ${kind === "rej" ? "rejection" : "rework"}</b><select id="dpK" style="width:auto"><option value="rej"${kind === "rej" ? " selected" : ""}>Rejection (pcs)</option><option value="rew"${kind === "rew" ? " selected" : ""}>Rework (pcs)</option></select></div>
    <div class="pg">${pareto("Part wise", q((d) => d.part_code), "pcs")}${pareto("Defect wise", q((d) => d.reason), "pcs")}${pareto("Process wise", q((d) => d.op_name), "pcs")}${pareto("Machine wise", q((d) => d.machine), "pcs")}${pareto("Operator wise", q((d) => d.operator), "pcs")}${pareto("Loss hours by D code", lossBy((l) => l.d_code + " — " + l.d_name), "h", "All machines")}</div>
    <div class="card"><h3>Daily rejection + rework rate</h3>${dk.length ? `<div style="display:flex;gap:3px;align-items:flex-end;height:90px">${dk.map((d) => { const r = day[d], t = r.ok + r.rej + r.rew, a = r.rej / Math.max(1, t), b = r.rew / Math.max(1, t); return `<div title="${d}: rejection ${(a * 100).toFixed(1)}%, rework ${(b * 100).toFixed(1)}%" style="flex:1;display:flex;flex-direction:column;justify-content:flex-end;min-width:6px;max-width:30px"><div style="height:${b / mxr * 80}px;background:var(--a)"></div><div style="height:${a / mxr * 80}px;background:var(--r)"></div></div>`; }).join("")}</div><div class="mut" style="font-size:11px">${esc(dk[0])} → ${esc(dk[dk.length - 1])} · red = rejection, amber = rework (share of pieces made that day)</div>` : '<p class="note">No entries in this period.</p>'}</div>`;
  }

  /* ---------- data readiness: how many parts have route, cycle time, machine, BOM weight and drawing ---------- */
  function ready(m) {
    const parts = m.parts || [], bom = {}; (m.bom || []).forEach((b) => { (bom[b.part_no] = bom[b.part_no] || []).push(b); });
    let ok = 0, route = 0, ct = 0, mc = 0, wt = 0;
    parts.forEach((p) => {
      const r = (m.routes || {})[p.code] || [], n = r.length, c = n && r.every((o) => +o.ct_sec > 0), mm = n && r.every((o) => o.type === "supplier" || (o.machine || "").trim()), b = bom[p.code] || [], w = b.some((x) => +x.blank_kg > 1 && +x.finished_kg > 0), d = (p.drawing_no || "").trim();
      if (n) route++; if (c) ct++; if (mm) mc++; if (w) wt++; if (n && c && mm && w && d) ok++;
    });
    return { parts: parts.length, ok, route, ct, mc, wt };
  }
  /* ---------- extra dashboards from machine capture, tooling, consumables and supplier processes ---------- */
  /* ---------- planning terms: takt time, cycle time, bottleneck, throughput time, process cycle efficiency ---------- */
  function planStats(PL) {
    const parts = (PL && PL.parts) || [], lots = (PL && PL.lots) || [], withCt = parts.filter((p) => p.meets_takt != null), ok = withCt.filter((p) => p.meets_takt).length;
    const done = lots.filter((l) => l.status !== "open" && +l.tt_days > 0), tt = done.length ? done.reduce((a, l) => a + +l.tt_days, 0) / done.length : null;
    const pce = done.filter((l) => +l.proc_h > 0).map((l) => (+l.proc_h) / Math.max(0.01, (+l.tt_days) * ((PL && PL.hours_per_day) || 16)));
    return { parts: parts.length, withCt: withCt.length, ok, okPct: withCt.length ? ok / withCt.length * 100 : null, tt, pce: pce.length ? pce.reduce((a, b) => a + b, 0) / pce.length * 100 : null, lots: lots.length, open: lots.filter((l) => l.status === "open").length };
  }
  function plan(m, PL) {
    if (!PL) return "";
    const S = planStats(PL), k = (v, l, c, s) => `<div class="kpi" style="--c:var(--${c})"><b>${v}</b><span>${l}${s ? `<br><i>${s}</i>` : ""}</span></div>`;
    const rows = (PL.parts || []).map((p) => `<tr><td><b>${esc(p.part)}</b><div class="mut">${esc(p.name || "")}</div></td><td class="n">${N(p.demand)}</td><td class="n">${N(p.per_day)}</td><td class="n">${N(p.takt_sec, 1)}</td><td class="n">${p.ct_max == null ? '<span class="mut">no cycle time</span>' : N(p.ct_max)}</td><td>${esc(p.bottleneck || "")}<div class="mut">${esc(p.machine || "")}</div></td><td class="n">${p.ct_total ? N(p.ct_total) : "—"}</td><td class="n">${p.machines_needed == null ? "—" : N(p.machines_needed)}</td><td>${p.meets_takt == null ? "" : `<span class="chip ${p.meets_takt ? "g" : "r"}">${p.meets_takt ? "meets takt" : "above takt"}</span>`}</td></tr>`).join("") || `<tr><td colspan="9" class="mut">No sales plan found for ${esc(String(PL.month || "").slice(0, 7))} — enter the month's plan in Sales Flow.</td></tr>`;
    const lots = (PL.lots || []).filter((l) => +l.tt_days > 0).slice(0, 30).map((l) => `<tr><td>${esc(l.lot)}</td><td>${esc(l.part)}</td><td class="n">${N(l.qty)}</td><td>${l.status === "open" ? "open" : "closed"}</td><td class="n">${N(l.tt_days, 1)}</td><td class="n">${N(l.proc_h, 1)}</td><td class="n">${+l.proc_h > 0 ? pc((+l.proc_h) / Math.max(0.01, (+l.tt_days) * (PL.hours_per_day || 16))) : "—"}</td></tr>`).join("");
    return `<div class="card" style="margin-top:14px"><h3>Planning — takt time, cycle time and throughput time</h3>
    <p class="note">${esc(String(PL.month || "").slice(0, 7))} sales plan from Sales Flow · ${N(PL.hours_per_day, 1)} h per day · ${N(PL.days)} working days · OEE target ${N((PL.oee || 0) * 100)}%. Cycle times from the Operations Master routes.</p>
    <div class="kpis">${k(S.parts, "Parts in the plan", "b")}${k(S.okPct == null ? "—" : N(S.okPct, 0) + "%", "Parts whose slowest step meets takt", S.okPct == null ? "x" : S.okPct >= 90 ? "g" : S.okPct >= 70 ? "a" : "r", S.ok + " of " + S.withCt + " with cycle times")}${k(S.tt == null ? "—" : N(S.tt, 1) + " d", "Average throughput time", "b", "issue of material → last entry, closed lots")}${k(S.pce == null ? "—" : N(S.pce, 1) + "%", "Process cycle efficiency", "b", "machine time ÷ throughput time")}${k(S.open, "Lots open", "b", "of " + S.lots + " in 180 days")}</div>
    <div style="overflow-x:auto"><table><thead><tr><th>Part</th><th class="n">Plan (pcs)</th><th class="n">Per day</th><th class="n">Takt time (s)</th><th class="n">Slowest step (s)</th><th>Bottleneck</th><th class="n">Total cycle (s)</th><th class="n">Machines needed</th><th>Status</th></tr></thead><tbody>${rows}</tbody></table></div>
    ${lots ? `<h4 style="margin:12px 0 4px">Throughput time by lot</h4><div style="overflow-x:auto"><table><thead><tr><th>Lot</th><th>Part</th><th class="n">Qty</th><th>Status</th><th class="n">Throughput (days)</th><th class="n">Machine time (h)</th><th class="n">Cycle efficiency</th></tr></thead><tbody>${lots}</tbody></table></div>` : ""}
    <details style="margin-top:10px"><summary><b>Planning terms used here</b></summary><div class="note"><p><b>Takt time</b> = available time per day ÷ customer demand per day. It is the beat at which a piece must be finished to meet the plan.<br><b>Cycle time</b> = machine time for one piece at one step (Operations Master). <b>Effective cycle time</b> = cycle time ÷ OEE.<br><b>Bottleneck</b> = the step with the longest cycle time; it sets the output of the part. <b>Machines needed</b> = bottleneck cycle time × pieces per day ÷ (available seconds × OEE).<br><b>Throughput time</b> (production lead time) = days from material issue to the last entry of the lot. <b>Process cycle efficiency</b> = machine time ÷ throughput time (how much of the lot's time was spent actually machining).<br><b>WIP</b> = pieces issued and not yet finished; <b>Little's law</b>: WIP = throughput rate × throughput time.<br><b>OEE</b> = Availability × Performance × Quality. <b>Utilisation</b> = standard hours made ÷ available hours.</p></div></details></div>`;
  }
  function extra(m, K, days) {
    K = K || {}; const R = ready(m), T = K.tools || {}, E = K.entries || {}, DC = K.dc || {}, C = K.cons || {}, MT = K.machine_time || [];
    const k = (v, l, c, s) => `<div class="kpi" style="--c:var(--${c})"><b>${v}</b><span>${l}${s ? `<br><i>${s}</i>` : ""}</span></div>`;
    const p = (a, b) => (b ? Math.round((a / b) * 1000) / 10 + "%" : "—");
    const rows = MT.map((r) => { const t = (+r.run || 0) + (+r.idle || 0) + (+r.alarm || 0); return `<tr><td><b>${esc(r.machine)}</b></td><td class="n">${N(r.run, 1)}</td><td class="n">${N(r.idle, 1)}</td><td class="n">${N(r.alarm, 1)}</td><td class="n">${t ? Math.round((r.run / t) * 100) + "%" : "—"}</td></tr>`; }).join("");
    const tm = (T.by_machine || []).map((r) => `<tr><td><b>${esc(r.machine)}</b></td><td class="n">${N(r.changes)}</td><td class="n">${N(Math.round(r.minutes))}</td></tr>`).join("");
    return `<h3 style="margin-top:18px">Process data readiness <span class="mut" style="font-weight:400">(from Operations Master — the base of every KPI above)</span></h3>
    <div class="kpis">${k(p(R.ok, R.parts), "parts ready for production", R.ok === R.parts && R.parts ? "g" : "r", R.ok + " of " + R.parts)}${k(p(R.route, R.parts), "parts with a process route", "b")}${k(p(R.ct, R.parts), "parts with every cycle time", "b")}${k(p(R.mc, R.parts), "parts with every machine", "b")}${k(p(R.wt, R.parts), "parts with real BOM weights", "b")}</div>
    <h3>Machine time measured from the machines — last ${days} days</h3><div class="sc"><table class="lt"><thead><tr><th>Machine</th><th class="n">Running (h)</th><th class="n">Idle (h)</th><th class="n">Alarm (h)</th><th class="n">Running share</th></tr></thead><tbody>${rows || '<tr><td colspan="5" class="mut">No machine status received yet. Connect machines in Production entry › Machine capture.</td></tr>'}</tbody></table></div>
    <div class="kpis">${k(p(E.machine || 0, E.total || 0), "production entries made from machine counts", "b", (E.machine || 0) + " of " + (E.total || 0) + " entries")}${k(N(T.changes || 0), "tool changes", "a", (T.breakages || 0) + " breakages")}${k(N(Math.round(T.change_min || 0)) + " min", "idle time from tool changes", "a")}${k(T.life_pct != null ? N(T.life_pct, 0) + "%" : "—", "tool life achieved vs standard", "b")}${k(N(T.due || 0), "tools due for change now", (T.due || 0) ? "r" : "g", (T.on_machines || 0) + " on machines")}${k(N(T.low_stock || 0), "tools below safety stock", (T.low_stock || 0) ? "r" : "g", (T.listed || 0) + " in the plan")}${k(N(C.low_stock || 0), "consumables below safety stock", (C.low_stock || 0) ? "r" : "g", (C.listed || 0) + " in the plan")}${k(p(DC.on_time || 0, DC.closed || 0), "outsourced lots back on time", "b", (DC.closed || 0) + " completed")}${k(N(DC.overdue || 0), "challans overdue at suppliers", (DC.overdue || 0) ? "r" : "g", (DC.sent || 0) + " sent in the period")}</div>
    ${tm ? `<div class="card"><h3>Tool changes by machine</h3><table class="lt" style="min-width:0"><thead><tr><th>Machine</th><th class="n">Changes</th><th class="n">Change time (min)</th></tr></thead><tbody>${tm}</tbody></table></div>` : ""}`;
  }
  window.MMDDash = { plan, planStats, mergeErp, wip: wipHtml, dash, extra, ready, plant, stuck: (m, x) => wip(m, x).items.filter((i) => i.st === "stuck").length };
})();
