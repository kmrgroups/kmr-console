/* KMR Apps — Year-wise Backup & Restore (company administrators), opened from Grand Master (all apps) and Data Master (one app).
   Backup : App › Financial year (Apr–Mar) › files — a JSON file and an Excel workbook (Dashboard, Analysis, Raw data) for every app and year,
            zipped, plus ONE overall JSON of the whole company.
   Restore: upload the overall JSON (or one app-year JSON) → every record goes back into its app, add + update only — nothing is deleted.
   Needs migration 0127 (kmr_yb_plan, kmr_yb_export, kmr_yb_import). Excel and ZIP are built in the browser, so large companies do not hit server time limits. */
(function () {
  "use strict";
  const NAME = { ops: "Operations Master", hrm: "HRM Suite", hrms: "HRM & Payroll", balloon: "Balloon Inspector", pd: "Process Documents", capacity: "Capacity Planner",
    sales: "Sales Flow", calib: "Calibration Hub", dcg: "Delivery Challan & GRN", inv: "Sales Invoicing", pnl: "Profit & Loss", rmp: "Raw Material Planning", mmd: "Material Movement",
    mnt: "Maintenance", apqp: "APQP Planner", ppap: "PPAP Submissions", msa: "MSA Studies", spc: "SPC Charts", crm: "CRM & RFQ", d8: "8D Problem Solving",
    aud: "Internal Audit", tsk: "ActionTrack", mom: "Minutes Of Meetings", cad: "KMR CAD Draft", layout: "Factory & Office Layout", dwm: "Daily Work Management",
    off: "KMR Office Suite", connect: "KMR Connect" };
  const MONTHS = ["Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar"];
  const RAW_CAP = 100000;            // rows per Excel raw-data sheet; the JSON file always holds every record
  const BIG = /(_files|_versions|_recordings|_drawings|bi_reports|pd_projects)$/;   // tables with file / drawing content: small pages
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const nf = (n) => Number(n || 0).toLocaleString("en-IN");
  const z = (n) => String(n).padStart(2, "0");
  const stamp = () => { const d = new Date(); return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}`; };
  const fyLabel = (fy) => (fy === "Masters" ? "Masters (no year)" : `FY ${fy}`);
  const fyRange = (fy) => { const y = parseInt(fy, 10); return `Apr ${y} – Mar ${y + 1}`; };
  const folder = (s) => String(s).replace(/&/g, "and").replace(/[\\/:*?"<>|]+/g, "-").trim();
  const sortFy = (a, b) => (a === "Masters" ? 1 : b === "Masters" ? -1 : a < b ? 1 : -1);
  const strip = (k, v) => (k === "_fy" || k === "_d" ? undefined : v);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function saveBlob(blob, name) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  }
  const scripts = {};
  function loadScript(src) {
    return (scripts[src] = scripts[src] || new Promise((res, rej) => {
      const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = () => rej(new Error("Could not load " + src + " (check the internet connection)."));
      document.head.appendChild(s);
    }));
  }
  async function libs(needExcel) {
    if (!window.JSZip) await loadScript("https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js");
    if (needExcel && !window.ExcelJS) await loadScript("https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js");
  }

  /* ------------------------------------------------------------------ Excel (Dashboard · Analysis · Raw data) */
  const NUMCOL = /(amount|total|value|qty|quantity|price|rate|cost|taxable|gst|net|gross|hours|minutes|weight|score|days|salary|pay)/i;
  const IDCOL = /(^id$|_id$|^sl$|_no$|^no$|_ref$|hsn|pincode|phone|gstin|year)/i;
  const CATCOL = /(status|kind|purpose|stage|result|type|class|state|department|shift|priority|severity|party|customer|supplier|category|reason|mode|source)/i;
  const ISO = /^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2})?/;
  const monthIx = (d) => (Number(d.slice(5, 7)) + 8) % 12;      // Apr = 0 … Mar = 11

  function analyse(rows) {
    const out = { n: rows.length, months: Array(12).fill(0), money: Array(12).fill(0), first: null, last: null, nums: [], cats: [], moneyCol: null };
    const keys = new Set(); rows.slice(0, 300).forEach((r) => Object.keys(r).forEach((k) => keys.add(k)));
    const numKeys = [...keys].filter((k) => NUMCOL.test(k) && !IDCOL.test(k) && rows.slice(0, 300).some((r) => typeof r[k] === "number"));
    const catKeys = [...keys].filter((k) => CATCOL.test(k) && !IDCOL.test(k) && rows.slice(0, 300).some((r) => typeof r[k] === "string"));
    out.moneyCol = numKeys.find((k) => /(amount|total|value|cost|price)/i.test(k)) || null;
    const nsum = Object.fromEntries(numKeys.map((k) => [k, { s: 0, c: 0, max: -Infinity }]));
    const cc = Object.fromEntries(catKeys.map((k) => [k, new Map()]));
    for (const r of rows) {
      if (r._d) {
        out.months[monthIx(r._d)]++;
        if (!out.first || r._d < out.first) out.first = r._d;
        if (!out.last || r._d > out.last) out.last = r._d;
        if (out.moneyCol && typeof r[out.moneyCol] === "number") out.money[monthIx(r._d)] += r[out.moneyCol];
      }
      for (const k of numKeys) { const v = r[k]; if (typeof v === "number" && isFinite(v)) { const o = nsum[k]; o.s += v; o.c++; if (v > o.max) o.max = v; } }
      for (const k of catKeys) { const v = r[k]; if (typeof v === "string" && v) { const m = cc[k]; if (m.size < 60 || m.has(v)) m.set(v, (m.get(v) || 0) + 1); } }
    }
    out.nums = numKeys.slice(0, 6).map((k) => ({ k, sum: nsum[k].s, avg: nsum[k].c ? nsum[k].s / nsum[k].c : 0, max: nsum[k].max === -Infinity ? 0 : nsum[k].max, n: nsum[k].c }));
    out.cats = catKeys.filter((k) => cc[k].size > 0 && cc[k].size <= 40).slice(0, 3).map((k) => ({ k, top: [...cc[k].entries()].sort((a, b) => b[1] - a[1]).slice(0, 10) }));
    return out;
  }

  function barPng(title, labels, vals, color) {
    const W = 860, H = 300, c = document.createElement("canvas"); c.width = W; c.height = H;
    const g = c.getContext("2d"); g.fillStyle = "#fff"; g.fillRect(0, 0, W, H);
    g.fillStyle = "#0F172A"; g.font = "bold 16px Arial"; g.fillText(title, 16, 26);
    const max = Math.max(1, ...vals), L = 60, T = 44, B = 44, bw = (W - L - 20) / vals.length;
    g.strokeStyle = "#E5E7EB"; g.fillStyle = "#64748B"; g.font = "11px Arial"; g.textAlign = "right";
    for (let i = 0; i <= 4; i++) { const y = T + (H - T - B) * (1 - i / 4); g.beginPath(); g.moveTo(L, y); g.lineTo(W - 10, y); g.stroke(); g.fillText(nf(Math.round((max * i) / 4)), L - 6, y + 4); }
    g.textAlign = "center";
    vals.forEach((v, i) => {
      const h = (H - T - B) * (v / max), x = L + i * bw + bw * 0.15;
      g.fillStyle = color; g.fillRect(x, H - B - h, bw * 0.7, h);
      g.fillStyle = "#0F172A"; g.font = "11px Arial"; if (v > 0) g.fillText(nf(Math.round(v)), x + bw * 0.35, H - B - h - 5);
      g.fillStyle = "#64748B"; g.fillText(String(labels[i]).slice(0, 12), x + bw * 0.35, H - B + 16);
    });
    return c.toDataURL("image/png");
  }

  async function makeXlsx(meta, tables) {
    const wb = new ExcelJS.Workbook(); wb.creator = "KMR Group"; wb.created = new Date();
    const names = Object.keys(tables).filter((t) => tables[t].length);
    const an = Object.fromEntries(names.map((t) => [t, analyse(tables[t])]));
    const total = names.reduce((s, t) => s + an[t].n, 0), months = Array(12).fill(0);
    names.forEach((t) => an[t].months.forEach((v, i) => (months[i] += v)));
    const peak = months.indexOf(Math.max(...months)), yr = parseInt(meta.fy, 10);
    const HEAD = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0F172A" } }, TILE = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFF6FF" } };
    const bar = (ws, ref) => { try { ws.addConditionalFormatting({ ref, rules: [{ type: "dataBar", priority: 1, gradient: false, cfvo: [{ type: "min" }, { type: "max" }], color: { argb: "FF60A5FA" } }] }); } catch (e) { /* older reader: plain numbers */ } };

    /* Dashboard */
    const ds = wb.addWorksheet("Dashboard", { views: [{ showGridLines: false }] });
    ds.columns = [{ width: 34 }, { width: 14 }, { width: 12 }, { width: 3 }, { width: 22 }, { width: 22 }, { width: 22 }, { width: 22 }];
    ds.mergeCells("A1:H1"); ds.getCell("A1").value = `${meta.appName} — ${meta.fy === "Masters" ? "Masters (no year)" : "Financial year " + meta.fy}`;
    ds.getCell("A1").font = { bold: true, size: 18, color: { argb: "FFFFFFFF" } }; ds.getCell("A1").fill = HEAD; ds.getRow(1).height = 34; ds.getCell("A1").alignment = { vertical: "middle", indent: 1 };
    ds.mergeCells("A2:H2"); ds.getCell("A2").value = `${meta.company}  ·  ${meta.fy === "Masters" ? "settings, number counters and records without a date" : fyRange(meta.fy)}  ·  backup taken ${meta.when}`;
    ds.getCell("A2").font = { color: { argb: "FF475569" }, italic: true };
    const first = names.map((t) => an[t].first).filter(Boolean).sort()[0], last = names.map((t) => an[t].last).filter(Boolean).sort().slice(-1)[0];
    const tiles = [["Records", nf(total)], ["Tables", String(names.length)], ["Busiest month", months[peak] ? `${MONTHS[peak]} ${peak < 9 ? yr : yr + 1} (${nf(months[peak])})` : "—"], ["Dates covered", first ? `${first} → ${last}` : "—"]];
    tiles.forEach((t, i) => {
      const col = i < 2 ? 1 + i : 5 + (i - 2) * 1; const c1 = i === 0 ? "A" : i === 1 ? "B" : i === 2 ? "E" : "F";
      const lab = ds.getCell(`${c1}4`), val = ds.getCell(`${c1}5`);
      lab.value = t[0]; lab.font = { size: 10, color: { argb: "FF64748B" } }; lab.fill = TILE; val.value = t[1]; val.font = { bold: true, size: 15, color: { argb: "FF0F172A" } }; val.fill = TILE;
      val.alignment = { wrapText: true, vertical: "middle" }; void col;
    });
    ds.getRow(5).height = 32;
    ds.getCell("A7").value = "Records by table"; ds.getCell("A7").font = { bold: true, size: 13 };
    ["Table", "Records", "Share"].forEach((h, i) => { const c = ds.getCell(8, 1 + i); c.value = h; c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = HEAD; });
    const byRows = names.slice().sort((a, b) => an[b].n - an[a].n);
    byRows.forEach((t, i) => { const r = 9 + i; ds.getCell(r, 1).value = t.replace(/_/g, " "); ds.getCell(r, 2).value = an[t].n; ds.getCell(r, 2).numFmt = "#,##0"; ds.getCell(r, 3).value = total ? an[t].n / total : 0; ds.getCell(r, 3).numFmt = "0.0%"; });
    if (byRows.length) bar(ds, `B9:B${8 + byRows.length}`);
    if (meta.fy !== "Masters" && months.some((v) => v)) {
      const img = wb.addImage({ base64: barPng("Records by month (all tables)", MONTHS, months, "#2563EB"), extension: "png" });
      ds.addImage(img, { tl: { col: 4, row: 7 }, ext: { width: 640, height: 222 } });
      const mon = names.map((t) => an[t].money.some((v) => v) ? t : null).filter(Boolean)[0];
      if (mon) {
        const img2 = wb.addImage({ base64: barPng(`${mon.replace(/_/g, " ")} — ${an[mon].moneyCol} by month`, MONTHS, an[mon].money, "#059669"), extension: "png" });
        ds.addImage(img2, { tl: { col: 4, row: 19 }, ext: { width: 640, height: 222 } });
      }
    }
    const capped = names.filter((t) => an[t].n > RAW_CAP);
    if (capped.length) { const r = 10 + byRows.length; ds.mergeCells(`A${r}:C${r + 2}`); ds.getCell(`A${r}`).value = `Raw data sheets show the first ${nf(RAW_CAP)} records of: ${capped.join(", ")}. The JSON file holds every record.`; ds.getCell(`A${r}`).alignment = { wrapText: true, vertical: "top" }; ds.getCell(`A${r}`).font = { color: { argb: "FFB45309" } }; }

    /* Analysis */
    const as = wb.addWorksheet("Analysis", { views: [{ showGridLines: false, state: "frozen", ySplit: 1 }] });
    as.columns = [{ width: 30 }, ...MONTHS.map(() => ({ width: 9 })), { width: 11 }];
    ["Records by month"].concat(MONTHS, ["Total"]).forEach((h, i) => { const c = as.getCell(1, 1 + i); c.value = h; c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = HEAD; c.alignment = { horizontal: i ? "center" : "left" }; });
    let r = 2; const dated = byRows.filter((t) => an[t].months.some((v) => v));
    dated.forEach((t) => { as.getCell(r, 1).value = t.replace(/_/g, " "); an[t].months.forEach((v, i) => { as.getCell(r, 2 + i).value = v; as.getCell(r, 2 + i).numFmt = "#,##0"; }); as.getCell(r, 14).value = an[t].n; as.getCell(r, 14).font = { bold: true }; r++; });
    if (dated.length) bar(as, `B2:M${r - 1}`);
    r += 1;
    const money = names.filter((t) => an[t].money.some((v) => v));
    if (money.length) {
      ["Value by month (first amount column)"].concat(MONTHS, ["Total"]).forEach((h, i) => { const c = as.getCell(r, 1 + i); c.value = h; c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = HEAD; });
      r++; const r0 = r;
      money.forEach((t) => { as.getCell(r, 1).value = `${t.replace(/_/g, " ")} · ${an[t].moneyCol}`; an[t].money.forEach((v, i) => { as.getCell(r, 2 + i).value = Math.round(v * 100) / 100; as.getCell(r, 2 + i).numFmt = "#,##0"; }); as.getCell(r, 14).value = Math.round(an[t].money.reduce((s, v) => s + v, 0)); as.getCell(r, 14).numFmt = "#,##0"; as.getCell(r, 14).font = { bold: true }; r++; });
      bar(as, `B${r0}:M${r - 1}`); r += 1;
    }
    ["Table", "Column", "Total", "Average", "Highest", "Filled"].forEach((h, i) => { const c = as.getCell(r, 1 + i); c.value = h; c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = HEAD; }); r++;
    names.forEach((t) => an[t].nums.forEach((n) => { as.getCell(r, 1).value = t.replace(/_/g, " "); as.getCell(r, 2).value = n.k; [n.sum, n.avg, n.max, n.n].forEach((v, i) => { as.getCell(r, 3 + i).value = Math.round(v * 100) / 100; as.getCell(r, 3 + i).numFmt = "#,##0.00"; }); r++; }));
    r += 1;
    ["Table", "Column", "Value", "Records"].forEach((h, i) => { const c = as.getCell(r, 1 + i); c.value = h; c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = HEAD; }); r++;
    const cr0 = r;
    names.forEach((t) => an[t].cats.forEach((c) => c.top.forEach(([v, n]) => { as.getCell(r, 1).value = t.replace(/_/g, " "); as.getCell(r, 2).value = c.k; as.getCell(r, 3).value = v; as.getCell(r, 4).value = n; as.getCell(r, 4).numFmt = "#,##0"; r++; })));
    if (r > cr0) bar(as, `D${cr0}:D${r - 1}`);

    /* Raw data — every table */
    const used = new Set(["Dashboard", "Analysis"]);
    for (const t of names) {
      let nm = ("Raw " + t).replace(/[\\/?*[\]:]/g, "").slice(0, 31), k = 2; while (used.has(nm)) nm = (("Raw " + t).slice(0, 28) + " " + k++);
      used.add(nm);
      const rows = tables[t], cols = []; const seen = new Set();
      rows.slice(0, 500).forEach((x) => Object.keys(x).forEach((c) => { if (c !== "_d" && !seen.has(c)) { seen.add(c); cols.push(c); } }));
      const kind = {}; cols.forEach((c) => { const v = rows.slice(0, 200).map((x) => x[c]).find((x) => typeof x === "string" && x); kind[c] = v && ISO.test(v) ? (v.length === 10 ? "d" : "t") : ""; });
      const ws = wb.addWorksheet(nm, { views: [{ state: "frozen", ySplit: 1 }] });
      ws.columns = cols.map((c) => ({ header: c, key: c, width: Math.min(34, Math.max(10, c.length + 2)) }));
      ws.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } }; ws.getRow(1).fill = HEAD;
      const lim = Math.min(rows.length, RAW_CAP);
      for (let i = 0; i < lim; i++) {
        const x = rows[i];
        ws.addRow(cols.map((c) => { const v = x[c]; if (v === null || v === undefined) return null; if (typeof v === "object") return JSON.stringify(v).slice(0, 32000); if (typeof v === "string") { if (kind[c] && ISO.test(v)) { const d = new Date(v.length === 10 ? v + "T00:00:00Z" : v); return isNaN(d) ? v : d; } return v.length > 32000 ? v.slice(0, 32000) : v; } return v; }));
      }
      cols.forEach((c, i) => { if (kind[c]) ws.getColumn(i + 1).numFmt = kind[c] === "d" ? "dd-mmm-yyyy" : "dd-mmm-yyyy hh:mm"; });
      ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: Math.max(1, cols.length) } };
      await sleep(0);
    }
    return wb.xlsx.writeBuffer();
  }

  /* ------------------------------------------------------------------ the screen */
  const shell = (ctx, body, back) => {
    ctx.main.innerHTML = `<h1>Year-wise Backup &amp; Restore</h1>
      <p class="sub">Every app’s real data, filed as <b>App › Financial year (April–March) › files</b>: a JSON file and an Excel workbook with a dashboard, analysis and the raw data for each. One overall JSON restores everything to the right app and year in one click — records are added or updated, <b>nothing is deleted</b>.</p>
      <p style="margin:0 0 14px"><button class="btn ghost" id="ybBack" style="height:36px">← ${back === "data" ? "Data Master" : "Grand Master"}</button>
      <button class="btn ghost" id="ybOther" style="height:36px">${back === "data" ? "Grand Master" : "Data Master"}</button></p>${body}`;
    const go = (to) => (to === "data" ? window.KMR_DATA : window.KMR_GRAND) && (to === "data" ? window.KMR_DATA : window.KMR_GRAND).overview(ctx);
    ctx.main.querySelector("#ybBack").onclick = () => go(back === "data" ? "data" : "grand");
    ctx.main.querySelector("#ybOther").onclick = () => go(back === "data" ? "grand" : "data");
  };

  /** matrix of apps × financial years with counts; returns { apps(), fys() } of what is ticked */
  function matrix(host, rows, only) {
    const fys = [...new Set(rows.flatMap((a) => Object.keys(a.fy)))].sort(sortFy);
    host.innerHTML = `<div style="overflow:auto;max-height:52vh"><table class="gm" style="min-width:560px"><thead><tr><th style="text-align:left"><label><input type="checkbox" id="ybAllA" checked> App</label></th>
      ${fys.map((f) => `<th style="text-align:right;white-space:nowrap"><label><input type="checkbox" class="ybF" value="${f}" checked> ${esc(f === "Masters" ? "Masters" : f)}</label></th>`).join("")}<th style="text-align:right">Records</th></tr></thead><tbody>
      ${rows.map((a) => `<tr><td><label><input type="checkbox" class="ybA" value="${a.app}" ${only && only !== a.app ? "" : "checked"}> ${esc(NAME[a.app] || a.app)}</label></td>
        ${fys.map((f) => `<td style="text-align:right">${a.fy[f] ? nf(a.fy[f]) : "<span style='color:#94A3B8'>–</span>"}</td>`).join("")}<td style="text-align:right"><b>${nf(a.total)}</b></td></tr>`).join("")}</tbody></table></div>`;
    host.querySelector("#ybAllA").onchange = (e) => host.querySelectorAll(".ybA").forEach((c) => (c.checked = e.target.checked));
    return { apps: () => [...host.querySelectorAll(".ybA:checked")].map((c) => c.value), fys: () => new Set([...host.querySelectorAll(".ybF:checked")].map((c) => c.value)) };
  }
  const progress = (ctx) => {
    const bar = ctx.main.querySelector("#ybBar"), log = ctx.main.querySelector("#ybLog"), box = ctx.main.querySelector("#ybProg");
    box.style.display = "block";
    return { pct: (p) => { bar.style.width = Math.max(0, Math.min(100, p)) + "%"; }, say: (t) => { log.textContent += t + "\n"; log.scrollTop = log.scrollHeight; } };
  };
  const progressHtml = `<div id="ybProg" class="card" style="display:none;margin-top:14px"><div style="height:8px;background:#E5E7EB;border-radius:4px"><div id="ybBar" style="height:8px;width:0;background:#1E7B4A;border-radius:4px;transition:width .3s"></div></div>
    <pre id="ybLog" style="max-height:200px;overflow:auto;font-size:12px;margin:10px 0 0;white-space:pre-wrap"></pre></div>`;

  window.KMR_YB = {
    _makeXlsx: makeXlsx,   // for tests
    /** ctx: { sb, slug, main, dialog }; opts: { app, back: "grand" | "data" } */
    async open(ctx, opts) {
      opts = opts || {}; const back = opts.back || "grand";
      shell(ctx, `<p class="msg">Counting your records by financial year…</p>`, back);
      const { data: plan, error } = await ctx.sb.rpc("kmr_yb_plan", { p_slug: ctx.slug });
      if (error) { ctx.main.querySelector(".msg").textContent = /does not exist|Could not find/i.test(error.message) ? "The year-wise backup needs the latest server update (migration 0127). Please contact KMR support." : error.message; return; }
      const apps = (plan.apps || []).map((a) => {
        const fy = {}; a.tables.forEach((t) => Object.entries(t.fy || {}).forEach(([k, n]) => (fy[k] = (fy[k] || 0) + Number(n))));
        return { app: a.app, tables: a.tables, fy, total: a.tables.reduce((s, t) => s + Number(t.rows), 0) };
      }).filter((a) => a.total > 0 && (!opts.app || a.app === opts.app));
      shell(ctx, `<div class="cards" style="grid-template-columns:repeat(auto-fit,minmax(340px,1fr))">
          <div class="card" style="--c:#1E7B4A"><h3>Backup</h3>
            <p>Tick the apps and years, then choose: <b>one JSON</b> with all the data, or a <b>ZIP</b> filed as <b>App › Year › JSON + Excel</b> (the overall JSON is inside it and also saved as its own file).</p>
            ${apps.length ? `<div id="ybMx"></div>
            <div class="gm-btns" style="margin-top:10px"><button class="btn" id="ybJson" style="height:38px">All data — one JSON file</button>
              <button class="btn ghost" id="ybGo" style="height:38px">App › Year files — ZIP (JSON + Excel)</button></div>
            <label style="display:flex;gap:8px;margin:10px 0 0;font-size:13px"><input type="checkbox" id="ybXl" checked> <span>Include Excel workbooks (Dashboard, Analysis, Raw data) in the ZIP — a large company takes a few minutes</span></label>` : `<p class="msg">There is no real data to back up yet.</p>`}</div>
          <div class="card" style="--c:#4F46E5"><h3>Restore from JSON</h3>
            <p>Upload the <b>overall JSON</b> (or one app-year JSON from the ZIP). You see what is inside, then one click puts every record back in its app and year. Records are <b>added or updated — nothing is deleted</b>.</p>
            <div class="gm-btns"><label class="btn ghost" style="height:38px;cursor:pointer">Upload JSON<input type="file" id="ybUp" accept=".json,application/json" hidden></label></div>
            <div id="ybRs" style="margin-top:12px"></div></div></div>${progressHtml}`, back);
      if (apps.length) {
        const mx = matrix(ctx.main.querySelector("#ybMx"), apps, opts.app);
        ctx.main.querySelector("#ybGo").onclick = (e) => this.backup(ctx, plan, apps, mx, ctx.main.querySelector("#ybXl").checked, e.target, back, "zip");
        ctx.main.querySelector("#ybJson").onclick = (e) => this.backup(ctx, plan, apps, mx, false, e.target, back, "json");
      }
      ctx.main.querySelector("#ybUp").onchange = (e) => this.read(ctx, e.target.files[0], e.target, back);
    },

    async backup(ctx, plan, apps, mx, withXl, btn, back, mode) {
      const selA = new Set(mx.apps()), selF = mx.fys(), chosen = apps.filter((a) => selA.has(a.app));
      if (!chosen.length || !selF.size) { alert("Tick at least one app and one year."); return; }
      const t0 = btn.textContent; btn.disabled = true; btn.textContent = "Working…";
      const P = progress(ctx), when = new Date().toLocaleString("en-IN"), company = ctx.slug;
      try {
        if (mode === "zip") await libs(withXl);
        const data = {};                       // app → fy → table → rows
        const jobs = chosen.flatMap((a) => a.tables.map((t) => ({ a, t }))).filter(({ t }) => Object.keys(t.fy || {}).some((f) => selF.has(f)));
        const rowsAll = jobs.reduce((s, j) => s + Number(j.t.rows), 0); let done = 0;
        for (const { a, t } of jobs) {
          let off = 0, lim = BIG.test(t.t) ? 40 : 2000, got = 0;
          P.say(`Reading ${NAME[a.app] || a.app} › ${t.t} (${nf(t.rows)})`);
          for (;;) {
            let r, tries = 0;
            for (;;) {
              r = await ctx.sb.rpc("kmr_yb_export", { p_slug: ctx.slug, p_app: a.app, p_table: t.t, p_offset: off, p_limit: lim });
              if (!r.error) break;
              if (++tries > 3 || lim <= 20) throw new Error(`${t.t}: ${r.error.message}`);
              lim = Math.max(20, Math.floor(lim / 2));
            }
            const page = r.data || [];
            for (const row of page) {
              const fy = row._fy; delete row._fy;
              if (!selF.has(fy)) continue;
              (((data[a.app] = data[a.app] || {})[fy] = data[a.app][fy] || {})[t.t] = data[a.app][fy][t.t] || []).push(row);
            }
            off += page.length; got += page.length; done += page.length; P.pct((done / Math.max(1, rowsAll)) * 70);
            if (page.length < lim) break;
          }
        }
        /* files */
        const zip = mode === "zip" ? new window.JSZip() : null, parts = [], exported = new Date().toISOString();
        parts.push(`{"format":"kmr-year-backup","version":1,"company":${JSON.stringify(company)},"exported_at":${JSON.stringify(exported)},"fy_basis":"Apr-Mar","apps":{`);
        let firstApp = true, files = 0; const apList = chosen.filter((a) => data[a.app]);
        for (const a of apList) {
          const years = Object.keys(data[a.app]).sort(sortFy);
          parts.push(`${firstApp ? "" : ","}${JSON.stringify(a.app)}:{"name":${JSON.stringify(NAME[a.app] || a.app)},"years":{`); firstApp = false;
          let firstY = true;
          for (const fy of years) {
            const ordered = {}; a.tables.forEach((t) => { if (data[a.app][fy][t.t]) ordered[t.t] = data[a.app][fy][t.t]; });
            const tj = JSON.stringify(ordered, strip);
            parts.push(`${firstY ? "" : ","}${JSON.stringify(fy)}:{"tables":${tj}}`); firstY = false;
            const dir = `${folder(NAME[a.app] || a.app)}/${fy === "Masters" ? "Masters (no year)" : fy}/`;
            const base = `${company}-${a.app}-${fy}`;
            if (mode === "zip") { zip.file(dir + base + ".json", `{"format":"kmr-year-app","version":1,"company":${JSON.stringify(company)},"app":${JSON.stringify(a.app)},"fy":${JSON.stringify(fy)},"exported_at":${JSON.stringify(exported)},"tables":${tj}}`); files++; }
            if (mode === "zip" && withXl) {
              P.say(`Excel: ${NAME[a.app] || a.app} › ${fy}`);
              zip.file(dir + base + "-dashboard-and-data.xlsx", await makeXlsx({ appName: NAME[a.app] || a.app, fy, company, when }, ordered)); files++;
            }
            P.pct(70 + (files / Math.max(1, apList.length * years.length * (withXl ? 2 : 1))) * 20);
          }
          parts.push("}}");
        }
        parts.push("}}");
        const overall = new Blob(parts, { type: "application/json" });
        const oname = `${company}-overall-backup-${stamp()}.json`;
        if (mode === "json") { saveBlob(overall, oname); P.pct(100); P.say(`Done — all data of ${company} in one JSON: ${oname} (${(overall.size / 1048576).toFixed(1)} MB).`); btn.disabled = false; btn.textContent = t0; return; }
        zip.file(oname, overall);
        zip.file("READ ME.txt", `KMR year-wise backup — ${company}\nTaken ${when}\n\nFolders: App › Financial year (April–March) › files.\nEach app-year folder has a JSON file (every record) and an Excel workbook (Dashboard, Analysis, Raw data).\nMasters (no year) holds settings and number counters.\n${oname} is the overall JSON: Grand Master › Year-wise Backup & Restore › Upload JSON puts every record back in its app and year (add + update, nothing deleted).\n`);
        P.say("Packing the ZIP…");
        const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE", compressionOptions: { level: 3 } }, (m) => P.pct(90 + m.percent / 10));
        saveBlob(blob, `${company}-year-backup-${stamp()}.zip`);
        await sleep(1500); saveBlob(overall, oname);
        P.pct(100); P.say(`Done — ${files} files in the ZIP (${(blob.size / 1048576).toFixed(1)} MB) and the overall JSON ${oname}.`);
      } catch (e) { P.say("Stopped: " + (e.message || e)); alert(e.message || e); }
      btn.disabled = false; btn.textContent = t0; void back;
    },

    async read(ctx, file, input, back) {
      if (!file) return;
      const host = ctx.main.querySelector("#ybRs");
      try {
        let j; try { j = JSON.parse(await file.text()); } catch { throw new Error("That file is not valid JSON."); }
        let items;     // [{ app, fy, tables }]
        if (j && j.format === "kmr-year-backup") items = Object.entries(j.apps || {}).flatMap(([app, o]) => Object.entries((o && o.years) || {}).map(([fy, y]) => ({ app, fy, tables: y.tables || {} })));
        else if (j && j.format === "kmr-year-app") items = [{ app: j.app, fy: j.fy, tables: j.tables || {} }];
        else throw new Error("This is not a year-wise backup file. Use the overall JSON from this screen (or one app-year JSON from the ZIP).");
        if (String(j.company || "").toLowerCase() !== String(ctx.slug).toLowerCase()) throw new Error(`This file is a backup of another company (${j.company}).`);
        const byApp = {}; items.forEach((it) => { const a = (byApp[it.app] = byApp[it.app] || { app: it.app, fy: {}, total: 0, items: [] }); const n = Object.values(it.tables).reduce((s, r) => s + r.length, 0); a.fy[it.fy] = (a.fy[it.fy] || 0) + n; a.total += n; a.items.push(it); });
        const rows = Object.values(byApp).filter((a) => a.total > 0);
        if (!rows.length) throw new Error("The file has no records.");
        host.innerHTML = `<p style="margin:0 0 6px"><b>${esc(file.name)}</b> — taken ${esc(String(j.exported_at || "").slice(0, 16).replace("T", " "))}. Tick what to restore:</p><div id="ybRx"></div>
          <div class="gm-btns" style="margin-top:10px"><button class="btn" id="ybRun" style="height:38px">Restore selected</button></div>`;
        const mx = matrix(host.querySelector("#ybRx"), rows);
        host.querySelector("#ybRun").onclick = (e) => this.restore(ctx, rows, mx, file.name, e.target, back);
      } catch (e) { host.innerHTML = `<p class="msg" style="color:#B00E28">${esc(e.message || e)}</p>`; }
      input.value = "";
    },

    async restore(ctx, rows, mx, fname, btn, back) {
      const selA = new Set(mx.apps()), selF = mx.fys(), chosen = rows.filter((a) => selA.has(a.app));
      if (!chosen.length || !selF.size) { alert("Tick at least one app and one year."); return; }
      const n = chosen.reduce((s, a) => s + Object.entries(a.fy).filter(([f]) => selF.has(f)).reduce((x, [, c]) => x + c, 0), 0);
      if (!confirm(`Restore ${nf(n)} records into ${chosen.length} app(s)?\n\nRecords in the file are added, and records that already exist are updated with the file's values. Nothing is deleted.`)) return;
      btn.disabled = true; btn.textContent = "Restoring…";
      const P = progress(ctx), done = {}, bad = []; let sent = 0;
      for (const a of chosen) {
        const order = [], by = {};
        a.items.filter((it) => selF.has(it.fy)).forEach((it) => Object.entries(it.tables).forEach(([t, r]) => { if (!by[t]) { by[t] = []; order.push(t); } for (const x of r) by[t].push(x); }));
        for (const t of order) {
          const all = by[t]; if (!all.length) continue;
          const sz = Math.max(200, JSON.stringify(all[0]).length), chunk = Math.max(5, Math.min(1000, Math.floor(1500000 / sz)));
          P.say(`Restoring ${NAME[a.app] || a.app} › ${t} (${nf(all.length)})`);
          try {
            for (let i = 0; i < all.length; i += chunk) {
              const { data, error } = await ctx.sb.rpc("kmr_yb_import", { p_slug: ctx.slug, p_app: a.app, p_table: t, p_rows: all.slice(i, i + chunk) });
              if (error) throw error;
              done[a.app] = (done[a.app] || 0) + Number(data.rows || 0); sent += Math.min(chunk, all.length - i); P.pct((sent / n) * 100);
            }
          } catch (e) { bad.push(`${NAME[a.app] || a.app} › ${t}: ${e.message || e}`); P.say("  failed: " + (e.message || e)); }
        }
      }
      P.pct(100);
      const okTxt = Object.entries(done).map(([a, c]) => `${NAME[a] || a} ${nf(c)}`).join(" · ");
      const note = `<b>Restored from ${esc(fname)}</b> (add + update, nothing deleted): ${esc(okTxt || "nothing")}.${bad.length ? `<br><span style="color:#B00E28">${bad.length} table(s) could not be restored: ${esc(bad.slice(0, 3).join(" | "))}${bad.length > 3 ? " …" : ""}</span>` : ""}`;
      ctx.main.querySelector("#ybRs").innerHTML = `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF">${note}
        <div class="gm-btns" style="margin-top:8px"><button class="btn ghost" id="ybToG" style="height:36px">Open Grand Master</button><button class="btn ghost" id="ybToD" style="height:36px">Open Data Master</button></div></div>`;
      ctx.main.querySelector("#ybToG").onclick = () => window.KMR_GRAND && window.KMR_GRAND.overview(ctx, note);
      ctx.main.querySelector("#ybToD").onclick = () => window.KMR_DATA && window.KMR_DATA.overview(ctx, note);
      btn.disabled = false; btn.textContent = "Restore selected"; void back;
    },
  };
})();
