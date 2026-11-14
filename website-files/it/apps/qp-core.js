/* =====================================================================
   APQP Planner + PPAP Submissions — shared core
   • sign-in handoff, company brand, role, rpc (cloud) or the in-memory demo (?demo=1)
   • the links to the other KMR apps: what Process Documents, Balloon Inspector, Calibration Hub, Capacity Planner,
     Sales Flow and the Operations Master already hold for a part is READ from them (kmr_qp_links) and shown with a
     link that opens that exact screen — it is never typed again.
   ===================================================================== */
(function () {
  "use strict";
  const qs = new URLSearchParams(location.search), DEMO = qs.has("demo");
  let slug = (qs.get("co") || "").toLowerCase(), sb = null, ctx = null, canEdit = false;
  const $ = (s, r = document) => r.querySelector(s);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const iso = (n = 0) => new Date(Date.now() + n * 864e5).toISOString().slice(0, 10);
  const today = () => iso(0);
  const fmt = (d) => (d ? new Date(String(d).slice(0, 10) + "T00:00:00").toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "—");
  const say = (m, ok) => { const el = $("#msg"); if (!el) return; el.innerHTML = m ? `<div class="msg${ok ? " ok" : ""}">${esc(m)}</div>` : ""; if (m && ok) setTimeout(() => { const e = $("#msg"); if (e) e.innerHTML = ""; }, 3500); };

  /* ---------- config + sign-in (same one KMR login as every app) ---------- */
  const CFG = { URL: (window.COMPANY_CONFIG || {}).supabaseUrl || "https://dehlcusptkzfhqvpfyjh.supabase.co" };
  const isPub = (k) => /^sb_publishable_|^eyJ/.test(String(k || ""));
  async function findKey() {
    const cc = (window.COMPANY_CONFIG || {}).supabaseAnonKey; if (cc && isPub(cc)) return cc;
    const c = sessionStorage.getItem("kmr_pub_key"); if (c) return c;
    try { const r = await fetch("/it/console/api/public-config"); if (r.ok) { const j = await r.json(); if (j.key && isPub(j.key)) { if (j.url) CFG.URL = j.url; sessionStorage.setItem("kmr_pub_key", j.key); return j.key; } } } catch (e) { /* ignore */ }
    throw new Error("The platform key is not configured (company-config.js).");
  }
  async function rpc(fn, args) {
    if (DEMO) return Demo.rpc(fn, args || {});
    const { data, error } = await sb.rpc(fn, args || {}); if (error) throw new Error(error.message); return data;
  }
  const call = (fn, args) => rpc(fn, Object.assign({ p_slug: slug }, args || {}));

  /* ---------- company logo + name top-left, tab icon (same as every KMR app) ---------- */
  async function showBrand() {
    let b = { name: (ctx && ctx.company) || "", logo: null };
    try { const pp = JSON.parse(localStorage.getItem("kmr-portal") || "null"); if (pp && (DEMO || pp.slug === slug)) b.logo = pp.logo || null; } catch (e) { /* ignore */ }
    if (!DEMO && sb && slug) {
      try { const { data } = await sb.rpc("kmr_portal_brand", { p_slug: slug }); if (data && data[0]) { b.logo = data[0].logo_url || b.logo; b.name = data[0].name || b.name; } } catch (e) { /* ignore */ }
      try { const old = JSON.parse(localStorage.getItem("kmr-portal") || "null") || {}; localStorage.setItem("kmr-portal", JSON.stringify({ ...old, slug, name: b.name, logo: b.logo || null })); } catch (e) { /* ignore */ }
    }
    const el = $("#clogo"); if (!el) return;
    const safe = String(b.logo || "").replace(/["<>]/g, "");
    el.innerHTML = safe ? `<img src="${safe}" alt="">` : String(b.name || "K").split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase().replace(/[<>&]/g, "");
    el.hidden = false;
    if (safe) { document.querySelectorAll('link[rel~="icon"]').forEach((l) => l.remove()); const ic = document.createElement("link"); ic.rel = "icon"; ic.href = safe; document.head.append(ic); }
  }

  async function init(code, ctxFn) {
    if (!DEMO) {
      const { createClient } = await import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm");
      sb = createClient(CFG.URL, await findKey());
      const { data: { session } } = await sb.auth.getSession();
      if (!session) { if (window.KMR_SSO) KMR_SSO.toPortal(null, { signin: true }); else location.href = "/it/apps.html?open=" + code; return null; }
      if (!slug) { const r = (document.referrer.match(/\/it\/app\/([^/?#]+)/) || [])[1]; if (r) slug = decodeURIComponent(r).toLowerCase(); }
      if (!slug) throw new Error("Open this app from your company’s KMR Apps page.");
    }
    ctx = ctxFn ? await call(ctxFn, {}) : await call("kmr_qp_context", { p_code: code });
    if (!ctx) throw new Error("You do not have access to this app, or the subscription is not active.");
    canEdit = ["admin", "editor"].includes(ctx.role);
    $("#co").textContent = ctx.company; $("#role").textContent = ctx.role; showBrand();
    if (window.KMRLock && window.QP_LOCKS && !DEMO) await KMRLock.init(sb, slug, code, QP_LOCKS.map, QP_LOCKS.names);
    return ctx;
  }

  /* ---------- the other apps: addresses of the exact screens ---------- */
  const PATH = { pd: "/it/pd.html", balloon: "/it/balloon.html", calib: "/it/calibration.html", capacity: "/it/capacity.html", sales: "/it/sales.html", rmp: "/it/rmp.html", dcg: "/it/dcg.html", inv: "/it/inv.html", mmd: "/it/mmd.html", mnt: "/it/mnt.html", mom: "/it/mom.html", hrms: "/it/hrm.html", tsk: "/it/tasks.html", msa: "/it/msa.html", spc: "/it/spc.html", crm: "/it/crm.html", d8: "/it/d8.html", qms: "/it/qms.html", aud: "/it/aud.html", off: "/it/office.html", cad: "/it/cad.html", apqp: "/it/apqp.html", ppap: "/it/ppap.html", dwm: "/it/dwm.html", connect: "/it/connect.html" };
  function appHref(code, o) {
    o = o || {};
    if (code === "ops") return DEMO ? "/it/apps.html#" + (o.hash || "ops") : "/it/app/" + encodeURIComponent(slug) + "#" + (o.hash || "ops");
    const p = new URLSearchParams();
    if (DEMO) { p.set("demo", "1"); if (code === "pd") p.set("sample", "1"); } else { p.set("kmr", "1"); if (slug) p.set("co", slug); }
    if (o.project && !DEMO) p.set("project", o.project);
    return (PATH[code] || "/it/apps.html") + "?" + p.toString() + (o.hash ? "#" + o.hash : "");
  }

  /* what each deliverable / element reads from, as a state + text + link */
  const KIND = { ready: "ready", partial: "partial", missing: "missing", na: "na" };
  function sourceInfo(src, L, part) {
    if (window.KMRLock && window.QP_LOCKS && QP_LOCKS.evidence && !KMRLock.has(QP_LOCKS.evidence)) return null;   // evidence from other KMR apps is an optional feature
    L = L || {};
    const pd = L.pd, bi = L.balloon, cal = L.calib, rt = L.routing, sa = L.sales, pp = (L.ppap || [])[0];
    const pdl = (doc) => appHref("pd", { project: pd && pd.id, hash: "go=" + doc + (pd && pd.id ? "&prj=" + pd.id : "") });
    const r = (state, text, href, app) => ({ state, text, href: href || "", app: app || "" });
    const noPd = r(KIND.missing, "No Process Documents project for this part yet", appHref("pd"), "Process Documents");
    const pdCount = (key, label, doc, unit) => (!pd ? noPd : pd[key] ? r(KIND.ready, `${label}: ${pd[key]} ${unit}`, pdl(doc), "Process Documents") : r(KIND.missing, `${label} not generated yet`, pdl(doc), "Process Documents"));
    switch (src) {
      case "pd:pfd": return pdCount("pfd", "Process flow", "pfd", "steps");
      case "pd:pfmea": return !pd ? noPd : pd.pfmea ? r(KIND.ready, `PFMEA (${pd.pfmea_std === "aiag4" ? "FMEA 4th ed." : "AIAG-VDA"}): ${pd.pfmea} lines`, pdl("pfmea"), "Process Documents") : r(KIND.missing, "PFMEA not generated yet", pdl("pfmea"), "Process Documents");
      case "pd:cp": return pdCount("cp", "Control plan", "cp", "lines");
      case "pd:sop": return pdCount("sop", "Process instructions", "sop", "operations");
      case "pd:msa": return pdCount("msa", "MSA studies", "msa", "studies");
      case "pd:spc": return pdCount("spc", "Process capability studies", "spc", "studies");
      case "pd:sc": return pdCount("sc", "Special characteristics", "sc", "listed");
      case "pd:chars": return pdCount("chars", "Characteristics matrix", "chars", "characteristics");
      case "pd:gauges": return pdCount("gauges", "Gauges / checking aids", "gauges", "listed");
      case "bi:report": return bi ? (bi.items ? r(KIND.ready, `Ballooned drawing: ${bi.items} characteristics`, appHref("balloon", { hash: "go=report&prj=" + bi.id }), "Balloon Inspector") : r(KIND.partial, "Drawing opened but not ballooned yet", appHref("balloon", { hash: "go=report&prj=" + bi.id }), "Balloon Inspector")) : r(KIND.missing, "No ballooned drawing for this part yet", appHref("balloon"), "Balloon Inspector");
      case "bi:measured": return bi ? (bi.measured ? r(bi.measured >= bi.items ? KIND.ready : KIND.partial, `Measured results: ${bi.measured} of ${bi.items} characteristics`, appHref("balloon", { hash: "go=report&prj=" + bi.id }), "Balloon Inspector") : r(KIND.missing, "No measured results entered yet", appHref("balloon", { hash: "go=report&prj=" + bi.id }), "Balloon Inspector")) : r(KIND.missing, "No ballooned drawing for this part yet", appHref("balloon"), "Balloon Inspector");
      case "cal:gauges": return cal ? (cal.overdue ? r(KIND.partial, `${cal.overdue} instrument(s) overdue for calibration`, appHref("calib", { hash: "go=inst" }), "Calibration Hub") : r(KIND.ready, `All ${cal.instruments} instruments in calibration${cal.due30 ? " · " + cal.due30 + " due within 30 days" : ""}`, appHref("calib", { hash: "go=inst" }), "Calibration Hub")) : r(KIND.na, "Calibration Hub is not on your plan", "", "");
      case "cap:load": return rt && rt.operations ? r(KIND.ready, `Routing: ${rt.operations} operations on ${(rt.machines || []).length} machines`, appHref("capacity", { hash: "capacity" }), "Capacity Planner") : r(KIND.missing, "No routing (cycle times) in the Operations Master", appHref("ops", { hash: "ops/cycle_times" }), "Operations Master");
      case "ops:part": return L.ops && L.ops.found ? r(KIND.ready, "Part master in the Operations Master", appHref("ops", { hash: "ops/parts" }), "Operations Master") : r(KIND.missing, "Part not in the Operations Master", appHref("ops", { hash: "ops/parts" }), "Operations Master");
      case "sales:plan": return sa ? r(KIND.ready, `Planned demand ${Number(sa.demand).toLocaleString("en-IN")} per month (${String(sa.month).slice(0, 7)})`, appHref("sales", { hash: "go=plan" }), "Sales Flow") : r(KIND.na, "No plan for this part in Sales Flow", appHref("sales"), "Sales Flow");
      case "ppap": return pp ? r(pp.status === "approved" || pp.status === "interim" ? KIND.ready : KIND.partial, `PPAP Level ${pp.level}: ${pp.status}`, appHref("ppap", { hash: "go=package&prj=" + pp.id }), "PPAP Submissions") : r(KIND.missing, "No PPAP submission yet", appHref("ppap"), "PPAP Submissions");
      case "apqp": return L.apqp ? r(KIND.ready, "APQP programme exists", appHref("apqp", { hash: "go=phases&prj=" + L.apqp.id }), "APQP Planner") : r(KIND.missing, "No APQP programme for this part", appHref("apqp"), "APQP Planner");
      default: return null;
    }
  }
  const stateChip = (st) => ({ ready: '<span class="chip g">linked</span>', partial: '<span class="chip a">partly</span>', missing: '<span class="chip x">not yet</span>', na: '<span class="chip x">n/a</span>' }[st] || "");

  /* ---------- the sample (demo) data: same calls as the database functions ---------- */
  const Demo = (function () {
    const TPL = () => window.QP_TEMPLATE || [];
    const id = () => "d" + Math.random().toString(36).slice(2, 10);
    const parts = [
      { code: "DP-1101", name: "Drive Flange", customer: "CUS-001", drawing_no: "DRG-1101-A", revision: "C", annual_volume: 99600, status: "Production" },
      { code: "DP-1102", name: "Wheel Hub", customer: "CUS-001", drawing_no: "DRG-1102-A", revision: "B", annual_volume: 67200, status: "Production" },
      { code: "DP-1103", name: "Gear Housing", customer: "CUS-002", drawing_no: "DRG-1103-A", revision: "A", annual_volume: 42000, status: "Development" }];
    const customers = [{ code: "CUS-001", name: "Deccan Motors Ltd" }, { code: "CUS-002", name: "Southern Auto Components" }];
    const cft = [{ code: "CFT-001", name: "R. Venkatesh", role: "CFT leader", function: "Management" }, { code: "CFT-002", name: "S. Priya", role: "CFT member", function: "Quality" },
      { code: "CFT-003", name: "K. Arun", role: "CFT member", function: "Production" }, { code: "CFT-004", name: "M. Divya", role: "CFT member", function: "Engineering" }];
    const projects = [], ppaps = [];
    function seed(partCode, level) {
      const p = parts.find((x) => x.code === partCode), c = customers.find((x) => x.code === p.customer);
      const pr = { id: id(), part_code: p.code, part_name: p.name, customer_code: p.customer, customer_name: c.name, drawing_no: p.drawing_no, drawing_rev: p.revision, program: "New part launch — " + p.name,
        sop_date: iso(60 + level * 15), annual_volume: p.annual_volume, team: cft.map((x) => ({ name: x.name, role: x.role, function: x.function })), gates: {}, status: "active", notes: "", sample: true, updated_at: new Date().toISOString() };
      pr.items = TPL().map((t, i) => ({ id: id(), project_id: pr.id, phase: t.phase, seq: t.seq, code: t.code, title: t.title, source: t.source || null,
        status: t.phase < level ? "done" : t.phase === level ? (t.seq % 3 === 0 ? "progress" : t.seq % 2 === 0 ? "done" : "open") : "open",
        owner: cft[(t.seq + i) % cft.length].name, due: iso((t.phase - level) * 21 + t.seq * 2 - 12), done_at: null, notes: "", evidence: "" }));
      for (let ph = 1; ph < level; ph++) pr.gates[ph] = { ok: true, by: "R. Venkatesh", at: iso(-30 + ph * 5) };
      projects.push(pr); return pr;
    }
    seed("DP-1101", 4); seed("DP-1102", 3);
    function mkEls(ready) { const e = {}; for (let i = 1; i <= 18; i++) e["e" + i] = { status: ready.includes(i) ? "ready" : "open", note: "" }; return e; }
    ppaps.push({ id: id(), apqp_id: projects[0].id, part_code: "DP-1101", part_name: "Drive Flange", customer_code: "CUS-001", customer_name: "Deccan Motors Ltd", drawing_no: "DRG-1101-A", drawing_rev: "C", level: 3, reason: "Initial submission", status: "draft",
      submitted_on: null, decided_on: null, disposition_notes: "", psw: { part_number: "DP-1101", part_name: "Drive Flange", org_name: "Demo Engineering", weight_kg: "1.8", purchase_order: "PO-4401", cavities: "1" }, elements: mkEls([1, 5, 7, 8, 11, 16]), sample: true, updated_at: new Date().toISOString() });
    const LNK = (part) => {
      const L = { ops: { found: true, name: part }, routing: { operations: 3, machines: ["CNC-T01", "CNC-T04", "VMC-M01"] }, calib: { instruments: 12, overdue: 0, due30: 3, oot_open: 1 }, sales: { month: iso(0).slice(0, 8) + "01", demand: 500 }, capacity: { has: true },
        ppap: ppaps.filter((x) => x.part_code === part).map((x) => ({ id: x.id, level: x.level, status: x.status })), apqp: (projects.find((x) => x.part_code === part) || {}) .id ? { id: projects.find((x) => x.part_code === part).id } : null };
      if (part !== "DP-1103") {
        L.pd = { id: "demo-pd", status: "in_review", rev: "C", chars: 24, ops: 9, pfd: 9, pfmea: 77, pfmea_std: "vda", cp: 40, sop: 9, msa: 2, spc: part === "DP-1101" ? 4 : 0, sc: 5, gauges: 14, machines: 6 };
        L.balloon = { id: "demo-bi", title: part, rev: "C", status: "approved", items: 24, measured: part === "DP-1101" ? 24 : 10, special: 5 };
      }
      return L;
    };
    const get = (pid) => { const p = projects.find((x) => x.id === pid); if (!p) throw new Error("Programme not found."); return p; };
    return {
      async rpc(fn, a) {
        const J = (o) => JSON.parse(JSON.stringify(o));
        switch (fn) {
          case "kmr_qp_context": return { role: "admin", company: "Demo Engineering (sample data)" };
          case "kmr_qp_template": return TPL();
          case "kmr_qp_parts": return J({ parts: parts.map((p) => Object.assign({ name: p.name }, p)), customers, cft });
          case "kmr_apqp_list": return J(projects.map((p) => { const act = p.items.filter((i) => i.status !== "na"); const ph = {}; p.items.forEach((i) => { const o = ph[i.phase] || (ph[i.phase] = { total: 0, done: 0 }); if (i.status !== "na") o.total++; if (i.status === "done") o.done++; });
            return Object.assign({}, p, { items: undefined, total: act.length, done: act.filter((i) => i.status === "done").length, overdue: p.items.filter((i) => ["open", "progress"].includes(i.status) && i.due && i.due < today()).length, phases: ph }); }));
          case "kmr_apqp_get": { const p = get(a.p_id); return J({ project: Object.assign({}, p, { items: undefined }), items: p.items }); }
          case "kmr_apqp_create": { const x = a.p, pc = (x.part_code || "").trim(); if (!pc) throw new Error("Choose the part."); if (projects.some((p) => p.part_code === pc)) throw new Error("There is already an APQP programme for part " + pc + ".");
            const pr = { id: id(), part_code: pc, part_name: x.part_name, customer_code: x.customer_code, customer_name: x.customer_name, drawing_no: x.drawing_no, drawing_rev: x.drawing_rev, program: x.program, sop_date: x.sop_date || null, annual_volume: x.annual_volume || null, team: x.team || [], gates: {}, status: "active", notes: x.notes || "", updated_at: new Date().toISOString() };
            pr.items = TPL().map((t) => ({ id: id(), project_id: pr.id, phase: t.phase, seq: t.seq, code: t.code, title: t.title, source: t.source || null, status: "open", owner: null, due: null, done_at: null, notes: "", evidence: "" })); projects.push(pr); return pr.id; }
          case "kmr_apqp_save": { const p = get(a.p.id); Object.assign(p, a.p); p.updated_at = new Date().toISOString(); return null; }
          case "kmr_apqp_item": { const p = projects.find((x) => x.items.some((i) => i.id === a.p.id)), it = p.items.find((i) => i.id === a.p.id); Object.assign(it, a.p); if (a.p.status) it.done_at = it.status === "done" ? (it.done_at || today()) : null; return null; }
          case "kmr_apqp_item_add": { const p = get(a.p.project_id), n = p.items.filter((i) => /^C/.test(i.code)).length + 1; const it = { id: id(), project_id: p.id, phase: +a.p.phase || 1, seq: 100 + n, code: "C" + n, title: a.p.title, source: null, status: "open", owner: a.p.owner || null, due: a.p.due || null, done_at: null, notes: "", evidence: "" }; p.items.push(it); return it.id; }
          case "kmr_apqp_item_delete": { projects.forEach((p) => { p.items = p.items.filter((i) => !(i.id === a.p_id && /^C/.test(i.code))); }); return null; }
          case "kmr_apqp_delete": { const i = projects.findIndex((p) => p.id === a.p_id); if (i >= 0) projects.splice(i, 1); return null; }
          case "kmr_ppap_list": return J(ppaps.map((s) => Object.assign({}, s, { psw: undefined, elements: undefined, ready: Object.values(s.elements).filter((e) => ["ready", "done", "na"].includes(e.status)).length })));
          case "kmr_ppap_get": { const s = ppaps.find((x) => x.id === a.p_id); if (!s) throw new Error("Submission not found."); return J(s); }
          case "kmr_ppap_save": { const x = a.p; let s = x.id && ppaps.find((e) => e.id === x.id);
            if (!s) { if (!x.part_code) throw new Error("Choose the part."); s = { id: id(), psw: {}, elements: mkEls([]), status: "draft", sample: false }; ppaps.push(s); }
            Object.assign(s, x, { id: s.id, updated_at: new Date().toISOString() });
            if (["approved", "interim"].includes(s.status) && s.apqp_id) { const p = projects.find((q) => q.id === s.apqp_id), it = p && p.items.find((i) => i.code === "4.4"); if (it && it.status !== "done") { it.status = "done"; it.done_at = today(); } } return s.id; }
          case "kmr_ppap_delete": { const i = ppaps.findIndex((s) => s.id === a.p_id); if (i >= 0) ppaps.splice(i, 1); return null; }
          case "kmr_qp_links": return J(LNK(a.p_part));
          default: { const h = (window.QP_DEMO || {})[fn]; if (h) return J(await h(a)); throw new Error("Not available in the sample: " + fn); }
        }
      }
    };
  })();

  window.QP = { DEMO, qs, $, esc, iso, today, fmt, say, rpc, call, init, appHref, sourceInfo, stateChip, KIND,
    get slug() { return slug; }, get ctx() { return ctx; }, get canEdit() { return canEdit; }, get sb() { return sb; } };
})();
