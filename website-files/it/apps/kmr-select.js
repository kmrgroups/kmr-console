/* KMR searchable dropdown - one shared script for every KMR app, Console and HRM.
   Every <select> opens a popup with a search box. Optional attributes on a <select>:
     data-multi  : a "Select multiple" switch appears; several values are stored joined as "A, B"
     data-add    : typing a value that is not in the list offers "+ Add ..."
     data-native : leave this one as the browser's own dropdown
   A <select multiple> works as a multi-select list. Values, events and form behaviour are unchanged. */
(function () {
  if (window.__kmrSelect) return; window.__kmrSelect = 1;
  var pop = null, cur = null, SEP = ", ", openW = 0, popPlace = null;
  function css() {
    if (document.getElementById("kmr-sel-css")) return;
    var s = document.createElement("style"); s.id = "kmr-sel-css";
    s.textContent = ".kmr-sp{position:fixed;z-index:2147483000;box-shadow:0 10px 30px rgba(0,0,0,.28);border:1px solid rgba(128,128,128,.45);border-radius:8px;display:flex;flex-direction:column;font:14px/1.3 system-ui,sans-serif;overflow:hidden}" +
      ".kmr-sp input[type=search]{margin:8px;padding:8px 10px;font:inherit;border:1px solid rgba(128,128,128,.55);border-radius:6px;background:transparent;color:inherit;outline:none;width:auto}" +
      ".kmr-sp input[type=search]:focus{border-color:#2563eb}.kmr-sp .kl{overflow:auto;flex:1;padding:0 4px 6px}" +
      ".kmr-sp .ko{padding:7px 10px;border-radius:5px;cursor:pointer;display:flex;gap:8px;align-items:center}.kmr-sp .ko.hi{background:rgba(37,99,235,.16)}.kmr-sp .ko.on{font-weight:700}" +
      ".kmr-sp .kg{padding:6px 10px 2px;font-size:11px;text-transform:uppercase;letter-spacing:.05em;opacity:.65}.kmr-sp .kf{display:flex;gap:10px;align-items:center;padding:6px 10px;border-top:1px solid rgba(128,128,128,.3);font-size:12.5px}" +
      ".kmr-sp .kf button{font:inherit;padding:4px 10px;border-radius:6px;border:1px solid rgba(128,128,128,.55);background:transparent;color:inherit;cursor:pointer}.kmr-sp .kn{padding:10px;opacity:.7}.kmr-sp .ko{min-height:40px;touch-action:manipulation}.kmr-sp input[type=search]{font-size:16px}.kmr-sp .kx{width:16px;text-align:center}";
    document.head.appendChild(s);
  }
  function ok(sel) { return sel && sel.tagName === "SELECT" && !sel.disabled && !sel.hasAttribute("data-native") && !(sel.size > 1) && !sel.closest(".kmr-sp"); }
  function close() { if (pop) { pop.remove(); pop = null; } if (popPlace && window.visualViewport) { window.visualViewport.removeEventListener("resize", popPlace); window.visualViewport.removeEventListener("scroll", popPlace); } popPlace = null; cur = null; }
  function fire(sel) { sel.dispatchEvent(new Event("input", { bubbles: true })); sel.dispatchEvent(new Event("change", { bubbles: true })); }
  function items(sel) {
    var out = [];
    Array.prototype.forEach.call(sel.children, function (c) {
      if (c.tagName === "OPTGROUP") { out.push({ g: c.label }); Array.prototype.forEach.call(c.children, function (o) { out.push({ o: o }); }); }
      else if (c.tagName === "OPTION") out.push({ o: c });
    });
    return out.filter(function (x) { return !(x.o && x.o.hasAttribute("data-kmr-synth")); });
  }
  function open(sel) {
    if (!ok(sel)) return; close(); css(); cur = sel;
    var nat = sel.multiple, mm = !nat && sel.hasAttribute("data-multi"), add = sel.hasAttribute("data-add");
    var curVal = nat ? Array.prototype.filter.call(sel.options, function (o) { return o.selected && o.value !== ""; }).map(function (o) { return o.value; }) : (sel.value || "").split(mm ? SEP : "\u0000").filter(Boolean);
    var multi = nat || (mm && curVal.length > 1), chosen = {}; curVal.forEach(function (v) { chosen[v] = 1; });
    var cs = getComputedStyle(sel), r = sel.getBoundingClientRect();
    pop = document.createElement("div"); pop.className = "kmr-sp";
    var bg = cs.backgroundColor; if (!bg || /rgba\(0, 0, 0, 0\)|transparent/.test(bg)) bg = getComputedStyle(document.body).backgroundColor; if (!bg || /rgba\(0, 0, 0, 0\)|transparent/.test(bg)) bg = "#fff";
    pop.style.background = bg; pop.style.color = cs.color || "inherit";
    pop.innerHTML = '<input type="search" placeholder="Search..." autocomplete="off" spellcheck="false" data-nospell><div class="kl" role="listbox"></div>' +
      (mm ? '<div class="kf"><label><input type="checkbox" class="km"' + (multi ? " checked" : "") + '> Select multiple</label></div>' : "") +
      '<div class="kf kd" style="display:none"><button type="button" class="kok">Done</button><button type="button" class="kc">Clear</button></div>';
    document.body.appendChild(pop);
    var w = Math.max(r.width, 240); pop.style.width = Math.min(w, window.innerWidth - 16) + "px";
    var left = Math.min(Math.max(8, r.left), window.innerWidth - w - 8); pop.style.left = left + "px";
    var vv = window.visualViewport, small = window.innerWidth <= 640 || (window.matchMedia && matchMedia("(pointer:coarse)").matches);
    openW = window.innerWidth;
    function place() {
      if (!pop) return;
      if (small) {   /* phone: sheet at the top of the visible area, so the keyboard never hides the list */
        var vh = vv ? vv.height : window.innerHeight, top = vv ? vv.offsetTop : 0, lft = vv ? vv.offsetLeft : 0, vw = vv ? vv.width : window.innerWidth;
        pop.style.left = (lft + 8) + "px"; pop.style.width = (vw - 16) + "px"; pop.style.bottom = "auto"; pop.style.top = (top + 8) + "px";
        pop.style.maxHeight = Math.max(160, Math.min(vh - 16, vh * 0.7)) + "px"; return;
      }
      var below = window.innerHeight - r.bottom, h = Math.min(340, Math.max(below, r.top) - 12);
      pop.style.maxHeight = Math.max(160, h) + "px"; if (below >= 220 || below >= r.top) pop.style.top = (r.bottom + 2) + "px"; else pop.style.bottom = (window.innerHeight - r.top + 2) + "px";
    }
    place(); popPlace = place; if (vv) { vv.addEventListener("resize", place); vv.addEventListener("scroll", place); }
    var inp = pop.querySelector("input[type=search]"), list = pop.querySelector(".kl"), done = pop.querySelector(".kd"), hi = 0, vis = [];
    var all = items(sel);
    function sync() { done.style.display = multi ? "flex" : "none"; }
    function draw() {
      var q = inp.value.trim().toLowerCase(), html = "", lastG = null; vis = [];
      all.forEach(function (x) {
        if (x.g != null) { lastG = x.g; return; }
        var t = x.o.text || ""; if (q && t.toLowerCase().indexOf(q) < 0 && String(x.o.value).toLowerCase().indexOf(q) < 0) return;
        if (x.o.value === "" && q) return;
        if (lastG != null) { html += '<div class="kg">' + esc(lastG) + "</div>"; lastG = null; }
        var on = multi ? !!chosen[x.o.value] : (x.o.value === sel.value);
        html += '<div class="ko' + (on ? " on" : "") + (x.o.disabled ? " dis" : "") + '" data-i="' + vis.length + '">' + (multi ? '<span class="kx">' + (on ? "\u2611" : "\u2610") + "</span>" : "") + "<span>" + esc(t === "" ? "\u2014" : t) + "</span></div>";
        vis.push(x.o);
      });
      var exact = all.some(function (x) { return x.o && x.o.text.toLowerCase() === q; });
      if (add && q && !exact) { html += '<div class="ko ka" data-i="add">+ Add \u201c' + esc(inp.value.trim()) + "\u201d</div>"; }
      if (!html) html = '<div class="kn">Nothing found</div>';
      list.innerHTML = html; if (hi >= vis.length + (add && q && !exact ? 1 : 0)) hi = 0; mark(); sync();
    }
    function mark() { var els = list.querySelectorAll(".ko"); Array.prototype.forEach.call(els, function (e, i) { e.classList.toggle("hi", i === hi); }); var e = els[hi]; if (e && e.scrollIntoView) e.scrollIntoView({ block: "nearest" }); }
    function apply() {
      if (nat) { Array.prototype.forEach.call(sel.options, function (o) { o.selected = !!chosen[o.value]; }); }
      else if (multi || mm) {
        var vals = Object.keys(chosen); Array.prototype.forEach.call(sel.querySelectorAll("option[data-kmr-synth]"), function (o) { o.remove(); });
        var order = Array.prototype.map.call(sel.options, function (o) { return o.value; }); vals.sort(function (a, b) { var x = order.indexOf(a), y = order.indexOf(b); return (x < 0 ? 1e9 : x) - (y < 0 ? 1e9 : y); });
        var v = vals.join(SEP); var has = Array.prototype.some.call(sel.options, function (o) { return o.value === v; });
        if (v && !has) { var o = new Option(v, v); o.setAttribute("data-kmr-synth", "1"); sel.appendChild(o); }
        sel.value = v;
      }
      fire(sel);
    }
    function pick(o, isAdd) {
      if (isAdd) { var t = inp.value.trim(); if (!t) return; var ex = Array.prototype.filter.call(sel.options, function (x) { return x.value.toLowerCase() === t.toLowerCase(); })[0]; if (!ex) { ex = new Option(t, t); ex.setAttribute("data-added", "1"); sel.appendChild(ex); all = items(sel); } o = ex; }
      if (!o || o.disabled) return;
      if (multi) { if (o.value === "") chosen = {}; else if (chosen[o.value]) delete chosen[o.value]; else chosen[o.value] = 1; apply(); draw(); inp.focus(); }
      else { if (mm || nat) { chosen = {}; if (o.value) chosen[o.value] = 1; apply(); } else { sel.value = o.value; fire(sel); } close(); sel.focus(); }
    }
    inp.addEventListener("input", function () { hi = 0; draw(); });
    inp.addEventListener("keydown", function (e) {
      var n = list.querySelectorAll(".ko").length;
      if (e.key === "ArrowDown") { hi = Math.min(n - 1, hi + 1); mark(); e.preventDefault(); }
      else if (e.key === "ArrowUp") { hi = Math.max(0, hi - 1); mark(); e.preventDefault(); }
      else if (e.key === "Enter") { e.preventDefault(); var el = list.querySelectorAll(".ko")[hi]; if (el) { if (el.dataset.i === "add") pick(null, true); else pick(vis[+el.dataset.i]); } }
      else if (e.key === "Escape") { e.preventDefault(); var s = sel; close(); s.focus(); }
      else if (e.key === "Tab") { close(); }
    });
    list.addEventListener("mousedown", function (e) { e.preventDefault(); });
    list.addEventListener("click", function (e) { var el = e.target.closest(".ko"); if (!el) return; if (el.dataset.i === "add") pick(null, true); else pick(vis[+el.dataset.i]); });
    var km = pop.querySelector(".km"); if (km) km.addEventListener("change", function () { multi = km.checked; if (!multi && Object.keys(chosen).length > 1) { var f = Object.keys(chosen)[0]; chosen = {}; chosen[f] = 1; apply(); } draw(); inp.focus(); });
    pop.querySelector(".kok").addEventListener("click", function () { var s = sel; close(); s.focus(); });
    pop.querySelector(".kc").addEventListener("click", function () { chosen = {}; apply(); draw(); inp.focus(); });
    draw(); var first = list.querySelector(".ko.on"); if (first && !multi) { hi = Array.prototype.indexOf.call(list.querySelectorAll(".ko"), first); mark(); }
    setTimeout(function () { try { inp.focus({ preventScroll: true }); } catch (x) { inp.focus(); } }, 0);
  }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  var lastOpen = 0;
  document.addEventListener("mousedown", function (e) {
    var t = e.target; if (pop && !t.closest(".kmr-sp") && t !== cur) close();
    if (e.button !== 0) return; var sel = t.closest && t.closest("select"); if (ok(sel)) { e.preventDefault(); lastOpen = Date.now(); open(sel); }
  }, true);
  document.addEventListener("click", function (e) { var sel = e.target.closest && e.target.closest("select"); if (ok(sel)) { e.preventDefault(); if (!pop && Date.now() - lastOpen > 600) open(sel); } }, true);
  document.addEventListener("keydown", function (e) {
    var sel = e.target; if (!ok(sel) || pop) return;
    if (e.key === "Enter" || e.key === " " || e.key === "F4" || (e.altKey && (e.key === "ArrowDown" || e.key === "ArrowUp"))) { e.preventDefault(); open(sel); }
  }, true);
  window.addEventListener("resize", function () { if (pop && window.innerWidth !== openW) close(); });   /* keyboard opening only changes height - keep the list open */
  window.addEventListener("scroll", function (e) { if (!pop) return; var t = e.target; if (t && t.closest && t.closest(".kmr-sp")) return; if (t === document || t === window || t === document.documentElement) return; close(); }, true);
  window.KMRSelect = { open: open, close: close };
})();
