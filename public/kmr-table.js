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
th.kmr-th{position:relative;white-space:nowrap;user-select:none}
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
.kmr-pop .acts{display:flex;justify-content:space-between;margin:8px 2px 4px;font-size:12px}.kmr-pop .acts a{color:#7C3AED;font-weight:700;cursor:pointer;text-decoration:none}
.kmr-pop .lst{max-height:240px;overflow:auto;border:1px solid #EEF1F6;border-radius:8px;padding:2px}
.kmr-pop label{display:flex;align-items:center;gap:8px;padding:5px 6px;border-radius:6px;cursor:pointer;line-height:1.25}.kmr-pop label:hover{background:#F5F0FF}
.kmr-pop label input{accent-color:#7C3AED;flex:none;margin:0}.kmr-pop label span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.kmr-pop label em{font-style:normal;color:#8A96A8;font-size:11.5px}
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
    return null;
  };
  const cmp = (a, b) => {
    if (a === b) return 0; if (a === "") return 1; if (b === "") return -1;
    const da = dateOf(a), db = dateOf(b); if (da != null && db != null) return da - db;
    const na = num(a), nb = num(b); if (na != null && nb != null) return na - nb;
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

  function enhance(t, hr) {
    const base = location.pathname + location.hash + "|" + [...hr.cells].map(txt).join("|");
    t.dataset.kmrk0 = base;
    const key = keyOf(t, hr);
    const st = states.get(key) || { sort: null, f: {}, q: "" };
    states.set(key, st); t._kmr = { st, hr, key };
    const edit = bodyRows(t, hr).some((r) => r.querySelector("input:not([type=checkbox]):not([type=hidden]),select,textarea"));
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
      if (!serial.has(i)) { const b = document.createElement("button"); b.type = "button"; b.className = "kmr-fb f"; b.title = "Filter / sort this column"; b.innerHTML = SVG_F; b.onclick = (e) => { e.stopPropagation(); openPop(t, i, b); }; ctl.append(b); }
      th.append(ctl);
      if (!edit && !serial.has(i)) lab.onclick = (e) => { e.stopPropagation(); setSort(t, i, st.sort && st.sort.c === i ? (st.sort.dir === "asc" ? "desc" : st.sort.dir === "desc" ? null : "asc") : "asc"); };
      else lab.style.cursor = "default";
    });
    // toolbar
    if (!t.previousElementSibling || !t.previousElementSibling.classList.contains("kmr-tt")) {
      const bar = document.createElement("div"); bar.className = "kmr-tt";
      bar.innerHTML = '<input type="search" placeholder="Search this table…" aria-label="Search this table"><span class="kmr-cnt"></span><button type="button" hidden>Clear filters</button>';
      t.parentNode.insertBefore(bar, t);
      const inp = bar.querySelector("input"); inp.value = st.q || "";
      inp.oninput = () => { st.q = inp.value; apply(t); };
      bar.querySelector("button").onclick = () => { st.f = {}; st.q = ""; inp.value = ""; apply(t); };
    }
    // when the app re-draws the rows, keep the filters
    const tb = t.tBodies[0] || t;
    const mo = new MutationObserver(() => { if (t._kmr.busy) return; clearTimeout(t._kmr.tm); t._kmr.tm = setTimeout(() => apply(t, true), 60); });
    mo.observe(t, { childList: true, subtree: true, characterData: true }); t._kmr.mo = mo;
    live.add(t);
    if (st.sort || st.q || Object.keys(st.f).length) apply(t, true); else counts(t);
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
        if (show && q) show = txt(r).toLowerCase().includes(q) || [...r.cells].some((c) => cellVal(c).toLowerCase().includes(q));
        r.classList.toggle("kmr-hid", !show);
      });
      if (st.sort && !k.edit) {
        const { c, dir } = st.sort, m = dir === "asc" ? 1 : -1;
        [...(t.tBodies.length ? t.tBodies : [t])].forEach((b) => {
          const rs = [...b.rows].filter((r) => r !== hr && !([...r.cells].some((x) => x.colSpan > 1 && x.colSpan >= hr.cells.length)));
          const idx = new Map(rs.map((r, i) => [r, i]));
          const vals = new Map(rs.map((r) => [r, cellVal(r.cells[c])]));
          const sorted = rs.slice().sort((a, b2) => m * cmp(vals.get(a), vals.get(b2)) || idx.get(a) - idx.get(b2));
          if (sorted.some((r, i) => r !== rs[i])) sorted.forEach((r) => b.append(r));
        });
      }
      k.serial.forEach((i) => { let n = 0; bodyRows(t, hr).forEach((r) => { if (!r.classList.contains("kmr-hid") && r.cells[i] && /^\d+$/.test(txt(r.cells[i]) || "x") ) r.cells[i].textContent = ++n; }); });
      [...hr.cells].forEach((th, i) => {
        const on = !!(st.f[i] && true), s = st.sort && st.sort.c === i;
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
    bar.querySelector("button").hidden = !(act || (k.st.q || "") || Object.keys(k.st.f).length);
  }

  function closePop() { if (pop) { pop.remove(); pop = null; } }
  function openPop(t, c, btn) {
    closePop();
    const k = t._kmr, st = k.st;
    const rows = bodyRows(t, k.hr).filter((r) => ![...r.cells].some((x) => x.colSpan > 1 && x.colSpan >= k.hr.cells.length));
    // values offered: those that pass the other columns' filters
    const cnt = new Map();
    rows.forEach((r) => { let ok = true; for (const o of Object.keys(st.f)) if (+o !== c && !st.f[o].has(cellVal(r.cells[+o]))) { ok = false; break; } const v = cellVal(r.cells[c]); if (ok || st.f[c]) cnt.set(v, (cnt.get(v) || 0) + (ok ? 1 : 0)); });
    const vals = [...cnt.keys()].sort(cmp);
    const sel = new Set(st.f[c] ? st.f[c] : vals);
    pop = document.createElement("div"); pop.className = "kmr-pop";
    const dir = st.sort && st.sort.c === c ? st.sort.dir : "";
    pop.innerHTML = (k.edit ? "" : `<div class="sr"><button type="button" data-s="asc" class="${dir === "asc" ? "on" : ""}">▲ Sort A→Z</button><button type="button" data-s="desc" class="${dir === "desc" ? "on" : ""}">▼ Z→A</button></div>`) +
      '<input class="q" type="search" placeholder="Search values…"><div class="acts"><a data-a="all">Select all</a><a data-a="none">Clear</a><a data-a="reset">Reset</a></div><div class="lst"></div>';
    const lst = pop.querySelector(".lst"), q = pop.querySelector(".q");
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
      if (t._kmr) { if (!t.isConnected) { live.delete(t); } else if (!t.previousElementSibling || !t.previousElementSibling.classList.contains("kmr-tt") || !t._kmr.hr.isConnected || [...t._kmr.hr.cells].some((th) => !th.classList.contains("kmr-th"))) { /* toolbar lost: re-enhance */ t._kmr.mo && t._kmr.mo.disconnect(); delete t._kmr; t.querySelectorAll(".kmr-th").forEach((th) => th.classList.remove("kmr-th")); const pv = t.previousElementSibling; if (pv && pv.classList.contains("kmr-tt")) pv.remove(); } else return; }
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
