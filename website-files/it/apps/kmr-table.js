/* KMR — smart tables: every ordinary data table gets, in its title row, sort + filter on every column
   (search inside the column, tick several values), plus a small search box above the table.
   Works on tables drawn at any time (re-drawn tables keep their filters). Same file is used in the apps and in the Console.
   Skip a table with  data-nofilter  on it or on a parent. Tables that are being edited (input cells) are filtered but never re-ordered. */
(function () {
  "use strict";
  if (window.__kmrTable) return; window.__kmrTable = true;
  const css = document.createElement("style");
  css.textContent = `
.kmr-hid{display:none!important}
th.kmr-th{position:sticky;top:0;z-index:3;white-space:nowrap;user-select:none}
th.kmr-th .kmr-lab{cursor:pointer}
th.kmr-th .kmr-ctl{display:inline-flex;align-items:center;gap:2px;margin-left:6px;vertical-align:middle;font-weight:400}
th.kmr-th .kmr-fb{border:1px solid transparent;background:transparent;border-radius:6px;width:22px;height:22px;padding:0;cursor:pointer;color:inherit;opacity:.55;display:inline-grid;place-items:center;font:inherit;line-height:1}
th.kmr-th .kmr-fb:hover{opacity:1;background:rgba(124,58,237,.12)}
th.kmr-th .kmr-fb svg{width:13px;height:13px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
th.kmr-th.kmr-on .kmr-fb.f{opacity:1;color:#fff;background:#7C3AED}
th.kmr-th .kmr-ar{font-size:11px;color:#7C3AED;font-weight:800;min-width:9px}
.kmr-tt{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:0 0 8px;font:500 13px "Segoe UI",Roboto,Arial,sans-serif;color:#5E6B7E}
.kmr-tt input{height:34px;min-width:200px;max-width:320px;flex:1 1 200px;border:1px solid #D3DBE6;border-radius:10px;padding:0 12px 0 32px;font:500 13.5px "Segoe UI",Roboto,Arial,sans-serif;color:#16233A;background:#fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%238A96A8' stroke-width='2.4' stroke-linecap='round'%3E%3Ccircle cx='11' cy='11' r='7'/%3E%3Cpath d='M20 20l-4-4'/%3E%3C/svg%3E") 10px 50%/15px no-repeat}
.kmr-tt input:focus{outline:none;border-color:#7C3AED;box-shadow:0 0 0 3px rgba(124,58,237,.14)}
.kmr-tt .kmr-cnt{white-space:nowrap}.kmr-tt button{border:1px solid #D3DBE6;background:#fff;color:#7C3AED;border-radius:999px;padding:4px 12px;font:700 12px "Segoe UI",Arial,sans-serif;cursor:pointer}
.kmr-tt button:hover{background:#F5F0FF}
.kmr-pop{position:fixed;z-index:2147483000;width:260px;max-width:calc(100vw - 16px);background:#fff;color:#16233A;border:1px solid #E3E8EF;border-radius:14px;box-shadow:0 18px 50px rgba(20,30,70,.28);padding:10px;font:500 13px "Segoe UI",Roboto,Arial,sans-serif;text-align:left;font-weight:500;text-transform:none;letter-spacing:0}
.kmr-pop .sr{display:flex;gap:6px;margin-bottom:8px}.kmr-pop .sr button{flex:1;border:1px solid #E3E8EF;background:#F9FBFD;border-radius:8px;padding:6px 4px;font:700 12px "Segoe UI",Arial,sans-serif;cursor:pointer;color:#16233A}
.kmr-pop .sr button.on{background:#7C3AED;border-color:#7C3AED;color:#fff}
.kmr-pop input.q{width:100%;height:32px;border:1px solid #D3DBE6;border-radius:8px;padding:0 10px;font:500 13px "Segoe UI",Arial,sans-serif;box-sizing:border-box}
.kmr-pop input.q:focus{outline:none;border-color:#7C3AED}
.kmr-pop .cnd{border:1px solid #EEF1F6;border-radius:8px;padding:6px;margin-bottom:8px;background:#F9FBFD}.kmr-pop .cnd select,.kmr-pop .cnd input{width:100%;box-sizing:border-box;height:30px;margin:2px 0;border:1px solid #D3DBE6;border-radius:7px;padding:0 8px;font:500 12.5px "Segoe UI",Arial,sans-serif;background:#fff;color:#16233A}.kmr-pop .cnd .cb{display:flex;gap:6px;margin-top:4px}.kmr-pop .cnd .cb button{flex:1;border:1px solid #D3DBE6;background:#fff;border-radius:8px;padding:5px;font:700 12px "Segoe UI",Arial,sans-serif;cursor:pointer;color:#16233A}.kmr-pop .cnd .cb button.go{background:#7C3AED;border-color:#7C3AED;color:#fff}.kmr-pop .cnd b{font-size:11.5px;color:#5E6B7E}
.kmr-pop .acts{display:flex;justify-content:space-between;margin:8px 2px 4px;font-size:12px}.kmr-pop .acts a{color:#7C3AED;font-weight:700;cursor:pointer;text-decoration:none}
.kmr-pop .lst{max-height:240px;overflow:auto;border:1px solid #EEF1F6;border-radius:8px;padding:2px}
.kmr-pop label{display:flex;align-items:center;gap:8px;padding:5px 6px;border-radius:6px;cursor:pointer;line-height:1.25}.kmr-pop label:hover{background:#F5F0FF}
.kmr-pop label input{accent-color:#7C3AED;flex:none;margin:0;width:16px!important;height:16px!important;min-width:16px!important;padding:0!important;border:0!important;box-shadow:none!important}.kmr-pop label{width:auto!important;margin:0!important;font-size:13px!important;color:#16233A!important}.kmr-pop label span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#16233A!important;font-size:13px!important;position:static!important;display:block!important}.kmr-pop label em{font-style:normal;color:#8A96A8!important;font-size:11.5px!important;position:static!important;display:block!important}
.kmr-tt .kd{display:flex;align-items:center;gap:4px;font-size:12px}.kmr-tt .kd input[type=date]{height:30px;border:1px solid #D3DBE6;border-radius:8px;padding:0 6px;font:500 12.5px 'Segoe UI',Arial,sans-serif;width:auto;min-width:0;color:#16233A;background:#fff}.kmr-tt .kb{border:0;border-radius:8px;padding:6px 12px;font:700 12px 'Segoe UI',Arial,sans-serif;cursor:pointer;color:#fff;background:#7C3AED}.kmr-tt .kb.x{background:#16A34A}.kmr-tt .kb.p{background:#DC2626}.kmr-tt .kb.o{background:#fff;color:#7C3AED;border:1px solid #7C3AED}
@media print{body.kmr-pr *{visibility:hidden!important}body.kmr-pr .kmr-pt,body.kmr-pr .kmr-pt *{visibility:visible!important}body.kmr-pr .kmr-pt{position:absolute;left:0;top:0;width:100%;overflow:visible!important;max-height:none!important}body.kmr-pr .kmr-pt table{min-width:0!important}body.kmr-pr .kmr-pt .kmr-tt,body.kmr-pr .kmr-pt .kmr-noprint{display:none!important}}
.kmr-pop .none{padding:10px;color:#8A96A8;text-align:center}
@media print{.kmr-tt,th.kmr-th .kmr-ctl{display:none!important}}`;
  document.head.append(css);

  const SVG_F = '<svg viewBox="0 0 24 24"><path d="M3 5h18l-7 8v6l-4 2v-8z"/></svg>';
  const states = new Map();       // key → {sort:{c,dir}, f:{col:Set|null}, q:""}
  const live = new Set();         // enhanced tables
  let pop = null;
  const txt = (el) => (el.textContent || "").replace(/\s+/g, " ").trim();
  const cellVal = (td) => {
    if (!td) return "";
    if (td.dataset && td.dataset.v != null) return td.dataset.v;
    const inp = td.querySelector("input:not([type=checkbox]):not([type=radio]):not([type=hidden]),textarea");
    if (inp) return (inp.value || "").trim();
    const sel = td.querySelector("select"); if (sel) return txt(sel.options[sel.selectedIndex] || sel);
    const cb = td.querySelector("input[type=checkbox]"); if (cb && !txt(td)) return cb.checked ? "Yes" : "No";
    return txt(td);
  };
  const num = (s) => { const m = String(s).replace(/[,₹$€\s]/g, "").match(/^[-+]?\d*\.?\d+(?:e[-+]?\d+)?(?=%|[a-z]{0,4}$)/i); return m ? parseFloat(m[0]) : null; };
  const dateOf = (s) => {
    let m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})/); if (m) return Date.UTC(+m[1], +m[2] - 1, +m[3]);
    m = String(s).match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{4})/); if (m) return Date.UTC(+m[3], +m[2] - 1, +m[1]);
    m = String(s).match(/^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{4})/); if (m) { const i = "jan feb mar apr may jun jul aug sep oct nov dec".split(" ").indexOf(m[2].toLowerCase()); if (i >= 0) return Date.UTC(+m[3], i, +m[1]); }
    return null;
  };
  const OPS = [["", "— Choose a condition —"], ["eq", "Equals"], ["ne", "Does not equal"], ["gt", "Greater than"], ["ge", "Greater than or equal to"], ["lt", "Less than"], ["le", "Less than or equal to"], ["between", "Between"], ["begins", "Begins with"], ["ends", "Ends with"], ["contains", "Contains"], ["notcontains", "Does not contain"], ["blank", "Is blank"], ["notblank", "Is not blank"]];
  const matchOp = (o, v) => {
    const op = o.op, a = o.a == null ? "" : String(o.a), b = o.b == null ? "" : String(o.b);
    if (op === "blank") return v === ""; if (op === "notblank") return v !== "";
    const lv = v.toLowerCase(), la = a.toLowerCase();
    if (op === "contains") return lv.includes(la); if (op === "notcontains") return !lv.includes(la);
    if (op === "begins") return lv.startsWith(la); if (op === "ends") return lv.endsWith(la);
    if (v === "") return false;
    const c = (x, y) => { const dx = dateOf(x), dy = dateOf(y); if (dx != null && dy != null) return dx - dy; const nx = num(x), ny = num(y); if (nx != null && ny != null) return nx - ny; return String(x).toLowerCase().localeCompare(String(y).toLowerCase(), undefined, { numeric: true }); };
    if (op === "eq") return c(v, a) === 0; if (op === "ne") return c(v, a) !== 0;
    if (op === "gt") return c(v, a) > 0; if (op === "ge") return c(v, a) >= 0; if (op === "lt") return c(v, a) < 0; if (op === "le") return c(v, a) <= 0;
    if (op === "between") return c(v, a) >= 0 && c(v, b) <= 0;
    return true;
  };
  const cmp = (a, b) => {
    if (a === b) return 0; if (a === "") return 1; if (b === "") return -1;
    const da = dateOf(a), db = dateOf(b); if (da != null && db != null) return da - db;
    const na = num(a), nb = num(b); if (na != null && nb != null) return na - nb;
    if (na != null) return -1; if (nb != null) return 1;                                              // numbers first (smallest to largest), then words
    return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
  };

  function headerRow(t) {
    let tr = t.tHead && t.tHead.rows.length ? t.tHead.rows[t.tHead.rows.length - 1] : null;
    if (!tr) { const f = t.rows[0]; if (f && [...f.cells].every((c) => c.tagName === "TH")) tr = f; }
    if (!tr || tr.cells.length < 2) return null;
    const cs = [...tr.cells]; if (cs.some((c) => c.colSpan > 1 || c.rowSpan > 1 || c.tagName !== "TH")) return null;
    if (t.tHead && t.tHead.rows.length > 1) return null;
    return tr;
  }
  function bodyRows(t, hr) {
    const out = []; [...t.tBodies].forEach((b) => [...b.rows].forEach((r) => { if (r !== hr) out.push(r); }));
    if (!t.tBodies.length) [...t.rows].forEach((r) => { if (r !== hr) out.push(r); });
    return out;
  }
  function eligible(t) {
    if (t.closest("[data-nofilter],.kmr-pop,.kmr-tt,.no-print,#print,.print-area")) return null;
    if (/^\/pay\//.test(location.pathname)) return null;
    const hr = headerRow(t); if (!hr) return null;
    const rows = bodyRows(t, hr);
    const data = rows.filter((r) => ![...r.cells].some((c) => c.colSpan > 1 && c.colSpan >= hr.cells.length));
    if (data.length < 3) return null;
    if (data.some((r) => [...r.cells].some((c) => c.rowSpan > 1))) return null;
    return hr;
  }
  const keyOf = (t, hr) => {
    let h = ""; let e = t.closest("section,.card,div") || t;
    const prev = (t.closest(".kmr-tw") || t).previousElementSibling; if (prev) h = txt(prev).slice(0, 40);
    const same = [...document.querySelectorAll("table")].filter((x) => x.dataset.kmrk0 === (location.pathname + location.hash + "|" + [...hr.cells].map(txt).join("|"))).indexOf(t);
    return location.pathname + "|" + location.hash.split("?")[0] + "|" + h + "|" + [...hr.cells].map((c) => txt(c)).join("|") + "|" + same;
  };


  function dateCol(t, hr) {
    const rows = bodyRows(t, hr).slice(0, 8), hs = [...hr.cells].map(txt);
    let best = -1;
    hs.forEach((h, i) => { if (best >= 0) return; if (/date|due|valid|expir|issued|received|from|to$/i.test(h) && rows.some((r) => dateOf(cellVal(r.cells[i])) != null)) best = i; });
    if (best < 0) hs.forEach((h, i) => { if (best < 0 && rows.length && rows.filter((r) => dateOf(cellVal(r.cells[i])) != null).length >= Math.ceil(rows.length / 2) && !/^\d+$/.test(h)) best = i; });
    return best;
  }
  const monthNum = (s) => { const m = String(s).match(/^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})$/); if (!m) return null; const i = "jan feb mar apr may jun jul aug sep oct nov dec".split(" ").indexOf(m[2].toLowerCase()); return i < 0 ? null : Date.UTC(+m[3], i, +m[1]); };
  const dateOf0 = dateOf;
  function exportRows(t) {
    const k = t._kmr, hr = k.hr, skip = new Set();
    [...hr.cells].forEach((th, i) => { const h = txt(th); if (/^(actions?|action|select|#)?$/i.test(h) || /^actions?$/i.test(h)) skip.add(i); });
    const head = [...hr.cells].map((th, i) => skip.has(i) ? null : txt(th.querySelector(".kmr-lab") || th)).map((x, i) => skip.has(i) ? null : x);
    const rows = bodyRows(t, hr).filter((r) => !r.classList.contains("kmr-hid") && ![...r.cells].some((c) => c.colSpan > 1 && c.colSpan >= hr.cells.length));
    const data = rows.map((r) => [...r.cells].map((c, i) => skip.has(i) ? null : cellVal(c)));
    return { skip, head: head.filter((x, i) => !skip.has(i)), data: data.map((r) => r.filter((x, i) => !skip.has(i))) };
  }
  const tname = (t) => { const prev = (t.closest(".kmr-tw") || t).previousElementSibling; const sec = t.closest("section"); let n = (document.querySelector(".tab.on") || {}).textContent || ""; n = n.replace(/\d+$/, "").trim(); return (n || document.title.split("·")[0].trim() || "Table").slice(0, 40); };
  async function exportXl(t) {
    const { head, data } = exportRows(t), name = tname(t), day = new Date(Date.now() + 19800000).toISOString().slice(0, 10);
    try {
      if (!window.ExcelJS) await new Promise((ok, no) => { const s = document.createElement("script"); s.src = "https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js"; s.onload = ok; s.onerror = no; document.head.append(s); });
      const wb = new ExcelJS.Workbook(), ws = wb.addWorksheet(name.slice(0, 30), { views: [{ state: "frozen", ySplit: 3 }], pageSetup: { orientation: "landscape", fitToPage: true, fitToWidth: 1, fitToHeight: 0, paperSize: 9, margins: { left: .4, right: .4, top: .6, bottom: .6, header: .3, footer: .3 } } });
      const co = (document.getElementById("co") || {}).textContent || "";
      ws.mergeCells(1, 1, 1, Math.max(1, head.length)); ws.getCell(1, 1).value = (co ? co + " — " : "") + name; ws.getCell(1, 1).font = { bold: true, size: 14 };
      ws.mergeCells(2, 1, 2, Math.max(1, head.length)); ws.getCell(2, 1).value = "Date: " + day + " · Rows: " + data.length; ws.getCell(2, 1).font = { color: { argb: "FF64748B" } };
      const hrw = ws.addRow(head); hrw.eachCell((c) => { c.font = { bold: true, color: { argb: "FFFFFFFF" } }; c.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF174B80" } }; c.alignment = { vertical: "middle", wrapText: true }; });
      data.forEach((r) => ws.addRow(r.map((v) => { const n = num(v); return (n != null && /^[-+₹,.\d\s]+$/.test(String(v)) && !/^0\d/.test(String(v).trim())) ? n : v; })));
      head.forEach((h, i) => { const w = Math.max(String(h).length, ...data.slice(0, 200).map((r) => String(r[i] == null ? "" : r[i]).length)); ws.getColumn(i + 1).width = Math.min(48, Math.max(9, w + 2)); });
      ws.autoFilter = { from: { row: 3, column: 1 }, to: { row: 3, column: Math.max(1, head.length) } };
      ws.headerFooter = { oddFooter: "&LKMR Apps&CPage &P of &N&R" + day };
      const buf = await wb.xlsx.writeBuffer(), a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" })); a.download = name.replace(/[^\w]+/g, "_") + "_" + day + ".xlsx"; document.body.append(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    } catch (e) {
      const q = (v) => '"' + String(v == null ? "" : v).replace(/"/g, '""') + '"', a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob(["\ufeff" + [head].concat(data).map((r) => r.map(q).join(",")).join("\n")], { type: "text/csv" })); a.download = name.replace(/[^\w]+/g, "_") + "_" + day + ".csv"; document.body.append(a); a.click(); setTimeout(() => a.remove(), 500);
    }
  }
  function exportPdf(t) {
    const name = tname(t), wrap = t.closest(".kmr-tw") || t.parentNode;
    try { if (window.KMRReport) { const i = KMRReport.info() || {}; KMRReport.set({ title: (i.title ? i.title + " – " : "") + name, doc: i.doc || "", format: i.format, rev: i.rev, date: i.date }); } } catch (e) { }
    const tgt = document.createElement("div"); tgt.className = "kmr-pt";
    const hold = document.createComment("kmr"); wrap.parentNode.insertBefore(hold, wrap); tgt.append(wrap); hold.parentNode.insertBefore(tgt, hold);
    [...t.querySelectorAll("th,td")].forEach((c) => { if (/^actions?$/i.test(txt(t._kmr.hr.cells[c.cellIndex] || "")) ) c.classList.add("kmr-noprint"); });
    document.body.classList.add("kmr-pr");
    const done = () => { document.body.classList.remove("kmr-pr"); tgt.parentNode.insertBefore(wrap, tgt); tgt.remove(); hold.remove(); window.removeEventListener("afterprint", done); };
    window.addEventListener("afterprint", done); setTimeout(() => window.print(), 50);
  }
  function enhance(t, hr) {
    const base = location.pathname + location.hash + "|" + [...hr.cells].map(txt).join("|");
    t.dataset.kmrk0 = base;
    const key = keyOf(t, hr);
    const st = states.get(key) || { sort: null, f: {}, q: "", o: {} }; if (!st.o) st.o = {};
    states.set(key, st); t._kmr = { st, hr, key };
    const edit = !t.hasAttribute("data-sortedit") && bodyRows(t, hr).some((r) => r.querySelector("input:not([type=checkbox]):not([type=hidden]),select,textarea"));
    t._kmr.edit = edit;
    // serial-number column: renumbered after sorting / filtering
    const serial = new Set();
    [...hr.cells].forEach((th, i) => { if (/^(s\.?\s*no\.?|sl\.?\s*no\.?|sr\.?\s*no\.?|sl\.?|#|no\.?)$/i.test(txt(th))) { const rs = bodyRows(t, hr).slice(0, 5); if (rs.every((r) => /^\d+$/.test(cellVal(r.cells[i])))) serial.add(i); } });
    t._kmr.serial = serial;
    [...hr.cells].forEach((th, i) => {
      if (th.classList.contains("kmr-th")) return;
      th.classList.add("kmr-th");
      const lab = document.createElement("span"); lab.className = "kmr-lab";
      while (th.firstChild) lab.append(th.firstChild);
      th.append(lab);
      const ctl = document.createElement("span"); ctl.className = "kmr-ctl";
      const ar = document.createElement("span"); ar.className = "kmr-ar"; ctl.append(ar);
      if (!serial.has(i)) { const b = document.createElement("button"); b.type = "button"; b.className = "kmr-fb f"; b.title = "Filter / sort this column"; b.innerHTML = SVG_F; b.onclick = (e) => { e.stopPropagation(); openPop(t, [...hr.cells].indexOf(th), b); }; ctl.append(b); }
      th.append(ctl);
      if (!edit && !serial.has(i)) lab.onclick = (e) => { e.stopPropagation(); const ci = [...hr.cells].indexOf(th); setSort(t, ci, st.sort && st.sort.c === ci ? (st.sort.dir === "asc" ? "desc" : st.sort.dir === "desc" ? null : "asc") : "asc"); };
      else lab.style.cursor = "default";
    });
    // toolbar
    if (!t.previousElementSibling || !t.previousElementSibling.classList.contains("kmr-tt")) {
      const bar = document.createElement("div"); bar.className = "kmr-tt";
      const dc = dateCol(t, hr);
      bar.innerHTML = '<input type="search" placeholder="Search this table…" aria-label="Search this table"><span class="kmr-cnt"></span><button type="button" hidden>Clear filters</button>' + (dc >= 0 ? '<span class="kd">From <input type="date" class="df"> To <input type="date" class="dt"> <button type="button" class="kb go">Search</button></span>' : '') + '<button type="button" class="kb x kxl">Excel</button><button type="button" class="kb p kpd">PDF</button>';
      t.parentNode.insertBefore(bar, t);
      const inp = bar.querySelector("input"); inp.value = st.q || "";
      inp.oninput = () => { st.q = inp.value; apply(t); };
      bar.querySelector("button").onclick = () => { st.f = {}; st.o = {}; st.q = ""; st.dr = null; inp.value = ""; const a = bar.querySelector(".df"), b = bar.querySelector(".dt"); if (a) { a.value = ""; b.value = ""; } apply(t); };
      t._kmr.dc = dc;
      if (dc >= 0) { const a = bar.querySelector(".df"), b = bar.querySelector(".dt"); if (st.dr) { a.value = st.dr.a || ""; b.value = st.dr.b || ""; } bar.querySelector(".go").onclick = () => { st.dr = (a.value || b.value) ? { a: a.value, b: b.value } : null; apply(t); }; }
      bar.querySelector(".kxl").onclick = () => exportXl(t);
      bar.querySelector(".kpd").onclick = () => exportPdf(t);
    }
    // when the app re-draws the rows, keep the filters
    const tb = t.tBodies[0] || t;
    const mo = new MutationObserver(() => { if (t._kmr.busy) return; clearTimeout(t._kmr.tm); t._kmr.tm = setTimeout(() => apply(t, true), 60); });
    mo.observe(t, { childList: true, subtree: true, characterData: true }); t._kmr.mo = mo;
    live.add(t);
    if (st.sort || st.q || Object.keys(st.f).length || Object.keys(st.o).length || st.dr) apply(t, true); else counts(t);
  }

  function setSort(t, c, dir) { t._kmr.st.sort = dir ? { c, dir } : null; apply(t); }

  function apply(t, soft) {
    const k = t._kmr; if (!k || !t.isConnected) return;
    k.busy = true;
    try {
      const st = k.st, hr = k.hr;
      const rows = bodyRows(t, hr);
      const q = (st.q || "").toLowerCase().trim();
      const cols = Object.keys(st.f).filter((c) => st.f[c] && st.f[c].size >= 0);
      rows.forEach((r) => {
        if ([...r.cells].some((c) => c.colSpan > 1 && c.colSpan >= hr.cells.length)) { r.classList.remove("kmr-hid"); return; }
        let show = true;
        for (const c of cols) { if (!st.f[c].has(cellVal(r.cells[+c]))) { show = false; break; } }
        if (show) for (const c of Object.keys(st.o)) { if (!matchOp(st.o[c], cellVal(r.cells[+c]))) { show = false; break; } }
        if (show && st.dr && k.dc >= 0) { const d = dateOf(cellVal(r.cells[k.dc])); if (d == null) show = false; else { if (st.dr.a && d < dateOf(st.dr.a)) show = false; if (st.dr.b && d > dateOf(st.dr.b)) show = false; } }
        if (show && q) show = txt(r).toLowerCase().includes(q) || [...r.cells].some((c) => cellVal(c).toLowerCase().includes(q));
        r.classList.toggle("kmr-hid", !show);
      });
      if (st.sort && !k.edit) {
        const { c, dir } = st.sort, m = dir === "asc" ? 1 : -1;
        [...(t.tBodies.length ? t.tBodies : [t])].forEach((b) => {
          const rs = [...b.rows].filter((r) => r !== hr && !([...r.cells].some((x) => x.colSpan > 1 && x.colSpan >= hr.cells.length)));
          const idx = new Map(rs.map((r, i) => [r, i]));
          const vals = new Map(rs.map((r) => [r, cellVal(r.cells[c])]));
          const sorted = rs.slice().sort((a, b2) => { const va = vals.get(a), vb = vals.get(b2); if (va === "" && vb !== "") return 1; if (vb === "" && va !== "") return -1; return m * cmp(va, vb) || idx.get(a) - idx.get(b2); });          // empty cells always last
          if (sorted.some((r, i) => r !== rs[i])) sorted.forEach((r) => b.append(r));
        });
      }
      k.serial.forEach((i) => { let n = 0; bodyRows(t, hr).forEach((r) => { if (!r.classList.contains("kmr-hid") && r.cells[i] && /^\d+$/.test(txt(r.cells[i]) || "x") ) r.cells[i].textContent = ++n; }); });
      [...hr.cells].forEach((th, i) => {
        const on = !!(st.f[i] || st.o[i]), s = st.sort && st.sort.c === i;
        th.classList.toggle("kmr-on", on);
        const ar = th.querySelector(".kmr-ar"); if (ar) ar.textContent = s ? (st.sort.dir === "asc" ? "▲" : "▼") : "";
      });
      counts(t);
    } finally { setTimeout(() => { k.busy = false; }, 0); }
  }
  function counts(t) {
    const k = t._kmr, bar = t.previousElementSibling; if (!bar || !bar.classList.contains("kmr-tt")) return;
    const rows = bodyRows(t, k.hr).filter((r) => ![...r.cells].some((c) => c.colSpan > 1 && c.colSpan >= k.hr.cells.length));
    const vis = rows.filter((r) => !r.classList.contains("kmr-hid")).length, act = vis !== rows.length;
    bar.querySelector(".kmr-cnt").textContent = act ? `Showing ${vis} of ${rows.length}` : `${rows.length} rows`;
    bar.querySelector("button").hidden = !(act || k.st.dr || (k.st.q || "") || Object.keys(k.st.f).length || Object.keys(k.st.o).length);
  }

  function closePop() { if (pop) { pop.remove(); pop = null; } }
  function openPop(t, c, btn) {
    closePop();
    const k = t._kmr, st = k.st;
    const rows = bodyRows(t, k.hr).filter((r) => ![...r.cells].some((x) => x.colSpan > 1 && x.colSpan >= k.hr.cells.length));
    // values offered: those that pass the other columns' filters
    const cnt = new Map();
    rows.forEach((r) => { let ok = true; for (const o of Object.keys(st.f)) if (+o !== c && !st.f[o].has(cellVal(r.cells[+o]))) { ok = false; break; } if (ok) for (const o of Object.keys(st.o)) if (+o !== c && !matchOp(st.o[o], cellVal(r.cells[+o]))) { ok = false; break; } const v = cellVal(r.cells[c]); if (ok || st.f[c]) cnt.set(v, (cnt.get(v) || 0) + (ok ? 1 : 0)); });
    const vals = [...cnt.keys()].sort(cmp);
    const sel = new Set(st.f[c] ? st.f[c] : vals);
    pop = document.createElement("div"); pop.className = "kmr-pop";
    const dir = st.sort && st.sort.c === c ? st.sort.dir : "";
    pop.innerHTML = (k.edit ? "" : `<div class="sr"><button type="button" data-s="asc" class="${dir === "asc" ? "on" : ""}">▲ Sort A→Z (smallest first)</button><button type="button" data-s="desc" class="${dir === "desc" ? "on" : ""}">▼ Z→A (largest first)</button></div>`) +
      '<div class="cnd"><b>Filter by condition</b><select class="op">' + OPS.map(([v, l]) => `<option value="${v}">${l}</option>`).join("") + '</select><input class="v1" placeholder="Value"><input class="v2" placeholder="and"><div class="cb"><button type="button" class="go">Apply</button><button type="button" class="cl">Clear</button></div></div>' +
      '<input class="q" type="search" placeholder="Search values…"><div class="acts"><a data-a="all">Select all</a><a data-a="none">Clear</a><a data-a="reset">Reset</a></div><div class="lst"></div>';
    const lst = pop.querySelector(".lst"), q = pop.querySelector(".q");
    const op = pop.querySelector(".op"), v1 = pop.querySelector(".v1"), v2 = pop.querySelector(".v2"), cur = st.o[c] || null;
    const showV = () => { const o = op.value; v1.style.display = o && o !== "blank" && o !== "notblank" ? "" : "none"; v2.style.display = o === "between" ? "" : "none"; };
    if (cur) { op.value = cur.op; v1.value = cur.a == null ? "" : cur.a; v2.value = cur.b == null ? "" : cur.b; } showV();
    op.onchange = showV;
    pop.querySelector(".cb .go").onclick = () => { if (!op.value) { delete st.o[c]; } else st.o[c] = { op: op.value, a: v1.value, b: v2.value }; apply(t); closePop(); };
    pop.querySelector(".cb .cl").onclick = () => { delete st.o[c]; apply(t); closePop(); };
    const commit = () => { const all = vals.every((v) => sel.has(v)); if (all) delete st.f[c]; else st.f[c] = new Set(sel); apply(t); };
    const draw = () => {
      const f = q.value.toLowerCase(); lst.textContent = "";
      const shown = vals.filter((v) => !f || v.toLowerCase().includes(f)).slice(0, 400);
      if (!shown.length) { const d = document.createElement("div"); d.className = "none"; d.textContent = "No match"; lst.append(d); return; }
      shown.forEach((v) => {
        const l = document.createElement("label"), cb = document.createElement("input"), s = document.createElement("span"), e = document.createElement("em");
        cb.type = "checkbox"; cb.checked = sel.has(v); s.textContent = v === "" ? "(blank)" : v; s.title = v; e.textContent = cnt.get(v) || 0;
        cb.onchange = () => { cb.checked ? sel.add(v) : sel.delete(v); commit(); };
        l.append(cb, s, e); lst.append(l);
      });
    };
    pop.addEventListener("click", (e) => {
      const s = e.target.closest("[data-s]"), a = e.target.closest("[data-a]");
      if (s) { setSort(t, c, st.sort && st.sort.c === c && st.sort.dir === s.dataset.s ? null : s.dataset.s); closePop(); }
      if (a) {
        const f = q.value.toLowerCase(), cur = vals.filter((v) => !f || v.toLowerCase().includes(f));
        if (a.dataset.a === "all") cur.forEach((v) => sel.add(v)); else if (a.dataset.a === "none") cur.forEach((v) => sel.delete(v)); else vals.forEach((v) => sel.add(v));
        commit(); draw();
      }
    });
    q.oninput = draw; draw();
    document.body.append(pop);
    const r = btn.getBoundingClientRect(), w = pop.offsetWidth, h = pop.offsetHeight;
    let x = Math.min(Math.max(8, r.left), window.innerWidth - w - 8), y = r.bottom + 6; if (y + h > window.innerHeight - 8) y = Math.max(8, r.top - h - 6);
    pop.style.left = x + "px"; pop.style.top = y + "px"; q.focus({ preventScroll: true });
  }
  document.addEventListener("mousedown", (e) => { if (pop && !pop.contains(e.target) && !e.target.closest(".kmr-fb")) closePop(); }, true);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") closePop(); });
  window.addEventListener("scroll", (e) => { if (pop && !pop.contains(e.target)) closePop(); }, true);

  let tm = null;
  function scan() {
    document.querySelectorAll("table").forEach((t) => {
      if (t._kmr) { if (!t.isConnected) { live.delete(t); } else if (!t.previousElementSibling || !t.previousElementSibling.classList.contains("kmr-tt") || !t._kmr.hr.isConnected || [...t._kmr.hr.cells].some((th) => !th.classList.contains("kmr-th"))) { /* toolbar lost: re-enhance */ t._kmr.mo && t._kmr.mo.disconnect(); delete t._kmr; t.querySelectorAll(".kmr-th").forEach((th) => { th.querySelectorAll(":scope > .kmr-ctl").forEach((x) => x.remove()); th.querySelectorAll(":scope > .kmr-lab").forEach((l) => { while (l.firstChild) th.insertBefore(l.firstChild, l); l.remove(); }); th.classList.remove("kmr-th", "kmr-on"); }); const pv = t.previousElementSibling; if (pv && pv.classList.contains("kmr-tt")) pv.remove(); } else return; }
      const hr = eligible(t); if (hr) enhance(t, hr);
    });
  }
  const mo = new MutationObserver((ms) => {
    if (ms.every((m) => (m.target.closest && m.target.closest(".kmr-pop,.kmr-tt")) || (m.addedNodes.length === 0 && m.removedNodes.length === 0))) return;
    clearTimeout(tm); tm = setTimeout(scan, 200);
  });
  const start = () => { scan(); mo.observe(document.body, { childList: true, subtree: true }); };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
  window.addEventListener("hashchange", () => setTimeout(scan, 250));
})();
