/* KMR Apps — Operations Master: one set of master data per customer, shared by every KMR tool.
   Access follows Administration › Users & access (Operations Master: admin / editor / viewer). */
(function () {
  "use strict";
  const T = (k, l, extra) => Object.assign({ k, l }, extra || {});
  const same = (a, b) => String(a || "").trim().toLowerCase() === String(b).toLowerCase();
  const KINDS = [
    { kind: "parts", label: "Parts", icon: "⚙", code: "Part number", name: "Part name", fields: [T("customer", "Customer"), T("drawing_no", "Drawing no."), T("revision", "Revision"), T("material", "Material"), T("weight_kg", "Weight (kg)", { type: "number" }), T("annual_volume", "Annual volume", { type: "number" }), T("status", "Status", { opts: ["Development", "PPAP", "Production", "Obsolete"] })] },
    { kind: "customers", label: "Customers", icon: "🏭", code: "Customer code", name: "Customer name", fields: [T("gstin", "GSTIN / tax ID"), T("city", "City"), T("country", "Country"), T("contact", "Contact person"), T("email", "Email"), T("phone", "Phone"), T("payment_terms", "Payment terms"), T("supplier_code", "Our supplier code (given by this customer)"), T("address", "Address"), T("cc_symbol", "Their CC symbol"), T("sc_symbol", "Their SC symbol"), T("approval", "Customer engineering approval")] },
    { kind: "suppliers", label: "Suppliers", icon: "🚚", code: "Supplier code", name: "Supplier name", fields: [T("category", "Category", { opts: ["Raw material", "Outsourced process", "Consumables", "Tooling", "Gauges & calibration", "Services"] }), T("gstin", "GSTIN / tax ID"), T("city", "City"), T("contact", "Contact person"), T("email", "Email"), T("phone", "Phone"), T("approved", "Approved supplier", { opts: ["Yes", "Conditional", "No"] }), T("rating", "Rating (%)", { type: "number" })] },
    { kind: "machines", label: "Machines", icon: "🛠", code: "Machine code", name: "Machine name", fields: [T("type", "Type", { opts: ["CNC Turning", "VMC", "HMC", "Grinding", "Gear Hobbing", "Broaching", "Press", "Welding", "Assembly", "Inspection", "Other"] }), T("make", "Make"), T("model", "Model"), T("cell", "Cell / line"), T("available_days", "Available days / month (blank = plant standard)", { type: "number" }), T("hours_per_day", "Hours per day (blank = plant standard)", { type: "number" }), T("status", "Status", { opts: ["Running", "Breakdown", "Idle", "Scrapped"] }), T("capacity", "Capacity (e.g. swing Ø 350, L 300)"), T("processes", "Processes it can do (Process Documents codes, e.g. TURN1, TURN2, VMC)"), T("max_size_mm", "Max job size (mm)", { type: "number" }), T("capability_mm", "Capability ± mm", { type: "number" }), T("pm_frequency", "PM frequency", { opts: ["Weekly", "Monthly", "Quarterly", "Half-yearly", "Yearly"] }), T("remarks", "Remarks")] },
    { kind: "gauges", label: "Gauges", icon: "📏", code: "Gauge ID", name: "Gauge name", fields: [T("type", "Type", { opts: ["Vernier", "Micrometer", "Bore gauge", "Plug gauge", "Ring gauge", "Height gauge", "CMM", "Dial", "Other"] }), T("make", "Make"), T("model", "Model"), T("serial_no", "Serial no."), T("range", "Range"), T("least_count", "Least count"), T("tolerance", "Tolerance"), T("department", "Department"), T("criticality", "Criticality", { opts: ["Critical", "Major", "Minor"] }), T("cal_source", "Calibrated", { opts: ["Internal", "External"] }), T("lab", "Calibration lab"), T("custodian", "Custodian"), T("cal_freq_months", "Calibration every (months) — pick or type", { type: "number", list: ["1", "3", "6", "9", "12", "18", "24", "36"] }), T("last_calibrated", "Last calibrated", { type: "date" }), T("next_due", "Next due (auto from frequency)", { type: "date" }), T("location", "Location", { from: "machines", extra: ["Gauge room"] }), T("gauge_room_no", "Gauge room location number", { showIf: { k: "location", v: "Gauge room" } })] },
    { kind: "tools", label: "Tools", icon: "🔩", code: "Tool code", name: "Tool name", fields: [T("type", "Type", { opts: ["Insert", "Drill", "Tap", "Reamer", "End mill", "Boring bar", "Fixture", "Die", "Other"] }), T("size", "Size / grade"), T("make", "Make"), T("tool_life", "Tool life (pcs)", { type: "number" }), T("cost", "Cost", { type: "number" }), T("stock", "In stock", { type: "number" })] },
    { kind: "consumables", label: "Consumables", icon: "🧴", code: "Item code", name: "Item name", fields: [T("processes", "Used in processes (Process Documents codes, e.g. TURN1, VMC, WASH)"), T("uom", "Unit"), T("min_stock", "Minimum stock", { type: "number" }), T("rate", "Rate", { type: "number" }), T("supplier", "Supplier")] },
    { kind: "raw_materials", label: "Raw material", icon: "🧱", code: "Material code", name: "Material name", fields: [T("grade", "Grade"), T("specification", "Specification"), T("form", "Form", { opts: ["Bar", "Forging", "Casting", "Sheet", "Tube", "Other"] }), T("size", "Size"), T("supplier", "Supplier"), T("rate_per_kg", "Rate per kg", { type: "number" })] },
    { kind: "rate_contracts", label: "Rate contracts", icon: "📄", code: "Contract no.", name: "Party", fields: [T("party_type", "Party type", { opts: ["Supplier", "Customer"] }), T("item", "Item / part"), T("rate", "Rate", { type: "number" }), T("currency", "Currency"), T("uom", "Unit"), T("valid_from", "Valid from", { type: "date" }), T("valid_to", "Valid to", { type: "date" }), T("terms", "Terms")] },
    { kind: "cycle_times", label: "Cycle times", icon: "⏱", code: "Part + operation", name: "Operation", fields: [T("part_no", "Part number"), T("machine", "Machine"), T("cycle_time_sec", "Cycle time (s)", { type: "number" }), T("alternates", "Alternate machines (comma-separated)"), T("setup_min", "Set-up (min)", { type: "number" }), T("parts_per_cycle", "Parts per cycle", { type: "number" })] },
    { kind: "cft", label: "CFT team & key contacts", icon: "👥", code: "Employee / contact ID", name: "Name", fields: [T("function", "Function", { opts: ["Quality", "Production", "Engineering", "Maintenance", "Purchase", "Stores", "Sales", "Management", "Customer contact", "Supplier contact"] }), T("cft_role", "Role", { opts: ["CFT leader", "CFT member", "Key contact", "Escalation"] }), T("email", "Email"), T("phone", "Phone"), T("organisation", "Organisation (for external contacts)")] },
    { kind: "plant_standards", label: "Plant standards", icon: "🏗", code: "Plant / unit code", name: "Plant name", single: true, fields: [T("oee", "OEE (%)", { type: "number" }), T("hoursPerDay", "Working hours per day", { type: "number" }), T("daysPerMonth", "Working days per month (when no holiday calendar)", { type: "number" }), T("weeklyOff", "Weekly off", { opts: ["Sunday", "Saturday & Sunday", "Friday", "None"] }), T("warnPct", "Warn when machine load is above (%)", { type: "number" }), T("transferLagHours", "Transfer time between operations (h)", { type: "number" }), T("lotSize", "Transfer lot size (pcs)", { type: "number" }), T("levelTargetPct", "Levelling target (%)", { type: "number" })] },
    { kind: "documents", label: "Documents & records", icon: "📚", code: "Document no.", name: "Title", fields: [T("doc_type", "Type", { opts: ["Quality manual", "Policy", "Procedure", "Work instruction", "Form / format", "Record", "Customer-specific requirement", "External standard"] }), T("iatf_clause", "IATF 16949 clause"), T("revision", "Revision"), T("effective_date", "Effective from", { type: "date" }), T("owner", "Owner"), T("review_due", "Review due", { type: "date" })], file: true },
  ];
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const cols = (K) => [["code", K.code], ["name", K.name], ...K.fields.map((f) => [f.k, f.l])];

  function csvParse(text) {
    const rows = []; let row = [], cur = "", q = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (q) { if (ch === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += ch; }
      else if (ch === '"') q = true;
      else if (ch === ",") { row.push(cur); cur = ""; }
      else if (ch === "\n" || ch === "\r") { if (ch === "\r" && text[i + 1] === "\n") i++; row.push(cur); cur = ""; if (row.some((c) => c !== "")) rows.push(row); row = []; }
      else cur += ch;
    }
    row.push(cur); if (row.some((c) => c !== "")) rows.push(row);
    return rows;
  }
  const csvCell = (v) => { v = String(v ?? ""); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };

  window.KMR_OPS = {
    KINDS,
    /** ctx: { sb, slug, main, dialog, $, role, customerId } */
    async overview(ctx, note) {
      const { data: counts, error } = await ctx.sb.rpc("kmr_ops_counts", { p_slug: ctx.slug });
      const nSample = (counts && counts._sample) || 0, admin = ctx.role === "admin", edit = ctx.role === "admin" || ctx.role === "editor";
      const sampleBar = error ? "" : admin
        ? `<div class="card" style="flex-direction:row;gap:14px;align-items:center;flex-wrap:wrap;margin-bottom:16px;border-style:dashed;--c:transparent">
            <div style="flex:1;min-width:240px"><b>Sample data</b><br><small style="color:var(--muted)">${nSample
              ? `${nSample} sample records are loaded, marked <span class="pill">Sample</span> in the lists. Flush removes only these. Records you have edited or imported over are yours and stay.`
              : "Try every list with one ready-made machining plant: 16 parts, 12 machines, 43 cycle times, plant standards, customers, suppliers, raw material, rate contracts, gauges, tools, consumables, CFT team and IATF 16949 documents. Nothing you already have is overwritten, and you can flush it all later."}</small></div>
            ${nSample ? `<button class="btn ghost" id="opsFlush" style="height:42px;color:#B00E28;align-self:center;margin:0">Flush sample data</button>` : `<button class="btn" id="opsLoad" style="height:42px;align-self:center;margin:0">Load sample data</button>`}
          </div>`
        : nSample ? `<p class="sub" style="margin-top:-12px">Includes ${nSample} sample records, marked <span class="pill">Sample</span>.</p>` : "";
      ctx.main.innerHTML = `<h1>Operations Master</h1><p class="sub">One set of master data for your company, used by every KMR app. ${ctx.role === "viewer" ? "You can view it." : "You can add, change and import."}</p>
        ${error ? `<p class="msg">${esc(error.message)}</p>` : ""}
        ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:12px">${note}</div>` : ""}
        ${sampleBar}
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px">
          <button class="btn ghost" id="opsXlsxExp" style="height:42px">Download all (Excel)</button>
          ${ctx.role === "admin" || ctx.role === "editor" ? `<label class="btn ghost" style="height:42px;cursor:pointer">Upload Excel workbook<input type="file" id="opsXlsxImp" accept=".xlsx" hidden></label>` : ""}
          <small style="color:var(--muted);align-self:center">One sheet per list. Fill it in Excel and upload it back — existing codes are updated, new ones added, nothing is deleted.</small>
        </div>
        <div class="cards">${KINDS.map((K) => {
          const all = (counts && counts[K.kind]) || 0, smp = (counts && counts["_sample_" + K.kind]) || 0, own = (counts && counts["_own_" + K.kind]) || 0;
          const b = (act, label, on, red) => `<button class="btn ghost" data-card="${act}" data-k="${K.kind}" style="height:32px;padding:0 10px;font-size:12.5px${red ? ";color:#B00E28" : ""}" ${on ? "" : "disabled"}>${label}</button>`;
          return `<div class="card" style="--c:#0EA5E9;cursor:pointer" data-kind="${K.kind}"><div style="font-size:26px;line-height:1">${K.icon}</div><h3>${esc(K.label)}</h3>
            <p><b style="font-size:22px;color:var(--ink)">${all}</b> records${smp ? ` · <span class="pill">${smp} sample</span>` : ""}${own ? ` · <span class="pill ok">${own} yours</span>` : ""}</p>
            ${admin || edit ? `<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:auto">
              ${admin ? b("sload", "Load sample", !smp) + b("sflush", "Flush sample", smp, true) : ""}
              <label class="btn ghost" data-card="dload" style="height:32px;padding:0 10px;font-size:12.5px;cursor:pointer">Load data<input type="file" accept=".json,application/json" data-dload="${K.kind}" hidden></label>
              ${admin ? b("dflush", "Flush data", own, true) : ""}
            </div>` : ""}</div>`;
        }).join("")}
        ${counts && counts._has_balloon !== undefined ? (() => {
          const nd = counts._drawings || 0, no = counts._own_drawings || 0, B = counts._has_balloon;
          const bb = (act, label, on, red) => `<button class="btn ghost" data-drawing="${act}" style="height:32px;padding:0 10px;font-size:12.5px${red ? ";color:#B00E28" : ""}" ${on ? "" : "disabled"}>${label}</button>`;
          return `<div class="card" style="--c:#8B5CF6"><div style="font-size:26px;line-height:1">🎯</div><h3>Balloon Inspector drawings</h3>
          <p>${B ? `<b style="font-size:22px;color:var(--ink)">${nd + no}</b> report${nd + no === 1 ? "" : "s"}${nd ? ` · <span class="pill">${nd} sample</span>` : ""}${no ? ` · <span class="pill ok">${no} yours</span>` : ""}` : "Balloon Inspector is not in your company’s plan."}</p>
          ${B ? `<p style="font-size:12.5px;color:var(--muted)">Load sample adds a ready-made drawing (Mounting Plate EX-2040) that is ballooned automatically when you open it in Balloon Inspector › Reports.</p>` : ""}
          ${admin && B ? `<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:auto">
            ${bb("load", "Load sample", !nd)}${bb("flush", "Flush sample", nd, true)}
            <label class="btn ghost" style="height:32px;padding:0 10px;font-size:12.5px;cursor:pointer">Load data<input type="file" accept=".json,application/json" id="biLoad" hidden></label>
            ${bb("dflush", "Flush data", no, true)}
            <a class="btn ghost" href="/it/balloon.html" style="height:32px;padding:0 10px;font-size:12.5px;grid-column:1/-1">Open Balloon Inspector</a></div>` : ""}</div>`;
        })() : ""}
        </div>`;
      ctx.main.querySelectorAll("[data-kind]").forEach((el) => (el.onclick = (e) => { if (e.target.closest("[data-card],[data-dload],button,label,input")) return; this.list(ctx, el.dataset.kind); }));
      ctx.main.querySelectorAll("[data-card]").forEach((btn) => btn.addEventListener("click", (e) => e.stopPropagation()));
      ctx.main.querySelectorAll("button[data-card]").forEach((btn) => (btn.onclick = (e) => { e.stopPropagation(); this.cardAction(ctx, btn.dataset.card, btn.dataset.k, btn); }));
      ctx.main.querySelectorAll("[data-dload]").forEach((inp) => (inp.onchange = (e) => this.loadData(ctx, inp.dataset.dload, e.target.files[0], inp)));
      ctx.main.querySelectorAll("[data-drawing]").forEach((btn) => (btn.onclick = () => this.drawingAction(ctx, btn.dataset.drawing, btn)));
      const biLoad = ctx.main.querySelector("#biLoad");
      if (biLoad) biLoad.onchange = (e) => this.drawingLoad(ctx, e.target.files[0], biLoad);
      const run = async (btn, rpc, done) => {
        btn.disabled = true; btn.textContent = "Working…";
        const res = await ctx.sb.rpc(rpc, { p_slug: ctx.slug });
        if (res.error) { btn.disabled = false; alert(res.error.message); return this.overview(ctx); }
        this.overview(ctx, done(res.data));
      };
      const xExp = ctx.main.querySelector("#opsXlsxExp"), xImp = ctx.main.querySelector("#opsXlsxImp");
      if (xExp) xExp.onclick = () => this.exportWorkbook(ctx, xExp);
      if (xImp) xImp.onchange = (e) => this.importWorkbook(ctx, e.target.files[0], xImp);
      const load = ctx.main.querySelector("#opsLoad"), flush = ctx.main.querySelector("#opsFlush");
      if (load) load.onclick = () => run(load, "kmr_ops_sample_load", (d) =>
        `<b>Sample data loaded:</b> ${d.added} records added${d.skipped ? `, ${d.skipped} skipped because you already have them` : ""}. Every KMR app (Process Documents, Capacity Planner) uses these lists the next time it opens.`);
      if (flush) flush.onclick = () => {
        if (!confirm(`Remove the ${nSample} sample records from every list? Your own records are not touched.`)) return;
        run(flush, "kmr_ops_sample_flush", (n) => `<b>Sample data flushed:</b> ${n} records removed. Your own records are unchanged.`);
      };
      window.scrollTo(0, 0);
    },
    /** per-card: load / flush sample, flush your own data (a JSON of it is downloaded first) */
    async cardAction(ctx, act, kind, btn) {
      const K = KINDS.find((k) => k.kind === kind), L = K.label.toLowerCase();
      const label = btn.textContent;
      const busy = () => { btn.disabled = true; btn.textContent = "Working…"; };
      const fail = (m) => { btn.disabled = false; btn.textContent = label; alert(m); };
      if (act === "sload" || act === "sflush") {
        if (act === "sflush" && !confirm(`Remove the sample records from ${K.label}? Records you added or changed are kept.`)) return;
        busy();
        const res = await ctx.sb.rpc(act === "sload" ? "kmr_ops_sample_load" : "kmr_ops_sample_flush", { p_slug: ctx.slug, p_kind: kind });
        if (res.error) return fail(res.error.message);
        return this.overview(ctx, act === "sload" ? `<b>Sample ${esc(L)} loaded:</b> ${res.data.added} added${res.data.skipped ? `, ${res.data.skipped} skipped (codes you already have)` : ""}.` : `<b>Sample ${esc(L)} flushed:</b> ${res.data} removed.`);
      }
      if (act === "dflush") {
        if (!confirm(`Flush YOUR ${K.label} (the records you added, changed or imported)?\n\nA JSON backup of them is downloaded first; sample records are not touched.`)) return;
        busy();
        const { data, error } = await ctx.sb.rpc("kmr_ops_list", { p_slug: ctx.slug, p_kind: kind });
        if (error) return fail(error.message);
        const mine = (data || []).filter((r) => !r.sample).map((r) => ({ code: r.code, name: r.name, data: r.data, active: r.active }));
        const d = new Date(), z = (n) => String(n).padStart(2, "0");
        const file = `${ctx.slug}-${kind}-${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}.json`;
        const a = document.createElement("a");
        a.href = URL.createObjectURL(new Blob([JSON.stringify({ format: "kmr-ops-list", version: 1, kind, company: ctx.slug, exported_at: new Date().toISOString(), records: mine })], { type: "application/json" }));
        a.download = file; document.body.appendChild(a); a.click(); a.remove();
        const res = await ctx.sb.rpc("kmr_ops_flush_data", { p_slug: ctx.slug, p_kind: kind });
        if (res.error) return fail(`Backup downloaded (${file}), but the flush failed: ${res.error.message}`);
        return this.overview(ctx, `<b>Your ${esc(L)} flushed:</b> ${res.data} removed. Backup downloaded: <b>${esc(file)}</b> — use <b>Load data</b> on this card to bring them back.`);
      }
    },
    /** Balloon Inspector card: sample drawing load / flush, and flush of your own reports (JSON backup downloaded first) */
    async drawingAction(ctx, act, btn) {
      const label = btn.textContent;
      const fail = (m) => { btn.disabled = false; btn.textContent = label; alert(m); };
      if (act === "flush" && !confirm("Remove the sample drawing from Balloon Inspector? Your own reports are not touched.")) return;
      if (act === "dflush" && !confirm("Flush YOUR Balloon Inspector reports (every report except the sample drawing)?\n\nA JSON backup of them is downloaded first. Drawing files are kept, so Load data with that file brings the reports back complete.")) return;
      btn.disabled = true; btn.textContent = "Working…";
      if (act === "dflush") {
        const { data, error } = await ctx.sb.rpc("kmr_balloon_own_export", { p_slug: ctx.slug });
        if (error) return fail(`Backup failed, nothing was removed: ${error.message}`);
        const d = new Date(), z = (n) => String(n).padStart(2, "0");
        const file = `${ctx.slug}-balloon-reports-${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}.json`;
        const a = document.createElement("a");
        a.href = URL.createObjectURL(new Blob([JSON.stringify(data)], { type: "application/json" }));
        a.download = file; document.body.appendChild(a); a.click(); a.remove();
        const res = await ctx.sb.rpc("kmr_balloon_own_flush", { p_slug: ctx.slug });
        if (res.error) return fail(`Backup downloaded (${file}), but the flush failed: ${res.error.message}`);
        return this.overview(ctx, `<b>Your Balloon Inspector reports flushed:</b> ${res.data} removed. Backup downloaded: <b>${esc(file)}</b> — use <b>Load data</b> on the Balloon Inspector card to bring them back.`);
      }
      const res = await ctx.sb.rpc("kmr_ops_sample_drawing", { p_slug: ctx.slug, p_action: act });
      if (res.error) return fail(res.error.message);
      this.overview(ctx, act === "load" ? "<b>Sample drawing loaded.</b> Open Balloon Inspector › Reports › “Sample drawing — Mounting Plate”; it is ballooned automatically." : "<b>Sample drawing removed</b> from Balloon Inspector.");
    },
    async drawingLoad(ctx, file, input) {
      if (!file) return;
      try {
        let j; try { j = JSON.parse(await file.text()); } catch { throw new Error("That file is not valid JSON."); }
        if (!j || j.format !== "kmr-app-data" || j.app !== "balloon") throw new Error("This is not a Balloon Inspector data file. Use the file downloaded by Flush data (or a Data Master Balloon backup).");
        const { data, error } = await ctx.sb.rpc("kmr_balloon_own_load", { p_slug: ctx.slug, p_data: j });
        if (error) throw new Error(error.message);
        this.overview(ctx, `<b>Balloon Inspector reports loaded</b> from ${esc(file.name)}: ${data} reports.`);
      } catch (e) { alert(e.message || e); }
      if (input) input.value = "";
    },
    /** Load data: a JSON file from “Flush data” (or any list of {code, name, data}) — existing codes are updated, new ones added */
    async loadData(ctx, kind, file, input) {
      if (!file) return;
      const K = KINDS.find((k) => k.kind === kind);
      try {
        let j; try { j = JSON.parse(await file.text()); } catch { throw new Error("That file is not valid JSON."); }
        let recs = Array.isArray(j) ? j : j.records;
        if (j && j.format === "kmr-ops-list" && j.kind !== kind) throw new Error(`This file holds ${(KINDS.find((k) => k.kind === j.kind) || {}).label || j.kind}, not ${K.label}.`);
        if (j && j.format === "kmr-app-data" && j.tables && j.tables.ops_records) recs = j.tables.ops_records.filter((r) => r.kind === kind);
        if (!Array.isArray(recs) || !recs.length) throw new Error("No records found in the file for " + K.label + ".");
        const rows = recs.filter((r) => r && String(r.code || "").trim()).map((r) => ({ code: String(r.code).trim(), name: r.name || "", data: r.data || {}, active: r.active !== false }));
        for (let i = 0; i < rows.length; i += 200) {
          const res = await ctx.sb.rpc("kmr_ops_save", { p_slug: ctx.slug, p_kind: kind, p_rows: rows.slice(i, i + 200) });
          if (res.error) throw new Error(res.error.message);
        }
        this.overview(ctx, `<b>${esc(K.label)} loaded</b> from ${esc(file.name)}: ${rows.length} records (existing codes updated, new ones added).`);
      } catch (e) { alert(e.message || e); }
      if (input) input.value = "";
    },
    async excel() {
      if (window.ExcelJS) return window.ExcelJS;
      await new Promise((res, rej) => { const sc = document.createElement("script"); sc.src = "https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js"; sc.onload = res; sc.onerror = () => rej(new Error("Couldn't load the Excel engine — check the internet connection.")); document.head.appendChild(sc); });
      return window.ExcelJS;
    },
    /** All lists in one workbook: one sheet per list; row 1 = column names, row 2 (hidden) = field keys used when uploading. */
    async exportWorkbook(ctx, btn) {
      const label = btn.textContent; btn.disabled = true; btn.textContent = "Preparing…";
      try {
        const X = await this.excel(), wbk = new X.Workbook(); wbk.creator = "KMR Apps — Operations Master"; wbk.created = new Date();
        for (const K of KINDS) {
          const { data, error } = await ctx.sb.rpc("kmr_ops_list", { p_slug: ctx.slug, p_kind: K.kind });
          if (error) throw error;
          const cs = [...cols(K), ["active", "In use (Yes / No)"]];
          const ws = wbk.addWorksheet(K.label.replace(/[\\/?*[\]:]/g, " ").slice(0, 31), { views: [{ state: "frozen", ySplit: 2 }] });
          ws.addRow(cs.map((c) => c[1])); ws.addRow(cs.map((c) => c[0]));
          ws.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };
          ws.getRow(1).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0B1C3A" } };
          ws.getRow(2).hidden = true;
          (data || []).forEach((r) => ws.addRow(cs.map((c) => (c[0] === "code" ? r.code : c[0] === "name" ? r.name : c[0] === "active" ? (r.active === false ? "No" : "Yes") : (r.data || {})[c[0]] ?? ""))));
          ws.columns.forEach((col, i) => { col.width = Math.min(40, Math.max(12, String(cs[i][1]).length + 2)); });
        }
        const buf = await wbk.xlsx.writeBuffer();
        const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }));
        a.download = `Operations-Master-${ctx.slug}-${new Date().toISOString().slice(0, 10)}.xlsx`; document.body.appendChild(a); a.click(); a.remove();
      } catch (e) { alert(e.message || e); }
      btn.disabled = false; btn.textContent = label;
    },
    async importWorkbook(ctx, file, input) {
      if (!file) return;
      try {
        const X = await this.excel(), wbk = new X.Workbook(); await wbk.xlsx.load(await file.arrayBuffer());
        const done = [], problems = [];
        const text = (v) => { if (v == null) return ""; if (v instanceof Date) return v.toISOString().slice(0, 10); if (typeof v === "object") return String(v.text ?? v.result ?? (v.richText ? v.richText.map((t) => t.text).join("") : "")); return String(v); };
        for (const ws of wbk.worksheets) {
          const K = KINDS.find((k) => k.label.toLowerCase() === ws.name.trim().toLowerCase() || k.kind === ws.name.trim().toLowerCase());
          if (!K) { problems.push(`sheet “${ws.name}” is not a list name — skipped`); continue; }
          const cs = [...cols(K), ["active", "In use (Yes / No)"]];
          const r1 = (ws.getRow(1).values || []).slice(1).map((v) => text(v).trim().toLowerCase()), r2 = (ws.getRow(2).values || []).slice(1).map((v) => text(v).trim());
          const hasKeys = r2.includes("code");
          const idx = cs.map((c) => { let i = hasKeys ? r2.indexOf(c[0]) : -1; if (i < 0) i = r1.indexOf(c[1].toLowerCase()); if (i < 0) i = r1.indexOf(c[0]); return i; });
          if (idx[0] < 0) { problems.push(`${K.label}: no “${K.code}” column`); continue; }
          const rows = [];
          ws.eachRow((row, n) => {
            if (n === 1 || (hasKeys && n === 2)) return;
            const v = (row.values || []).slice(1).map(text);
            const code = (v[idx[0]] || "").trim(); if (!code) return;
            const rec = { code, name: idx[1] >= 0 ? (v[idx[1]] || "").trim() : "", data: {} };
            cs.slice(2).forEach((c, j) => { const i = idx[j + 2]; if (i < 0) return; const val = (v[i] || "").trim(); if (c[0] === "active") { if (val) rec.active = !/^(no|n|false|0)$/i.test(val); } else if (val !== "") rec.data[c[0]] = val; });
            rows.push(rec);
          });
          if (!rows.length) continue;
          for (let i = 0; i < rows.length; i += 200) {
            const res = await ctx.sb.rpc("kmr_ops_save", { p_slug: ctx.slug, p_kind: K.kind, p_rows: rows.slice(i, i + 200) });
            if (res.error) throw new Error(`${K.label}: ${res.error.message}`);
          }
          done.push(`${K.label} ${rows.length}`);
        }
        this.overview(ctx, `<b>Workbook uploaded.</b> ${done.length ? done.join(" · ") + " records saved (existing codes updated, new ones added)." : "No rows found."}${problems.length ? `<br><small>${problems.map(esc).join("; ")}</small>` : ""}`);
      } catch (e) { alert(e.message || e); }
      if (input) input.value = "";
    },
    async list(ctx, kind, note) {
      const K = KINDS.find((x) => x.kind === kind); const edit = ctx.role === "admin" || ctx.role === "editor";
      ctx.main.innerHTML = `<p><button class="btn ghost" id="opsBack" style="height:36px">← Operations Master</button></p><h1>${K.icon} ${esc(K.label)}</h1><p class="msg">Loading…</p>`;
      ctx.main.querySelector("#opsBack").onclick = () => this.overview(ctx);
      const { data, error } = await ctx.sb.rpc("kmr_ops_list", { p_slug: ctx.slug, p_kind: kind });
      if (error) { ctx.main.querySelector(".msg").textContent = error.message; return; }
      const rows = data || [];
      const shown = [["code", K.code], ["name", K.name], ...K.fields.slice(0, 4).map((f) => [f.k, f.l])];
      ctx.main.innerHTML = `<p><button class="btn ghost" id="opsBack" style="height:36px">← Operations Master</button></p>
        <h1>${K.icon} ${esc(K.label)}</h1><p class="sub">${rows.length} records</p>
        ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:12px">${note}</div>` : ""}
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px">
          <input id="opsQ" placeholder="Search…" style="height:42px;border-radius:12px;border:1px solid #D3DBE6;padding:0 14px;min-width:240px;flex:1">
          ${edit ? `<button class="btn" id="opsAdd" style="height:42px">+ Add</button><label class="btn ghost" style="height:42px;cursor:pointer">Import CSV<input type="file" id="opsImp" accept=".csv,text/csv" hidden></label>` : ""}
          <button class="btn ghost" id="opsExp" style="height:42px">Export CSV</button>
          ${ctx.role === "admin" ? `<span style="flex:1"></span>${rows.some((r) => r.sample)
            ? `<button class="btn ghost" id="opsKFlush" style="height:42px;color:#B00E28">Flush sample ${esc(K.label.toLowerCase())} (${rows.filter((r) => r.sample).length})</button>`
            : `<button class="btn ghost" id="opsKLoad" style="height:42px">Load sample ${esc(K.label.toLowerCase())}</button>`}` : ""}
        </div>
        <div class="card" style="padding:0;overflow:auto"><table style="width:100%;border-collapse:collapse;font-size:14px">
          <thead><tr style="background:#F5F7FB;text-align:left">${shown.map((c) => `<th style="padding:10px 12px;white-space:nowrap">${esc(c[1])}</th>`).join("")}${K.file ? '<th style="padding:10px 12px">File</th>' : ""}<th></th></tr></thead>
          <tbody id="opsBody"></tbody></table></div>`;
      const body = ctx.main.querySelector("#opsBody");
      const val = (r, k) => (k === "code" ? r.code : k === "name" ? r.name : (r.data || {})[k]);
      const draw = (q) => {
        const f = rows.filter((r) => !q || JSON.stringify([r.code, r.name, r.data]).toLowerCase().includes(q.toLowerCase()));
        body.innerHTML = f.map((r) => `<tr style="border-top:1px solid var(--line)${r.active === false ? ";opacity:.5" : ""}">${shown.map((c) => `<td style="padding:9px 12px">${c[0] === "code" ? `<b>${esc(val(r, c[0]))}</b>${r.sample ? ' <span class="pill">Sample</span>' : ""}` : esc(val(r, c[0]) ?? "")}</td>`).join("")}
          ${K.file ? `<td style="padding:9px 12px">${r.data && r.data.file_path ? `<button class="btn ghost" data-file="${esc(r.data.file_path)}" style="height:32px">Open</button>` : '<small style="color:var(--muted)">—</small>'}</td>` : ""}
          <td style="padding:9px 12px;text-align:right"><button class="btn ghost" data-id="${r.id}" style="height:32px">${edit ? "Edit" : "View"}</button></td></tr>`).join("") || `<tr><td colspan="9" style="padding:18px;color:var(--muted)">${rows.length ? "No match." : "No records yet."}</td></tr>`;
        body.querySelectorAll("[data-id]").forEach((b) => (b.onclick = () => this.edit(ctx, K, rows.find((r) => r.id === b.dataset.id))));
        body.querySelectorAll("[data-file]").forEach((b) => (b.onclick = async () => { const s = await ctx.sb.storage.from("kmr-docs").createSignedUrl(b.dataset.file, 300); if (s.data) window.open(s.data.signedUrl, "_blank"); }));
      };
      draw("");
      ctx.main.querySelector("#opsQ").oninput = (e) => draw(e.target.value);
      ctx.main.querySelector("#opsBack").onclick = () => this.overview(ctx);
      const kLoad = ctx.main.querySelector("#opsKLoad"), kFlush = ctx.main.querySelector("#opsKFlush");
      const kRun = async (btn, rpc, done) => {
        btn.disabled = true; btn.textContent = "Working…";
        const res = await ctx.sb.rpc(rpc, { p_slug: ctx.slug, p_kind: K.kind });
        if (res.error) { btn.disabled = false; alert(res.error.message); return this.list(ctx, K.kind); }
        this.list(ctx, K.kind, done(res.data));
      };
      if (kLoad) kLoad.onclick = () => kRun(kLoad, "kmr_ops_sample_load", (d) => `<b>Sample ${esc(K.label.toLowerCase())} loaded:</b> ${d.added} added${d.skipped ? `, ${d.skipped} skipped because you already have those codes` : ""}. Only this list was changed — every KMR app now uses it.`);
      if (kFlush) kFlush.onclick = () => {
        if (!confirm(`Remove the sample records from ${K.label}? Records you added or changed are kept.`)) return;
        kRun(kFlush, "kmr_ops_sample_flush", (n) => `<b>Sample ${esc(K.label.toLowerCase())} flushed:</b> ${n} removed. Records you added or changed are kept. Every KMR app now uses the rest.`);
      };
      ctx.main.querySelector("#opsExp").onclick = () => {
        const cs = cols(K); const lines = [cs.map((c) => csvCell(c[1])).join(",")].concat(rows.map((r) => cs.map((c) => csvCell(val(r, c[0]))).join(",")));
        const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob(["\ufeff" + lines.join("\r\n")], { type: "text/csv" })); a.download = `${K.kind}.csv`; a.click();
      };
      if (edit) {
        ctx.main.querySelector("#opsAdd").onclick = () => this.edit(ctx, K, null);
        ctx.main.querySelector("#opsImp").onchange = async (e) => {
          const file = e.target.files[0]; if (!file) return;
          const grid = csvParse((await file.text()).replace(/^\ufeff/, "")); if (grid.length < 2) return alert("The file has no rows.");
          const cs = cols(K), head = grid[0].map((h) => h.trim().toLowerCase());
          const idx = cs.map((c) => { let i = head.indexOf(c[1].toLowerCase()); if (i < 0) i = head.indexOf(c[0]); return i; });
          if (idx[0] < 0) return alert(`The first row must contain the column "${K.code}". Tip: use Export CSV to get the right columns.`);
          const out = grid.slice(1).map((g) => { const r = { code: (g[idx[0]] || "").trim(), name: idx[1] >= 0 ? (g[idx[1]] || "").trim() : "", data: {} };
            cs.slice(2).forEach((c, j) => { const i = idx[j + 2]; if (i >= 0 && g[i] !== undefined && g[i] !== "") r.data[c[0]] = g[i].trim(); }); return r; }).filter((r) => r.code);
          const res = await ctx.sb.rpc("kmr_ops_save", { p_slug: ctx.slug, p_kind: K.kind, p_rows: out });
          if (res.error) return alert(res.error.message);
          this.list(ctx, K.kind, `<b>Imported ${res.data} records.</b> Existing codes were updated, new ones added.`);
        };
      }
      window.scrollTo(0, 0);
    },
    async edit(ctx, K, r) {
      for (const f of K.fields) if (f.from) { const res = await ctx.sb.rpc("kmr_ops_list", { p_slug: ctx.slug, p_kind: f.from }), L = Array.isArray(res.data) ? res.data : ((res.data && res.data.records) || []); f.opts = [...L.filter((x) => x.active !== false).map((x) => ({ v: x.code, l: `${x.code} · ${x.name}` })), ...(f.extra || [])]; }
      const edit = ctx.role === "admin" || ctx.role === "editor"; const isNew = !r; r = r || { code: "", name: "", data: {}, active: true };
      const input = (f, v) => f.from ? `<div class="in"><input id="of_${f.k}" list="dl_${f.k}" value="${esc(v ?? "")}" placeholder="Pick a machine, or type" ${edit ? "" : "readonly"}><datalist id="dl_${f.k}">${f.opts.map((o) => `<option value="${esc(o.v || o)}" label="${esc(o.l || o)}"></option>`).join("")}</datalist></div>`
        : f.opts ? `<select id="of_${f.k}" ${edit ? "" : "disabled"}><option value=""></option>${(v && !f.opts.some((o) => (o.v || o) === v) ? [...f.opts, v] : f.opts).map((o) => { const ov = typeof o === "string" ? o : o.v, ol = typeof o === "string" ? o : o.l; return `<option value="${esc(ov)}" ${ov === v ? "selected" : ""}>${esc(ol)}</option>`; }).join("")}</select>`
        : `<div class="in"><input id="of_${f.k}" type="${f.type || "text"}" ${f.list ? `list="dl_${f.k}"` : ""} value="${esc(v ?? "")}" ${edit ? "" : "readonly"}>${f.list ? `<datalist id="dl_${f.k}">${f.list.map((o) => `<option value="${o}"></option>`).join("")}</datalist>` : ""}</div>`;
      ctx.dialog(isNew ? `Add — ${K.label}` : `${esc(r.code)} · ${K.label}`, `
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:0 14px;max-height:62vh;overflow:auto;padding-right:4px">
          <label class="f">${esc(K.code)}${input({ k: "code" }, r.code)}</label><label class="f">${esc(K.name)}${input({ k: "name" }, r.name)}</label>
          ${K.fields.map((f) => `<label class="f" id="ofw_${f.k}" ${f.showIf && !same((r.data || {})[f.showIf.k], f.showIf.v) ? 'style="display:none"' : ""}>${esc(f.l)}${input(f, (r.data || {})[f.k])}</label>`).join("")}
          ${K.file ? `<label class="f" style="grid-column:1/-1">File (PDF, Word, Excel — up to 25 MB)${r.data && r.data.file_path ? `<small style="display:block;color:var(--muted);text-transform:none;letter-spacing:0">Current: ${esc(r.data.file_name || "attached")}</small>` : ""}${edit ? '<input type="file" id="of_file" style="margin-top:6px">' : ""}</label>` : ""}
          <label style="display:flex;gap:8px;align-items:center;grid-column:1/-1;margin:4px 0 10px"><input type="checkbox" id="of_active" ${r.active !== false ? "checked" : ""} ${edit ? "" : "disabled"}> In use (untick to keep the record but hide it from new work)</label>
        </div>${r.sample && edit ? '<p style="font-size:13px;color:var(--muted);margin:0 0 8px">This is a sample record. Once you save it, it becomes your own record and <b>Flush sample data</b> leaves it alone.</p>' : ""}<span class="msg" id="ofM"></span>`,
        edit ? `<button class="btn" id="ofSave">Save</button>${isNew ? "" : '<button class="btn ghost" id="ofDel" style="color:#B00E28">Delete</button>'}` : "");
      const dlg = document.querySelector(".veil .dlg"); if (dlg) dlg.style.maxWidth = "760px";   // two-column master forms need room
      if (!edit) return;
      const $ = (s) => document.querySelector(s);
      K.fields.filter((f) => f.showIf).forEach((f) => { const src = $("#of_" + f.showIf.k); if (src) src.oninput = src.onchange = () => { $("#ofw_" + f.k).style.display = same(src.value, f.showIf.v) ? "" : "none"; }; });
      if (K.kind === "gauges" && $("#of_next_due")) {   // next due = last calibrated + frequency (month-end safe), unless typed by hand
        const am = (d, n) => { const [y, m, dn] = d.split("-").map(Number), t = new Date(Date.UTC(y, m - 1 + n, 1)); t.setUTCDate(Math.min(dn, new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 0)).getUTCDate())); return t.toISOString().slice(0, 10); };
        const auto = () => { const l = $("#of_last_calibrated").value || new Date().toISOString().slice(0, 10), f = parseInt($("#of_cal_freq_months").value); if (l && f > 0 && !$("#of_next_due").dataset.man) $("#of_next_due").value = am(l, f); };
        $("#of_next_due").oninput = () => { $("#of_next_due").dataset.man = $("#of_next_due").value ? "1" : ""; };
        $("#of_last_calibrated").onchange = auto; $("#of_cal_freq_months").oninput = $("#of_cal_freq_months").onchange = auto;
      }
      $("#ofSave").onclick = async () => {
        const m = $("#ofM"); m.className = "msg"; m.textContent = "Saving…";
        const data = Object.assign({}, r.data || {}); K.fields.forEach((f) => { let v = $("#of_" + f.k).value.trim(); if (f.showIf && !same($("#of_" + f.showIf.k).value, f.showIf.v)) v = ""; if (v) data[f.k] = v; else delete data[f.k]; });
        const code = $("#of_code").value.trim(); if (!code) { m.textContent = `${K.code} is required.`; return; }
        const file = K.file && $("#of_file") && $("#of_file").files[0];
        if (file) {
          if (file.size > 25 * 1024 * 1024) { m.textContent = "The file must be under 25 MB."; return; }
          const path = `customers/${ctx.customerId}/documents/${code.replace(/[^A-Za-z0-9._-]+/g, "_")}-${Date.now()}.${(file.name.split(".").pop() || "bin").toLowerCase()}`;
          const up = await ctx.sb.storage.from("kmr-docs").upload(path, file, { contentType: file.type || "application/octet-stream" });
          if (up.error) { m.textContent = "Upload failed: " + up.error.message; return; }
          data.file_path = path; data.file_name = file.name;
        }
        const res = await ctx.sb.rpc("kmr_ops_save", { p_slug: ctx.slug, p_kind: K.kind, p_rows: [Object.assign(isNew ? {} : { id: r.id }, { code, name: $("#of_name").value.trim(), data, active: $("#of_active").checked })] });
        if (res.error) { m.textContent = /duplicate|unique/.test(res.error.message) ? `${K.code} "${code}" already exists.` : res.error.message; return; }
        document.querySelector(".veil")?.remove(); this.list(ctx, K.kind, `<b>Saved</b> ${esc(code)}.`);
      };
      if ($("#ofDel")) $("#ofDel").onclick = async () => {
        if (!confirm(`Delete ${r.code}? Tools that used it keep their own copy of past work.`)) return;
        const res = await ctx.sb.rpc("kmr_ops_delete", { p_slug: ctx.slug, p_kind: K.kind, p_id: r.id });
        if (res.error) { $("#ofM").textContent = res.error.message; return; }
        document.querySelector(".veil")?.remove(); this.list(ctx, K.kind, `<b>Deleted</b> ${esc(r.code)}.`);
      };
    },
  };
})();
