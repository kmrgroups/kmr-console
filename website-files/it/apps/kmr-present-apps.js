/* KMR Presentation - the KPIs of every app, taken live from that app's own records.
   KMRPA[key] = { name, code (licence code), std (standards key), controls(), load(call, values) -> {period, kpis, charts} }
   Targets are the defaults used for the tower lights (green = on target, amber = within tolerance, red = off target). */
(function () {
  "use strict";
  var KMRPA = (window.KMRPA = window.KMRPA || {});
  var localIso = function (d) { var p = function (n) { return String(n).padStart(2, "0"); }; return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()); };
  var ym = function (d) { return localIso(d).slice(0, 7); };
  var today = function () { return new Date().toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }); };
  var N = function (v) { return v == null || v === "" || isNaN(+v) ? null : +v; };
  var pct = function (a, b) { return b ? a / b * 100 : null; };
  var ent = function (o) { return Object.keys(o || {}).map(function (k) { return [k, +o[k] || 0]; }).sort(function (a, b) { return b[1] - a[1]; }); };
  var barOf = function (title, o, name, kpi, limit) { var e = ent(o).slice(0, limit || 10); return { title: title, kind: "bar", kpi: kpi, labels: e.map(function (x) { return x[0]; }), series: [{ name: name, values: e.map(function (x) { return x[1]; }) }] }; };
  var std = function () { return [].slice.call(arguments).map(function (s) { var i = s.indexOf(" "); return [s.slice(0, i), s.slice(i + 1)]; }); };

  /* ---------- 8D ---------- */
  KMRPA.d8 = { name: "8D Problem Solving", code: "d8", std: "d8", load: async function (call) {
    var d = await call("kmr_d8_dashboard"), S = std;
    return { period: "Live position · " + today(), kpis: [
      { id: "open", name: "Open 8Ds", value: d.open, std: S("ISO 10.2.1", "IATF 10.2.3"), why: "8D reports not yet closed." },
      { id: "over", name: "8Ds past due date", value: d.overdue, target: 0, amber: 2, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3", "ISO 9.1.2"), why: "Open 8Ds whose target date has passed." },
      { id: "crit", name: "Critical 8Ds open", value: d.critical_open, target: 0, amber: 1, dir: "low", std: S("IATF 10.2.3", "VDA P7"), why: "Open 8Ds with severity Critical." },
      { id: "cont", name: "No containment after 1 day", value: d.no_containment, target: 0, amber: 1, dir: "low", std: S("IATF 8.7.1", "IATF 10.2.3", "ISO 8.7"), why: "Open 8Ds older than a day with no D3 interim containment." },
      { id: "days", name: "Average days to close", value: N(d.avg_days_to_close), unit: "days", target: 30, tol: 20, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3", "ISO 9.1.2"), why: "Average days from opening to closure of 8Ds closed in the last 6 months." },
      { id: "cl90", name: "Closed in 90 days", value: d.closed_90, std: S("ISO 10.2.2", "IATF 10.2.6"), why: "8Ds closed in the last 90 days." },
      { id: "aopen", name: "Open actions", value: d.actions_open, std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Corrective and preventive actions still open on open 8Ds." },
      { id: "aover", name: "Overdue actions", value: d.actions_overdue, target: 0, amber: 3, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3", "VDA P7.4"), why: "Open actions whose due date has passed." }],
      charts: [barOf("Where the open 8Ds are stuck", d.by_step, "Open 8Ds", "open"), barOf("Where problems come from (12 months)", d.by_source, "8Ds", "open"), barOf("Root-cause category (12 months)", d.by_cause, "8Ds", "open")] };
  } };

  /* ---------- CRM & RFQ ---------- */
  KMRPA.crm = { name: "CRM & RFQ", code: "crm", std: "crm", load: async function (call) {
    var d = await call("kmr_crm_dashboard"), S = std, st = d.by_stage || {}, stn = Object.keys(st);
    return { period: "Live position · " + today(), kpis: [
      { id: "leads", name: "Open leads", value: d.leads_open, std: S("ISO 8.2.1", "ISO 9.1.2"), why: "Leads not yet won or lost." },
      { id: "pipe", name: "Pipeline value", value: N(d.pipeline_value), unit: "₹", std: S("ISO 8.2.1", "ISO 9.1.2"), why: "Value of the open leads." },
      { id: "fo", name: "Follow-ups overdue", value: d.followups_overdue, target: 0, amber: 3, dir: "low", std: S("ISO 8.2.1", "ISO 8.2.2"), why: "Customer follow-ups past their date and not done." },
      { id: "rfq", name: "Open RFQs", value: d.rfq_open, std: S("ISO 8.2.2", "ISO 8.2.3", "IATF 8.2.3.1"), why: "Requests for quotation received, in costing, quoted or in negotiation." },
      { id: "rfqo", name: "RFQs past due date", value: d.rfq_overdue, target: 0, amber: 2, dir: "low", std: S("ISO 8.2.3", "IATF 8.2.3.1", "ISO 9.1.2"), why: "RFQs still to be quoted whose due date has passed." },
      { id: "qo", name: "Quotations out (value)", value: N(d.quotes_out_value), unit: "₹", std: S("ISO 8.2.3"), why: "Value of quotations sent and not yet decided." },
      { id: "win", name: "Win rate", value: N(d.win_rate), unit: "%", target: 30, tol: 25, dir: "high", std: S("ISO 9.1.2", "ISO 8.2.3"), why: "Won ÷ (won + lost) RFQs and leads." },
      { id: "won", name: "Orders won, last 90 days", value: N(d.won_value_90), unit: "₹", std: S("ISO 9.1.2"), why: "Value of accepted quotations in the last 90 days." }],
      charts: [{ title: "Pipeline by stage (₹)", kind: "bar", kpi: "pipe", labels: stn, series: [{ name: "Value", values: stn.map(function (k) { return N((st[k] || {}).value) || 0; }) }] },
        { title: "Leads by stage (count)", kind: "bar", kpi: "leads", labels: stn, series: [{ name: "Leads", values: stn.map(function (k) { return N((st[k] || {}).n) || 0; }) }] },
        barOf("Why RFQs were lost", d.lost_reasons, "RFQs", "win")] };
  } };

  /* ---------- MSA ---------- */
  KMRPA.msa = { name: "MSA Studies", code: "msa", std: "msa", load: async function (call) {
    var d = await call("kmr_msa_dashboard"), S = std, bd = d.by_decision || {}, ok = 0, bad = 0, cond = 0, tot = d.total || 0;
    Object.keys(bd).forEach(function (k) { if (/not calculated/i.test(k)) return; if (/^acceptable$/i.test(k)) ok += bd[k]; else if (/^conditional/i.test(k)) cond += bd[k]; else bad += bd[k]; });
    var done = ok + bad + cond;
    return { period: "Live position · " + today(), kpis: [
      { id: "tot", name: "Studies on record", value: tot, std: S("IATF 7.1.5.1.1", "ISO 7.1.5.1"), why: "All gauge R&R, attribute, bias, linearity and stability studies." },
      { id: "acc", name: "Measurement systems acceptable", value: done ? pct(ok, done) : null, unit: "%", target: 90, tol: 10, dir: "high", std: S("IATF 7.1.5.1.1", "ISO 7.1.5.1", "VDA P6"), why: "Acceptable studies ÷ studies with a decision (AIAG MSA 4th ed. criteria: GRR under 10% acceptable, 10-30% conditional, over 30% not acceptable)." },
      { id: "bad", name: "Studies not acceptable", value: bad, target: 0, amber: 2, dir: "low", std: S("IATF 7.1.5.1.1", "IATF 7.1.5.2"), why: "Studies whose decision is Not acceptable; the gauge or method needs action." },
      { id: "cond", name: "Studies conditionally acceptable", value: cond, target: 0, amber: 3, dir: "low", std: S("IATF 7.1.5.1.1"), why: "Studies acceptable only with the customer's approval or a change." },
      { id: "draft", name: "Studies not finished (draft)", value: d.draft, target: 0, amber: 3, dir: "low", std: S("ISO 7.5.3"), why: "Studies started but not calculated or closed." }],
      charts: [barOf("Studies by decision", bd, "Studies", "acc"), barOf("Studies by type", d.by_type, "Studies", "tot")] };
  } };

  /* ---------- SPC ---------- */
  KMRPA.spc = { name: "SPC Charts", code: "spc", std: "spc", load: async function (call) {
    var d = await call("kmr_spc_dashboard"), S = std;
    return { period: "Live position · " + today(), kpis: [
      { id: "act", name: "Active control charts", value: d.active, std: S("IATF 9.1.1.1", "IATF 9.1.1.2", "ISO 9.1.1"), why: "Control charts in use on the shop floor." },
      { id: "sig", name: "Charts with signals", value: d.signals, target: 0, amber: 2, dir: "low", std: S("IATF 9.1.1.3", "IATF 10.2.3", "ISO 8.5.1"), why: "Active charts with an out-of-control signal in the latest summary." },
      { id: "lcpk", name: "Charts with Cpk below 1.33", value: d.low_cpk, target: 0, amber: 2, dir: "low", std: S("IATF 9.1.1.2", "IATF 8.5.1.1", "ISO 9.1.3"), why: "Active charts whose process capability is under the usual 1.33 requirement." },
      { id: "cap", name: "Charts capable (Cpk 1.33 or more)", value: d.active ? pct(d.active - d.low_cpk, d.active) : null, unit: "%", target: 90, tol: 10, dir: "high", std: S("IATF 9.1.1.2", "ISO 9.1.3"), why: "Active charts that do not have a low Cpk." },
      { id: "chs", name: "Charts on record", value: d.charts, std: S("IATF 9.1.1.1"), why: "All charts, active or not." }],
      charts: [{ title: "Active charts: stable and capable or not", kind: "bar", kpi: "cap", labels: ["Active", "With signals", "Cpk < 1.33"], series: [{ name: "Charts", values: [d.active, d.signals, d.low_cpk] }] }] };
  } };

  /* ---------- ActionTrack ---------- */
  KMRPA.tsk = { name: "ActionTrack", code: "tsk", std: "tsk", load: async function (call) {
    var d = await call("kmr_tsk_dashboard", { p: { scope: "team" } }), S = std, open = (d.open || 0) + (d.progress || 0) + (d.blocked || 0), bp = d.by_priority || {};
    return { period: "Live position · " + today() + (d.team ? " · whole team" : " · my tasks"), kpis: [
      { id: "open", name: "Open tasks", value: open, std: S("ISO 6.2", "ISO 9.3.3", "IATF 10.2.3"), why: "Tasks not done: open, in progress or blocked." },
      { id: "over", name: "Overdue tasks", value: d.overdue, target: 0, amber: 3, dir: "low", std: S("ISO 9.3.3", "ISO 10.2", "IATF 9.3.1.1"), why: "Tasks past their due date." },
      { id: "overp", name: "Overdue % of open tasks", value: open ? pct(d.overdue, open) : null, unit: "%", target: 5, tol: 100, dir: "low", std: S("ISO 9.3.3", "ISO 10.2"), why: "Overdue tasks ÷ open tasks." },
      { id: "blk", name: "Blocked tasks", value: d.blocked, target: 0, amber: 2, dir: "low", std: S("ISO 6.2", "ISO 7.4"), why: "Tasks that cannot move without help." },
      { id: "nod", name: "Tasks without a due date", value: d.no_date, target: 0, amber: 3, dir: "low", std: S("ISO 6.2", "ISO 5.3"), why: "Open tasks with no target date." },
      { id: "dw", name: "Done in the last 7 days", value: d.done_week, std: S("ISO 9.3.3"), why: "Tasks completed in the last week." },
      { id: "comp", name: "Completion rate", value: d.total ? pct(d.done_total, d.total) : null, unit: "%", target: 80, tol: 15, dir: "high", std: S("ISO 9.3.3", "ISO 10.2"), why: "Done ÷ all tasks." }],
      charts: [{ title: "Tasks created and done (last 14 days)", kind: "line", kpi: "dw", labels: (d.trend || []).map(function (x) { return String(x.d).slice(5); }), series: [{ name: "Created", values: (d.trend || []).map(function (x) { return x.created; }) }, { name: "Done", values: (d.trend || []).map(function (x) { return x.done; }) }] },
        { title: "Open tasks by priority", kind: "bar", kpi: "open", labels: ["urgent", "high", "normal", "low"], series: [{ name: "Tasks", values: [bp.urgent, bp.high, bp.normal, bp.low] }] },
        { title: "Open and overdue by person", kind: "bar", kpi: "over", labels: (d.by_person || []).slice(0, 10).map(function (x) { return x.name; }), series: [{ name: "Open", values: (d.by_person || []).slice(0, 10).map(function (x) { return x.open; }) }, { name: "Overdue", values: (d.by_person || []).slice(0, 10).map(function (x) { return x.overdue; }) }] }] };
  } };

  /* ---------- Internal audit ---------- */
  KMRPA.aud = { name: "Internal Audit", code: "aud", std: "aud", controls: function () { var y = new Date().getFullYear(); return [{ id: "year", label: "Audit year", type: "select", value: y, options: [y - 2, y - 1, y, y + 1].map(function (v) { return [v, v]; }) }]; }, load: async function (call, v) {
    var yr = +v.year || new Date().getFullYear(), d = await call("kmr_aud_dashboard", { p_year: yr }), n = null, S = std;
    try { n = await call("kmr_aud_dash2", { p_year: yr }); } catch (e) { n = null; }
    var k = [
      { id: "comp", name: "Audit programme completion", value: N(d.completion), unit: "%", target: 100, tol: 10, dir: "high", std: S("ISO 9.2.1", "ISO 9.2.2", "IATF 9.2.2.4"), why: "Audits done (reported or closed) ÷ audits planned for the year." },
      { id: "late", name: "Audits past planned date", value: d.late_audits, target: 0, amber: 1, dir: "low", std: S("ISO 9.2.2", "IATF 9.2.2.4"), why: "Planned audits whose date has passed without being done." },
      { id: "score", name: "Average process audit score", value: N(d.avg_score), unit: "%", target: 85, tol: 12, dir: "high", std: S("VDA P1-P7 (6.3)", "IATF 9.2.2.3"), why: "Average VDA 6.3 score of the process audits of the last 12 months (A 90 or more, B 80-90)." },
      { id: "oa", name: "Open audit actions", value: d.open_actions, std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Audit actions not yet done." },
      { id: "ova", name: "Overdue audit actions", value: d.overdue_actions, target: 0, amber: 3, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3", "IATF 10.2.4"), why: "Open audit actions past their due date." },
      { id: "unv", name: "Actions done but not verified", value: d.unchecked, target: 0, amber: 3, dir: "low", std: S("ISO 10.2.1 (e)", "IATF 10.2.3"), why: "Completed actions waiting for the auditor to confirm effectiveness." }], ch = [];
    if (n) {
      k.push({ id: "nc", name: "Open nonconformities", value: n.open, std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Audit findings still open." },
        { id: "maj", name: "Major nonconformities open", value: n.major_open, target: 0, amber: 1, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Open findings graded Major." },
        { id: "ncod", name: "Nonconformities past due", value: n.overdue, target: 0, amber: 2, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Open findings whose next step is overdue." },
        { id: "rep", name: "Repeat nonconformities", value: n.repeat, target: 0, amber: 1, dir: "low", std: S("ISO 10.2.1 (e)", "IATF 10.2.3"), why: "Findings that came back after closure." },
        { id: "dtc", name: "Average days to close a finding", value: N(n.avg_days_to_close), unit: "days", target: 60, tol: 25, dir: "low", std: S("ISO 10.2.1", "IATF 10.2.4"), why: "Average days from raising to closing." },
        { id: "ont", name: "Corrective actions on time", value: N(n.on_time_pct), unit: "%", target: 90, tol: 10, dir: "high", std: S("ISO 10.2.1", "IATF 10.2.3"), why: "Permanent actions completed by their due date." },
        { id: "eff", name: "Actions found effective", value: N(n.effective_pct), unit: "%", target: 90, tol: 10, dir: "high", std: S("ISO 10.2.1 (e)", "IATF 10.2.3"), why: "Effectiveness checks with an effective result." });
      var a = n.ageing || {}; ch.push({ title: "Ageing of open findings (days)", kind: "bar", kpi: "nc", labels: ["0-30", "31-60", "61-90", "over 90"], series: [{ name: "Findings", values: [a.d30, a.d60, a.d90, a.over90] }] });
      ch.push({ title: "Findings raised and closed (12 months)", kind: "line", kpi: "dtc", labels: (n.trend || []).map(function (x) { return x.m; }), series: [{ name: "Raised", values: (n.trend || []).map(function (x) { return x.raised; }) }, { name: "Closed", values: (n.trend || []).map(function (x) { return x.closed; }) }] });
      ch.push({ title: "Findings by standard (12 months)", kind: "bar", kpi: "nc", labels: (n.by_standard || []).map(function (x) { return x.k; }), series: [{ name: "Findings", values: (n.by_standard || []).map(function (x) { return x.n; }) }] });
    }
    var bt = d.by_type || {}, tn = Object.keys(bt);
    ch.unshift({ title: "Audits planned and done by type - " + yr, kind: "bar", kpi: "comp", labels: tn, series: [{ name: "Planned", values: tn.map(function (t) { return bt[t].planned; }) }, { name: "Done", values: tn.map(function (t) { return bt[t].done; }) }] });
    return { period: "Audit year " + yr, kpis: k, charts: ch };
  } };

  var days = function (a, b) { return Math.round((Date.parse(b) - Date.parse(a)) / 864e5); };
  var todayIso = function () { return localIso(new Date()); };
  var monthKey = function (d) { return String(d).slice(0, 7); };
  var last12 = function () { var o = [], d = new Date(); d.setDate(1); for (var i = 11; i >= 0; i--) { var x = new Date(d.getFullYear(), d.getMonth() - i, 1); o.push(x.getFullYear() + "-" + String(x.getMonth() + 1).padStart(2, "0")); } return o; };

  /* ---------- Minutes of meetings ---------- */
  KMRPA.mom = { name: "Minutes Of Meetings", code: "mom", std: "mom", load: async function (call) {
    var L = await call("kmr_mom_load"), A = []; try { A = await call("kmr_mom_actions"); } catch (e) { A = []; }
    var S = std, M = (L.meetings || []).filter(function (m) { return m.status !== "void"; }), td = L.today || todayIso(), ms = last12();
    var pts = M.reduce(function (s, m) { return s + (+m.points || 0); }, 0), done = M.reduce(function (s, m) { return s + (+m.done_points || 0); }, 0), openP = M.reduce(function (s, m) { return s + (+m.open_points || 0); }, 0);
    var closed = M.filter(function (m) { return m.status === "closed" && m.closed_at; }), ontime = closed.filter(function (m) { return days(m.meeting_date, String(m.closed_at).slice(0, 10)) <= 3; }).length;
    var over = A.filter(function (a) { return a.due_on && String(a.due_on).slice(0, 10) < td; }), nodate = A.filter(function (a) { return !a.due_on; }), nowho = A.filter(function (a) { return !a.who; });
    var byM = {}; M.forEach(function (m) { var k = monthKey(m.meeting_date); byM[k] = (byM[k] || 0) + 1; });
    var types = {}; A.forEach(function (a) { types[a.ptype] = (types[a.ptype] || 0) + 1; });
    var openM = M.filter(function (m) { return m.status === "open" && days(m.meeting_date, td) > 3; }).length;
    return { period: "Live position · " + today(), kpis: [
      { id: "mt", name: "Meetings (last 12 months)", value: M.filter(function (m) { return ms.indexOf(monthKey(m.meeting_date)) >= 0; }).length, std: S("ISO 9.3", "IATF 9.3.1.1"), why: "Meetings with minutes recorded in the last twelve months." },
      { id: "cl", name: "Minutes closed within 3 days", value: closed.length ? pct(ontime, closed.length) : null, unit: "%", target: 90, tol: 15, dir: "high", std: S("ISO 7.5.3", "IATF 7.5.3.2.1", "ISO 9.3"), why: "Closed minutes whose closing date is within 3 days of the meeting." },
      { id: "old", name: "Meetings still open after 3 days", value: openM, target: 0, amber: 2, dir: "low", std: S("ISO 7.5.3", "ISO 9.3"), why: "Minutes not closed and issued within 3 days." },
      { id: "op", name: "Open points and actions", value: A.length || openP, std: S("ISO 10.2", "IATF 10.2.3"), why: "Actions, decisions, risks and queries still open or in progress." },
      { id: "ov", name: "Actions past their date", value: over.length, target: 0, amber: 3, dir: "low", std: S("ISO 10.2", "IATF 10.2.3", "ISO 9.3"), why: "Open points whose target date has passed." },
      { id: "nd", name: "Open points without a date or owner", value: nodate.length + nowho.length, target: 0, amber: 3, dir: "low", std: S("ISO 5.3", "ISO 7.4", "ISO 10.2"), why: "Open points with no 'when' or no 'who' - they cannot be followed up." },
      { id: "cr", name: "Point closure rate", value: pts ? pct(done, pts) : null, unit: "%", target: 80, tol: 15, dir: "high", std: S("ISO 10.2", "IATF 9.3.3.1"), why: "Points done ÷ all points recorded." }],
      charts: [{ title: "Meetings per month", kind: "bar", kpi: "mt", labels: ms, series: [{ name: "Meetings", values: ms.map(function (m) { return byM[m] || 0; }) }] }, barOf("Open points by type", types, "Points", "op")] };
  } };

  /* ---------- APQP ---------- */
  KMRPA.apqp = { name: "APQP", code: "apqp", std: "apqp", load: async function (call) {
    var P = await call("kmr_apqp_list"), S = std, td = todayIso(), act = P.filter(function (p) { return p.status === "active"; });
    var tot = 0, dn = 0, ov = 0, withOv = 0, risk = 0, ph = {}; 
    act.forEach(function (p) { tot += +p.total || 0; dn += +p.done || 0; ov += +p.overdue || 0; if (+p.overdue > 0) withOv++; if (p.sop_date && days(td, String(p.sop_date).slice(0, 10)) <= 90 && days(td, String(p.sop_date).slice(0, 10)) >= 0 && pct(p.done, p.total) < 80) risk++; Object.keys(p.phases || {}).forEach(function (k) { var x = ph[k] = ph[k] || { t: 0, d: 0 }; x.t += p.phases[k].total; x.d += p.phases[k].done; }); });
    var late = act.filter(function (p) { return p.sop_date && String(p.sop_date).slice(0, 10) < td && pct(p.done, p.total) < 100; }).length;
    var low = act.map(function (p) { return { n: p.part_code, v: pct(p.done, p.total) || 0 }; }).sort(function (a, b) { return a.v - b.v; }).slice(0, 10), st = {}; P.forEach(function (p) { st[p.status] = (st[p.status] || 0) + 1; });
    return { period: "Live position · " + today(), kpis: [
      { id: "act", name: "Active APQP projects", value: act.length, std: S("APQP Phases 1-5", "IATF 8.3.2"), why: "Projects not on hold or closed." },
      { id: "comp", name: "Checklist completion", value: tot ? pct(dn, tot) : null, unit: "%", std: S("APQP Phases 1-5", "ISO 8.3.2", "IATF 8.3.2"), why: "Checklist items done ÷ items that apply, over active projects." },
      { id: "ov", name: "Overdue checklist items", value: ov, target: 0, amber: 5, dir: "low", std: S("APQP Phases 1-5", "IATF 8.3.4", "ISO 8.3.4"), why: "Open or in-progress items past their due date." },
      { id: "pov", name: "Projects with overdue items", value: withOv, target: 0, amber: 2, dir: "low", std: S("IATF 8.3.4", "ISO 8.3.4"), why: "Active projects having at least one overdue item." },
      { id: "risk", name: "SOP within 90 days and below 80% complete", value: risk, target: 0, amber: 1, dir: "low", std: S("APQP Phases 1-5", "IATF 8.3.4", "VDA P2 / P3 / P4"), why: "Launch risk: start of production is near but the plan is not ready." },
      { id: "sop", name: "Past SOP date and not complete", value: late, target: 0, amber: 1, dir: "low", std: S("IATF 8.3.4", "VDA P2 / P3 / P4"), why: "Active projects whose SOP date has passed with items still open." }],
      charts: [{ title: "Completion by APQP phase", kind: "bar", kpi: "comp", labels: ["1 Plan", "2 Design", "3 Process", "4 Validation", "5 Feedback"], series: [{ name: "Done %", values: [1, 2, 3, 4, 5].map(function (i) { var x = ph[i]; return x && x.t ? pct(x.d, x.t) : null; }) }] }, { title: "Projects with the lowest completion %", kind: "bar", kpi: "comp", labels: low.map(function (x) { return x.n; }), series: [{ name: "Complete %", values: low.map(function (x) { return x.v; }) }] }, barOf("Projects by status", st, "Projects", "act")] };
  } };

  /* ---------- PPAP ---------- */
  KMRPA.ppap = { name: "PPAP", code: "ppap", std: "ppap", load: async function (call) {
    var P = await call("kmr_ppap_list"), S = std, td = todayIso(), dec = P.filter(function (p) { return /approved|interim|rejected/.test(p.status); }), ap = P.filter(function (p) { return p.status === "approved"; }), rj = P.filter(function (p) { return p.status === "rejected"; });
    var wait = P.filter(function (p) { return p.status === "submitted" && p.submitted_on && days(String(p.submitted_on).slice(0, 10), td) > 30; }), ready = P.reduce(function (s, p) { return s + (+p.ready || 0); }, 0), dd = dec.filter(function (p) { return p.submitted_on && p.decided_on; });
    var avg = dd.length ? dd.reduce(function (s, p) { return s + days(String(p.submitted_on).slice(0, 10), String(p.decided_on).slice(0, 10)); }, 0) / dd.length : null, st = {}, lv = {}; P.forEach(function (p) { st[p.status] = (st[p.status] || 0) + 1; lv["Level " + p.level] = (lv["Level " + p.level] || 0) + 1; });
    var drafts = P.filter(function (p) { return p.status === "draft" && p.updated_at && days(String(p.updated_at).slice(0, 10), td) > 30; }).length;
    return { period: "Live position · " + today(), kpis: [
      { id: "tot", name: "PPAP submissions", value: P.length, std: S("PPAP 18 elements", "IATF 8.3.4.4"), why: "All submissions on record." },
      { id: "ap", name: "First-time approval rate", value: dec.length ? pct(ap.length, dec.length) : null, unit: "%", target: 90, tol: 10, dir: "high", std: S("PPAP Part Submission Warrant (PSW)", "IATF 8.3.4.4", "ISO 8.6"), why: "Approved ÷ decided submissions (approved, interim or rejected)." },
      { id: "rj", name: "Rejected submissions", value: rj.length, target: 0, amber: 1, dir: "low", std: S("IATF 8.3.4.4", "ISO 8.6", "VDA P4"), why: "Submissions rejected by the customer." },
      { id: "wt", name: "Submitted over 30 days, no decision", value: wait.length, target: 0, amber: 1, dir: "low", std: S("IATF 8.3.4.4", "VDA P4"), why: "Submissions waiting for a customer decision for more than 30 days." },
      { id: "dd", name: "Average days to customer decision", value: avg, unit: "days", target: 30, tol: 30, dir: "low", std: S("IATF 8.3.4.4", "APQP Phase 4"), why: "Average days from submission to decision." },
      { id: "dr", name: "Drafts untouched for 30 days", value: drafts, target: 0, amber: 2, dir: "low", std: S("PPAP 18 elements", "APQP Phase 4"), why: "Submissions still in draft and not updated for a month." },
      { id: "el", name: "Elements ready", value: P.length ? pct(ready, P.length * 18) : null, unit: "%", std: S("PPAP 18 elements"), why: "Elements ready, done or not applicable ÷ 18 per submission." }],
      charts: [barOf("Submissions by status", st, "Submissions", "tot"), barOf("Submissions by level", lv, "Submissions", "tot")] };
  } };

  /* ---------- CAD drafting ---------- */
  KMRPA.cad = { name: "CAD Drafting", code: "cad", std: "cad", load: async function (call) {
    var D = await call("kmr_cad_list"), S = std, td = todayIso(), cur = D.filter(function (d) { return d.status !== "superseded" && d.status !== "obsolete"; }), st = {}; D.forEach(function (d) { st[d.status] = (st[d.status] || 0) + 1; });
    var rel = cur.filter(function (d) { return d.status === "released"; }).length, rev = cur.filter(function (d) { return d.status === "review"; }), oldr = rev.filter(function (d) { return d.updated_at && days(String(d.updated_at).slice(0, 10), td) > 14; }).length, oldd = cur.filter(function (d) { return d.status === "draft" && d.updated_at && days(String(d.updated_at).slice(0, 10), td) > 30; }).length;
    var nums = {}; D.forEach(function (d) { nums[d.number] = d.revs; }); var mr = Math.max.apply(null, [0].concat(Object.keys(nums).map(function (k) { return nums[k]; })));
    var ms = last12(), by = {}; D.forEach(function (d) { var k = monthKey(d.created_at); by[k] = (by[k] || 0) + 1; });
    return { period: "Live position · " + today(), kpis: [
      { id: "tot", name: "Drawings (current revisions)", value: cur.length, std: S("ISO 7.5.2", "ISO 7.5.3", "IATF 7.5.3.2.1"), why: "Drawings that are not superseded or obsolete." },
      { id: "rel", name: "Drawings released", value: cur.length ? pct(rel, cur.length) : null, unit: "%", std: S("ISO 7.5.3", "IATF 8.3.5.1", "ISO 8.3.5"), why: "Released ÷ current drawings: only released drawings are issued to the shop floor." },
      { id: "rv", name: "In review over 14 days", value: oldr, target: 0, amber: 2, dir: "low", std: S("ISO 8.3.5", "IATF 8.3.5.1"), why: "Drawings waiting in review for more than two weeks." },
      { id: "dr", name: "Drafts untouched over 30 days", value: oldd, target: 0, amber: 3, dir: "low", std: S("ISO 7.5.3", "IATF 7.5.3.2.1"), why: "Drawings left in draft." },
      { id: "mx", name: "Most revisions on one drawing", value: mr, std: S("ISO 8.3.6", "IATF 8.3.6.1"), why: "A high number can indicate unstable design inputs." }],
      charts: [barOf("Drawings by status", st, "Drawings", "tot"), { title: "Drawings created per month", kind: "bar", kpi: "tot", labels: ms, series: [{ name: "Drawings", values: ms.map(function (m) { return by[m] || 0; }) }] }] };
  } };

  /* ---------- Office suite ---------- */
  KMRPA.off = { name: "Office (Docs, Sheets, Slides)", code: "off", std: "off", load: async function (call) {
    var r = await call("kmr_off_list", { p: {} }), F = r.files || [], S = std, td = todayIso(), k = { doc: 0, sheet: 0, slide: 0 }; F.forEach(function (f) { k[f.kind] = (k[f.kind] || 0) + 1; });
    var rev = F.filter(function (f) { return +f.rev > 1; }).length, rec = F.filter(function (f) { return f.updated_at && days(String(f.updated_at).slice(0, 10), td) <= 30; }).length, stale = F.filter(function (f) { return f.updated_at && days(String(f.updated_at).slice(0, 10), td) > 365; }).length, ms = last12(), by = {};
    F.forEach(function (f) { var m = monthKey(f.updated_at); by[m] = (by[m] || 0) + 1; });
    return { period: "Live position · " + today(), kpis: [
      { id: "tot", name: "Controlled files", value: F.length, std: S("ISO 7.5.1", "ISO 7.5.2"), why: "Documents, sheets and presentations held with a unique number." },
      { id: "rev", name: "Files with revision history", value: F.length ? pct(rev, F.length) : null, unit: "%", std: S("ISO 7.5.3.2", "IATF 7.5.3.2.2"), why: "Files at revision 2 or later - changes are kept as versions." },
      { id: "rec", name: "Files updated in the last 30 days", value: rec, std: S("ISO 7.5.3.1"), why: "Activity in the last month." },
      { id: "old", name: "Files not reviewed for a year", value: stale, target: 0, amber: 5, dir: "low", std: S("ISO 7.5.3.2", "IATF 7.5.3.2.1"), why: "Files not changed for more than 365 days; check they are still valid." }],
      charts: [{ title: "Files by type", kind: "bar", kpi: "tot", labels: ["Documents", "Sheets", "Presentations"], series: [{ name: "Files", values: [k.doc, k.sheet, k.slide] }] }, { title: "Files last updated per month", kind: "bar", kpi: "rec", labels: ms, series: [{ name: "Files", values: ms.map(function (m) { return by[m] || 0; }) }] }] };
  } };

  /* ---------- Maintenance ---------- */
  KMRPA.mnt = { name: "Maintenance", code: "mnt", std: "mnt", deps: ["/it/apps/mnt-calc.js"], controls: function () { return [{ id: "days", label: "Period", type: "select", value: 90, options: [[30, "Last 30 days"], [90, "Last 90 days"], [180, "Last 180 days"]] }]; }, load: async function (call, v) {
    var days_ = +v.days || 90, m = await call("kmr_mnt_load"), x = await call("kmr_mnt_data", { p_days: Math.max(180, days_) }), C = window.MNTCalc, S = std;
    var st = C.stats(x, m, days_, null), an = C.analysis(x, m, days_), pm = C.pm(x, x.today || todayIso()), openB = x.breakdowns.filter(function (b) { return b.status === "open" || b.status === "attended"; }).length;
    var top = an.byMachine.slice().sort(function (a, b) { return b.v - a.v; }).slice(0, 10), cat = an.byCat.slice().sort(function (a, b) { return b.v - a.v; }).slice(0, 8);
    return { period: "Last " + days_ + " days · " + today(), kpis: [
      { id: "av", name: "Plant availability", value: st.avail != null ? st.avail * 100 : null, unit: "%", target: 95, tol: 4, dir: "high", std: S("IATF 8.5.1.5", "ISO 7.1.3", "VDA P6"), why: "MTBF ÷ (MTBF + MTTR), from the breakdowns of the period." },
      { id: "mtbf", name: "MTBF", value: st.mtbf, unit: "h", std: S("IATF 8.5.1.5", "IATF 7.1.3.1"), why: "Operating hours ÷ number of breakdowns." },
      { id: "mttr", name: "MTTR", value: st.mttr, unit: "h", target: 4, tol: 25, dir: "low", std: S("IATF 8.5.1.5", "ISO 7.1.3"), why: "Breakdown downtime ÷ number of breakdowns." },
      { id: "bd", name: "Breakdowns", value: st.n, std: S("IATF 8.5.1.5", "ISO 10.2"), why: "Breakdowns started in the period." },
      { id: "dn", name: "Breakdown hours", value: st.down, unit: "h", std: S("IATF 8.5.1.5"), why: "Total machine stop time due to breakdowns." },
      { id: "rs", name: "Average response time", value: st.resp, unit: "h", target: 1, tol: 50, dir: "low", std: S("IATF 8.5.1.5", "VDA P6"), why: "Time from machine stop to the maintenance person attending." },
      { id: "pm", name: "PM done on time", value: pm.compliance != null ? pm.compliance * 100 : null, unit: "%", target: 90, tol: 10, dir: "high", std: S("IATF 8.5.1.5", "IATF 7.1.3.1", "ISO 7.1.3"), why: "Preventive maintenance done on or before its due date." },
      { id: "pmo", name: "PM plans overdue", value: pm.over, target: 0, amber: 2, dir: "low", std: S("IATF 8.5.1.5", "ISO 7.1.3"), why: "Preventive maintenance plans past their due date." },
      { id: "rep", name: "Repeat failures (same machine and cause 3+ times)", value: an.repeats.length, target: 0, amber: 1, dir: "low", std: S("ISO 10.2", "IATF 8.5.1.5"), why: "Needs root-cause action rather than another repair." },
      { id: "ob", name: "Breakdowns still open", value: openB, target: 0, amber: 1, dir: "low", std: S("IATF 8.5.1.5"), why: "Machines stopped or being attended now." }],
      charts: [{ title: "Breakdown hours by machine", kind: "bar", kpi: "dn", labels: top.map(function (a) { return a.l; }), series: [{ name: "Hours", values: top.map(function (a) { return a.v; }) }] },
        { title: "Breakdown hours by category", kind: "bar", kpi: "dn", labels: cat.map(function (a) { return a.l; }), series: [{ name: "Hours", values: cat.map(function (a) { return a.v; }) }] },
        { title: "Breakdowns and downtime by month", kind: "bar", kpi: "bd", labels: an.months.map(function (a) { return a.m; }), series: [{ name: "Breakdowns", values: an.months.map(function (a) { return a.n; }) }, { name: "Downtime h", values: an.months.map(function (a) { return a.down; }) }] },
        { title: "Availability by machine (%)", kind: "bar", kpi: "av", labels: an.rows.slice(0, 12).map(function (r) { return r.code; }), series: [{ name: "Availability %", values: an.rows.slice(0, 12).map(function (r) { return r.avail != null ? r.avail * 100 : null; }) }] }] };
  } };

  /* ---------- MMD: material movement, OEE, rejection ---------- */
  KMRPA.mmd = { name: "Material Movement (MMD)", code: "mmd", std: "mmd", deps: ["/it/apps/mmd-dash.js"], controls: function () { return [{ id: "days", label: "Period", type: "select", value: 30, options: [[7, "Last 7 days"], [30, "Last 30 days"], [90, "Last 90 days"]] }]; }, load: async function (call, v) {
    var days_ = +v.days || 30, m = await call("kmr_mmd_load"), x = await call("kmr_mmd_data", { p_days: Math.max(days_, 30) }), D = window.MMDDash, P = D.plant(m), S = std, td = m.today || todayIso();
    var since = Date.parse(td + "T00:00:00") - (days_ - 1) * 864e5, inWin = function (iso) { return Date.parse(String(iso).slice(0, 10) + "T00:00:00") >= since; }, wd = 0;
    for (var i = 0; i < days_; i++) { var dow = new Date(since + i * 864e5).getDay(), off = P.off === "Sunday" ? dow === 0 : P.off === "Saturday & Sunday" ? dow === 0 || dow === 6 : P.off === "Friday" ? dow === 5 : false; if (!off) wd++; }
    var lc = {}; (m.loss_codes || []).forEach(function (l) { lc[l.code] = l; });
    var pe = (x.entries || []).filter(function (e) { return e.status === "ok" && e.kind === "process" && inWin(e.entry_at) && e.machine; }), loss = (x.loss || []).filter(function (l) { return inWin(l.loss_date); }), mach = {};
    var M = function (c) { return (mach[c] = mach[c] || { c: c, ok: 0, rej: 0, rew: 0, std: 0, std_ok: 0, loss: 0, plan: 0 }); };
    pe.forEach(function (e) { var r = M(e.machine); r.ok += +e.ok_qty; r.rej += +e.rej_qty; r.rew += +e.rew_qty; var ct = +e.ct_sec || 0; r.std += ct * (+e.ok_qty + +e.rej_qty + +e.rew_qty) / 3600; r.std_ok += ct * +e.ok_qty / 3600; });
    loss.forEach(function (l) { var r = M(l.machine_code), pl = (lc[l.d_code] || {}).planned === "Yes"; if (pl) r.plan += +l.minutes / 60; else r.loss += +l.minutes / 60; });
    var R = Object.keys(mach).sort().map(function (k) { var r = mach[k], avail = P.H * wd - r.plan, op = Math.max(0.01, avail - r.loss), A = avail > 0 ? op / avail : 0, tot = r.ok + r.rej + r.rew, Pf = r.std ? Math.min(1, r.std / op) : null, Q = tot ? r.ok / tot : null; r.avail = avail; r.op = op; r.A = A; r.oee = Pf != null && Q != null ? A * Pf * Q : null; return r; });
    var T = R.reduce(function (a, r) { ["ok", "rej", "rew", "std", "std_ok", "loss", "plan", "avail", "op"].forEach(function (k) { a[k] += r[k]; }); return a; }, { ok: 0, rej: 0, rew: 0, std: 0, std_ok: 0, loss: 0, plan: 0, avail: 0, op: 0 });
    var tot = T.ok + T.rej + T.rew, TA = T.avail > 0 ? T.op / T.avail : null, TP = T.std ? Math.min(1, T.std / Math.max(0.01, T.op)) : null, TQ = tot ? T.ok / tot : null, TO = TA != null && TP != null && TQ != null ? TA * TP * TQ : null, tg = P.oee || 0.85;
    var df = (x.defects || []).filter(function (d) { return inWin(d.entry_at) && d.kind === "rej"; }), byR = {}; df.forEach(function (d) { var k = d.reason || "—"; byR[k] = (byR[k] || 0) + +d.qty; });
    var byL = {}; loss.forEach(function (l) { var k = (l.d_code || "") + " " + (l.d_name || ""); byL[k] = (byL[k] || 0) + +l.minutes / 60; });
    var day = {}; pe.forEach(function (e) { var d = String(e.entry_at).slice(0, 10), r = (day[d] = day[d] || { ok: 0, rej: 0, rew: 0 }); r.ok += +e.ok_qty; r.rej += +e.rej_qty; r.rew += +e.rew_qty; });
    var dk = Object.keys(day).sort().slice(-30), stuck = 0; try { stuck = D.stuck(m, x); } catch (e) { stuck = null; }
    return { period: "Last " + days_ + " days · " + wd + " working days", kpis: [
      { id: "oee", name: "OEE", value: TO != null ? TO * 100 : null, unit: "%", target: tg * 100, tol: 15, dir: "high", std: S("IATF 9.1.1.1", "IATF 8.5.2.1", "VDA P6"), why: "Availability × Performance × Quality, from the stage entries and loss hours." },
      { id: "av", name: "Availability", value: TA != null ? TA * 100 : null, unit: "%", target: 90, tol: 8, dir: "high", std: S("IATF 9.1.1.1", "ISO 8.5.2"), why: "(Available hours − unplanned loss hours) ÷ available hours." },
      { id: "pf", name: "Performance", value: TP != null ? TP * 100 : null, unit: "%", target: 90, tol: 8, dir: "high", std: S("IATF 9.1.1.1", "ISO 8.5.2"), why: "Standard hours of everything made ÷ operating hours." },
      { id: "q", name: "Quality (first pass OK)", value: TQ != null ? TQ * 100 : null, unit: "%", target: 97, tol: 2, dir: "high", std: S("ISO 8.7", "IATF 8.7.1", "IATF 9.1.1.1"), why: "OK ÷ (OK + rejected + rework)." },
      { id: "rej", name: "Rejection %", value: tot ? T.rej / tot * 100 : null, unit: "%", target: 2, tol: 50, dir: "low", std: S("ISO 8.7", "IATF 8.7.1", "IATF 9.1.1.1"), why: "Rejected pieces ÷ all pieces produced." },
      { id: "rew", name: "Rework %", value: tot ? T.rew / tot * 100 : null, unit: "%", target: 2, tol: 50, dir: "low", std: S("ISO 8.7", "IATF 8.7.1"), why: "Pieces sent for rework ÷ all pieces produced." },
      { id: "loss", name: "Unplanned loss hours", value: T.loss, unit: "h", std: S("IATF 9.1.1.1", "VDA P6"), why: "Machine hours lost to unplanned D codes." },
      { id: "stuck", name: "Lots not moving", value: stuck, target: 0, amber: 2, dir: "low", std: S("ISO 8.5.2", "IATF 8.5.2.1", "ISO 8.4"), why: "Lots waiting longer than the transfer time plus the run time at the OEE target." }],
      charts: [{ title: "OEE by machine (%)", kind: "bar", kpi: "oee", labels: R.map(function (r) { return r.c; }), series: [{ name: "OEE %", values: R.map(function (r) { return r.oee != null ? r.oee * 100 : null; }) }] },
        barOf("Rejection by defect (pcs)", byR, "Pieces", "rej"), barOf("Loss hours by D code", byL, "Hours", "loss"),
        { title: "Daily rejection and rework rate (%)", kind: "line", kpi: "rej", labels: dk.map(function (d) { return d.slice(5); }), series: [{ name: "Rejection %", values: dk.map(function (d) { var r = day[d], t = r.ok + r.rej + r.rew; return t ? r.rej / t * 100 : null; }) }, { name: "Rework %", values: dk.map(function (d) { var r = day[d], t = r.ok + r.rej + r.rew; return t ? r.rew / t * 100 : null; }) }] }] };
  } };

  /* ---------- Calibration ---------- */
  KMRPA.calibration = { name: "Calibration Hub", code: "calibration", ctxFn: "kmr_cal_context", std: "calibration", load: async function (call) {
    var D = await call("kmr_cal_load"), S = std, td = todayIso(), DUE = 30, ms = function (d) { return Date.parse(d + "T00:00:00"); };
    var AllI = D.instruments || [], I = AllI.filter(function (i) { return i.status !== "Scrapped"; }), use = I.filter(function (i) { return i.status === "In use"; }), dd = function (i) { return i.next_due ? Math.round((ms(i.next_due) - ms(td)) / 864e5) : null; };
    var od = use.filter(function (i) { return i.next_due && dd(i) < 0; }), soon = use.filter(function (i) { var d = dd(i); return d != null && d >= 0 && d <= DUE; }), nocal = use.filter(function (i) { return !i.next_due; });
    var oot = (D.oot || []).filter(function (o) { return o.status !== "Closed"; }), rec = D.records || [], cert = rec.filter(function (r) { return r.cert_no; }).length, msa = D.msa || [];
    var grr = msa.map(function (m) { return +((m.results || {}).pctGRR); }).filter(function (x) { return isFinite(x); }), bad = grr.filter(function (g) { return g > 30; }).length;
    var by = {}; I.forEach(function (i) { var k = i.department || "—"; by[k] = by[k] || { t: 0, o: 0 }; by[k].t++; if (od.indexOf(i) >= 0) by[k].o++; });
    var mo = {}; for (var k = 0; k < 6; k++) { var d = new Date(); d.setDate(1); d.setMonth(d.getMonth() + k); mo[ym(d)] = 0; }
    use.forEach(function (i) { if (i.next_due && mo[i.next_due.slice(0, 7)] != null) mo[i.next_due.slice(0, 7)]++; });
    var dk = Object.keys(by);
    return { period: "As on " + today(), kpis: [
      { id: "ok", name: "Calibrated on time", value: use.length ? (use.length - od.length) / use.length * 100 : null, unit: "%", target: 100, tol: 5, dir: "high", std: S("IATF 7.1.5.2.1", "ISO 7.1.5.2", "VDA 6.3 P6"), why: "Instruments in use that are not past their due date." },
      { id: "od", name: "Overdue instruments", value: od.length, target: 0, amber: 3, dir: "low", std: S("IATF 7.1.5.2.1", "ISO 7.1.5.2"), why: "Past due date — must not be used for acceptance." },
      { id: "soon", name: "Due in " + DUE + " days", value: soon.length, std: S("IATF 7.1.5.2.1"), why: "Plan these now so none goes overdue." },
      { id: "nc", name: "In use with no calibration date", value: nocal.length, target: 0, amber: 2, dir: "low", std: S("IATF 7.1.5.2.1", "ISO 7.1.5.2"), why: "No traceable calibration status." },
      { id: "oot", name: "Open out-of-tolerance cases", value: oot.length, target: 0, amber: 1, dir: "low", std: S("IATF 7.1.5.2.1", "ISO 7.1.5.2", "ISO 8.7"), why: "Parts measured since the last good calibration must be assessed." },
      { id: "cert", name: "Records with certificate", value: rec.length ? cert / rec.length * 100 : null, unit: "%", target: 100, tol: 10, dir: "high", std: S("IATF 7.1.5.3.2", "ISO 7.1.5.2"), why: "Traceability to national standards needs a certificate number." },
      { id: "grr", name: "MSA studies with %GRR above 30", value: bad, target: 0, amber: 1, dir: "low", std: S("IATF 7.1.5.1.1", "AIAG MSA"), why: msa.length + " studies on record; above 30% the gauge is not acceptable." },
      { id: "scrap", name: "Gauges moved to the scrap list", value: AllI.length - I.length, std: S("ISO 7.1.5.2"), why: "Gauges found unfit and withdrawn from use, each with date and reason." },
      { id: "cost", name: "Calibration cost this year (INR)", value: Math.round(rec.filter(function (r) { return String(r.cal_date || "").slice(0, 4) === td.slice(0, 4); }).reduce(function (a, r) { return a + (+r.cost || 0); }, 0)), std: S("ISO 7.1.5.1", "ISO 9.3.2"), why: "Spend on calibration this year, from the cost entered on each calibration." }],
      charts: [{ title: "Instruments due by month", kind: "bar", kpi: "soon", labels: Object.keys(mo), series: [{ name: "Due", values: Object.keys(mo).map(function (m) { return mo[m]; }) }] },
        { title: "Overdue by department", kind: "bar", kpi: "od", labels: dk, series: [{ name: "Overdue", values: dk.map(function (x) { return by[x].o; }) }, { name: "Total", values: dk.map(function (x) { return by[x].t; }) }] }] };
  } };

  /* ---------- Raw Material Planning ---------- */
  KMRPA.rmp = { name: "Raw Material Planning", code: "rmp", std: "rmp", deps: ["/it/apps/rmp-calc.js"], controls: function () { var o = [], d = new Date(); d.setDate(1); for (var k = 0; k < 4; k++) { var m = ym(d); o.push([m, m]); d.setMonth(d.getMonth() + 1); } return [{ id: "month", label: "Month", type: "select", value: o[0][0], options: o }]; }, load: async function (call, v) {
    var data = await call("kmr_rmp_load", { p_month: v.month }), P = window.RMPCalc.plan(data, v.month), S = std, L = P.lines || [];
    var ord = L.filter(function (l) { return l.order > 0; }), late = L.filter(function (l) { return l.late; }), sh = L.filter(function (l) { return l.short > 0; });
    var val = ord.reduce(function (a, l) { return a + (l.value || 0); }, 0), top = ord.slice().sort(function (a, b) { return b.value - a.value; }).slice(0, 10);
    var sup = {}; ord.forEach(function (l) { var k = l.supplier || "—"; sup[k] = (sup[k] || 0) + (l.value || 0); });
    return { period: "Plan for " + v.month, kpis: [
      { id: "late", name: "Orders already late", value: late.length, target: 0, amber: 2, dir: "low", std: S("IATF 8.4.2.1", "ISO 8.4.1", "VDA 6.3 P5"), why: "Order-by date has passed — material will reach production late." },
      { id: "sh", name: "Materials short of requirement", value: sh.length, target: 0, amber: 3, dir: "low", std: S("ISO 8.1", "IATF 8.4.2.1", "VDA 6.3 P5"), why: "Stock plus safety stock does not cover the plan." },
      { id: "pr", name: "Data problems in the plan", value: (P.problems || []).length, target: 0, amber: 3, dir: "low", std: S("ISO 7.5.3", "ISO 8.1"), why: "Missing weights, drawings or BOM lines that make the plan uncertain." },
      { id: "no", name: "Materials to order", value: ord.length, std: S("ISO 8.4.1"), why: "Lines with a net order quantity." },
      { id: "va", name: "Order value", value: val, unit: "₹", std: S("ISO 8.4.1"), why: "Total value of the orders to place." }],
      charts: [barOf("Order value by material (₹)", Object.fromEntries(top.map(function (l) { return [l.code, l.value]; })), "₹", "va"), barOf("Order value by supplier (₹)", sup, "₹", "va")] };
  } };

  /* ---------- Sales Flow ---------- */
  KMRPA.sales = { name: "Sales Flow", code: "sales", ctxFn: "kmr_sf_context", std: "sales", controls: function () { var o = [], d = new Date(); d.setDate(1); for (var k = 0; k < 6; k++) { var m = ym(d); o.push([m, m]); d.setMonth(d.getMonth() - 1); } return [{ id: "month", label: "Month", type: "select", value: o[0][0], options: o }]; }, load: async function (call, v) {
    var r = await call("kmr_sf_month", { p_month: v.month + "-01" }), S = std, td = todayIso(), L = r.lines || [], dsp = {};
    (r.despatch || []).forEach(function (d) { (dsp[d.line_id] = dsp[d.line_id] || {})[d.day] = +d.qty; });
    var dim = new Date(+v.month.slice(0, 4), +v.month.slice(5, 7), 0).getDate(), upto = td < v.month + "-01" ? 0 : td.slice(0, 7) === v.month ? +td.slice(8) : dim, f = Math.min(1, upto / dim);
    var rows = L.map(function (l) { var dem = +l.demand_qty || 0, done = Object.keys(dsp[l.id] || {}).reduce(function (a, k) { return a + dsp[l.id][k]; }, 0), exp = l.sched_type === "date" ? (l.sched_date && l.sched_date <= td ? dem : 0) : dem * f, price = +l.price || 0; return { l: l, dem: dem, done: done, exp: exp, price: price, cur: l.currency || "INR", ratio: exp > 0 ? done / exp : null }; });
    var plan = rows.filter(function (x) { return x.dem > 0; }), tot = plan.reduce(function (a, x) { return a + x.dem; }, 0), dn = plan.reduce(function (a, x) { return a + Math.min(x.done, x.dem); }, 0), ex = plan.reduce(function (a, x) { return a + x.exp; }, 0);
    var behind = plan.filter(function (x) { return x.ratio != null && x.ratio < 0.7; }), slip = plan.filter(function (x) { return x.ratio != null && x.ratio >= 0.7 && x.ratio < 0.9; }), nothing = plan.filter(function (x) { return x.exp > 0 && x.done === 0; });
    var unp = rows.reduce(function (a, x) { return a + (x.dem === 0 ? x.done : Math.max(x.done - x.dem, 0)); }, 0), np = plan.filter(function (x) { return !(x.price > 0); }).length;
    var worst = plan.filter(function (x) { return x.exp - x.done > 0; }).sort(function (a, b) { return (b.exp - b.done) - (a.exp - a.done); }).slice(0, 10), days = {};
    Object.keys(dsp).forEach(function (id) { Object.keys(dsp[id]).forEach(function (d) { days[d] = (days[d] || 0) + dsp[id][d]; }); });
    var dk = Object.keys(days).sort(), name = function (x) { return x.l.part_code || x.l.part_no || x.l.part || x.l.id; };
    return { period: v.month + " · " + upto + " of " + dim + " days", kpis: [
      { id: "ach", name: "Despatched against plan", value: pct(dn, tot), unit: "%", std: S("IATF 8.2.1", "IATF 9.1.1.1", "ISO 9.1.2"), why: "Pieces despatched ÷ the month's customer demand." },
      { id: "otd", name: "Despatched against due-by-today", value: ex ? dn / ex * 100 : null, unit: "%", target: 100, tol: 10, dir: "high", std: S("IATF 9.1.1.1", "IATF 8.2.1", "VDA 6.3 P7"), why: "Pieces despatched ÷ pieces scheduled up to today. Below 90% is slipping." },
      { id: "bh", name: "Parts behind plan (under 70%)", value: behind.length, target: 0, amber: 2, dir: "low", std: S("IATF 8.2.1", "VDA 6.3 P7"), why: "Needs a recovery plan with date and owner." },
      { id: "sl", name: "Parts slipping (70–90%)", value: slip.length, target: 0, amber: 3, dir: "low", std: S("IATF 8.2.1"), why: "Early warning before they go behind." },
      { id: "no", name: "Parts due but nothing despatched", value: nothing.length, target: 0, amber: 1, dir: "low", std: S("IATF 8.2.1", "ISO 8.5.4"), why: "Check stock, quality holds and the customer schedule." },
      { id: "up", name: "Unplanned despatch (pcs)", value: unp, std: S("ISO 8.2.1", "IATF 8.2.1"), why: "Despatched with no customer demand, or above the planned quantity." },
      { id: "np", name: "Planned parts without a price", value: np, target: 0, amber: 3, dir: "low", std: S("ISO 8.2.3"), why: "Value cannot be reported without a price." }],
      charts: [{ title: "Pending quantity — top 10 parts", kind: "bar", kpi: "otd", labels: worst.map(name), series: [{ name: "Due by today", values: worst.map(function (x) { return Math.round(x.exp); }) }, { name: "Despatched", values: worst.map(function (x) { return x.done; }) }] },
        { title: "Daily despatch (pcs)", kind: "bar", kpi: "ach", labels: dk.map(function (d) { return d.slice(8); }), series: [{ name: "Pieces", values: dk.map(function (d) { return days[d]; }) }] }] };
  } };
  /* Sales Flow, redesigned: value KPIs (plan, actual, loss), loss by reason, conclusion and the six-step method, from the same model as the Sales Flow screens (apps/sales-all.js) */
  (function () {
    var P = KMRPA.sales, old = P.load;
    P.deps = (P.deps || []).concat(["/it/apps/sales-all.js"]);
    P.load = async function (call, v) {
      var base = await old(call, v), r = await call("kmr_sf_month", { p_month: v.month + "-01" }), acts = [];
      try { acts = await call("kmr_sf_actions", {}) || []; } catch (e) { acts = []; }
      var code = "This plant", tag = function (x) { return Object.assign({}, x, { plant_code: code }); };
      var M = SalesAll.build({ lines: (r.lines || []).map(tag), despatch: r.despatch || [], plants: [{ code: code, slug: "", name: code }], actions: acts.map(tag), month: v.month, basis: "today" }), d = SalesAll.presentData(M), drop = { ach: 1, otd: 1 };
      base.charts.forEach(function (c) { c.kpi = "ach"; });
      return { period: base.period, kpis: d.kpis.concat(base.kpis.filter(function (k) { return !drop[k.id]; })), charts: d.charts.concat(base.charts), extra: d.extra };
    };
  })();
  /* ---------- Daily Work Management: every employee's DWM added up (same model as the Dashboards screen, apps/dwm-core.js) ---------- */
  KMRPA.dwm = { name: "Daily Work Management", code: "dwm", ctxFn: "kmr_dwm_context", std: "dwm", deps: ["/it/apps/dwm-core.js"], controls: function () { var o = [], d = new Date(); d.setDate(1); for (var k = 0; k < 6; k++) { var m = ym(d); o.push([m, m]); d.setMonth(d.getMonth() - 1); } return [{ id: "month", label: "Month", type: "select", value: o[0][0], options: o }]; }, load: async function (call, v) {
    var S = std, m = v.month, D = window.DWM, td = todayIso(), slug = (window.QP && QP.slug) || "", emps = [], docs = {};
    var esc = function (x) { return String(x == null ? "" : x).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); };
    try { var st = await call("kmr_dwm_get", { p_key: "staff" }); emps = (st && st.emps) || []; (await call("kmr_dwm_month", { p_month: m }) || []).forEach(function (r) { docs[r.key.split(":")[2]] = r.doc; }); } catch (e) { emps = []; }
    if (!emps.length) { try { var ls = JSON.parse(localStorage.getItem("kmr_dwm_" + slug + "_staff") || "null"); emps = (ls && ls.emps) || []; emps.forEach(function (e) { var x = localStorage.getItem("kmr_dwm_" + slug + "_dwm:" + m + ":" + e.id); if (x) docs[e.id] = JSON.parse(x); }); } catch (e2) { emps = []; } }
    if (!emps.length) return { period: m, kpis: [], charts: [], extra: [{ title: "Daily Work Management", std: S("ISO 9.3.2", "ISO 5.1.1"), html: '<div class="note">No employee has a DWM sheet yet. Add employees and their reviews in the DWM screen.</div>' }] };
    var A = D.summary(emps, docs, m, td, 98), T = A.total, tg = A.target, rows = A.rows.filter(function (r) { return r.T.plan > 0; }), below = rows.filter(function (r) { return r.light === "r" || r.light === "a"; }).length;
    var K = [
      { id: "fm", name: "Full-month adherence (all employees)", value: T.pct, unit: "%", target: tg, amber: tg - 8, dir: "high", std: S("ISO 9.1.3", "ISO 5.1.1", "IATF 9.1.1.1", "VDA P6"), why: "Completed reviews ÷ all reviews planned for the month, added up over every employee. Future planned reviews stay in the denominator." },
      { id: "td", name: "Adherence to date (all employees)", value: T.pctTo, unit: "%", target: tg, amber: tg - 8, dir: "high", std: S("ISO 9.1.3", "IATF 9.1.1.1", "ISO 9.3.2", "VDA P6", "VDA P7"), why: "Completed ÷ planned for the days up to today (" + T.doneTo + " of " + T.planTo + ")." },
      { id: "eb", name: "Employees below target", value: below, target: 0, amber: 1, dir: "low", std: S("ISO 5.3", "IATF 5.3.1", "ISO 9.3.3", "VDA P1"), why: "Employees whose adherence to date is under the target of " + tg + "%, out of " + rows.length + " with a plan." },
      { id: "od", name: "Past days still showing O", value: T.overdue, target: 0, amber: 3, dir: "low", std: S("ISO 10.2", "ISO 9.1.3", "VDA P6"), why: "Reviews whose date has passed but are still marked as planned: update them to C, X or E." },
      { id: "xm", name: "Missed reviews (X)", value: T.missed, target: 0, amber: 3, dir: "low", std: S("ISO 10.2", "ISO 9.3.2", "VDA P7"), why: "Each miss needs a reason and a recovery date." },
      { id: "ec", name: "Concessions (E)", value: T.conc, target: 0, amber: 3, dir: "low", std: S("ISO 10.2", "ISO 5.3"), why: "Concessions stay in the plan and do not count as completed." }];
    rows.forEach(function (r) { K.push({ id: "e_" + r.emp.id, name: r.emp.name + " — adherence to date", value: r.pctTo != null ? r.pctTo : r.pct, unit: "%", target: r.target, amber: r.target - 8, dir: "high", std: S("ISO 5.3", "ISO 9.1.3", "IATF 5.3.1", "VDA P1"), why: r.emp.name + (r.emp.desig ? " (" + r.emp.desig + ")" : "") + ": " + r.T.doneTo + " of " + r.T.planTo + " reviews due so far are completed." }); });
    var lab = [], pd = []; for (var d = 1; d <= A.n; d++) { lab.push(String(d)); pd.push(d <= A.dayNo && A.perDay[d - 1].plan ? +A.perDay[d - 1].pct.toFixed(1) : null); }
    var byEmp = rows.slice().sort(function (a, b) { return (a.pctTo != null ? a.pctTo : a.pct || 0) - (b.pctTo != null ? b.pctTo : b.pct || 0); });
    var tb = function (head, rs) { return "<table><thead><tr>" + head.map(function (h) { return "<th>" + h + "</th>"; }).join("") + "</tr></thead><tbody>" + rs.join("") + "</tbody></table>"; };
    var act = []; A.rows.forEach(function (r) { r.c.rows.forEach(function (x) { if (x.planTo > 0 && x.doneTo / x.planTo * 100 < tg) act.push({ r: r, x: x }); }); }); act.sort(function (a, b) { return a.x.doneTo / a.x.planTo - b.x.doneTo / b.x.planTo; });
    var logs = []; A.rows.forEach(function (r) { ((r.doc && r.doc.acts) || []).forEach(function (a) { for (var d = 1; d <= A.n; d++) { var c = D.cell(a, d); if (c === "X" || c === "E") logs.push({ r: r, a: a, d: d, c: c, L: ((r.doc.log || {})[a.id + ":" + d]) || {} }); } }); });
    return { period: m + " · day " + A.dayNo + " of " + A.n + " · " + emps.length + " employee(s) · " + T.plan + " reviews planned", kpis: K,
      charts: [{ title: "Adherence to date by employee (%)", kind: "bar", kpi: "td", labels: byEmp.map(function (r) { return r.emp.name.split(" ")[0]; }), series: [{ name: "Adherence %", values: byEmp.map(function (r) { var v = r.pctTo != null ? r.pctTo : r.pct; return +(v || 0).toFixed(0); }) }], note: "Target " + tg + "% or more. Lowest first." },
        { title: "Adherence by day — all employees (%)", kind: "line", kpi: "fm", labels: lab.slice(0, Math.max(A.dayNo, 1)), series: [{ name: "Adherence %", values: pd.slice(0, Math.max(A.dayNo, 1)) }], note: "Completed ÷ planned for each day." }],
      extra: [
        { title: "Employee-wise DWM adherence", std: S("ISO 5.3", "ISO 9.1.3", "ISO 9.3.2", "IATF 5.3.1", "VDA P1", "VDA P6"), html: rows.length ? tb(["Employee", "Designation", "Planned", "Completed", "Missed", "Concession", "Full month", "To date"], byEmp.map(function (r) { return "<tr><td>" + esc(r.emp.name) + "</td><td>" + esc(r.emp.desig || "") + "</td><td>" + r.T.plan + "</td><td>" + r.T.done + "</td><td>" + r.T.missed + "</td><td>" + r.T.conc + "</td><td>" + (r.pct == null ? "—" : r.pct.toFixed(1) + "%") + '</td><td><i class="dot l-' + (r.light === "n" ? "n" : r.light) + '"></i> ' + (r.pctTo == null ? "—" : r.pctTo.toFixed(1) + "%") + "</td></tr>"; })) : '<div class="note">No employee has planned reviews this month.</div>' },
        { title: "Activities below target — where to act", std: S("ISO 9.3.3", "ISO 10.2", "ISO 5.1.1", "VDA P6"), html: act.length ? tb(["Employee", "Activity", "Planned to date", "Completed", "Adherence"], act.slice(0, 12).map(function (z) { return "<tr><td>" + esc(z.r.emp.name) + "</td><td>" + esc(z.x.a.activity || "") + "</td><td>" + z.x.planTo + "</td><td>" + z.x.doneTo + "</td><td>" + (z.x.doneTo / z.x.planTo * 100).toFixed(0) + "%</td></tr>"; })) : '<div class="note">Every activity due so far is at or above the target.</div>' },
        { title: "Missed and concession record", std: S("ISO 10.2", "ISO 9.3.3", "VDA P7"), html: logs.length ? tb(["Date", "Employee", "Activity", "Status", "Reason", "Approver", "Revised due", "Action ref."], logs.slice(0, 12).map(function (z) { return "<tr><td>" + (z.d < 10 ? "0" : "") + z.d + "-" + m.slice(5) + "-" + m.slice(0, 4) + "</td><td>" + esc(z.r.emp.name) + "</td><td>" + esc(z.a.activity || "") + "</td><td>" + (z.c === "X" ? "Missed" : "Concession") + "</td><td>" + esc(z.L.reason || "—") + "</td><td>" + esc(z.L.approver || "—") + "</td><td>" + esc(z.L.due || "—") + "</td><td>" + esc(z.L.ref || "—") + "</td></tr>"; })) : '<div class="note">No missed reviews or concessions this month.</div>' }] };
  } };
  /* ---------- Delivery Challan & GRN ---------- */
  KMRPA.dcg = { name: "Delivery Challan & GRN", code: "dcg", ctxFn: "kmr_dcg_context", std: "dcg", load: async function (call) {
    var d = await call("kmr_dcg_load"), S = std, td = new Date(Date.now() + 19800000).toISOString().slice(0, 10), mo = td.slice(0, 7), y = +td.slice(0, 4), fs = (+td.slice(5, 7) < 4 ? y - 1 : y) + "-04-01";
    var pend = function (l) { return Math.max(0, +l.qty - +(l.returned_qty || 0)); };
    var open = d.dcs.filter(function (c) { return c.kind === "returnable" && (c.status === "issued" || c.status === "part_returned"); });
    var over = open.filter(function (c) { return c.expected_return && c.expected_return < td; });
    var grns = d.grns.filter(function (g) { return g.status === "posted"; }), gy = grns.filter(function (g) { return g.grn_date >= fs; });
    var rec = 0, rej = 0, bySup = {}, byParty = {};
    gy.forEach(function (g) { g.lines.forEach(function (l) { rec += +l.received_qty; rej += +l.rejected_qty; if (g.gtype === "po_receipt") { var k = g.party_name || "-"; bySup[k] = (bySup[k] || 0) + +l.rejected_qty; } }); });
    open.forEach(function (c) { byParty[c.party_name] = (byParty[c.party_name] || 0) + c.lines.filter(function (l) { return pend(l) > 0; }).length; });
    var outG = (d.instruments || []).filter(function (i) { return i.status === "Out for calibration"; }).length;
    var oldest = over.reduce(function (m, c) { var n = Math.round((new Date(td) - new Date(c.expected_return)) / 864e5); return n > m ? n : m; }, 0);
    return { period: "Live position · " + today(), kpis: [
      { id: "open", name: "Returnable challans out", value: open.length, std: S("ISO 8.5.4", "ISO 8.5.2", "GST Rule 55"), why: "Returnable delivery challans issued and not yet fully received back." },
      { id: "over", name: "Returns overdue", value: over.length, target: 0, amber: 2, dir: "low", std: S("ISO 8.5.4", "ISO 10.2", "GST Section 143"), why: "Returnable challans past their expected return date." },
      { id: "age", name: "Oldest overdue return", value: oldest, unit: "days", target: 0, amber: 15, dir: "low", std: S("ISO 8.5.4", "ISO 10.2"), why: "Days past the expected return date of the oldest overdue challan." },
      { id: "gau", name: "Gauges out for calibration", value: outG, std: S("ISO 7.1.5.1", "IATF 7.1.5.2.1"), why: "Gauges sent out on a calibration challan and not yet calibrated and received." },
      { id: "grn", name: "GRNs this month", value: grns.filter(function (g) { return g.grn_date.slice(0, 7) === mo; }).length, std: S("ISO 8.6", "ISO 8.4.2"), why: "Goods Receipt Notes posted in the month." },
      { id: "rej", name: "Rejection on receipt (year)", value: rec ? +(rej / rec * 100).toFixed(1) : null, unit: "%", target: 1, amber: 3, dir: "low", std: S("ISO 8.4.2", "ISO 8.7", "IATF 8.4.2.4", "VDA P5"), why: "Rejected quantity ÷ received quantity on GRNs since 1 April." },
      { id: "po", name: "Open purchase orders", value: d.pos.filter(function (p) { return p.status === "open" || p.status === "part_received"; }).length, std: S("ISO 8.4.3", "VDA P5"), why: "Purchase orders with material still to be received." }],
      charts: [barOf("Items waiting to come back, by party", byParty, "Items", "open"), barOf("Rejected quantity by supplier (this year)", bySup, "Rejected", "rej")] };
  } };
  KMRPA.inv = { name: "Sales Invoicing", code: "inv", ctxFn: "kmr_inv_context", std: "inv", load: async function (call) {
    var d = await call("kmr_inv_load", { p_months: 12 }), S = std, td = new Date(Date.now() + 19800000).toISOString().slice(0, 10), y = +td.slice(0, 4), fs = (+td.slice(5, 7) < 4 ? y - 1 : y) + "-04-01";
    var iss = d.invoices.filter(function (i) { return i.status === "issued"; }), fy = iss.filter(function (i) { return i.inv_date >= fs; }), byC = {};
    var tot = function (a, k) { return a.reduce(function (s, i) { return s + +(i[k] || 0); }, 0); };
    fy.forEach(function (i) { byC[i.buyer_name] = (byC[i.buyer_name] || 0) + +i.total; });
    var noIrn = iss.filter(function (i) { return i.supply_type === "B2B" && i.doc_type === "INV" && !i.irn; }).length;
    return { period: "Financial year from " + fs, kpis: [
      { id: "n", name: "Invoices issued (year)", value: fy.length, std: S("GST Section 31", "GST Rule 46"), why: "Tax invoices issued since 1 April." },
      { id: "val", name: "Invoice value (year, lakh)", value: +(tot(fy, "total") / 1e5).toFixed(2), unit: "lakh", std: S("ISO 9.1.3"), why: "Total invoice value including GST since 1 April." },
      { id: "gst", name: "GST charged (year, lakh)", value: +((tot(fy, "cgst") + tot(fy, "sgst") + tot(fy, "igst")) / 1e5).toFixed(2), unit: "lakh", std: S("GST Section 31"), why: "CGST + SGST + IGST on invoices since 1 April." },
      { id: "dr", name: "Drafts not issued", value: d.invoices.filter(function (i) { return i.status === "draft"; }).length, target: 0, amber: 3, dir: "low", std: S("ISO 7.5.3.2"), why: "Invoices saved but not yet issued." },
      { id: "irn", name: "Invoices without IRN", value: noIrn, target: 0, amber: 3, dir: "low", std: S("GST Rule 48"), why: "Issued B2B invoices whose IRN is not yet recorded." },
      { id: "tal", name: "Not yet sent to Tally", value: iss.filter(function (i) { return !i.tally_at; }).length, target: 0, amber: 10, dir: "low", std: S("ISO 7.5.3.2"), why: "Issued invoices not yet exported to Tally." }],
      charts: [barOf("Invoice value by customer (this year)", byC, "Value", "val")] };
  } };
})();
