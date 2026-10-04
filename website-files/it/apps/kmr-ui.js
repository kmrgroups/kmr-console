/* KMR shared UI helpers (all apps): 1) PDFs open in a viewer first, download on request  2) right-click / long-press "Open in new tab / window" on menus and buttons. */
(function () {
  /* ---------- PDF viewer ---------- */
  function view(blob, name) {
    const url = URL.createObjectURL(blob), v = document.createElement("div");
    v.style.cssText = "position:fixed;inset:0;z-index:2000;background:#0b1020ee;display:flex;flex-direction:column";
    v.innerHTML = '<div style="display:flex;gap:8px;align-items:center;padding:10px 14px;background:#0f172a;color:#fff;flex-wrap:wrap"><b style="flex:1;min-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap"></b>' +
      '<a id="kvDl" style="background:linear-gradient(90deg,#2563eb,#7c3aed);color:#fff;border-radius:9px;padding:8px 14px;font-weight:700;text-decoration:none;cursor:pointer">⬇ Download</a>' +
      '<a id="kvNew" target="_blank" rel="noopener" style="border:1px solid #fff8;color:#fff;border-radius:9px;padding:8px 14px;text-decoration:none">Open in new tab</a>' +
      '<button id="kvX" style="border:1px solid #fff8;background:none;color:#fff;border-radius:9px;padding:8px 14px;cursor:pointer">✕ Close</button></div>' +
      '<iframe style="flex:1;border:0;background:#fff;width:100%"></iframe>';
    v.querySelector("b").textContent = name;
    v.querySelector("iframe").src = url;
    const dl = v.querySelector("#kvDl"); dl.href = url; dl.download = name;
    v.querySelector("#kvNew").href = url;
    const close = () => { v.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000); };
    v.querySelector("#kvX").onclick = close; document.body.appendChild(v);
    document.addEventListener("keydown", function esc(e) { if (e.key === "Escape") { close(); document.removeEventListener("keydown", esc); } });
  }
  window.KMRPdf = { view };

  /* ---------- right-click: open this screen in a new tab / window ---------- */
  const menu = document.createElement("div");
  menu.style.cssText = "position:fixed;z-index:2100;display:none;background:#fff;color:#0f172a;border:1px solid #e5e9f2;border-radius:10px;box-shadow:0 10px 30px #0004;padding:4px;font:14px system-ui,sans-serif;min-width:200px";
  document.addEventListener("DOMContentLoaded", () => document.body.appendChild(menu));
  const hide = () => { menu.style.display = "none"; };
  function target(el) {                      // what does this element open?
    const b = el.closest("[data-go],[data-t],[data-view],a[href]"); if (!b) return null;
    if (b.matches("a[href]") && !/^javascript:|^#/.test(b.getAttribute("href"))) return { url: b.href };
    const key = b.dataset.go || b.dataset.t || b.dataset.view; if (!key) return null;
    const prj = window.PDApp && window.PDApp.S && window.PDApp.S.prj && window.PDApp.S.prj.id;
    return { url: location.href.split("#")[0] + "#go=" + encodeURIComponent(key) + (prj ? "&prj=" + prj : "") };
  }
  const show = (x, y, t) => {
    menu.innerHTML = '<a target="_blank" rel="noopener" style="display:block;padding:8px 12px;color:inherit;text-decoration:none;border-radius:7px">Open in new tab</a><a data-w style="display:block;padding:8px 12px;color:inherit;text-decoration:none;border-radius:7px;cursor:pointer">Open in new window</a>';
    const [a, w] = menu.children; a.href = t.url; a.onclick = hide;
    w.onclick = () => { hide(); window.open(t.url, "_blank", "popup=yes,width=" + Math.min(screen.availWidth, 1280) + ",height=" + Math.min(screen.availHeight, 860)); };
    [a, w].forEach(e => { e.onmouseenter = () => e.style.background = "#eef2ff"; e.onmouseleave = () => e.style.background = ""; });
    menu.style.display = "block"; menu.style.left = Math.min(x, innerWidth - 220) + "px"; menu.style.top = Math.min(y, innerHeight - 100) + "px";
  };
  document.addEventListener("contextmenu", e => { const t = target(e.target); if (!t) { hide(); return; } e.preventDefault(); show(e.clientX, e.clientY, t); });
  let lp = null;                              // long-press on touch screens
  document.addEventListener("touchstart", e => { const tt = e.touches[0], t = target(e.target); if (!t) return; lp = setTimeout(() => show(tt.clientX, tt.clientY, t), 650); }, { passive: true });
  ["touchend", "touchmove", "touchcancel"].forEach(n => document.addEventListener(n, () => clearTimeout(lp), { passive: true }));
  document.addEventListener("click", hide); window.addEventListener("scroll", hide, true);

  /* ---------- open a screen from a link made above (#go=…&prj=…) — each app calls KMRNav.pending() once it is ready ---------- */
  window.KMRNav = { pending() { const m = location.hash.match(/go=([^&]+)(?:&prj=([0-9a-f-]+))?/i); return m ? { go: decodeURIComponent(m[1]), prj: m[2] || null } : null; } };
})();
