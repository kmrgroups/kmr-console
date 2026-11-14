/* KMR searchable / multi-select dropdowns.
   1) Every ordinary <select> on the page (6 or more choices) becomes a dropdown with a search box (add data-plain to skip one).
   2) KMRSel.multi(host, {label, options:[{v,l}], value:[...], onChange(arr)}) makes a filter dropdown where several choices can be ticked,
      with Search, Select all and Clear. Nothing ticked = all. */
(function () {
  if (window.KMRSel) return;
  const css = document.createElement("style");
  css.textContent = `.ks-btn{display:flex;align-items:center;justify-content:space-between;gap:8px;width:100%;min-width:130px;border:1px solid #D3DBE6;border-radius:8px;background:#fff;color:#16233A;padding:6px 10px;font:500 13px "Segoe UI",Roboto,Arial,sans-serif;cursor:pointer;text-align:left;min-height:34px}
.ks-btn span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}.ks-btn i{font-style:normal;color:#64748B;font-size:10px}.ks-btn.on{border-color:#7C3AED;background:#F5F0FF}.ks-btn[disabled]{opacity:.55;cursor:default}
.ks-wrap{display:inline-block;vertical-align:top;min-width:150px;max-width:260px}.ks-lab{display:block;font-size:12px;color:#64748B;font-weight:600;margin-bottom:2px}
.ks-pop{position:fixed;z-index:2147483100;width:280px;max-width:calc(100vw - 16px);background:#fff;color:#16233A;border:1px solid #E3E8EF;border-radius:12px;box-shadow:0 18px 50px rgba(20,30,70,.28);padding:8px;font:500 13px "Segoe UI",Roboto,Arial,sans-serif}
.ks-pop input.ks-q{width:100%!important;box-sizing:border-box;height:32px;border:1px solid #D3DBE6;border-radius:8px;padding:0 10px;font:500 13px "Segoe UI",Arial,sans-serif;background:#fff;color:#16233A}
.ks-pop .ks-act{display:flex;justify-content:space-between;margin:6px 2px 4px;font-size:12px}.ks-pop .ks-act a{color:#7C3AED;font-weight:700;cursor:pointer}
.ks-pop .ks-l{max-height:250px;overflow:auto;border:1px solid #EEF1F6;border-radius:8px;padding:2px;margin-top:6px}
.ks-pop .ks-o{display:flex;align-items:center;gap:8px;padding:6px 8px;border-radius:6px;cursor:pointer;line-height:1.25;width:auto!important;margin:0!important;color:#16233A!important;font-size:13px!important}.ks-pop .ks-o:hover,.ks-pop .ks-o.cur{background:#F5F0FF}
.ks-pop .ks-o input{width:16px!important;height:16px!important;min-width:16px!important;padding:0!important;margin:0;accent-color:#7C3AED;flex:none}.ks-pop .ks-o span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ks-pop .ks-none{padding:10px;color:#8A96A8;text-align:center}.ks-pop .ks-done{margin-top:6px;width:100%;border:0;border-radius:8px;padding:7px;font-weight:700;color:#fff;background:#7C3AED;cursor:pointer}`;
  document.head.append(css);
  let pop = null;
  const close = () => { if (pop) { pop.remove(); pop = null; document.removeEventListener("keydown", esc, true); } };
  const esc = (e) => { if (e.key === "Escape") close(); };
  document.addEventListener("mousedown", (e) => { if (pop && !pop.contains(e.target) && !e.target.closest(".ks-btn")) close(); }, true);
  window.addEventListener("scroll", (e) => { if (pop && !pop.contains(e.target)) close(); }, true);
  window.addEventListener("resize", close);

  /* the dropdown list: multi=true gives tick boxes; pick() is called with the full array of chosen values */
  function openList(btn, options, chosen, multi, pick) {
    close();
    const sel = new Set(chosen.map(String));
    pop = document.createElement("div"); pop.className = "ks-pop";
    pop.innerHTML = '<input class="ks-q" type="search" placeholder="Search…" autocomplete="off">' + (multi ? '<div class="ks-act"><a data-k="all">Select all</a><a data-k="none">Clear</a></div>' : "") + '<div class="ks-l"></div>' + (multi ? '<button type="button" class="ks-done">Done</button>' : "");
    document.body.append(pop);
    const r = btn.getBoundingClientRect(), h = Math.min(400, window.innerHeight - 20);
    pop.style.left = Math.max(8, Math.min(r.left, window.innerWidth - 290)) + "px";
    pop.style.top = (r.bottom + 4 + 360 > window.innerHeight && r.top > 360 ? Math.max(8, r.top - 4 - Math.min(h, 360)) : r.bottom + 4) + "px";
    const L = pop.querySelector(".ks-l"), Q = pop.querySelector(".ks-q");
    const draw = () => {
      const f = Q.value.trim().toLowerCase(); L.textContent = "";
      const shown = options.filter((o) => !f || String(o.l).toLowerCase().includes(f));
      if (!shown.length) { const d = document.createElement("div"); d.className = "ks-none"; d.textContent = "No match"; L.append(d); return; }
      shown.slice(0, 500).forEach((o) => {
        const lab = document.createElement("label"); lab.className = "ks-o" + (!multi && sel.has(String(o.v)) ? " cur" : "");
        if (multi) { const cb = document.createElement("input"); cb.type = "checkbox"; cb.checked = sel.has(String(o.v)); cb.onchange = () => { cb.checked ? sel.add(String(o.v)) : sel.delete(String(o.v)); pick([...sel]); }; lab.append(cb); }
        const s = document.createElement("span"); s.textContent = o.l === "" ? "(blank)" : o.l; s.title = o.l; lab.append(s);
        if (!multi) lab.onclick = (e) => { e.preventDefault(); close(); pick([String(o.v)]); };
        L.append(lab);
      });
      if (shown.length > 500) { const d = document.createElement("div"); d.className = "ks-none"; d.textContent = "Type to narrow the list (" + shown.length + " choices)"; L.append(d); }
    };
    Q.oninput = draw; draw(); Q.focus();
    pop.querySelectorAll(".ks-act a").forEach((a) => { a.onclick = () => { const f = Q.value.trim().toLowerCase(); const vis = options.filter((o) => !f || String(o.l).toLowerCase().includes(f)); if (a.dataset.k === "all") vis.forEach((o) => sel.add(String(o.v))); else if (f) vis.forEach((o) => sel.delete(String(o.v))); else sel.clear(); pick([...sel]); draw(); }; });
    const dn = pop.querySelector(".ks-done"); if (dn) dn.onclick = close;
    document.addEventListener("keydown", esc, true);
  }

  /* filter dropdown with several choices */
  function multi(host, o) {
    host.classList.add("ks-wrap");
    let val = (o.value || []).map(String);
    host.innerHTML = (o.label ? '<span class="ks-lab"></span>' : "") + '<button type="button" class="ks-btn"><span></span><i>▼</i></button>';
    if (o.label) host.querySelector(".ks-lab").textContent = o.label;
    const b = host.querySelector(".ks-btn"), t = b.querySelector("span");
    const show = () => { const n = val.length; const map = new Map((o.options || []).map((x) => [String(x.v), x.l])); t.textContent = !n ? "All" : n === 1 ? (map.get(val[0]) || val[0]) : n + " selected"; b.classList.toggle("on", n > 0); };
    show();
    b.onclick = () => { if (pop) { close(); return; } openList(b, o.options || [], val, true, (arr) => { val = arr; show(); if (o.onChange) o.onChange(arr.slice()); }); };
    return { get: () => val.slice(), set: (a) => { val = a.map(String); show(); } };
  }

  /* ordinary <select>: same choices, plus a search box */
  function enhance(s) {
    if (s._ks || s.multiple || s.hasAttribute("data-plain") || s.closest(".kmr-pop,.ks-pop") || s.options.length < 6) return;
    s._ks = 1;
    const b = document.createElement("button"); b.type = "button"; b.className = "ks-btn"; b.innerHTML = "<span></span><i>▼</i>";
    const t = b.querySelector("span");
    const sync = () => { const o = s.options[s.selectedIndex]; t.textContent = o ? o.text : ""; b.disabled = s.disabled; };
    s.style.display = "none"; s.after(b); sync();
    b.onclick = () => { if (pop) { close(); return; } openList(b, [...s.options].map((o) => ({ v: o.value, l: o.text, d: o.disabled })).filter((x) => !x.d), [s.value], false, (arr) => { s.value = arr[0]; sync(); s.dispatchEvent(new Event("input", { bubbles: true })); s.dispatchEvent(new Event("change", { bubbles: true })); }); };
    s.addEventListener("change", sync); new MutationObserver(sync).observe(s, { childList: true, subtree: true, attributes: true });
  }
  const scan = (root) => (root || document).querySelectorAll("select").forEach(enhance);
  new MutationObserver((ms) => { if (ms.some((m) => m.addedNodes.length)) scan(); }).observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState !== "loading") scan(); else document.addEventListener("DOMContentLoaded", () => scan());
  window.KMRSel = { multi, enhance, scan, close };
})();
