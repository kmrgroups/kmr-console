/* Material Movement (MMD) — sample data for the demo (?demo=1).
   It follows the database functions step by step (same rules, same messages, same answers), so the demo behaves like the real thing. */
(function () {
  "use strict";
  const DAY = 864e5, nowMs = () => Date.now(), isoD = (ms) => new Date(ms).toISOString().slice(0, 10);
  let uid = 0; const id = () => "m" + (++uid).toString(36) + Math.random().toString(36).slice(2, 6);
  const ME = "demo@kmr.test";
  const parts = [
    { code: "DP-1101", name: "Drive Flange", material: "RM-EN8-65", weight_kg: 1.8, customer: "CUS-001" }, { code: "DP-1102", name: "Wheel Hub", material: "RM-EN8-65", weight_kg: 2.4, customer: "CUS-001" },
    { code: "DP-1103", name: "Gear Housing", material: "RM-EN353-F", weight_kg: 3.1, customer: "CUS-002" }, { code: "DP-1104", name: "Pinion Shaft", material: "RM-EN19-45", weight_kg: 0.9, customer: "CUS-002" },
    { code: "DP-1105", name: "Sleeve", material: "RM-EN19-45", weight_kg: 0.35, customer: "CUS-001" }];
  const customers = { "CUS-001": "Apex Drivetrain Pvt Ltd", "CUS-002": "Vega Gearboxes Ltd" };
  const materials = [{ code: "RM-EN8-65", name: "EN8 bar Ø65", form: "Bar", size: "Ø65 × 3 m", grade: "EN8", specification: "IS 5517 / BS 970", supplier: "SUP-001" }, { code: "RM-EN353-F", name: "EN353 forging blank", form: "Forging", size: "Ø110 × 38", grade: "EN353", specification: "BS 970", supplier: "SUP-002" },
    { code: "RM-EN19-45", name: "EN19 bar Ø45", form: "Bar", size: "Ø45 × 3 m", grade: "EN19", specification: "BS 970 709M40", supplier: "SUP-001" }];
  const suppliers = [{ code: "SUP-001", name: "Coimbatore Steels" }, { code: "SUP-002", name: "Rajkot Forgings" }, { code: "SUP-004", name: "Outsourced process" }];
  const machines = [{ code: "CNC-T01", name: "CNC Turning 1" }, { code: "CNC-T02", name: "CNC Turning 2" }, { code: "VMC-M01", name: "VMC 1" }, { code: "GRN-G01", name: "Cylindrical Grinder" }, { code: "QA-01", name: "Inspection bench" }];
  const loss_codes = [["D01", "Machine breakdown — mechanical", "Availability", "Breakdown"], ["D02", "Tool change / breakage", "Availability", "Tooling"], ["D03", "Set-up / changeover", "Availability", "Set-up & changeover"], ["D04", "Waiting for material", "Availability", "Material"], ["D05", "Waiting for operator", "Availability", "Manpower"], ["D06", "Power failure", "Availability", "Utilities"], ["D07", "Reduced speed", "Performance", "Speed"], ["D08", "No plan / no order", "Availability", "Planning"]].map((x) => ({ code: x[0], name: x[1], category: x[2], group: x[3], planned: "No" }));
  const defect_codes = [["DF01", "OD oversize", "Rework"], ["DF02", "Undersize", "Rejection"], ["DF03", "Surface finish not OK", "Rejection"], ["DF04", "Burr / sharp edge", "Rework"], ["DF05", "Tool mark", "Rejection"], ["DF06", "Crack / material defect", "Rejection"], ["DF07", "Hardness out of range", "Rejection"]].map((x) => ({ code: x[0], name: x[1], type: x[2] }));
  const shifts = [{ code: "A", name: "Shift A", start: "06:00", end: "14:00" }, { code: "B", name: "Shift B", start: "14:00", end: "22:00" }, { code: "C", name: "Shift C", start: "22:00", end: "06:00" }];
  const op = (n, name, mc, type, sup, ct) => ({ seq: n, op_no: n * 10, name, machine: mc || "", type: type || "in", supplier: sup || null, ct_sec: ct || 60 });
  const routes = {
    "DP-1101": [op(1, "Turning OP10", "CNC-T01", 0, 0, 55), op(2, "Turning OP20", "CNC-T02", 0, 0, 48), op(3, "PCD Drilling OP30", "VMC-M01", 0, 0, 62), op(4, "Heat treatment OP40", "", "supplier", "SUP-004"), op(5, "Grinding OP50", "GRN-G01", 0, 0, 40), op(6, "Final inspection OP60", "QA-01", 0, 0, 55)],
    "DP-1102": [op(1, "Turning OP10", "CNC-T01", 0, 0, 70), op(2, "Turning OP20", "CNC-T02", 0, 0, 65), op(3, "Drilling OP30", "VMC-M01", 0, 0, 50), op(4, "Final inspection OP40", "QA-01", 0, 0, 55)],
    "DP-1103": [op(1, "Facing & boring OP10", "CNC-T01", 0, 0, 120), op(2, "Milling OP20", "VMC-M01", 0, 0, 150), op(3, "Final inspection OP30", "QA-01", 0, 0, 60)],
    "DP-1104": [op(1, "Turning OP10", "CNC-T02", 0, 0, 45), op(2, "Milling OP20", "VMC-M01", 0, 0, 55), op(3, "Heat treatment OP30", "", "supplier", "SUP-004"), op(4, "Grinding OP40", "GRN-G01", 0, 0, 38), op(5, "Final inspection OP50", "QA-01", 0, 0, 55)],
    "DP-1105": [op(1, "Turning OP10", "CNC-T01", 0, 0, 30), op(2, "Drilling OP20", "VMC-M01", 0, 0, 25), op(3, "Final inspection OP30", "QA-01", 0, 0, 40)]
  };
  const rsL = [], tags = [], ents = [], defs = [], dcs = [], grns = [], loss = [], ctr = {};
  const T = (a, k) => a.find((x) => x.id === k);
  const err = (m) => { throw new Error(m); };
  const nz = (v) => (v === "" || v == null ? null : v), num = (v) => { const n = +v; return isFinite(n) ? n : 0; };
  const yymm = (ms) => { const d = new Date(ms + 19800000); return String(d.getUTCFullYear()).slice(2) + String(d.getUTCMonth() + 1).padStart(2, "0"); };
  const next = (k) => (ctr[k] = (ctr[k] || 0) + 1);
  const iso = (ms) => new Date(ms).toISOString();

  function newTag(rs, kind, seq, loc, qty, parent, entry, opDone, at, x) {
    const t = { id: id(), tag_no: "TG-" + yymm(at) + "-" + String(next("TG-" + yymm(at))).padStart(5, "0"), rs_id: rs.id, kind, seq, loc, qty, bal: qty, status: "open", parent_tag: parent, entry_id: entry, op_done: opDone,
      reason_code: (x && x.reason_code) || null, reason: (x && x.reason) || null, spec: (x && x.spec) || null, actual: (x && x.actual) || null, dispo: null, dispo_note: null, created_at: iso(at), created_by: ME };
    tags.push(t); return t;
  }
  function progress(rs) {
    return rs.ops.map((o) => {
      const S = (f) => tags.filter(f).reduce((a, t) => a + t.bal, 0), ent = (f) => ents.filter((e) => e.rs_id === rs.id && e.seq === o.seq && e.status === "ok" && f(e));
      return Object.assign({}, o, { rs_qty: rs.qty,
        arrived: tags.filter((t) => t.rs_id === rs.id && t.seq === o.seq && ["RM", "OK"].includes(t.kind) && t.status !== "void").reduce((a, t) => a + t.qty, 0),
        ok: ent((e) => ["process", "rework", "grn"].includes(e.kind)).reduce((a, e) => a + e.ok_qty, 0), rej: ent((e) => ["process", "rework", "grn"].includes(e.kind)).reduce((a, e) => a + e.rej_qty, 0),
        rew: ent((e) => e.kind === "process").reduce((a, e) => a + e.rew_qty, 0),
        rew_open: S((t) => t.rs_id === rs.id && t.seq === o.seq && t.kind === "REW" && t.status === "open"), waiting: S((t) => t.rs_id === rs.id && t.seq === o.seq && ["RM", "OK"].includes(t.kind) && t.status === "open"),
        at_supplier: dcs.filter((d) => d.rs_id === rs.id && d.seq === o.seq && ["open", "part"].includes(d.status)).reduce((a, d) => a + d.qty - d.received_qty, 0) });
    });
  }
  function rsCheck(rs) {
    if (rs.status === "cancelled") return;
    const busy = tags.some((t) => t.rs_id === rs.id && t.status === "open" && t.bal > 0 && ["op", "rework", "supplier"].includes(t.loc)) || dcs.some((d) => d.rs_id === rs.id && ["open", "part"].includes(d.status));
    rs.status = busy ? "open" : "closed"; rs.closed_at = busy ? null : rs.closed_at || iso(nowMs());
  }
  const tagJson = (t) => { const rs = T(rsL, t.rs_id); return { tag: t, rs, progress: progress(rs), op: t.seq ? rs.ops[t.seq - 1] : null, parent: (T(tags, t.parent_tag) || {}).tag_no || null, entry: T(ents, t.entry_id) || null }; };

  function issue(p, at) {
    at = at || nowMs();
    const part = parts.find((x) => x.code === String(p.part_code || "").trim()); if (!part) err("Part " + (p.part_code || "") + " is not in Operations Master › Parts.");
    const qty = num(p.qty); if (qty <= 0) err("Enter the quantity to be produced.");
    const mc = String(p.material_code || part.material || ""), mat = materials.find((m) => m.code === mc); if (!mat) err("Choose the raw material (Operations Master › Raw material).");
    const heat = String(p.heat_code || "").trim(); if (!heat) err("Enter the heat / lot code of the material (from the mill test certificate).");
    const route = routes[part.code]; if (!route || !route.length) err("Part " + part.code + " has no operations. Add its routing in Operations Master › Cycle times.");
    const kgs = nz(p.rm_kg) != null ? num(p.rm_kg) : Math.round(part.weight_kg * 1.2 * qty * 1000) / 1000;
    const rs = { id: id(), rs_no: "RS-" + yymm(at) + "-" + String(next("RS-" + yymm(at))).padStart(4, "0"), part_code: part.code, part_name: part.name, customer_name: customers[part.customer], qty, status: "open", ops: JSON.parse(JSON.stringify(route)),
      rm_material: mc, rm_spec: mat.grade + " · " + mat.specification, rm_size: mat.size, heat_code: heat, rm_kg: kgs, mill_cert: nz(p.mill_cert), due_date: nz(p.due_date), notes: nz(p.notes), created_by: ME, created_at: iso(at), closed_at: null };
    rsL.unshift(rs); const t = newTag(rs, "RM", 1, "op", qty, null, null, 0, at); return { rs_id: rs.id, rs_no: rs.rs_no, tag_id: t.id };
  }
  function checkLines(ls, kind) {
    (ls || []).forEach((l) => {
      if (num(l.qty) <= 0) return; const rc = nz(String(l.code || "").trim()), rn = nz(String(l.reason || "").trim()) || (defect_codes.find((d) => d.code === rc) || {}).name;
      if (!rn) err("Choose the reason for every " + (kind === "rej" ? "rejection" : "rework") + " line.");
      if (!nz(String(l.spec || "").trim()) || !nz(String(l.actual || "").trim())) err("Enter the specification and the actual value for " + rn + " (" + (kind === "rej" ? "rejection" : "rework") + ").");
    });
  }
  function lines(entry, rs, src, kind, ls, seq, at, opName, mach, oper) {
    (ls || []).forEach((l) => {
      const q = num(l.qty); if (q <= 0) return;
      const rc = nz(String(l.code || "").trim()), rn = nz(String(l.reason || "").trim()) || (defect_codes.find((d) => d.code === rc) || {}).name;
      if (!rn) err("Choose the reason for every " + (kind === "rej" ? "rejection" : "rework") + " line.");
      const sp = nz(String(l.spec || "").trim()), ac = nz(String(l.actual || "").trim());
      if (!sp || !ac) err("Enter the specification and the actual value for " + rn + " (" + (kind === "rej" ? "rejection" : "rework") + ").");
      const tg = newTag(rs, kind === "rej" ? "REJ" : "REW", kind === "rej" ? null : seq, kind === "rej" ? "rejection" : "rework", q, src, entry, seq, at, { reason_code: rc, reason: rn, spec: sp, actual: ac });
      defs.push({ id: id(), entry_id: entry, rs_id: rs.id, tag_id: tg.id, kind, reason_code: rc, reason: rn, qty: q, spec: sp, actual: ac, part_code: rs.part_code, op_name: opName, machine: mach, operator: oper, entry_at: iso(at), void: false });
    });
  }
  const sumQ = (ls) => (ls || []).reduce((a, l) => a + num(l.qty), 0);
  const addEnt = (o) => { const e = Object.assign({ id: id(), ok_qty: 0, rej_qty: 0, rew_qty: 0, status: "ok", note: null, void_reason: null }, o); ents.push(e); return e; };
  const byNo = (no) => tags.find((t) => t.tag_no === String(no || "").trim().toUpperCase());
  const outs = (e) => ({ entry_id: e.id, tags: tags.filter((x) => x.entry_id === e.id).map(tagJson) });

  function entry(p, at) {
    at = at || (nz(p.entry_at) ? Date.parse(p.entry_at) : nowMs());
    const t = byNo(p.tag_no); if (!t) err("Tag " + (p.tag_no || "") + " was not found.");
    if (t.status !== "open" || t.bal <= 0) err("Tag " + t.tag_no + " has no quantity left.");
    if (!["RM", "OK"].includes(t.kind) || t.loc !== "op") err("Scan the RM or OK tag of the previous process — a " + t.kind + " tag cannot be processed here.");
    const rs = T(rsL, t.rs_id); if (rs.status === "cancelled") err("Route sheet " + rs.rs_no + " is cancelled.");
    const o = rs.ops[t.seq - 1], n = rs.ops.length; if (o.type === "supplier") err("“" + o.name + "” is a supplier process — issue a delivery challan (DC) instead.");
    const mach = nz(String(p.machine || "").trim()) || nz(o.machine); if (!mach) err("Enter the machine.");
    const oper = nz(String(p.operator || "").trim()); if (!oper) err("Enter the operator name.");
    const ok = Math.max(0, num(p.ok)), rej = sumQ(p.rej_lines), rew = sumQ(p.rew_lines);
    if (ok + rej + rew <= 0) err("Enter the OK, rejection or rework quantity.");
    if (ok + rej + rew > t.bal) err("Only " + t.bal + " pcs are left on tag " + t.tag_no + "."); checkLines(p.rej_lines, "rej"); checkLines(p.rew_lines, "rew");
    const e = addEnt({ rs_id: rs.id, tag_id: t.id, kind: "process", seq: t.seq, op_name: o.name, machine: mach, ok_qty: ok, rej_qty: rej, rew_qty: rew, entry_at: iso(at), shift: nz(p.shift), operator: oper, engineer: nz(p.engineer) || ME, note: nz(p.note) });
    t.bal -= ok + rej + rew; if (t.bal <= 0) t.status = "used";
    const ns = t.seq + 1; if (ok > 0) newTag(rs, "OK", ns > n ? null : ns, ns > n ? "fg" : "op", ok, t.id, e.id, t.seq, at);
    lines(e.id, rs, t.id, "rej", p.rej_lines, t.seq, at, o.name, mach, oper); lines(e.id, rs, t.id, "rew", p.rew_lines, t.seq, at, o.name, mach, oper);
    rsCheck(rs); return outs(e);
  }
  function rework(p, at) {
    at = at || (nz(p.entry_at) ? Date.parse(p.entry_at) : nowMs());
    const t = byNo(p.tag_no); if (!t) err("Tag " + (p.tag_no || "") + " was not found.");
    if (t.kind !== "REW" || t.status !== "open" || t.bal <= 0) err("Tag " + t.tag_no + " is not an open rework tag.");
    const rs = T(rsL, t.rs_id), o = rs.ops[t.seq - 1], n = rs.ops.length, mach = nz(String(p.machine || "").trim()) || nz(o.machine) || "Rework bench", oper = nz(String(p.operator || "").trim());
    if (!oper) err("Enter the operator name.");
    const ok = Math.max(0, num(p.ok)), rej = sumQ(p.rej_lines); if (ok + rej <= 0) err("Enter the OK or rejected quantity after rework.");
    if (ok + rej > t.bal) err("Only " + t.bal + " pcs are left on tag " + t.tag_no + "."); checkLines(p.rej_lines, "rej");
    const e = addEnt({ rs_id: rs.id, tag_id: t.id, kind: "rework", seq: t.seq, op_name: o.name, machine: mach, ok_qty: ok, rej_qty: rej, entry_at: iso(at), shift: nz(p.shift), operator: oper, engineer: nz(p.engineer) || ME, note: nz(p.note) });
    t.bal -= ok + rej; if (t.bal <= 0) t.status = "used";
    const ns = t.seq + 1; if (ok > 0) newTag(rs, "OK", ns > n ? null : ns, ns > n ? "fg" : "op", ok, t.id, e.id, t.seq, at);
    lines(e.id, rs, t.id, "rej", p.rej_lines, t.seq, at, o.name, mach, oper); rsCheck(rs); return outs(e);
  }
  function dc(p, at) {
    at = at || (nz(p.entry_at) ? Date.parse(p.entry_at) : nowMs());
    const t = byNo(p.tag_no); if (!t) err("Tag " + (p.tag_no || "") + " was not found.");
    if (t.status !== "open" || t.bal <= 0 || !["RM", "OK"].includes(t.kind) || t.loc !== "op") err("Tag " + t.tag_no + " cannot be sent to a supplier.");
    const rs = T(rsL, t.rs_id), o = rs.ops[t.seq - 1]; if (o.type !== "supplier") err("“" + o.name + "” is done in-house — enter it as a stage entry.");
    const q = num(p.qty); if (q <= 0 || q > t.bal) err("Enter a quantity up to " + t.bal + " pcs.");
    const sup = nz(String(p.supplier_code || "").trim()) || o.supplier; if (!sup) err("Choose the supplier for “" + o.name + "”.");
    const sn = (suppliers.find((s) => s.code === sup) || {}).name;
    const d = { id: id(), dc_no: "DC-" + yymm(at) + "-" + String(next("DC-" + yymm(at))).padStart(4, "0"), rs_id: rs.id, tag_id: t.id, seq: t.seq, op_name: o.name, supplier_code: sup, supplier_name: sn, qty: q, received_qty: 0, status: "open", vehicle: nz(p.vehicle), dispatch_at: iso(at), expected_date: nz(p.expected_date), note: nz(p.note), created_by: ME, created_at: iso(at) };
    dcs.push(d); addEnt({ rs_id: rs.id, tag_id: t.id, dc_id: d.id, kind: "dc", seq: t.seq, op_name: o.name, machine: sn || sup, entry_at: iso(at), shift: nz(p.shift), operator: nz(p.operator), engineer: nz(p.engineer) || ME, note: nz(p.note) });
    t.bal -= q; if (t.bal <= 0) t.status = "used"; rsCheck(rs); return { dc_id: d.id, dc_no: d.dc_no };
  }
  function grn(p, at) {
    at = at || (nz(p.entry_at) ? Date.parse(p.entry_at) : nowMs());
    const d = dcs.find((x) => x.dc_no === String(p.dc_no || "").trim().toUpperCase()); if (!d) err("DC " + (p.dc_no || "") + " was not found.");
    if (!["open", "part"].includes(d.status)) err("DC " + d.dc_no + " is already " + d.status + ".");
    const rs = T(rsL, d.rs_id), n = rs.ops.length, ok = Math.max(0, num(p.ok)), rej = sumQ(p.rej_lines);
    if (ok + rej <= 0) err("Enter the quantity received."); if (ok + rej > d.qty - d.received_qty) err("Only " + (d.qty - d.received_qty) + " pcs are pending on DC " + d.dc_no + "."); checkLines(p.rej_lines, "rej");
    const e = addEnt({ rs_id: rs.id, tag_id: d.tag_id, dc_id: d.id, kind: "grn", seq: d.seq, op_name: d.op_name, machine: d.supplier_name || d.supplier_code, ok_qty: ok, rej_qty: rej, entry_at: iso(at), shift: nz(p.shift), operator: nz(p.operator), engineer: nz(p.engineer) || ME, note: nz(p.note) });
    const g = { id: id(), grn_no: "GRN-" + yymm(at) + "-" + String(next("GRN-" + yymm(at))).padStart(4, "0"), dc_id: d.id, rs_id: rs.id, entry_id: e.id, ok_qty: ok, rej_qty: rej, inv_no: nz(p.inv_no), received_at: iso(at), note: nz(p.note), created_by: ME, created_at: iso(at) };
    grns.push(g); d.received_qty += ok + rej; d.status = d.received_qty >= d.qty ? "closed" : "part";
    const ns = d.seq + 1; if (ok > 0) newTag(rs, "OK", ns > n ? null : ns, ns > n ? "fg" : "op", ok, d.tag_id, e.id, d.seq, at);
    lines(e.id, rs, d.tag_id, "rej", p.rej_lines, d.seq, at, d.op_name, d.supplier_name || d.supplier_code, d.supplier_name || d.supplier_code); rsCheck(rs);
    return Object.assign({ grn_id: g.id, grn_no: g.grn_no }, outs(e));
  }
  function dispatch(p) {
    const t = byNo(p.tag_no); if (!t || t.loc !== "fg" || t.status !== "open") err("Tag " + (p.tag_no || "") + " is not in finished goods.");
    const q = num(p.qty); if (q <= 0 || q > t.bal) err("Enter a quantity up to " + t.bal + " pcs.");
    addEnt({ rs_id: t.rs_id, tag_id: t.id, kind: "dispatch", ok_qty: q, entry_at: iso(nowMs()), shift: nz(p.shift), operator: nz(p.operator), engineer: nz(p.engineer) || ME, note: nz(p.ref) });
    t.bal -= q; if (t.bal <= 0) { t.status = "used"; t.loc = "dispatched"; } return null;
  }
  function dispose(a) {
    if (!["Scrapped", "Returned to supplier", "Accepted under concession", "Sorted / regraded"].includes(a.p_action)) err("Choose the disposition.");
    const t = byNo(a.p_tag); if (!t || t.kind !== "REJ") err("Tag " + (a.p_tag || "") + " is not a rejection tag.");
    if (t.dispo) err("Tag " + t.tag_no + " already has a disposition (" + t.dispo + ").");
    if (a.p_action === "Accepted under concession" && !String(a.p_note || "").trim()) err("A concession needs the customer / authority reference in the note.");
    Object.assign(t, { dispo: a.p_action, dispo_by: ME, dispo_at: iso(nowMs()), dispo_note: nz(String(a.p_note || "").trim()), status: "used", bal: 0, loc: "closed" }); return null;
  }
  function voidEntry(a) {
    if (!String(a.p_reason || "").trim()) err("Give the reason for voiding the entry.");
    const e = T(ents, a.p_entry); if (!e) err("Entry not found."); if (e.status === "void") err("This entry is already void."); if (e.kind === "dispatch") err("A dispatch cannot be voided here.");
    tags.filter((x) => x.entry_id === e.id).forEach((x) => { if (x.status !== "open" || x.bal !== x.qty) err("Cannot void: pieces of tag " + x.tag_no + " have already moved on or been dispositioned."); });
    if (e.kind === "dc" && ents.some((g) => g.dc_id === e.dc_id && g.kind === "grn" && g.status === "ok")) err("Cannot void a DC that has receipts. Void the GRN first.");
    tags.filter((x) => x.entry_id === e.id).forEach((x) => { x.status = "void"; x.bal = 0; }); defs.filter((x) => x.entry_id === e.id).forEach((x) => (x.void = true));
    Object.assign(e, { status: "void", void_reason: String(a.p_reason).trim(), void_at: iso(nowMs()) }); const tot = e.ok_qty + e.rej_qty + e.rew_qty;
    if (["process", "rework"].includes(e.kind)) { const s = T(tags, e.tag_id); s.bal += tot; s.status = "open"; }
    else if (e.kind === "grn") { const d = T(dcs, e.dc_id); d.received_qty = Math.max(0, d.received_qty - tot); d.status = d.received_qty <= 0 ? "open" : "part"; grns.filter((g) => g.entry_id === e.id).forEach((g) => { g.ok_qty = 0; g.rej_qty = 0; }); }
    else if (e.kind === "dc") { const d = T(dcs, e.dc_id); d.status = "cancelled"; const s = T(tags, e.tag_id); s.bal += d.qty; s.status = "open"; }
    rsCheck(T(rsL, e.rs_id)); return null;
  }

  /* ---------- sample: five route sheets, in different states, over the last two weeks ---------- */
  function seed() {
    const K = 30; // the sample plant runs a month of work, so the dashboards look like a real shop
    const N = nowMs(), H = 36e5, ago = (d, h) => N - d * DAY - (h || 0) * H, ln = (code, q, sp, ac) => [{ code, qty: q, spec: sp, actual: ac }];
    const mk = (part, qty, d, due, heat) => { const r = issue({ part_code: part, qty, heat_code: heat, mill_cert: "MTC-" + heat, due_date: isoD(N + due * DAY) }, ago(d)); return tags.find((t) => t.id === r.tag_id); };
    // 1 Drive Flange — through turning, drilling; waiting at heat treatment (supplier) → a DC is out
    let t = mk("DP-1101", 400 * K, 12, 4, "H-23871");
    let r = entry({ tag_no: t.tag_no, machine: "CNC-T01", operator: "Murugan", shift: "A", ok: 392 * K, rej_lines: ln("DF01", 5 * K, "Ø42.5 ±0.02", "Ø42.56"), rew_lines: ln("DF04", 3 * K, "No burr", "Burr on bore") }, ago(11, 2));
    r = entry({ tag_no: r.tags[0].tag.tag_no, machine: "CNC-T02", operator: "Selvam", shift: "B", ok: 390 * K, rej_lines: ln("DF03", 2 * K, "Ra 1.6", "Ra 2.8") }, ago(10, 1));
    r = entry({ tag_no: r.tags[0].tag.tag_no, operator: "Kavitha", shift: "A", ok: 388 * K, rej_lines: ln("DF02", 2 * K, "Ø8.0 +0.05", "Ø7.93") }, ago(9, 3));
    const d1 = dc({ tag_no: r.tags[0].tag.tag_no, qty: 388 * K, vehicle: "TN 38 AB 4521", expected_date: isoD(N + 1 * DAY) }, ago(8)); const d1o = dcs.find((x) => x.dc_no === d1.dc_no);
    grn({ dc_no: d1.dc_no, ok: 200 * K, operator: "Stores", shift: "A", inv_no: "HT-2210" }, ago(2)); // part received → 200 waiting at grinding, 188 still out
    const rw = tags.find((x) => x.kind === "REW" && x.rs_id === T(rsL, d1o.rs_id).id); rework({ tag_no: rw.tag_no, operator: "Murugan", ok: 3 * K }, ago(10, 0));
    // 2 Wheel Hub — complete, FG partly dispatched
    t = mk("DP-1102", 120 * K, 9, -2, "H-23904"); r = entry({ tag_no: t.tag_no, operator: "Selvam", shift: "A", ok: 120 * K }, ago(8, 2));
    r = entry({ tag_no: r.tags[0].tag.tag_no, operator: "Selvam", shift: "A", ok: 118 * K, rej_lines: ln("DF05", 2 * K, "No tool marks", "Tool mark on face") }, ago(7, 1));
    r = entry({ tag_no: r.tags[0].tag.tag_no, operator: "Kavitha", shift: "B", ok: 118 * K }, ago(6, 4)); r = entry({ tag_no: r.tags[0].tag.tag_no, operator: "QA-Priya", shift: "B", ok: 118 * K }, ago(5, 2));
    dispatch({ tag_no: r.tags[0].tag.tag_no, qty: 60 * K, ref: "INV-8841" });
    // 3 Gear Housing — stuck at milling for days (the throughput alert)
    t = mk("DP-1103", 80 * K, 8, 2, "H-24012"); entry({ tag_no: t.tag_no, operator: "Murugan", shift: "A", ok: 80 * K }, ago(6, 0));
    // 4 Pinion Shaft — in progress at turning, partly done
    t = mk("DP-1104", 600 * K, 3, 9, "H-24101"); entry({ tag_no: t.tag_no, operator: "Selvam", shift: "B", ok: 250 * K, rej_lines: ln("DF01", 6 * K, "Ø24 ±0.02", "Ø24.07") }, ago(1, 5));
    // 5 Sleeve — just issued
    mk("DP-1105", 1000 * K, 0, 12, "H-24133");
    // losses
    [["CNC-T01", "D02", 35, 11], ["CNC-T02", "D01", 120, 10], ["VMC-M01", "D03", 45, 9], ["CNC-T01", "D04", 60, 8], ["GRN-G01", "D01", 90, 6], ["VMC-M01", "D02", 25, 4], ["CNC-T02", "D05", 30, 3], ["CNC-T01", "D06", 40, 2], ["VMC-M01", "D04", 55, 1]]
      .forEach((x) => loss.push({ id: id(), loss_date: isoD(N - x[3] * DAY), shift: "A", machine_code: x[0], d_code: x[1], d_name: loss_codes.find((l) => l.code === x[1]).name, minutes: x[2] * 6, status: "ok", operator: "Murugan", created_at: iso(N - x[3] * DAY) }));
  }
  seed();

  const tagRow = (t) => { const rs = T(rsL, t.rs_id), o = t.seq ? rs.ops[t.seq - 1] : null; return Object.assign({}, t, { rs_no: rs.rs_no, part_code: rs.part_code, part_name: rs.part_name, customer_name: rs.customer_name, due_date: rs.due_date, op_name: o && o.name, machine: o && o.machine, op_type: o && o.type, ops_n: rs.ops.length }); };
  const dcRow = (d) => { const rs = T(rsL, d.rs_id); return Object.assign({}, d, { rs_no: rs.rs_no, part_code: rs.part_code, part_name: rs.part_name, customer_name: rs.customer_name }); };
  const entRow = (e) => { const rs = T(rsL, e.rs_id); return Object.assign({}, e, { ct_sec: e.seq ? (rs.ops[e.seq - 1] || {}).ct_sec || 0 : 0, rs_no: rs.rs_no, part_code: rs.part_code, part_name: rs.part_name, out_tags: tags.filter((t) => t.entry_id === e.id).map((t) => t.tag_no).join(", ") }); };

  window.QP_DEMO = {
    kmr_mmd_load() { const rt = {}; parts.forEach((p) => (rt[p.code] = routes[p.code])); return { parts, materials, suppliers, machines, loss_codes, defect_codes, shifts, bom: [], routes: rt, has_rmp: false, plant: { hoursPerDay: 16, transferLagHours: 2, oee: 80, weeklyOff: "Sunday" }, today: isoD(nowMs()), now: iso(nowMs()) }; },
    kmr_mmd_data() {
      return { rs: rsL.map((s) => Object.assign({}, s, { ops_n: s.ops.length, ops: undefined,
          wip_qty: tags.filter((t) => t.rs_id === s.id && t.status === "open" && ["op", "rework"].includes(t.loc)).reduce((a, t) => a + t.bal, 0), supplier_qty: dcs.filter((d) => d.rs_id === s.id && ["open", "part"].includes(d.status)).reduce((a, d) => a + d.qty - d.received_qty, 0),
          fg_qty: tags.filter((t) => t.rs_id === s.id && ["fg", "dispatched"].includes(t.loc) && t.status !== "void").reduce((a, t) => a + t.qty, 0), rej_qty: defs.filter((q) => q.rs_id === s.id && q.kind === "rej" && !q.void).reduce((a, q) => a + q.qty, 0),
          rew_open: tags.filter((t) => t.rs_id === s.id && t.kind === "REW" && t.status === "open").reduce((a, t) => a + t.bal, 0) })),
        tags: tags.filter((t) => t.status !== "void").map(tagRow), dcs: dcs.map(dcRow), entries: ents.slice().sort((a, b) => b.entry_at.localeCompare(a.entry_at)).map(entRow), defects: defs.filter((d) => !d.void), loss: loss.filter((l) => l.status === "ok"), today: isoD(nowMs()), now: iso(nowMs()) };
    },
    kmr_mmd_stage_map() {
      return { today: iso(nowMs()).slice(0, 10), lots: rsL.map((s) => ({ id: s.id, rs_no: s.rs_no, part_code: s.part_code, part_name: s.part_name, customer_name: s.customer_name, heat_code: s.heat_code, rm_material: s.rm_material, qty: s.qty, status: s.status, due_date: s.due_date, created_at: s.created_at,
        ops: s.ops.map((o, i) => { const q = i + 1, ee = ents.filter((e) => e.rs_id === s.id && e.status === "ok" && e.kind === "process" && e.seq === q), sm = (f) => ee.reduce((a, e) => a + (+e[f] || 0), 0);
          return { seq: q, name: o.name, machine: o.machine, type: o.type, wait: tags.filter((t) => t.rs_id === s.id && t.status === "open" && ["RM", "OK"].includes(t.kind) && t.loc === "op" && t.seq === q).reduce((a, t) => a + t.bal, 0), supplier: dcs.filter((d) => d.rs_id === s.id && ["open", "part"].includes(d.status) && d.seq === q).reduce((a, d) => a + d.qty - d.received_qty, 0), ok: sm("ok_qty"), rej: sm("rej_qty"), rew: sm("rew_qty"), rew_open: tags.filter((t) => t.rs_id === s.id && t.status === "open" && t.kind === "REW" && t.seq === q).reduce((a, t) => a + t.bal, 0) }; }),
        fg: tags.filter((t) => t.rs_id === s.id && t.loc === "fg" && t.status !== "void").reduce((a, t) => a + t.qty, 0), dispatched: tags.filter((t) => t.rs_id === s.id && t.loc === "dispatched" && t.status !== "void").reduce((a, t) => a + t.qty, 0),
        rej_wait: tags.filter((t) => t.rs_id === s.id && t.kind === "REJ" && t.status === "open" && !t.dispo).reduce((a, t) => a + t.bal, 0), rej_total: defs.filter((q) => q.rs_id === s.id && q.kind === "rej" && !q.void).reduce((a, q) => a + q.qty, 0), rew_total: defs.filter((q) => q.rs_id === s.id && q.kind === "rew" && !q.void).reduce((a, q) => a + q.qty, 0) })) };
    },
    kmr_mmd_tag(a) { const t = byNo(a.p_no); if (!t) err("No tag with the number “" + (a.p_no || "") + "”."); return tagJson(t); },
    kmr_mmd_dc_get(a) { const d = dcs.find((x) => x.dc_no === String(a.p_no || "").trim().toUpperCase()); if (!d) err("No DC with the number “" + (a.p_no || "") + "”."); const rs = T(rsL, d.rs_id); return { dc: d, rs, progress: progress(rs), grns: grns.filter((g) => g.dc_id === d.id && g.ok_qty + g.rej_qty > 0) }; },
    kmr_mmd_issue(a) { const r = issue(a.p); return tagJson(T(tags, r.tag_id)); },
    kmr_mmd_feed_load() {
      const w = tags.filter((t) => t.status === "open" && t.loc === "op" && ["RM", "OK"].includes(t.kind) && t.bal > 0).map((t) => { const rs = T(rsL, t.rs_id), o = rs.ops[t.seq - 1] || {}; return { tag_no: t.tag_no, rs_no: rs.rs_no, part_code: rs.part_code, part_name: rs.part_name, seq: t.seq, bal: t.bal, op_name: o.name, machine: String(o.machine || "").toUpperCase(), op_type: o.type, kind: t.kind, created_at: t.created_at }; });
      const live = machines.slice(0, 4).map((m, i) => ({ machine: m.code, state: ["run", "run", "idle", "alarm"][i], last_at: iso(nowMs() - 60000), good: [120, 85, 0, 0][i], rej: [2, 0, 0, 0][i], upto: 1 }));
      return { can_edit: true, gateways: [{ id: "g1", name: "Demo gateway", location: "Shop floor", enabled: true, last_seen: iso(nowMs() - 30000), rows_total: 1840, push_key: "demo0000" }], map: [], live, waiting: w };
    },
    kmr_mmd_entry_feed(a) { return entry(a.p); }, kmr_mmd_gw_save() { return { ok: true }; }, kmr_mmd_map_save() { return { ok: true }; },
    kmr_mmd_issue_info() { return { rmp_bom: [], stock: { "RM-EN8-65": { on_hand: 4200, safety: 500 } }, heats: { "RM-EN8-65": [{ heat: "H-24012", cert: "MTC-7781", at: iso(nowMs()) }] } }; },
    kmr_mmd_tp_load() {
      return { can_edit: true, demand_month: "", demand: { "DP-1101": 40000, "DP-1102": 24000 },
        tools: [{ code: "T1", name: "CNMG 120408 turning insert", type: "Insert", rate: "180", supplier: "Demo Tools", std_life: 400, on_hand: 20, min_qty: 10, lead_days: 7 }, { code: "T2", name: "Ø8.5 carbide drill", type: "Drill", rate: "2400", supplier: "Demo Tools", std_life: 6000, on_hand: 2, min_qty: 2, lead_days: 14 }],
        plan: [{ id: "p1", part_code: "DP-1101", op_no: "10", tool_code: "T1", qty_per_set: 1 }, { id: "p2", part_code: "DP-1102", op_no: "30", tool_code: "T2", qty_per_set: 1 }],
        fits: [{ id: "f1", machine: "CNC-T01", tool_code: "T1", part_code: "DP-1101", op_no: "10", fitted_at: iso(nowMs() - 3 * DAY), fitted_by: "Murugan", removed_at: null, pcs: 360 }, { id: "f2", machine: "VMC-M01", tool_code: "T2", part_code: "DP-1102", op_no: "30", fitted_at: iso(nowMs() - 9 * DAY), removed_at: null, pcs: 2100 }, { id: "f3", machine: "CNC-T01", tool_code: "T1", fitted_at: iso(nowMs() - 20 * DAY), removed_at: iso(nowMs() - 12 * DAY), reason: "wear", minutes: 8, pcs: 380 }],
        cons: [{ code: "C1", name: "Soluble cutting oil", category: "Consumables", rate: "210", supplier: "Demo Oils", on_hand: 40, min_qty: 20, lead_days: 5, unit: "litre", used30: 55 }],
        cuse: [{ id: "u1", code: "C1", part_code: "", machine_code: "", per_1000: 1.5, per_month: 20 }], issues: [{ code: "C1", qty: 10, machine: "CNC-T01", operator: "Murugan", at: iso(nowMs() - DAY) }] };
    },
    kmr_mmd_catalog() { return []; }, kmr_mmd_tool_save() { return { ok: true }; }, kmr_mmd_toolplan_save() { return { ok: true }; }, kmr_mmd_tool_fit() { return { ok: true, pcs: 100 }; }, kmr_mmd_cons_save() { return { ok: true }; }, kmr_mmd_consuse_save() { return { ok: true }; }, kmr_mmd_cons_issue() { return { ok: true }; },
    kmr_mmd_trace_map(a) { return { matrix:[{lot:'RS-2611-0001',heat:'H-23871',cert:'MC-554',part:'1003 062 025',part_name:'DRIVE SHAFT',seq:1,process:'CNC TURNING',machine:'EPI-B-07',ok:900,rej:12,rew:3,operators:'Ravi',last:new Date().toISOString(),dc_nos:''}], defects:[{lot:'RS-2611-0001',heat:'H-23871',part:'1003 062 025',process:'CNC TURNING',machine:'EPI-B-07',reason:'Oversize',kind:'rej',qty:12,at:new Date().toISOString(),operator:'Ravi'}], erp:[{month:'2026-09',part:'1003 062 025',process:'VMC',machine:'EPI-B-1',qty:9000,hours:110,days:12,operators:'Ravi'}] }; },
    kmr_mmd_plan() { return {month:'2026-11-01',hours_per_day:21,days:26,oee:0.85,parts:[{part:'1003 062 025',name:'DRIVE SHAFT',demand:39000,per_day:1500,takt_sec:50.4,ops:9,ct_total:300,ct_max:100,bottleneck:'CNC TURNING 2ND SIDE',machine:'EPI-B-07',machines_needed:3,meets_takt:false},{part:'1003 062 362',name:'SHAFT',demand:4500,per_day:173,takt_sec:436.8,ops:10,ct_total:280,ct_max:100,bottleneck:'CNC TURNING',machine:'EPI-B-1',machines_needed:1,meets_takt:true}],lots:[{lot:'RS-2611-0001',part:'1003 062 025',qty:900,status:'closed',tt_days:4.2,proc_h:12.5}]}; },
    kmr_mmd_erp() { var t=new Date(),o=[],id=[];for(var i=1;i<=20;i++){var dt=new Date(t-i*864e5).toISOString().slice(0,10);o.push([dt,"EPI-B-07",300+i,0,(300+i)*100/3600,10.5,i%2?"RAVI":"SURESH"]);o.push([dt,"EPI-B-1",900,0,900*27/3600,11,"MAHESH"]);}id.push([new Date(t-864e5).toISOString().slice(0,10),"EPI-B-07","TOOL CHANGE",1.5]);return {rows:40,last:o[0][0],prod:o,idle:id,parts:[]}; },
    kmr_mmd_kpi() { return { machine_time: [{ machine: "CNC-T01", run: 120, idle: 30, alarm: 4 }, { machine: "VMC-M01", run: 95, idle: 50, alarm: 0 }], entries: { total: 40, machine: 12 }, tools: { changes: 6, breakages: 1, change_min: 74, life_pct: 92, by_machine: [{ machine: "CNC-T01", changes: 4, minutes: 50 }], on_machines: 2, due: 1, low_stock: 0, listed: 2 }, cons: { listed: 1, low_stock: 1 }, dc: { sent: 5, overdue: 1, closed: 3, on_time: 2 } }; },
    kmr_mmd_entry(a) { return entry(a.p); }, kmr_mmd_rework(a) { return rework(a.p); }, kmr_mmd_dc_create(a) { return dc(a.p); }, kmr_mmd_grn(a) { return grn(a.p); },
    kmr_mmd_dispatch(a) { return dispatch(a.p); }, kmr_mmd_dispose(a) { return dispose(a); }, kmr_mmd_void(a) { return voidEntry(a); },
    kmr_mmd_rs_cancel(a) {
      if (!String(a.p_reason || "").trim()) err("Give the reason for cancelling the route sheet."); const rs = T(rsL, a.p_rs);
      if (ents.some((e) => e.rs_id === rs.id && e.status === "ok")) err("Entries exist on this route sheet — void them first, or let it run to completion."); rs.status = "cancelled"; tags.filter((t) => t.rs_id === rs.id).forEach((t) => { t.status = "void"; t.bal = 0; }); return null;
    },
    kmr_mmd_loss_save(a) {
      const p = a.p, l = loss_codes.find((x) => x.code === p.d_code); if (!p.machine_code) err("Choose the machine."); if (!l) err("Choose a loss code (Operations Master › Loss codes).");
      const m = num(p.minutes); if (m <= 0 || m > 1440) err("Enter the loss in minutes (1–1440).");
      const r = { id: id(), loss_date: p.loss_date || isoD(nowMs()), shift: nz(p.shift), machine_code: p.machine_code, d_code: l.code, d_name: l.name, minutes: m, part_code: nz(p.part_code), op_name: nz(p.op_name), remark: nz(p.remark), operator: nz(p.operator), status: "ok", created_at: iso(nowMs()) }; loss.unshift(r); return r.id;
    },
    kmr_mmd_loss_void(a) { if (!String(a.p_reason || "").trim()) err("Give the reason for voiding the entry."); const l = T(loss, a.p_id); if (l) { l.status = "void"; l.void_reason = a.p_reason; } return null; },
    kmr_mmd_trace(a) {
      const q = String(a.p_q || "").trim().toUpperCase(); if (!q) err("Enter a heat code, route sheet, tag, DC or part number.");
      const ids = new Set(); rsL.forEach((s) => { if ([s.rs_no, s.heat_code, s.part_code, s.mill_cert || ""].some((v) => String(v).toUpperCase() === q)) ids.add(s.id); });
      tags.forEach((t) => { if (t.tag_no === q) ids.add(t.rs_id); }); dcs.forEach((d) => { if (d.dc_no === q) ids.add(d.rs_id); }); grns.forEach((g) => { if (g.grn_no === q) ids.add(g.rs_id); });
      if (!ids.size) err("Nothing found for “" + a.p_q + "”.");
      return { rs: rsL.filter((s) => ids.has(s.id)).map((s) => ({ rs: s, progress: progress(s), tags: tags.filter((t) => t.rs_id === s.id), entries: ents.filter((e) => e.rs_id === s.id), dcs: dcs.filter((d) => d.rs_id === s.id), grns: grns.filter((g) => g.rs_id === s.id) })) };
    }
  };
})();
