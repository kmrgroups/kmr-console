/* KMR shared text-field helpers (every app, every screen):
   1) A number box never changes when the mouse wheel / trackpad is scrolled over it — the page scrolls instead.
   2) Spell-check is on in every text box and notes field. Double-click (or select) a word to see whether it is spelled
      correctly, the suggested spellings, and its synonyms and antonyms; click one to replace the word. */
(function () {
  "use strict";
  if (window.__kmrText) return; window.__kmrText = 1;

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
