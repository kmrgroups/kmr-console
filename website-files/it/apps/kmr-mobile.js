/* KMR phone and tablet hardening (Android, iPhone, iPad, desktop):
   - inputs are 16 px on touch screens so iPhone does not zoom in when you tap a box
   - buttons and boxes are big enough to tap; no 300 ms tap delay; safe areas for the notch and the home bar
   - pop-up boxes fit the visible screen (keyboard open too) and stop the page behind from scrolling
   - KMRDlg.yes(text) and KMRDlg.ask(text) replace the browser's confirm() and prompt(), which Android web views and iPhone home-screen apps block */
(function () {
  if (window.KMRDlg) return;
  var css = `
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{-webkit-tap-highlight-color:rgba(124,58,237,.12);overscroll-behavior-y:none}
button,a.tab,.btn,select,input[type=checkbox],input[type=radio],label{touch-action:manipulation}
header{padding-top:max(12px,env(safe-area-inset-top))!important;padding-left:max(18px,env(safe-area-inset-left))!important;padding-right:max(18px,env(safe-area-inset-right))!important}
.back{bottom:calc(12px + env(safe-area-inset-bottom))!important;left:calc(12px + env(safe-area-inset-left))!important}
input[type=date],input[type=month],input[type=time],input[type=datetime-local]{min-height:38px;-webkit-appearance:none;appearance:none}
.tabs{-webkit-overflow-scrolling:touch;scrollbar-width:thin}
.modal{overscroll-behavior:contain;padding:max(10px,env(safe-area-inset-top)) max(10px,env(safe-area-inset-right)) max(10px,env(safe-area-inset-bottom)) max(10px,env(safe-area-inset-left))!important}
.modal .in{max-height:calc(100vh - 24px);max-height:calc(100dvh - 24px);-webkit-overflow-scrolling:touch;overscroll-behavior:contain}
.panel{-webkit-overflow-scrolling:touch}
body.kmr-lock{overflow:hidden;position:fixed;width:100%}
@media(pointer:coarse){
  .btn,button,select,.tab{min-height:42px}.btn.sm,.sm{min-height:36px;padding:7px 12px!important}
  input:not([type=checkbox]):not([type=radio]),select,textarea{min-height:42px}
  input[type=checkbox],input[type=radio]{width:22px;height:22px}
}
@media(max-width:820px){
  input,select,textarea{font-size:16px!important}
  header h1{font-size:16px}.panel{padding:12px;border-radius:0 0 12px 12px}main{padding:0 8px!important}
  .frm{grid-template-columns:1fr!important}.row{gap:8px}.row input,.row select{width:100%!important;flex:1 1 140px}
  .kpis{grid-template-columns:repeat(2,1fr)!important}
  .modal{align-items:flex-end!important;padding:0!important}.modal .in{width:100%!important;max-height:94vh;max-height:94dvh;border-radius:16px 16px 0 0!important;padding-bottom:max(16px,env(safe-area-inset-bottom))!important}
}
.kdlg{position:fixed;inset:0;z-index:100000;background:#0009;display:flex;align-items:center;justify-content:center;padding:14px}
.kdlg .b{background:var(--card,#fff);color:var(--ink,#0f172a);border-radius:14px;max-width:420px;width:100%;padding:18px;box-shadow:0 10px 40px #0006}
.kdlg p{margin:0 0 12px;white-space:pre-wrap;line-height:1.45}.kdlg textarea,.kdlg input{width:100%;margin-bottom:12px;font-size:16px}
.kdlg .acts{display:flex;gap:10px;justify-content:flex-end}.kdlg .acts button{min-width:90px;min-height:44px;border-radius:10px;font-weight:700;border:0;padding:0 16px;cursor:pointer}
.kdlg .acts .ok{background:linear-gradient(90deg,var(--b1,#0ea5e9),var(--b2,#7c3aed));color:#fff}.kdlg .acts .no{background:none;border:1px solid var(--b2,#7c3aed);color:var(--b2,#7c3aed)}`;
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  // lock the page behind any open pop-up box
  function watch() {
    var m = document.querySelectorAll(".modal"), any = false;
    for (var i = 0; i < m.length; i++) if (m[i].classList.contains("on") || (m[i].offsetParent !== null && getComputedStyle(m[i]).display !== "none")) any = true;
    if (any && !document.body.classList.contains("kmr-lock")) { window.__kmrY = window.scrollY; document.body.style.top = -window.__kmrY + "px"; document.body.classList.add("kmr-lock"); }
    if (!any && document.body.classList.contains("kmr-lock")) { document.body.classList.remove("kmr-lock"); document.body.style.top = ""; window.scrollTo(0, window.__kmrY || 0); }
  }
  new MutationObserver(watch).observe(document.documentElement, { attributes: true, subtree: true, attributeFilter: ["class", "style"] });
  function dlg(text, ask, def) {
    return new Promise(function (res) {
      var d = document.createElement("div"); d.className = "kdlg"; d.setAttribute("role", "dialog");
      d.innerHTML = '<div class="b"><p></p>' + (ask ? '<textarea rows="3"></textarea>' : "") + '<div class="acts"><button class="no" type="button">Cancel</button><button class="ok" type="button">OK</button></div></div>';
      d.querySelector("p").textContent = text; var f = d.querySelector("textarea"); if (f) f.value = def || "";
      function done(v) { document.removeEventListener("keydown", key, true); d.remove(); res(v); }
      function key(e) { if (e.key === "Escape") { e.stopPropagation(); done(ask ? null : false); } else if (e.key === "Enter" && !ask) { e.preventDefault(); done(true); } }
      d.querySelector(".ok").onclick = function () { done(ask ? f.value : true); };
      d.querySelector(".no").onclick = function () { done(ask ? null : false); };
      document.addEventListener("keydown", key, true); document.body.appendChild(d); (f || d.querySelector(".ok")).focus();
    });
  }
  window.KMRDlg = { yes: function (t) { return dlg(t, false); }, ask: function (t, def) { return dlg(t, true, def); } };
})();
