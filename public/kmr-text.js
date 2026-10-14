/* KMR shared text-field helpers (every app, every screen):
   0) Every table gets an auto-numbered "S.No" first column (follows searches/filters, restarts from 1 in each table).
   1) A number box never changes when the mouse wheel / trackpad is scrolled over it — the page scrolls instead.
   2) Spell-check is on in every text box and notes field. Double-click (or select) a word to see whether it is spelled
      correctly, the suggested spellings, and its synonyms and antonyms; click one to replace the word. */
(function () {
  "use strict";
  if (window.__kmrText) return; window.__kmrText = 1;


  /* ---------- 0) automatic serial numbers in every table ---------- */
  const SKIP_T = ".heat,.invoice-lines,[data-nosno],.no-sno,.cal,.calendar";
  const SERIAL = /^(s\.?\s*no\.?|sr\.?\s*no\.?|sl\.?\s*no\.?|serial(\s*no\.?)?)$/i;
  const rowsOf = (sec) => Array.prototype.filter.call(sec.children, (c) => c.tagName === "TR");
  const secs = (t) => Array.prototype.filter.call(t.children, (c) => /^(THEAD|TBODY|TFOOT)$/.test(c.tagName));
  const span = (c) => c.colSpan || 1;
  const hdrRow = (t) => {
    if (t.tHead && t.tHead.rows.length) return t.tHead.rows[t.tHead.rows.length - 1];
    const f = secs(t).concat([t]).map((s) => rowsOf(s)[0]).find(Boolean);
    return f && f.children.length && Array.prototype.every.call(f.children, (c) => c.tagName === "TH") ? f : null;
  };
  const eligible = (t) => {
    if (t.matches(SKIP_T) || t.closest(SKIP_T)) return null;
    const h = hdrRow(t); if (!h) return null;
    const cells = Array.prototype.filter.call(h.children, (c) => c.tagName === "TH" || c.tagName === "TD");
    if (cells.length < 2 || cells.some((c) => c.rowSpan > 1)) return null;
    const first = h.querySelector("[data-sno]") ? null : cells[0];
    if (first && SERIAL.test((first.textContent || "").trim())) return null;
    return h;
  };
  const sno = (t) => {
    const h = eligible(t); if (!h) return;
    const n = Array.prototype.reduce.call(h.children, (a, c) => a + (c.hasAttribute("data-sno") ? 0 : span(c)), 0);
    if (!h.querySelector("[data-sno]")) { const th = document.createElement("th"); th.setAttribute("data-sno", ""); th.textContent = "S.No"; th.style.cssText = "width:52px;text-align:center;white-space:nowrap"; h.insertBefore(th, h.firstChild); }
    let i = 0;
    secs(t).forEach((sec) => rowsOf(sec).forEach((r) => {
      if (r === h) return;
      let c = r.firstElementChild && r.firstElementChild.hasAttribute("data-sno") ? r.firstElementChild : null;
      const real = Array.prototype.filter.call(r.children, (x) => !x.hasAttribute("data-sno"));
      if (!real.length) return;
      const all = real.length === 1 && span(real[0]) >= n;          // "No records" / group row spanning the whole table
      if (!c) { c = document.createElement(sec.tagName === "THEAD" ? "th" : "td"); c.setAttribute("data-sno", ""); r.insertBefore(c, r.firstChild); }
      if (all || sec.tagName !== "TBODY") { c.textContent = ""; c.style.width = "52px"; return; }
      const hidden = r.hidden || r.style.display === "none";
      c.style.cssText = "text-align:center;color:#6B778A;width:52px;font-variant-numeric:tabular-nums" + (hidden ? ";display:none" : "");
      if (!hidden) c.textContent = String(++i);
    }));
  };
  const dirty = new Set(); let sched = 0, mo = null;
  const flush = () => { sched = 0; if (mo) mo.disconnect(); dirty.forEach((t) => { try { if (t.isConnected) sno(t); } catch (e) {} }); dirty.clear(); watch(); };
  const queue = (t) => { if (t && t.tagName === "TABLE") { dirty.add(t); if (!sched) sched = requestAnimationFrame(flush); } };
  const tablesIn = (n) => { if (n.nodeType !== 1) return; if (n.tagName === "TABLE") queue(n); else if (n.closest && n.closest("table")) queue(n.closest("table")); if (n.querySelectorAll) n.querySelectorAll("table").forEach(queue); };
  const watch = () => {
    if (!mo) mo = new MutationObserver((ms) => ms.forEach((m) => { tablesIn(m.target); m.addedNodes.forEach(tablesIn); if (m.type === "attributes") tablesIn(m.target); }));
    mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["hidden", "style"] });
  };
  const startSno = () => { document.querySelectorAll("table").forEach(queue); watch(); };
  const nextApp = !!(window.next || window.__next_f || document.getElementById("__next"));
  const go = () => (nextApp ? setTimeout(startSno, 1200) : startSno());
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", go); else go();

  /* ---------- 1) mouse wheel must not change a number ---------- */
  const guard = (e) => { const t = e.target; if (t && t.tagName === "INPUT" && t.type === "number" && document.activeElement === t) t.blur(); };
  document.addEventListener("wheel", guard, { capture: true, passive: true });
  document.addEventListener("mousewheel", guard, { capture: true, passive: true });
  document.addEventListener("DOMMouseScroll", guard, { capture: true, passive: true });

  /* ---------- 2) spell-check on ---------- */
  const SKIP = /^(password|email|url|tel|number|date|time|datetime-local|month|week|color|file|hidden|range|checkbox|radio|button|submit|reset|image)$/;
  const mark = (el) => {
    if (el.__kt) return; el.__kt = 1;
    if (el.tagName === "INPUT" && SKIP.test(el.type || "text")) return;
    if (el.hasAttribute("data-nospell")) return;
    el.setAttribute("spellcheck", "true"); if (!el.getAttribute("lang") && !el.closest("[lang]")) el.setAttribute("lang", "en");
  };
  const scan = (root) => (root.querySelectorAll ? root.querySelectorAll("input,textarea") : []).forEach(mark);
  const start = () => { scan(document); new MutationObserver((ms) => ms.forEach((m) => m.addedNodes.forEach((n) => { if (n.nodeType === 1) { if (n.matches && n.matches("input,textarea")) mark(n); scan(n); } }))).observe(document.documentElement, { childList: true, subtree: true }); };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();

  /* ---------- word helper ---------- */
  const API = "https://api.datamuse.com/words?max=8&";
  const cache = {};
  const get = (q) => cache[q] || (cache[q] = fetch(API + q).then((r) => r.json()).catch(() => []));
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  let box = null;
  const close = () => { if (box) { box.remove(); box = null; } };
  const wordAt = (el) => {
    let a = el.selectionStart, b = el.selectionEnd, v = el.value;
    if (a == null || b == null) return null;
    if (a === b) return null;
    const w = v.slice(a, b).trim(); if (!/^[A-Za-z][A-Za-z'-]{2,29}$/.test(w)) return null;
    return { w, a: a + v.slice(a, b).indexOf(w), b: a + v.slice(a, b).indexOf(w) + w.length };
  };
  const setVal = (el, a, b, text) => {
    const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const nv = el.value.slice(0, a) + text + el.value.slice(b);
    Object.getOwnPropertyDescriptor(proto, "value").set.call(el, nv);
    el.focus(); try { el.setSelectionRange(a + text.length, a + text.length); } catch (e) {}
    el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true }));
  };
  const caseLike = (src, w) => (src[0] === src[0].toUpperCase() && src[0] !== src[0].toLowerCase() ? w[0].toUpperCase() + w.slice(1) : w);
  async function help(el) {
    const s = wordAt(el); if (!s) return close();
    const low = s.w.toLowerCase(), r = el.getBoundingClientRect();
    close();
    box = document.createElement("div");
    box.style.cssText = "position:fixed;z-index:99999;max-width:340px;background:#fff;color:#16233A;border:1px solid #D3DBE6;border-radius:12px;box-shadow:0 12px 40px rgba(10,20,50,.25);padding:10px 12px;font:13px/1.45 'Segoe UI',Arial";
    box.innerHTML = `<b>${esc(s.w)}</b> <small style="color:#6B778A">checking…</small>`;
    document.body.appendChild(box);
    const place = () => { if (!box) return; const h = box.offsetHeight; let top = r.bottom + 6; if (top + h > innerHeight - 8) top = Math.max(8, r.top - h - 6); box.style.top = top + "px"; box.style.left = Math.max(8, Math.min(r.left, innerWidth - box.offsetWidth - 8)) + "px"; };
    place();
    const [sp, syn, ant] = await Promise.all([get("sp=" + encodeURIComponent(low)), get("rel_syn=" + encodeURIComponent(low)), get("rel_ant=" + encodeURIComponent(low))]);
    if (!box) return;
    const ok = sp.length && sp[0].word.toLowerCase() === low;
    const chips = (list, bad) => list.length ? list.map((x) => `<button type="button" data-w="${esc(x.word)}" style="margin:2px 4px 2px 0;border:1px solid ${bad ? "#E8A4AE" : "#C9D6EE"};background:${bad ? "#FDEEF0" : "#F1F5FC"};color:#0B2A6F;border-radius:999px;padding:2px 10px;font:600 12px 'Segoe UI',Arial;cursor:pointer">${esc(x.word)}</button>`).join("") : '<span style="color:#6B778A">none found</span>';
    const sugg = sp.filter((x) => x.word.toLowerCase() !== low).slice(0, 6);
    box.innerHTML = `<div style="display:flex;justify-content:space-between;gap:10px"><b>${esc(s.w)}</b><a href="#" data-x style="color:#6B778A;text-decoration:none">✕</a></div>
      <div style="margin:2px 0 6px;font-weight:700;color:${ok ? "#1E7B4A" : "#B00E28"}">${ok ? "✔ Spelled correctly" : "✖ Possible spelling mistake"}</div>
      ${ok ? "" : `<div><span style="color:#6B778A">Did you mean</span><br>${chips(sugg, true)}</div>`}
      <div style="margin-top:6px"><span style="color:#6B778A">Synonyms</span><br>${chips(syn.slice(0, 6))}</div>
      <div style="margin-top:6px"><span style="color:#6B778A">Antonyms</span><br>${chips(ant.slice(0, 6))}</div>
      <div style="margin-top:6px;color:#8795A8;font-size:11px">Click a word to replace “${esc(s.w)}”.</div>`;
    box.querySelector("[data-x]").onclick = (e) => { e.preventDefault(); close(); };
    box.querySelectorAll("[data-w]").forEach((b) => (b.onmousedown = (e) => { e.preventDefault(); setVal(el, s.a, s.b, caseLike(s.w, b.dataset.w)); close(); }));
    place();
  }
  const isText = (t) => t && ((t.tagName === "TEXTAREA") || (t.tagName === "INPUT" && /^(text|search|)$/.test(t.type || "text"))) && !t.hasAttribute("data-nospell");
  document.addEventListener("dblclick", (e) => { if (isText(e.target)) setTimeout(() => help(e.target), 0); }, true);
  document.addEventListener("mousedown", (e) => { if (box && !box.contains(e.target)) close(); }, true);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); }, true);
  document.addEventListener("scroll", () => { if (box) close(); }, true);
})();
