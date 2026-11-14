/* KMR mobile tables: on phones (width 700 px or less) every ordinary data table shows each row as a small card
   (heading name on the left, value on the right) so nothing needs sideways scrolling.
   Day-by-day grids (class "sheetg") and printed documents (class "doc") are left as they are: grids keep their sideways scroll with the name column fixed. */
(function () {
  if (window.__kmrMTable) return; window.__kmrMTable = 1;
  const css = `
@media(max-width:700px){
  table.mcard{min-width:0!important;width:100%!important;display:block;border-collapse:separate}
  table.mcard>thead{display:none}
  table.mcard>tbody{display:block}
  table.mcard>tbody>tr{display:block;margin:0 0 10px;padding:6px 12px;border:1px solid var(--line,#e5e9f2);border-radius:10px;background:var(--card,#fff)}
  table.mcard>tbody>tr>td{display:flex;justify-content:space-between;align-items:center;gap:14px;padding:6px 0;border:0;border-bottom:1px dashed var(--line,#e5e9f2);text-align:right!important;min-width:0;width:auto!important;max-width:none!important;word-break:break-word}
  table.mcard>tbody>tr>td:last-child{border-bottom:0}
  table.mcard>tbody>tr>td::before{content:attr(data-label);flex:none;max-width:42%;text-align:left;font-size:11px;font-weight:700;text-transform:uppercase;color:var(--mut,#64748b)}
  table.mcard>tbody>tr>td:not([data-label])::before,table.mcard>tbody>tr>td[data-label=""]::before{content:none}
  table.mcard>tbody>tr>td[data-sno]{justify-content:flex-start;font-weight:700;color:var(--b1,#0d9488)}
  table.mcard>tbody>tr>td[data-sno]::before{content:"S.No : ";margin-right:6px}
  table.mcard>tbody>tr>td:empty{display:none}
  table.mcard>tbody>tr>td[colspan]{display:block;text-align:left!important}
  table.mcard>tbody>tr>td[colspan]::before{content:none}
  table.mcard .btn,table.mcard button{margin-left:6px}
  .twrap:has(table.mcard){max-height:none!important;overflow:visible!important}
}`;
  const st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

  const clean = (th) => { const c = th.cloneNode(true); c.querySelectorAll("small,.dw,.mut").forEach((x) => x.remove()); return c.textContent.replace(/[▲▼↕]/g, "").replace(/\s+/g, " ").trim(); };
  function prep(t) {
    if (t.closest(".doc,.sheet,.dt")) return;
    if (t.classList.contains("sheetg") || t.classList.contains("hdr")) return;
    const hr = t.tHead && t.tHead.rows[0]; if (!hr) return;
    const labels = []; Array.prototype.forEach.call(hr.cells, (th) => { const n = Math.max(1, th.colSpan || 1), s = clean(th); for (let i = 0; i < n; i++) labels.push(s); });
    if (!labels.length) return;
    t.classList.add("mcard");
    Array.prototype.forEach.call(t.tBodies, (b) => Array.prototype.forEach.call(b.rows, (r) => {
      let i = 0;
      Array.prototype.forEach.call(r.cells, (td) => { if (!td.hasAttribute("data-label") || td.__ml) { td.setAttribute("data-label", labels[i] || ""); td.__ml = 1; } i += Math.max(1, td.colSpan || 1); });
    }));
  }
  let q = 0;
  const run = () => { q = 0; document.querySelectorAll("table").forEach(prep); };
  const kick = () => { if (!q) q = requestAnimationFrame(run); };
  new MutationObserver(kick).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener("DOMContentLoaded", kick); kick();
})();
