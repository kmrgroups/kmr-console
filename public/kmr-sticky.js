/* KMR — frozen table titles: every data table keeps its heading row visible while its rows scroll, and fits the screen width.
   One shared file for all apps and the Console. Opt out with  data-nosticky  on a table or a parent. Printed documents (.doc) are left alone. */
(function () {
  "use strict";
  if (window.__kmrSticky) return; window.__kmrSticky = true;
  const st = document.createElement("style");
  st.textContent = `
table.kmr-stk>thead>tr>th,table.kmr-stk>thead>tr>td{position:sticky;top:0;z-index:4;background-clip:padding-box}
table.kmr-stk>thead>tr:nth-child(2)>th{top:var(--kmr-h1,30px)}
.kmr-stw{overflow:auto!important;max-width:100%;max-height:calc(100vh - 190px);-webkit-overflow-scrolling:touch}
.kmr-stw.kmr-own{max-height:none}
@media print{.kmr-stw{max-height:none!important;overflow:visible!important}table.kmr-stk>thead>tr>th{position:static}}`;
  document.head.appendChild(st);
  const skip = (t) => t.closest("[data-nosticky],.doc,.kmr-pop,.kmr-pt,.invoice,.sheetg-print") || !t.tHead || !t.tHead.rows.length || t.tBodies.length === 0 || t.rows.length < 2;
  const scrolls = (el) => { const o = getComputedStyle(el); return /(auto|scroll)/.test(o.overflowY) && el.clientHeight > 0 && el.scrollHeight >= el.clientHeight; };
  function fix(t) {
    if (t.classList.contains("kmr-stk") || skip(t)) return;
    t.classList.add("kmr-stk");
    // opaque heading cells, or the rows would show through while scrolling
    t.querySelectorAll(":scope>thead th,:scope>thead td").forEach((c) => {
      const bg = getComputedStyle(c).backgroundColor;
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") c.style.backgroundColor = "#f4f6fb";
    });
    const r1 = t.tHead.rows[0]; if (t.tHead.rows.length > 1 && r1) t.style.setProperty("--kmr-h1", r1.offsetHeight + "px");
    let p = t.parentElement;
    // already inside a box that scrolls up/down (own max-height): nothing more to do
    if (p && p !== document.body && /(auto|scroll)/.test(getComputedStyle(p).overflowY) && getComputedStyle(p).maxHeight !== "none") return;
    if (p && p.children.length === 1 && p !== document.body && !p.matches("td,th,li,form,main,section,article")) { p.classList.add("kmr-stw"); return; }
    const w = document.createElement("div"); w.className = "kmr-stw"; p.insertBefore(w, t); w.appendChild(t);
  }
  let q = 0;
  const run = () => { q = 0; document.querySelectorAll("table").forEach(fix); };
  const later = () => { if (!q) q = setTimeout(run, 250); };
  new MutationObserver(later).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener("DOMContentLoaded", run); later();
})();
