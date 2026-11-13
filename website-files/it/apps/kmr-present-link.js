/* Adds the "Presentation" screen link to every KMR app (the screen itself is /it/present.html, one shared engine). */
(function () {
  "use strict";
  var MAP = { sales: "sales", calibration: "calibration", apqp: "apqp", ppap: "ppap", rmp: "rmp", mmd: "mmd", mnt: "mnt", msa: "msa", crm: "crm", d8: "d8", office: "off", aud: "aud", spc: "spc", tasks: "tsk", mom: "mom", cad: "cad", dwm: "dwm" };
  var m = location.pathname.match(/\/it\/([a-z0-9]+)\.html/), key = m && MAP[m[1]];
  if (!key || /[?&]demo=1(&|$)/.test(location.search) || /[?&]scope=all(&|$)/.test(location.search)) return;   // the all-plants Sales Flow has its own Presentation tab
  function add() {
    if (document.getElementById("kp-link")) return true;
    var slug = (window.QP && QP.slug) || new URLSearchParams(location.search).get("co"); if (!slug) return false;
    var href = "/it/present.html?app=" + key + "&kmr=1&co=" + encodeURIComponent(slug), tabs = document.querySelector(".tabs"), a = document.createElement("a");
    a.id = "kp-link"; a.href = href;
    a.addEventListener("click", function (e) {
      e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
      try {   // remember this app's tabs so the Presentation page can show them and lead back
        var list = [].slice.call(document.querySelectorAll(".tabs a.tab, .tabs button, .tabs .tab")).filter(function (x) { return x.id !== "kp-link" && !x.hidden && x.offsetParent !== null; }).map(function (x) { var k = x.dataset.t || x.dataset.tab || x.dataset.go || x.dataset.k || ""; return k ? { t: k, label: (x.textContent || "").trim() } : null; }).filter(Boolean);
        sessionStorage.setItem("kmr_tabs_" + key, JSON.stringify({ url: location.pathname + location.search, tabs: list }));
      } catch (er) {}
      location.href = href;
    }, true);
    if (tabs) { a.className = "tab"; a.textContent = "Presentation"; tabs.appendChild(a); }
    else { a.textContent = "Presentation"; a.style.cssText = "position:fixed;right:14px;bottom:40px;z-index:8990;background:#1e3a8a;color:#fff;padding:7px 14px;border-radius:999px;font:600 13px 'Segoe UI',Arial;text-decoration:none;box-shadow:0 2px 10px #0004"; document.body.appendChild(a); }
    return true;
  }
  // coming back from the Presentation page with #go=<tab>: open that tab if the app did not already do it
  (function () {
    var g = (location.hash.match(/[#&]go=([A-Za-z0-9_-]+)/) || [])[1]; if (!g) return; var tries = 0;
    var h = setInterval(function () {
      var el = document.querySelector('.tabs [data-t="' + g + '"],.tabs [data-tab="' + g + '"],.tabs [data-go="' + g + '"],.tabs [data-k="' + g + '"]');
      if (el && el.offsetParent !== null) { if (!/\b(on|active)\b/.test(el.className) && el.getAttribute("aria-selected") !== "true") el.click(); if (++tries > 3) clearInterval(h); }
      else if (++tries > 20) clearInterval(h);
    }, 700);
  })();
  var n = 0, t = setInterval(function () { if (add() || ++n > 40) clearInterval(t); }, 500);
})();
