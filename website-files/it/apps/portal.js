/* KMR Apps portal — one link per customer (www.kmr-groups.com/it/app/<customer>).
   Signed-in people see the apps their company bought (Console licences) and can open them; the others can be
   tried with sample data only, with a Buy subscription link. The same KMR login works in every app. */
(function () {
  "use strict";
  const C = window.COMPANY_CONFIG || {};
  const sb = window.supabase.createClient(C.supabaseUrl, C.supabaseAnonKey);
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const m = location.pathname.match(/\/it\/app\/([a-z0-9-]{2,61})/i) || location.search.match(/[?&]c=([a-z0-9-]{2,61})/i);
  const SLUG = m && !/^(undefined|null)$/i.test(m[1]) ? m[1].toLowerCase() : "";
  const OPEN = (location.search.match(/[?&]open=([a-z0-9-]+)/i) || [])[1] || "";   // a tool sent the person here to sign in
  const HASH = location.hash.replace(/^#/, "");                                      // the screen this address points at (#ops, #users …)
  /* Every menu item is a real link, so right-click › Open in new tab / new window works and opens that exact screen.
     A normal left click still switches screen in place (no reload); ctrl / ⌘ / shift / middle-click follow the link. */
  const BASE = location.pathname + (/\/it\/app\//.test(location.pathname) || !SLUG ? "" : "?c=" + SLUG);
  const appHref = (code) => BASE + (BASE.includes("?") ? "&" : "?") + "open=" + encodeURIComponent(code);
  const viewHref = (v) => BASE + (v ? "#" + v : "");
  const plain = (e) => e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey;
  const setView = (v) => { try { history.replaceState(null, "", viewHref(v)); } catch (e) { /* ignore */ } };
  const onLink = (sel, fn) => document.querySelectorAll(sel).forEach((el) => el.addEventListener("click", (e) => { if (!plain(e)) return; e.preventDefault(); fn(el, e); }));
  const META = {
    msa: { color: "#0F766E", desc: "Prove your gauges before you trust the numbers: Gage R&R (range and ANOVA), bias, linearity, stability and attribute agreement, with a clear decision and a register of every study.", demo: "/it/msa.html?demo=1" },
    qms: { color: "#0F766E", desc: "Learn ISO 9001, IATF 16949, VDA 6.3, the Control Plan and the core tools (APQP, PPAP, FMEA, MSA, SPC) clause by clause in plain words, and present them on a big screen for training: what each requirement means, how to implement it, which documents and records to keep, and a filled-in example. Shows which clauses the KMR apps already cover.", demo: "/it/qms.html?demo=1" },
    d8: { color: "#B91C1C", desc: "Solve a customer complaint or an internal rejection step by step, D0 to D8: team, problem, containment, root causes, corrective actions, prevention and a printed 8D report. A step is ticked only when its proof is there.", demo: "/it/d8.html?demo=1" },
    off: { color: "#4F46E5", desc: "Write documents, build spreadsheets and make presentations in the browser, saved to your company with a revision every time. Procedures, work instructions, minutes and letters start from ready templates. Open Word, Excel and PowerPoint files and download your work in those formats; printouts carry your logo and a reference number.", demo: "/it/office.html?demo=1" },
    aud: { color: "#0F766E", desc: "Plan the year of audits and run them: system, process (VDA 6.3 style score), product and supplier. Rate a checklist, record findings, give each one an action with owner and date, check it worked, and print the audit report. The auditor cannot audit their own work.", demo: "/it/aud.html?demo=1" },
    crm: { color: "#BE185D", desc: "From the first enquiry to a priced, numbered quotation: leads and follow-ups, customers and suppliers, RFQs with a costing sheet that works out the price, supplier prices side by side, and quotations with revisions.", demo: "/it/crm.html?demo=1" },
    spc: { color: "#0891B2", desc: "Control charts from the readings you type or paste in: X̄-R, X̄-S, I-MR, p, np, c and u, with signals explained, cause and action notes, and Cp / Cpk / Pp / Ppk.", demo: "/it/spc.html?demo=1" },
    tsk: { color: "#4F46E5", desc: "Assign tasks to people with a due date and priority, follow them to done, and get a message on your phone or computer. Create tasks straight from Minutes of Meetings and Sales Flow.", demo: "/it/tasks.html?demo=1" },
    hrms: { color: "#0D9488", desc: "Employees, attendance by hand or from fingerprint and face machines, shifts, leave and payroll that works itself out each month — PF, ESI, professional tax, overtime, payslips and bank file.", demo: "/it/hrm.html?demo=1" },
    balloon: { color: "#A855F7", desc: "Balloon any drawing and build the inspection report.", demo: "/it/balloon.html?demo=1" },
    pd: { color: "#F59E0B", desc: "PFD, PFMEA, Control Plan, SOP, SPC, MSA and reports from the ballooned drawing.", demo: "/it/pd.html?demo=1&sample=1" },
    capacity: { color: "#10B981", desc: "Capacity plan, takt time and machine loading for every plant, with version history.", demo: "/it/capacity.html?demo=1" },
    sales: { color: "#E11D48", desc: "Monthly sales plan vs actual despatch, daily tracking, loss reasons and action plans.", demo: "/it/sales.html?demo=1" },
    apqp: { color: "#0891B2", desc: "Plan every new part through the five APQP phases — deliverables, owners, due dates and gates, linked to your other apps.", demo: "/it/apqp.html?demo=1" },
    ppap: { color: "#B45309", desc: "Assemble the PPAP package and the Part Submission Warrant from the drawings, FMEA and control plans you already have.", demo: "/it/ppap.html?demo=1" },
    cad: { color: "#0369A1", desc: "Draw 2D engineering drawings the AutoCAD way — command line, snaps, layers, dimensions, hatches, blocks, title blocks, DXF in and out, print to PDF, with revision control.", demo: "/it/cad.html?demo=1" },
    mom: { color: "#7C3AED", desc: "Record every meeting by voice or typing, in Indian and international languages; one click turns the text into points; translate them and follow up the actions.", demo: "/it/mom.html?demo=1" },
    mnt: { color: "#EA580C", desc: "Log every breakdown with root cause and action, track MTBF, MTTR and downtime, plan preventive maintenance and print the machine history card.", demo: "/it/mnt.html?demo=1" },
    mmd: { color: "#2563EB", desc: "Issue raw material with QR tags, follow every part machine by machine to finished goods, run supplier DC and GRN, and see rejection, rework and loss hours.", demo: "/it/mmd.html?demo=1" },
    rmp: { color: "#0D9488", desc: "Turn the capacity plan into kilograms of raw material, compare with stock, and plan MOQ-rounded supplier orders with lead times.", demo: "/it/rmp.html?demo=1" },
    calib: { color: "#6366F1", desc: "Instrument register, calibration due control, gauge history, MSA and out-of-tolerance cases.", demo: "/it/calibration.html?demo=1" },
    inv: { color: "#0D9488", desc: "Make the GST tax invoice from the Operations Master, then get the e-invoice and e-way bill files for the government portals and the sales vouchers for Tally." },
    connect: { color: "#0891B2", desc: "See and control your laptops and PCs from any browser or phone (screen, mouse, keyboard, files, programs), meet online with Teams or Google Meet links, record the meeting and get minutes in your language." },
    dcg: { color: "#D97706", desc: "Make delivery challans (returnable and non-returnable) and Goods Receipt Notes against the challan and the purchase order. Calibration gauges go out on a returnable challan and are calibrated on the GRN." },
    dwm: { color: "#174B80", desc: "The Plant Head\u2019s monthly Daily Work Management sheet: every review planned by day, marked Completed, Missed or Concession, with adherence against the 98% target, review standards and Executive Director reporting.", demo: "/it/dwm.html?demo=1" },
    layout: { color: "#7C3AED", desc: "1:1 metric scale factory machine shop and office layout generator — converts line concepts into lean cellular layouts with DXF export.", demo: "/it/layout.html?demo=1" },
  };
  const SOON = [["ppc", "Production Planning & Control (full MES)"], ["qms", "QMS"], ["proc", "Procurement"], ["wms", "Warehouse Management"], ["8d", "8D Problem Solving"], ["audit", "IATF / ISO / VDA 6.3 audits"]];
  let brand = { name: "KMR Apps", logo_url: null }, rows = [], user = null, stats = {}, isAdmin = false, view = "home", ops = null, media = {}, plants = [], THEME = "";

  /** top of an app card: the app photo set in Website CMS (or the built-in illustration) — never a video: videos are for the public website only */
  const ART = { hrms: 1, balloon: 1, pd: 1, capacity: 1, sales: 1, calib: 1, apqp: 1, ppap: 1, rmp: 1, mmd: 1, mnt: 1, bud: 1, ppl: 1, mlp: 1, mom: 1, cad: 1, tsk: 1, msa: 1, spc: 1, crm: 1, d8: 1, qms: 1, aud: 1, off: 1, layout: 1, dwm: 1, dcg: 1, inv: 1, connect: 1, pnl: 1, bud: 1 };
  const safeUrl = (u) => (/^(https:\/\/|\/)/.test(u || "") ? String(u).replace(/["<>]/g, "") : "");
  function mediaHtml(r) {
    const m = media[r.product_code] || {}, img = safeUrl(m.img) || (ART[r.product_code] ? `/img/kmr/app-${r.product_code}.svg` : "");
    return img ? `<div class="media"><img src="${img}" alt="" loading="lazy"></div>` : "";
  }

  const logo = (b, cls) => b.logo_url ? `<img src="${esc(b.logo_url)}" alt="${esc(b.name)}">` : `<span class="fb ${cls || ""}">${esc((b.name || "K").split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase())}</span>`;
  function setIcon(url) {
    if (!url) return;
    document.querySelectorAll('link[rel~="icon"]').forEach((l) => l.remove());
    const ic = document.createElement("link"); ic.rel = "icon"; ic.href = url; document.head.append(ic);
  }
  const buyUrl = (code) => `/it/?buy=${encodeURIComponent(code)}${SLUG ? "&c=" + SLUG : ""}#pilot`;

  function dialog(title, body, actions) {
    const v = document.createElement("div"); v.className = "veil";
    v.innerHTML = `<div class="dlg" role="dialog" aria-modal="true"><h3>${esc(title)}</h3><p>${body}</p><div class="row">${actions}<button class="btn ghost" data-close>Close</button></div></div>`;
    v.addEventListener("click", (e) => { if (e.target === v || e.target.hasAttribute("data-close")) v.remove(); });
    document.body.append(v);
  }

  // Digital records notice: shown once after each sign-in; can be reopened from the menu
  function digitalNotice() {
    dialog("Digital records and documents",
      "Documents and records in KMR Apps are kept as controlled electronic records. ISO 9001:2015 (7.5.2, 7.5.3) and IATF 16949:2016 do not require paper or handwritten shopfloor records when the documented-information controls, retention rules and customer-specific requirements are met; VDA 6.3 assesses process evidence, not the medium.<br><br><small>Interpretive briefing, not a certification-body ruling. Please check your customers' specific requirements before retiring any paper record.</small>",
      '<a class="btn" href="/it/digital-records.html" target="_blank" rel="noopener">Open full details</a>');
  }

  function loginView(note) {
    $("#root").innerHTML = `<div class="split">
      <section class="vis" id="vis" aria-hidden="true"><div class="aur"><i></i><i></i><i></i><i></i></div><canvas></canvas>
        <div class="chip"><b>K</b>KMR Apps</div>
        <div class="cap"><h2>Agentic AI · <em>Intelligent Digital Manufacturing Systems</em></h2><p>HR, quality, planning and plant operations — one sign-in, one platform.</p></div></section>
      <section class="panel"><div class="form">
        <div class="co">${logo(brand)}<div>${esc(brand.name)}<small>${SLUG ? "Your KMR apps" : "KMR Group of Companies"}</small></div></div>
        <h1>Welcome</h1><p class="sub">Sign in once — the same login opens every app your company uses.</p>
        <form id="lf">
          <label class="f">Email<div class="in"><input name="email" type="email" autocomplete="username" required></div></label>
          <label class="f">Password<div class="in"><input name="password" type="password" autocomplete="current-password" required><button type="button" class="eye" aria-label="Show password">👁</button></div></label>
          <div class="msg" id="lm">${esc(note || "")}</div>
          <button class="btn block" type="submit">Sign in</button>
        </form>
        <div class="links"><button id="forgot" type="button">Forgot password? Email me a sign-in link</button></div>
      </div></section></div>`;
    window.KMR_SCENE && window.KMR_SCENE($("#vis"));
    const f = $("#lf"), msg = $("#lm");
    f.querySelector(".eye").onclick = () => { const i = f.password; i.type = i.type === "password" ? "text" : "password"; };
    f.onsubmit = async (e) => {
      e.preventDefault(); msg.className = "msg"; msg.textContent = "Signing in…";
      const { error } = await sb.auth.signInWithPassword({ email: f.email.value.trim(), password: f.password.value });
      if (error) { msg.textContent = /Invalid login/i.test(error.message) ? "Wrong email or password." : error.message; return; }
      start();
    };
    $("#forgot").onclick = async () => {
      const email = f.email.value.trim(); if (!email) { msg.textContent = "Enter your email first."; return; }
      const { error } = await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: false, emailRedirectTo: location.href } });
      msg.className = error ? "msg" : "msg ok"; msg.textContent = error ? "Could not send the link. Please try again in a minute." : `If ${email} has a KMR login, a sign-in link is on its way.`;
    };
  }

  async function open(code) {
    const r = rows.find((x) => x.product_code === code);
    if (r && r.purchased && !r.ok) return dialog(`${r.product_name} is ${esc(r.status || "paused")}`, "This app is switched off for this plant, so your data is not opened. Ask KMR to switch it on.", `<a class="btn" href="${buyUrl(code)}">Contact KMR</a>`);
    if (!r || !r.purchased || !r.ok) {
      const meta = META[code];
      if (!DEV) return dialog(`${r ? r.product_name : code}`, "This app is not in your company's plan. Contact KMR to enable it.", `<a class="btn" href="${buyUrl(code)}">Contact KMR</a>`);
      if (!meta) return dialog(`${r ? r.product_name : code} — sample data`, "The sample-data version of this app is not available yet. Ask KMR for a demo.", `<a class="btn" href="${buyUrl(code)}">Contact KMR</a>`);
      location.href = meta.demo + (meta.demo.includes("?") ? "&" : "?") + "from=" + encodeURIComponent(SLUG);
      return;
    }
    remember(code);
    if (!r.has_access) {
      if (!r.is_contact && !isAdmin) return dialog(`No access to ${r.product_name}`, "Your company has this app, but you have not been given access to it. Your company administrator can add it under Administration › Users & access.", "");
      const j = await sb.rpc("kmr_portal_join", { p_slug: SLUG, p_product: code });
      if (j.error) return dialog(`Could not open ${r.product_name}`, esc(j.error.message), "");
      r.has_access = true;
    }
    let path = r.app_path;
    try { const back = sessionStorage.getItem("kmr-return-" + code); sessionStorage.removeItem("kmr-return-" + code);
      if (back && back.split(/[?#]/)[0] === r.app_path.split("?")[0]) path = back; } catch (e) {}
    let tail = ""; const hi = path.indexOf("#"); if (hi >= 0) { tail = path.slice(hi); path = path.slice(0, hi); }   // the screen (#go=…) stays at the end
    path = path.replace(/([?&])co=[^&]*&?/, "$1").replace(/[?&]$/, "");
    location.href = path + (path.includes("?") ? "&" : "?") + "kmr=1" + (SLUG ? "&co=" + encodeURIComponent(SLUG) : "") + tail;
  }

  const GROUPS = [["Quality & engineering", "#7C3AED", ["cad", "balloon", "pd", "apqp", "ppap", "calib", "msa", "spc", "d8", "aud", "qms"]], ["Planning & production", "#10B981", ["capacity", "sales", "crm", "rmp", "mmd", "dcg", "inv", "pnl", "bud", "ppl", "mlp", "mnt"]], ["People & meetings", "#0EA5E9", ["hrms", "mom", "connect", "tsk", "off", "dwm"]]];
  function imgOf(r) { const m = media[r.product_code] || {}; return safeUrl(m.img) || (ART[r.product_code] ? `/img/kmr/app-${r.product_code}.svg` : ""); }
  function tile(r, locked) {
    const m = META[r.product_code] || {}, im = imgOf(r), st = stats[r.product_code] || {};
    const noAcc = !locked && r.ok && !r.has_access && !r.is_contact && !isAdmin;
    const bad = Object.entries(st).find(([k, v]) => /overdue|open|due/i.test(k) && Number(v) > 0);
    const sub = locked ? (DEV ? "Try with sample data" : "Not in your plan") : !r.ok ? esc(r.status || "Paused") : noAcc ? "Ask your administrator" : (r.valid_until ? "Trial · until " + esc(r.valid_until) : esc(r.status || "Active"));
    const inner = `${bad ? `<b class="bd">${esc(bad[1])} ${esc(bad[0])}</b>` : ""}<span class="ic">${im ? `<img src="${im}" alt="" loading="lazy">` : esc((r.product_name || "?")[0])}</span><h3>${esc(r.product_name)}</h3><small class="${locked || !r.ok ? "dim" : noAcc ? "dim" : "on"}">${sub}</small>`;
    const nm = esc(String(r.product_name || "").toLowerCase()), tip = esc((m.desc || "") + (Object.keys(st).length ? "  ·  " + Object.entries(st).map(([k, v]) => v + " " + k).join(", ") : ""));
    return noAcc ? `<div class="tile off" title="${tip}" data-name="${nm}" style="--c:${m.color}">${inner}</div>` : `<a class="tile${locked ? " lk" : ""}" title="${tip}" href="${appHref(r.product_code)}" data-open="${r.product_code}" data-name="${nm}" style="--c:${m.color}">${inner}</a>`;
  }
  /* Home-screen themes (apps/portal-themes.js). Theme "a" is the standard launcher below; a theme is chosen per customer in the Console. */
  const recentKey = () => "kmr-recent-" + (SLUG || "all");
  const recent = () => { try { return JSON.parse(localStorage.getItem(recentKey()) || "[]"); } catch (e) { return []; } };
  const remember = (code) => { try { localStorage.setItem(recentKey(), JSON.stringify([code].concat(recent().filter((x) => x !== code)).slice(0, 6))); } catch (e) { /* ignore */ } };
  function themeCtx(mine, others) {
    const sub = (r) => !r.ok ? (r.status || "Paused") : (r.valid_until ? "Trial · until " + r.valid_until : (r.status || "Active"));
    const link = (r, cls, inner, locked) => {
      const m = META[r.product_code] || {}, noAcc = !locked && r.ok && !r.has_access && !r.is_contact && !isAdmin;
      const nm = esc(String(r.product_name || "").toLowerCase()), tip = esc(m.desc || "");
      return noAcc ? `<div class="${cls} off" title="${tip}" data-name="${nm}" style="--c:${m.color}">${inner}</div>`
        : `<a class="${cls}${locked ? " lk" : ""}" title="${tip}" href="${appHref(r.product_code)}" data-open="${r.product_code}" data-name="${nm}" style="--c:${m.color}">${inner}</a>`;
    };
    const known = GROUPS.flatMap((g) => g[2]), rest = mine.filter((r) => !known.includes(r.product_code));
    const groups = GROUPS.map(([name, color, codes]) => ({ name, color, items: mine.filter((r) => codes.includes(r.product_code)) })).concat(rest.length ? [{ name: "Other apps", color: "#64748B", items: rest }] : []).filter((g) => g.items.length);
    return { mine, others, groups, plants, isAdmin, ops, stats, brand, user, esc, META, imgOf, appHref, viewHref, sub, link, recent, logoHtml: logo(brand) };
  }
  function appView() {
    window.scrollTo(0, 0); setView("");
    const mine = rows.filter((r) => r.purchased), others = rows.filter((r) => !r.purchased);
    const pill = (r) => r.ok ? `<span class="pill ok">${esc(r.status)}${r.valid_until ? " · until " + esc(r.valid_until) : ""}</span>` : `<span class="pill warn">${esc(r.status)}</span>`;
    const TH = THEME && THEME !== "a" && window.KMR_THEMES && window.KMR_THEMES[THEME] ? window.KMR_THEMES[THEME] : null;
    $("#root").innerHTML = `<div class="app${TH && TH.full ? " nosb" : ""}">
      <aside class="side">
        <a class="who" href="${viewHref("")}" title="Your apps">${logo(brand)}<div><b>${esc(brand.name)}</b><small>${esc(user.email)}</small></div></a>
        ${plants.length > 1 ? `<label style="display:block;padding:6px 10px"><small style="display:block;opacity:.7;margin-bottom:3px">Plant</small><select id="plantSel" style="width:100%;padding:6px;border-radius:8px">${plants.map((x) => `<option value="${esc(x.slug)}"${x.slug === SLUG ? " selected" : ""}>${esc(x.is_main ? "Main · " + x.name : x.plant_code + " · " + x.name.split(" – ").pop())}</option>`).join("")}${plants[0].is_all ? `<option value="__all"${view === "plants" ? " selected" : ""}>★ All plants · dashboard</option>` : ""}</select></label>` : ""}
        <h4>Your apps</h4>${mine.map((r) => `<a href="${appHref(r.product_code)}" data-open="${r.product_code}"><i style="background:${META[r.product_code]?.color || "#999"}"></i>${esc(r.product_name)}${r.ok ? "" : '<span class="lock">Paused</span>'}</a>`).join("") || `<small style="padding:0 10px;opacity:.6">No apps yet</small>`}
        ${ops || isAdmin ? `<h4>Masters</h4>` : ""}${ops ? `<a href="${viewHref("ops")}" data-ops="1"><i style="background:#0EA5E9"></i>Operations Master</a>` : ""}${isAdmin ? `<a href="${viewHref("data")}" data-datam="1"><i style="background:#0EA5E9"></i>Data Master</a><a href="${viewHref("grand")}" data-grand="1"><i style="background:#B45309"></i>Grand Master</a>` : ""}
        ${isAdmin ? `<h4>Administration</h4><a href="${viewHref("company")}" data-admin="company"><i style="background:#F3C55A"></i>Company details &amp; logo</a><a href="${viewHref("users")}" data-admin="users"><i style="background:#F3C55A"></i>Users &amp; access</a><a href="${viewHref("digest")}" data-admin="digest"><i style="background:#F3C55A"></i>Daily management mail</a><a href="${viewHref("wa")}" data-admin="wa"><i style="background:#F3C55A"></i>WhatsApp evening report</a><a href="${viewHref("finance")}" data-admin="finance"><i style="background:#F3C55A"></i>Finance mail (top management)</a><a href="${viewHref("backup")}" data-admin="backup"><i style="background:#F3C55A"></i>Daily backup mail</a><a href="${viewHref("invoices")}" data-admin="invoices"><i style="background:#F3C55A"></i>Invoices &amp; payments</a>` : ""}
        <h4>More KMR apps</h4>${others.map((r) => `<a href="${appHref(r.product_code)}" data-open="${r.product_code}"><i style="background:${META[r.product_code]?.color || "#999"}"></i>${esc(r.product_name)}<span class="lock">Try</span></a>`).join("")}
        ${SOON.map(([k, n]) => `<button data-soon="${k}" data-name="${esc(n)}"><i style="background:#64748b"></i>${esc(n)}<span class="lock">Soon</span></button>`).join("")}
        <a href="/it/digital-records.html" id="drn" target="_blank" rel="noopener"><i style="background:#14B8A6"></i>Digital records notice</a>
        <button id="pw">Change password</button>
        <button class="out" id="out">Sign out</button>
      </aside>
      <main class="main${TH ? " th th-" + THEME + (TH.full ? " th-full" : "") : ""}">${TH ? TH.html(themeCtx(mine, others)) : `
        <header class="hero"><div><h1>Welcome back</h1><p class="sub">Open any app your company uses. The same login works everywhere.</p></div>
          <label class="find"><input id="appFind" type="search" placeholder="Find an app…" autocomplete="off"></label></header>
        <div class="chips"><span><b>${mine.length}</b> apps in your plan</span>${plants.length > 1 ? `<span><b>${plants.length}</b> plants</span>` : ""}${isAdmin ? "<span>Administrator</span>" : ""}</div>
        ${GROUPS.map(([gname, gcolor, codes]) => { const gm = mine.filter((r) => codes.includes(r.product_code)); return gm.length ? `<section class="grp" style="--g:${gcolor}"><h2><i></i>${gname}<small>${gm.length}</small></h2><div class="tiles">${gm.map((r) => tile(r)).join("")}</div></section>` : ""; }).join("")}
        ${(() => { const known = GROUPS.flatMap((g) => g[2]); const rest = mine.filter((r) => !known.includes(r.product_code)); return rest.length ? `<section class="grp" style="--g:#64748B"><h2><i></i>Other apps<small>${rest.length}</small></h2><div class="tiles">${rest.map((r) => tile(r)).join("")}</div></section>` : ""; })()}
        ${ops || isAdmin ? `<section class="grp" style="--g:#0EA5E9"><h2><i></i>Masters<small>${(ops ? 1 : 0) + (isAdmin ? 2 : 0)}</small></h2><div class="tiles">
          ${ops ? `<a class="tile mini" href="${viewHref("ops")}" data-ops="1" data-name="operations master" style="--c:#0EA5E9"><span class="ic">⚙</span><h3>Operations Master</h3><small class="on">Open</small></a>` : ""}
          ${isAdmin ? `<a class="tile mini" href="${viewHref("data")}" data-datam="1" data-name="data master" style="--c:#0EA5E9"><span class="ic">🗄</span><h3>Data Master</h3><small class="on">Open</small></a><a class="tile mini" href="${viewHref("grand")}" data-grand="1" data-name="grand master" style="--c:#B45309"><span class="ic">★</span><h3>Grand Master</h3><small class="on">Open</small></a>` : ""}</div></section>` : ""}
        ${others.length ? `<section class="grp" style="--g:#94A3B8"><h2><i></i>Try more of the platform<small>${others.length}</small></h2><div class="tiles">${others.map((r) => tile(r, true)).join("")}</div></section>` : ""}`}
      </main></div>`;
    if (TH && TH.bind) TH.bind(themeCtx(mine, others), document.querySelector(".main"));
    { const t = $("#sbToggle"), ap = document.querySelector(".app"); if (t) { t.onclick = (e) => { e.stopPropagation(); ap.classList.toggle("sb"); }; document.querySelector(".main").addEventListener("click", () => ap.classList.remove("sb")); } }
    onLink("[data-home]", () => appView());
    { const f = $("#appFind"); if (f) f.oninput = () => { const q = f.value.toLowerCase().trim(), mn = document.querySelector(".main");
      if (q && TH) { const all = mn.querySelector('.tabs [data-t=""]'); if (all && !all.classList.contains("on")) all.click(); }
      mn.querySelectorAll("[data-name]").forEach((t) => { if (t.closest(".tb")) return; t.style.display = !q || (t.dataset.name + " " + t.textContent.toLowerCase()).includes(q) ? "" : "none"; });
      mn.querySelectorAll(".grp:not(.pane)").forEach((g) => { g.style.display = [...g.querySelectorAll("[data-name]")].some((t) => t.style.display !== "none") ? "" : "none"; }); }; }
    onLink("[data-open]", (b) => open(b.dataset.open));
    onLink("[data-admin]", (b) => (b.dataset.admin === "company" ? companyView() : b.dataset.admin === "invoices" ? invoicesView() : b.dataset.admin === "digest" ? digestView() : b.dataset.admin === "wa" ? waView() : b.dataset.admin === "backup" ? backupView() : b.dataset.admin === "finance" ? financeView() : usersView()));
    onLink("[data-datam]", () => dataView());
    onLink("[data-grand]", () => grandView());
    onLink("[data-ops]", () => opsView());
    onLink(".side .who", () => appView());
    if ($("#plantSel")) $("#plantSel").onchange = (e) => { if (e.target.value === "__all") plantsView(); else location.href = "/it/app/" + encodeURIComponent(e.target.value); };
    document.querySelectorAll("[data-soon]").forEach((b) => b.addEventListener("click", () => dialog(`${b.dataset.name} — coming soon`, "This module of the KMR Intelligent Digital Manufacturing platform is on its way. Register your interest and we'll invite you to the pilot.", `<a class="btn" href="${buyUrl(b.dataset.soon)}">Register interest</a>`)));
    $("#out").onclick = async () => { await sb.auth.signOut(); try { localStorage.removeItem("kmr-portal"); } catch (e) {} loginView(); };
    $("#drn").onclick = (e) => { if (e.metaKey || e.ctrlKey || e.shiftKey || e.button) return; e.preventDefault(); digitalNotice(); };
    $("#pw").onclick = () => {
      dialog("Change password", `<label class="f">New password<div class="in"><input id="np1" type="password" minlength="8" autocomplete="new-password"></div></label><label class="f">Repeat new password<div class="in"><input id="np2" type="password" minlength="8" autocomplete="new-password"></div></label><span class="msg" id="npm"></span>`,
        `<button class="btn" id="npSave">Save password</button>`);
      $("#npSave").onclick = async () => {
        const a = $("#np1").value, b = $("#np2").value, m = $("#npm");
        if (a.length < 8) { m.textContent = "Use at least 8 characters."; return; }
        if (a !== b) { m.textContent = "The two passwords do not match."; return; }
        const { error } = await sb.auth.updateUser({ password: a });
        m.className = error ? "msg" : "msg ok"; m.textContent = error ? error.message : "Password changed. Use it for every KMR app.";
      };
    };
  }


  /* ---------------- Administration (company administrators) ---------------- */
  const ROLE_OPTS = {
    other: [["", "No access"], ["admin", "Admin"], ["editor", "Editor"], ["viewer", "Viewer"]],
  };
  const mainEl = () => document.querySelector(".main");
  function adminHead(title, sub) { window.scrollTo(0, 0); document.querySelector(".main")?.scrollTo?.(0, 0); return `<p><a class="btn ghost" id="backApps" href="${viewHref("")}" style="height:36px">← Your apps</a></p><h1>${esc(title)}</h1><p class="sub">${esc(sub)}</p>`; }
  function bindBack() { const b = $("#backApps"); if (b) b.onclick = (e) => { if (!plain(e)) return; e.preventDefault(); appView(); }; }

  /* Sample data belongs in the KMR demo workspace only. A real company never gets the Load-sample buttons (the database refuses anyway).
     Before the 0049 database update the question cannot be answered, so nothing is hidden then. */
  let SAMPLE_OK = true, DEV = false;
  const ctxOf = () => ({ sb, slug: SLUG, main: document.querySelector(".main"), dialog, base: BASE, setView, sampleOk: SAMPLE_OK, dev: DEV });
  function dataView() { if (!window.KMR_DATA) return; setView("data"); return window.KMR_DATA.overview(ctxOf()); }
  /* All plants on one screen: each plant's apps and numbers side by side */
  async function plantsView() {
    setView("plants");
    const main = document.querySelector(".main");
    main.innerHTML = `<h1>All plants</h1><p class="sub">${esc(brand.name.split(" – ")[0])} · every plant at a glance. Pick a plant in the menu to work in it.</p><p class="sub">Loading…</p>`;
    const res = await Promise.all(plants.map(async (x) => {
      const [pr, st] = await Promise.all([sb.rpc("kmr_portal", { p_slug: x.slug }), sb.rpc("kmr_portal_stats", { p_slug: x.slug })]);
      return { x, rows: (pr.data || []).filter((r) => r.purchased && (r.product_code !== "pnl" || r.has_access || DEV)), stats: (st && st.data) || {} };
    }));
    const salesSlug = (plants.find((x) => x.is_main) || plants[0]).slug;
    main.innerHTML = `<h1>All plants</h1><p class="sub">${esc(brand.name.split(" – ")[0])} · every plant at a glance. Pick a plant in the menu to work in it.</p>
      <p><a class="btn" href="/it/sales.html?kmr=1&co=${encodeURIComponent(salesSlug)}&scope=all">Sales Flow · all-plants dashboard</a></p>
      <div class="cards">${res.map(({ x, rows: rs, stats: stt }) => `<div class="card" style="--c:#0B2A6F"><h3>${esc(x.is_main ? "Main" : x.plant_code)} · ${esc(x.name.split(" – ").pop())}</h3>
        ${rs.length ? rs.map((r) => `<p style="margin:6px 0"><b>${esc(r.product_name)}</b> <span class="pill ${r.ok ? "ok" : "warn"}">${esc(r.status)}</span><br><small>${Object.entries(stt[r.product_code] || {}).map(([k, v]) => `${esc(k)}: <b>${esc(v)}</b>`).join(" · ") || "—"}</small></p>`).join("") : `<p><small>No apps switched on for this plant yet.</small></p>`}
        <a class="btn ghost" href="/it/app/${encodeURIComponent(x.slug)}">Open ${esc(x.is_main ? "main" : x.plant_code)}</a></div>`).join("")}</div>`;
  }
  function grandView() { if (!window.KMR_GRAND) return; setView("grand"); return window.KMR_GRAND.overview(ctxOf()); }
  async function opsView(kind) {
    if (!window.KMR_OPS || !ops) return;
    const c = { ...ctxOf(), role: ops.role, customerId: ops.customer_id };
    setView("ops"); await window.KMR_OPS.overview(c);
    if (kind) window.KMR_OPS.list(c, kind);
  }

  async function invoicesView() {
    setView("invoices");
    const head = adminHead("Invoices & payments", "Invoices from KMR for your subscriptions. Open one to view, print or pay it.");
    const m = mainEl(); m.innerHTML = head + `<p class="msg">Loading…</p>`; bindBack();
    const { data, error } = await sb.rpc("kmr_portal_invoices", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = error.message; return; }
    const today = new Date().toISOString().slice(0, 10);
    const money = (v, c) => (c === "INR" ? "₹" : c === "USD" ? "$" : c === "EUR" ? "€" : c + " ") + Number(v).toLocaleString(c === "INR" ? "en-IN" : "en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const date = (d) => (d ? new Date(d + "T00:00:00").toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "—");
    const tag = (r) => r.status === "paid" ? '<span class="pill ok">Paid</span>' : r.status === "cancelled" ? '<span class="pill off">Cancelled</span>'
      : r.reported ? '<span class="pill">Confirming payment</span>' : r.due_date && r.due_date < today ? '<span class="pill warn">Overdue</span>' : '<span class="pill">Due ' + esc(date(r.due_date)) + "</span>";
    const rows = data || [];
    m.innerHTML = head + `<div class="card" style="padding:0;overflow:auto;max-width:900px"><table style="width:100%;border-collapse:collapse;font-size:14px">
      <thead><tr style="background:#F5F7FB;text-align:left"><th style="padding:10px 14px">Invoice</th><th style="padding:10px 14px">Date</th><th style="padding:10px 14px;text-align:right">Amount</th><th style="padding:10px 14px">Status</th><th></th></tr></thead>
      <tbody>${rows.map((r) => `<tr style="border-top:1px solid var(--line)"><td style="padding:10px 14px"><b>${esc(r.number)}</b></td><td style="padding:10px 14px">${esc(date(r.issue_date))}</td>
        <td style="padding:10px 14px;text-align:right;white-space:nowrap">${esc(money(r.total, r.currency))}</td><td style="padding:10px 14px">${tag(r)}</td>
        <td style="padding:10px 14px;text-align:right"><a class="btn ${r.status === "issued" ? "" : "ghost"}" style="height:34px" href="/it/console/pay/${encodeURIComponent(r.pay_token)}" target="_blank" rel="noopener">${r.status === "issued" && !r.reported ? "View &amp; pay" : "View"}</a></td></tr>`).join("")
        || '<tr><td colspan="5" style="padding:18px;color:var(--muted)">No invoices yet.</td></tr>'}</tbody></table></div>`;
    bindBack();
  }

  async function companyView() {
    setView("company");
    const m = mainEl(); m.innerHTML = adminHead("Company details & logo", "Shown in every KMR app your company uses — change it once here.") + `<p class="msg">Loading…</p>`; bindBack();
    const { data: c, error } = await sb.rpc("kmr_admin_company", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = error.message; return; }
    const f = (k, label, full) => `<label class="f"${full ? ' style="grid-column:1/-1"' : ""}>${label}<div class="in"><input name="${k}" value="${esc(c[k] || "")}"></div></label>`;
    m.innerHTML = adminHead("Company details & logo", "Shown in every KMR app your company uses — change it once here.") + `
      <div class="card" style="max-width:760px">
        <div style="display:flex;gap:18px;align-items:center;flex-wrap:wrap">
          <div id="lgBox" style="width:96px;height:96px;border-radius:16px;border:1px solid var(--line);display:grid;place-items:center;background:#fff;overflow:hidden">${c.logo_url ? `<img src="${esc(c.logo_url)}" style="max-width:86px;max-height:86px;object-fit:contain">` : `<small style="color:var(--muted)">No logo</small>`}</div>
          <div><b>Company logo</b><br><small style="color:var(--muted)">PNG, JPG, WebP or SVG, under 2 MB. Square logos look best.</small><br><input type="file" id="lgFile" accept="image/png,image/jpeg,image/webp,image/svg+xml" style="margin-top:8px"></div>
        </div>
        <form id="cf" style="display:grid;grid-template-columns:1fr 1fr;gap:4px 16px;margin-top:18px">
          ${f("name", "Company name")}${f("legal_name", "Legal name (invoices, documents)")}${f("tax_id", "GSTIN / tax ID")}${f("contact_phone", "Phone")}
          ${f("address", "Address", true)}${f("city", "City")}${f("state", "State / region")}${f("postal_code", "Postal code")}
          <div style="grid-column:1/-1;display:flex;gap:12px;align-items:center"><button class="btn" type="submit">Save — update all apps</button><span class="msg" id="cm"></span></div>
        </form>
        <p style="font-size:13px;color:var(--muted);margin:10px 0 0">Applies to: ${(c.tools || []).map((t) => esc(t.name)).join(", ") || "your apps"}. Main contact: ${esc(c.contact_name || "")} (${esc(c.contact_email || "")}) — ask KMR to change it.</p>
      </div>`;
    bindBack();
    let logoUrl = null;
    $("#lgFile").onchange = async (e) => {
      const file = e.target.files[0]; const msg = $("#cm"); if (!file) return;
      if (file.size > 2 * 1024 * 1024) { msg.className = "msg"; msg.textContent = "The logo must be under 2 MB."; return; }
      msg.className = "msg"; msg.textContent = "Uploading logo…";
      const path = `customers/${c.id}/logo-${Date.now()}.${(file.name.split(".").pop() || "png").toLowerCase()}`;
      const up = await sb.storage.from("kmr-public").upload(path, file, { contentType: file.type, upsert: true });
      if (up.error) { msg.textContent = "Upload failed: " + up.error.message; return; }
      logoUrl = sb.storage.from("kmr-public").getPublicUrl(path).data.publicUrl;
      $("#lgBox").innerHTML = `<img src="${esc(logoUrl)}" style="max-width:86px;max-height:86px;object-fit:contain">`;
      msg.textContent = "Logo ready — click Save to apply it everywhere.";
    };
    $("#cf").onsubmit = async (e) => {
      e.preventDefault(); const d = Object.fromEntries(new FormData(e.target)); if (logoUrl) d.logo_url = logoUrl;
      const msg = $("#cm"); msg.className = "msg"; msg.textContent = "Saving…";
      const r = await sb.rpc("kmr_admin_save_company", { p_slug: SLUG, p: d });
      if (r.error) { msg.textContent = r.error.message; return; }
      msg.className = "msg ok"; msg.textContent = "Saved. Every app now shows the new details.";
      brand = { name: d.name, logo_url: logoUrl || brand.logo_url }; try { localStorage.setItem("kmr-portal", JSON.stringify({ slug: SLUG, name: d.name, logo: brand.logo_url || null })); } catch (x) {}
      setIcon(brand.logo_url);
    };
  }


  /* Daily management mail: one mail a day with every app's dashboard and KPIs, what is OK and what to do. Sent at about 8:30 am India time. */
  const DG_SECTIONS = [["production", "mmd", "Production efficiency (month to date, last entry, machine-wise, day-wise)"], ["delivery", "sales", "Delivery to customers (despatch against plan)"], ["dcg", "dcg", "Delivery challans overdue, purchase orders and GRN"], ["calibration", "calib", "Calibration of gauges"],
    ["maintenance", "mnt", "Maintenance (breakdowns, preventive maintenance)"], ["hrm", "hrms", "People and attendance"], ["actions", "tsk", "Actions (ActionTrack)"], ["meetings", "mom", "Meeting actions"], ["audit", "aud", "Internal audit findings"], ["invoicing", "inv", "Invoicing"], ["rmp", "rmp", "Raw material planning (plan vs received, delays, low stock, overdue orders)"]];
  async function backupView(note) {
    setView("backup");
    const m = mainEl(), T0 = "Daily backup mail", S0 = "Every night all the data of this plant (every app, settings, users and masters) is backed up. A mail with the download links goes to the people chosen here. Backups are kept for the number of days you set.";
    m.innerHTML = adminHead(T0, S0) + `<p class="msg">Loading…</p>`; bindBack();
    const { data: g, error } = await sb.rpc("kmr_bk_get", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = /does not exist|Could not find/i.test(error.message) ? "This needs the latest KMR database update (0134). Please contact KMR support." : error.message; return; }
    const d = g.last_detail || {}, last = g.last_run_on ? String(g.last_run_on).split("-").reverse().join("-") : "";
    m.innerHTML = adminHead(T0, S0) + `
      ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:14px;max-width:820px">${note}</div>` : ""}
      <div class="card" style="max-width:820px">
        <label style="display:flex;gap:10px;align-items:center;margin:0 0 14px"><b>Daily backup</b>
          <select id="bkOn" style="padding:6px 10px"><option value="true" ${g.enabled ? "selected" : ""}>On</option><option value="false" ${g.enabled ? "" : "selected"}>Off</option></select></label>
        <label class="f" style="display:block">Send the backup mail to — e-mail addresses, separated by comma
          <div class="in"><textarea id="bkTo" rows="2" style="width:100%" placeholder="name@company.com, other@company.com">${esc(g.recipients)}</textarea></div></label>
        <p style="margin:6px 0"><button class="btn ghost" id="bkMe" style="height:34px">＋ Add my e-mail (${esc(g.me)})</button></p>
        <label class="f" style="display:block;max-width:260px">Keep backups for (days)
          <div class="in"><input type="number" id="bkKeep" min="7" max="365" step="1" value="${esc(g.keep_days)}"></div></label>
        <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-top:16px"><button class="btn" id="bkSave">Save</button><span class="msg" id="bkMsg"></span></div>
        <p style="font-size:13px;color:var(--muted);margin:14px 0 0">${last ? `Last backup: ${esc(last)} — ${esc(g.last_status || "")}${d.records ? `, ${Number(d.records).toLocaleString("en-IN")} records in ${esc(d.groups)} groups` : ""}.` : "No backup has run yet."} The backup runs after midnight (India time). Each mail carries a unique reference number and the report format revision in its footer.</p>
      </div>`;
    bindBack();
    $("#bkMe").onclick = () => { const t = $("#bkTo"), cur = t.value.split(/[,;\s]+/).filter(Boolean); if (!cur.includes(g.me)) { cur.push(g.me); t.value = cur.join(", "); } };
    $("#bkSave").onclick = async () => {
      const msg = $("#bkMsg"); msg.className = "msg"; msg.textContent = "Saving…";
      const r = await sb.rpc("kmr_bk_save", { p_slug: SLUG, p: { enabled: $("#bkOn").value, recipients: $("#bkTo").value, keep_days: $("#bkKeep").value } });
      if (r.error) { msg.textContent = r.error.message; return; }
      msg.className = "msg ok"; msg.textContent = "Saved.";
    };
  }
  async function digestView(note) {
    setView("digest");
    const m = mainEl(), T0 = "Daily management mail", S0 = "One mail every morning with the dashboards and KPIs of all your apps: what is OK, where management has to concentrate and what each team has to do. It also carries the Calibration Hub due list, so the separate calibration mail is no longer sent.";
    m.innerHTML = adminHead(T0, S0) + `<p class="msg">Loading…</p>`; bindBack();
    const { data: g, error } = await sb.rpc("kmr_digest_get", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = /does not exist|Could not find/i.test(error.message) ? "This needs the latest KMR database update (0128). Please contact KMR support." : error.message; return; }
    const tg = g.targets || {}, dv = { eff_target: 85, attendance_target: 92, despatch_target: 95, cal_days: 14 }, tv = (k) => (tg[k] !== undefined && tg[k] !== null ? tg[k] : dv[k]);
    const sec = (key, code, label) => { const has = (g.apps || []).includes(code), on = g.sections[key] !== false; return `<label style="display:flex;gap:8px;align-items:flex-start;margin:5px 0;${has ? "" : "opacity:.5"}"><input type="checkbox" data-sec="${key}" ${has && on ? "checked" : ""} ${has ? "" : "disabled"} style="margin-top:3px"><span>${esc(label)}${has ? "" : " <small>(app not in your plan)</small>"}</span></label>`; };
    const num = (id, label, val, hint) => `<label class="f">${label}<div class="in"><input type="number" id="${id}" min="0" max="365" step="1" value="${esc(val)}"></div><small style="color:var(--muted)">${hint}</small></label>`;
    m.innerHTML = adminHead(T0, S0) + `
      ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:14px;max-width:820px">${note}</div>` : ""}
      <div class="card" style="max-width:820px">
        <label style="display:flex;gap:10px;align-items:center;margin:0 0 14px"><b>Daily management mail</b>
          <select id="dgOn" style="padding:6px 10px"><option value="true" ${g.enabled ? "selected" : ""}>On</option><option value="false" ${g.enabled ? "" : "selected"}>Off</option></select>
          <select id="dgDays" style="padding:6px 10px"><option value="daily" ${g.send_days === "daily" ? "selected" : ""}>Every day</option><option value="mon_sat" ${g.send_days === "mon_sat" ? "selected" : ""}>Monday to Saturday</option></select></label>
        <label class="f" style="display:block">Send to — e-mail addresses, separated by comma
          <div class="in"><textarea id="dgTo" rows="2" style="width:100%" placeholder="name@company.com, other@company.com">${esc(g.recipients)}</textarea></div></label>
        <label style="display:flex;gap:8px;align-items:center;margin:8px 0"><input type="checkbox" id="dgAdm" ${g.include_users ? "checked" : ""}> Also send to every company administrator (${(g.admins || []).length}${(g.admins || []).length ? ": " + esc(g.admins.join(", ")) : ""})</label>
        <p style="margin:6px 0"><button class="btn ghost" id="dgMe" style="height:34px">＋ Add my e-mail (${esc(g.me)})</button></p>
        <h3 style="margin:18px 0 4px">What the mail shows</h3>
        <div>${DG_SECTIONS.map((x) => sec(x[0], x[1], x[2])).join("")}</div>
        <h3 style="margin:18px 0 4px">Targets <small style="font-weight:400;color:var(--muted)">(used for the red / amber / green status)</small></h3>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 16px">
          ${num("dgEff", "Production efficiency target (%)", tv("eff_target"), "Green at or above; amber within 15 points; red below that.")}
          ${num("dgAtt", "Attendance target (%)", tv("attendance_target"), "Green at or above; amber within 5 points.")}
          ${num("dgDesp", "Despatch pace target (%)", tv("despatch_target"), "How much of the month's expected despatch must be done so far.")}
          ${num("dgCal", "Calibration: list gauges due within (days)", tv("cal_days"), "Gauges coming due inside this window are listed.")}
        </div>
        <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-top:16px"><button class="btn" id="dgSave">Save</button><span class="msg" id="dgMsg"></span></div>
        <hr style="border:0;border-top:1px solid var(--line);margin:18px 0">
        <label class="f" style="display:block">Send a test mail with today's figures to
          <div class="in"><input type="email" id="dgTest" value="${esc(g.me)}" style="min-width:280px"></div></label>
        <p style="margin:8px 0"><button class="btn ghost" id="dgTestBtn">✉ Send test mail</button> <span class="msg" id="dgTMsg"></span></p>
        <p style="font-size:13px;color:var(--muted);margin:6px 0 0">The test mail does not count as sent, so the morning mail still goes out. ${g.last_sent_on ? "Last morning mail: " + esc(String(g.last_sent_on).split("-").reverse().join("-")) + "." : ""} Each report carries a unique reference number and the report format revision in its footer.</p>
      </div>`;
    bindBack();
    $("#dgMe").onclick = () => { const t = $("#dgTo"), cur = t.value.split(/[,;\s]+/).filter(Boolean); if (!cur.includes(g.me)) { cur.push(g.me); t.value = cur.join(", "); } };
    $("#dgSave").onclick = async () => {
      const msg = $("#dgMsg"); msg.className = "msg"; msg.textContent = "Saving…";
      const sections = {}; document.querySelectorAll("[data-sec]").forEach((c) => { if (!c.disabled && !c.checked) sections[c.dataset.sec] = false; });
      const targets = { eff_target: +$("#dgEff").value, attendance_target: +$("#dgAtt").value, despatch_target: +$("#dgDesp").value, cal_days: +$("#dgCal").value };
      const r = await sb.rpc("kmr_digest_save", { p_slug: SLUG, p: { enabled: $("#dgOn").value, send_days: $("#dgDays").value, recipients: $("#dgTo").value, include_users: $("#dgAdm").checked ? "true" : "false", sections, targets } });
      if (r.error) { msg.textContent = r.error.message; return; }
      msg.className = "msg ok"; msg.textContent = "Saved.";
    };
    $("#dgTestBtn").onclick = async (e) => {
      const b = e.currentTarget, msg = $("#dgTMsg"); b.disabled = true; msg.className = "msg"; msg.textContent = "Sending…";
      try {
        const ss = await sb.auth.getSession(), tk = ss && ss.data && ss.data.session && ss.data.session.access_token;
        const r = await fetch("/it/console/api/digest/test", { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + (tk || "") }, body: JSON.stringify({ slug: SLUG, to: $("#dgTest").value }) });
        const j = await r.json().catch(() => ({}));
        if (!r.ok || !j.ok) throw new Error(j.error || "The test mail could not be sent.");
        msg.className = "msg ok"; msg.textContent = `Test mail sent to ${j.to}: ${j.act} area${j.act === 1 ? "" : "s"} need action, ${j.watch} to watch.`;
      } catch (x) { msg.textContent = x.message; }
      b.disabled = false;
    };
  }

  // ---- WhatsApp evening report (7:30 pm): switch on / off and the people who get it; add, edit, delete ----
  async function waView(note) {
    setView("wa");
    const m = mainEl(), T0 = "WhatsApp evening report", S0 = "Every day at 7:30 pm this unit's sales value (plan, done, pending), today's invoices, dispatch status, customer-wise schedule, raw material / forging slug stock and stage-wise stock go on WhatsApp as pictures to the unit in-charges and the people listed here.";
    m.innerHTML = adminHead(T0, S0) + `<p class="msg">Loading…</p>`; bindBack();
    const { data: g, error } = await sb.rpc("kmr_wa_get", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = error.message; return; }
    const parse = (t) => String(t || "").split(/[\n;]+/).map((x) => x.trim()).filter(Boolean).map((x) => { const i = x.indexOf(","); return { name: i < 0 ? x : x.slice(0, i).trim(), phone: i < 0 ? "" : x.slice(i + 1).trim() }; });
    const norm = (v) => { const d = String(v || "").replace(/[^0-9]/g, ""); return d.length === 10 ? "91" + d : d; };
    let rows = parse(g.people);
    m.innerHTML = adminHead(T0, S0) + `
      <div class="card" style="max-width:820px">
        <label style="display:flex;gap:10px;align-items:center;margin:0 0 14px"><b>WhatsApp evening report</b>
          <select id="waOn" style="padding:6px 10px"><option value="true" ${g.enabled ? "selected" : ""}>On</option><option value="false" ${g.enabled ? "" : "selected"}>Off</option></select></label>
        <p style="margin:0 0 10px;font-size:13px;color:var(--muted)">Unit in-charges with a mobile number (mobile kept by KMR support) get it automatically${(g.incharges || []).length ? ": " + (g.incharges || []).map((x) => esc(x.name) + (x.phone ? " " + esc(x.phone) : " (no mobile yet)")).join(", ") : "."}</p>
        <h3 style="margin:10px 0 6px">Other people</h3>
        <div id="waRows"></div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin:10px 0"><input id="waN" placeholder="Name" style="width:180px"><input id="waP" placeholder="Mobile (10 digits or with 91)" inputmode="tel" style="width:230px"><button class="btn ghost" id="waAdd" style="height:36px">＋ Add person</button></div>
        <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-top:14px"><button class="btn" id="waSave">Save</button><span class="msg" id="waMsg"></span></div>
        <p style="font-size:13px;color:var(--muted);margin:10px 0 0">Change a name or number in its row, or press Delete; then press Save. A 10-digit Indian number gets 91 added.${g.last_sent_on ? " Last sent: " + esc(String(g.last_sent_on).split("-").reverse().join("-")) + "." : ""}</p>
      </div>`;
    bindBack();
    const draw = () => {
      $("#waRows").innerHTML = rows.length ? rows.map((r, i) => `<div style="display:flex;gap:8px;align-items:center;margin:5px 0;flex-wrap:wrap"><input data-wn="${i}" value="${esc(r.name)}" style="width:180px" aria-label="Name"><input data-wp="${i}" value="${esc(r.phone)}" style="width:230px" inputmode="tel" aria-label="Mobile number"><button class="btn ghost" data-wd="${i}" style="height:34px">Delete</button></div>`).join("") : `<p style="color:var(--muted);margin:4px 0">No extra people yet.</p>`;
      document.querySelectorAll("[data-wn]").forEach((e) => (e.oninput = () => { rows[+e.dataset.wn].name = e.value; }));
      document.querySelectorAll("[data-wp]").forEach((e) => (e.oninput = () => { rows[+e.dataset.wp].phone = e.value; }));
      document.querySelectorAll("[data-wd]").forEach((b) => (b.onclick = () => { const r = rows[+b.dataset.wd]; if (confirm("Delete " + (r.name || "this person") + "?")) { rows.splice(+b.dataset.wd, 1); draw(); } }));
    };
    draw();
    const add = () => { const n = $("#waN").value.trim(), p = norm($("#waP").value); if (!n || p.length < 10) { const x = $("#waMsg"); x.className = "msg"; x.textContent = "Type a name and a mobile number first."; return; } rows.push({ name: n, phone: p }); $("#waN").value = ""; $("#waP").value = ""; draw(); };
    $("#waAdd").onclick = add; $("#waP").onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); add(); } };
    $("#waSave").onclick = async () => {
      const msg = $("#waMsg"); msg.className = "msg"; msg.textContent = "Saving…";
      const people = rows.filter((r) => r.name || r.phone).map((r) => `${r.name}, ${norm(r.phone)}`).join("\n");
      const r = await sb.rpc("kmr_wa_save", { p_slug: SLUG, p_enabled: $("#waOn").value === "true", p_people: people });
      if (r.error) { msg.textContent = r.error.message; return; }
      rows = rows.map((x) => ({ name: x.name, phone: norm(x.phone) })); draw();
      msg.className = "msg ok"; msg.textContent = "Saved.";
    };
  }

  // ---- Finance mail for top management (migration 0129): settings, and the money data typed or pasted here when the figures are not loaded by the ERP bridge ----
  const FN_SECTIONS = [["sales", "Sales value (from Sales Invoicing)"], ["receivables", "Receivables: money to collect, overdue, ageing, days sales outstanding"], ["payables", "Payables: money to pay, overdue, due in 7 days"], ["expenses", "Expenses against budget, and cost as % of sales"], ["pnl", "Profit and loss, month to date (needs the Profit & Loss app)"], ["cash", "Cash movement of the month"]];
  const fnDate = (v) => { v = String(v || "").trim(); let m = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/); if (m) return `${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`; m = v.match(/^(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2}|\d{4})$/); if (m) return `${m[3].length === 2 ? "20" + m[3] : m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`; return ""; };
  const fnRows = (txt) => String(txt || "").split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map((l) => l.split(l.includes("\t") ? "\t" : ",").map((c) => c.trim().replace(/^"|"$/g, "")));
  const fnIsHead = (r) => r.length && !/\d/.test(r[r.length - 1] || "x");
  async function financeView(note) {
    setView("finance");
    const m = mainEl(), T0 = "Finance mail for top management", S0 = "A separate daily mail only for the top management: sales, money to collect, money to pay, expenses against budget and as a percentage of sales, and cash movement, with what to do. It is not the plant mail.";
    m.innerHTML = adminHead(T0, S0) + `<p class="msg">Loading…</p>`; bindBack();
    const { data: g, error } = await sb.rpc("kmr_fin_get", { p_slug: SLUG });
    if (error) { m.querySelector(".msg").textContent = /does not exist|Could not find/i.test(error.message) ? "This needs the latest KMR database update (0129). Please contact KMR support." : error.message; return; }
    const tg = g.targets || {}, tv = (k, d) => (tg[k] !== undefined && tg[k] !== null ? tg[k] : d), src = g.source || "app", c = g.counts || {};
    const sec = ([key, label]) => `<label style="display:flex;gap:8px;align-items:flex-start;margin:5px 0"><input type="checkbox" data-fsec="${key}" ${g.sections[key] !== false ? "checked" : ""} style="margin-top:3px"><span>${esc(label)}</span></label>`;
    const num = (id, label, val, hint, ph) => `<label class="f">${label}<div class="in"><input type="number" id="${id}" min="0" max="365" step="1" value="${esc(val)}" placeholder="${ph || ""}"></div><small style="color:var(--muted)">${hint}</small></label>`;
    const ta = (id, ph, rows) => `<textarea id="${id}" rows="${rows || 5}" style="width:100%;font-family:monospace;font-size:12px" placeholder="${esc(ph)}"></textarea>`;
    const own = src === "app";
    m.innerHTML = adminHead(T0, S0) + `
      ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:14px;max-width:860px">${note}</div>` : ""}
      <div class="card" style="max-width:860px">
        <label style="display:flex;gap:10px;align-items:center;margin:0 0 14px;flex-wrap:wrap"><b>Finance mail</b>
          <select id="fnOn" style="padding:6px 10px"><option value="true" ${g.enabled ? "selected" : ""}>On</option><option value="false" ${g.enabled ? "" : "selected"}>Off</option></select>
          <select id="fnDays" style="padding:6px 10px"><option value="daily" ${g.send_days === "daily" ? "selected" : ""}>Every day</option><option value="mon_sat" ${g.send_days === "mon_sat" ? "selected" : ""}>Monday to Saturday</option></select></label>
        <label class="f" style="display:block">Send to — top management e-mail addresses only, separated by comma
          <div class="in"><textarea id="fnTo" rows="2" style="width:100%" placeholder="md@company.com, finance-head@company.com">${esc(g.recipients)}</textarea></div></label>
        <p style="margin:6px 0"><button class="btn ghost" id="fnMe" style="height:34px">＋ Add my e-mail (${esc(g.me)})</button></p>
        <label class="f" style="display:block;margin-top:10px">Where do receivables, payables, expenses and receipts come from?
          <div class="in"><select id="fnSrc" style="padding:6px 10px"><option value="app" ${src === "app" ? "selected" : ""}>Typed or pasted here (below)</option><option value="tally" ${src === "tally" ? "selected" : ""}>Tally (loaded by the KMR ERP Bridge)</option><option value="erp" ${src === "erp" ? "selected" : ""}>Esbee ERP (loaded by the KMR ERP Bridge)</option></select></div>
          <small style="color:var(--muted)">Sales value always comes from Sales Invoicing${g.invoicing ? "" : " (the Invoicing app is not in your plan, so the sales section stays empty)"}. Raw material cost comes from Raw Material Planning${g.rmp ? "" : " (not in your plan)"}. Now loaded: ${nfmt(c.recv)} receivable bills, ${nfmt(c.pay)} payable bills, ${nfmt(c.entries)} receipts / payments / expenses, ${nfmt(c.budget)} budget lines${c.loaded_on ? "; bills loaded on " + esc(String(c.loaded_on).split("-").reverse().join("-")) : ""}.</small></label>
        <h3 style="margin:18px 0 4px">What the mail shows</h3>
        <div>${FN_SECTIONS.map(sec).join("")}</div>
        <h3 style="margin:18px 0 4px">Targets <small style="font-weight:400;color:var(--muted)">(used for the red / amber / green status)</small></h3>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 16px">
          ${num("fnDso", "Days sales outstanding target (days)", tv("dso_target", 60), "Green at or below; amber up to 15 days more.")}
          ${num("fnOd", "Overdue share of receivables (%)", tv("overdue_pct_target", 10), "Green at or below; amber up to 15 points more.")}
          ${num("fnEx", "Expenses as % of sales (optional)", tv("expense_pct_target", ""), "Leave empty to show without a colour.", "none")}
          ${num("fnMa", "Raw material as % of sales (optional)", tv("material_pct_target", ""), "Leave empty to show without a colour.", "none")}
        </div>
        <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-top:16px"><button class="btn" id="fnSave">Save</button><span class="msg" id="fnMsg"></span></div>
        <hr style="border:0;border-top:1px solid var(--line);margin:18px 0">
        <label class="f" style="display:block">Send a test mail with today's figures to
          <div class="in"><input type="email" id="fnTest" value="${esc(g.me)}" style="min-width:280px"></div></label>
        <p style="margin:8px 0"><button class="btn ghost" id="fnTestBtn">✉ Send test mail</button> <span class="msg" id="fnTMsg"></span></p>
        <p style="font-size:13px;color:var(--muted);margin:6px 0 0">The test mail does not count as sent. ${g.last_sent_on ? "Last finance mail: " + esc(String(g.last_sent_on).split("-").reverse().join("-")) + ". " : ""}It carries a unique reference number and the report format revision in its footer, and is marked confidential.</p>
      </div>
      ${own ? `
      <div class="card" style="max-width:860px;margin-top:14px"><h3 style="margin:0 0 4px">1. Outstanding bills (receivable and payable)</h3>
        <p style="font-size:13px;color:var(--muted);margin:0 0 8px">Paste from your accounts sheet, one bill per line: <b>party, bill no, bill date, due date, outstanding amount</b>. The old list of that type is replaced. Dates as 31-12-2026 or 2026-12-31.</p>
        <select id="fnObK" style="padding:6px 10px"><option value="recv">Receivable — customers owe us</option><option value="pay">Payable — we owe suppliers</option></select>
        ${ta("fnOb", "Bosch India, INV/26-27/0012, 05-11-2026, 05-12-2026, 590000", 5)}
        <p style="margin:8px 0"><button class="btn" id="fnObBtn">Save this list</button> <span class="msg" id="fnObMsg"></span></p></div>
      <div class="card" style="max-width:860px;margin-top:14px"><h3 style="margin:0 0 4px">2. Receipts, payments and expenses</h3>
        <div style="display:grid;grid-template-columns:repeat(6,1fr);gap:8px;align-items:end;margin:6px 0">
          <label class="f">Type<div class="in"><select id="fnEk"><option value="expense">Expense</option><option value="receipt">Receipt</option><option value="payment">Payment</option></select></div></label>
          <label class="f">Date<div class="in"><input type="date" id="fnEd" value="${new Date().toISOString().slice(0, 10)}"></div></label>
          <label class="f">Party<div class="in"><input id="fnEp" placeholder="optional"></div></label>
          <label class="f">Expense head<div class="in"><input id="fnEh" placeholder="Power, Salaries…"></div></label>
          <label class="f">Amount (₹)<div class="in"><input type="number" id="fnEa" min="0" step="0.01"></div></label>
          <button class="btn" id="fnEBtn">Add</button></div>
        <details style="margin:6px 0"><summary style="cursor:pointer;font-size:13px">Or paste many lines: type, date, party, head, amount</summary>
          ${ta("fnEp2", "expense, 05-11-2026, , Power, 90000\nreceipt, 06-11-2026, Bosch India, , 250000", 4)}<p style="margin:6px 0"><button class="btn ghost" id="fnEBtn2">Save pasted lines</button></p></details>
        <span class="msg" id="fnEMsg"></span><div id="fnRecent"></div></div>
      <div class="card" style="max-width:860px;margin:14px 0"><h3 style="margin:0 0 4px">3. Monthly budget per expense head</h3>
        <p style="font-size:13px;color:var(--muted);margin:0 0 8px">One line per head: <b>head, amount</b> (every month), or <b>head, amount, 2026-12</b> for one month only. A head you enter again is replaced.</p>
        ${ta("fnBg", "Salaries, 600000\nPower, 70000\nRent, 40000", 4)}
        <p style="margin:8px 0"><button class="btn" id="fnBgBtn">Save budget</button> <span class="msg" id="fnBgMsg"></span></p><div id="fnBgList"></div></div>`
      : `<div class="card" style="max-width:860px;margin:14px 0"><b>${src === "tally" ? "Tally" : "Esbee ERP"} is the source.</b> Receivables, payables, receipts, payments and expenses are loaded by the KMR ERP Bridge on the plant computer. Monthly budgets are still entered here.
        <div style="margin-top:10px"><h3 style="margin:0 0 4px">Monthly budget per expense head</h3>${ta("fnBg", "Salaries, 600000\nPower, 70000", 4)}<p style="margin:8px 0"><button class="btn" id="fnBgBtn">Save budget</button> <span class="msg" id="fnBgMsg"></span></p><div id="fnBgList"></div></div></div>`}`;
    bindBack();
    const rupee = (v) => "₹" + Number(v).toLocaleString("en-IN");
    const refresh = async () => {
      const r = await sb.rpc("kmr_fin_recent", { p_slug: SLUG }); if (r.error || !r.data) return;
      const E = $("#fnRecent");
      if (E) E.innerHTML = (r.data.entries || []).length ? `<table style="width:100%;border-collapse:collapse;font-size:13px;margin-top:8px"><thead><tr style="text-align:left;background:#F5F7FB"><th style="padding:5px">Date</th><th>Type</th><th>Party / head</th><th style="text-align:right">Amount</th><th></th></tr></thead><tbody>${r.data.entries.map((e) => `<tr><td style="padding:4px 5px">${esc(String(e.entry_date).split("-").reverse().join("-"))}</td><td>${esc(e.kind)}</td><td>${esc([e.party, e.head].filter(Boolean).join(" · "))}</td><td style="text-align:right">${rupee(e.amount)}</td><td><button class="btn ghost" data-fdel="entry:${e.id}" style="height:26px;padding:0 8px">✕</button></td></tr>`).join("")}</tbody></table><small style="color:var(--muted)">Latest 25 lines typed here.</small>` : "";
      const B = $("#fnBgList");
      if (B) B.innerHTML = (r.data.budget || []).length ? `<table style="width:100%;border-collapse:collapse;font-size:13px"><tbody>${r.data.budget.map((b) => `<tr><td style="padding:4px 5px">${esc(b.head)}</td><td>${b.month === "*" ? "every month" : esc(b.month)}</td><td style="text-align:right">${rupee(b.amount)}</td><td><button class="btn ghost" data-fdel="budget:${esc(b.head)}:${esc(b.month)}" style="height:26px;padding:0 8px">✕</button></td></tr>`).join("")}</tbody></table>` : "";
      document.querySelectorAll("[data-fdel]").forEach((b) => (b.onclick = async () => { const [w, id, mo] = b.dataset.fdel.split(":"); const d = await sb.rpc("kmr_fin_delete", { p_slug: SLUG, p_what: w, p_id: id, p_month: mo || null }); if (!d.error) refresh(); }));
    };
    refresh();
    const run = async (msgSel, fn) => { const msg = $(msgSel); msg.className = "msg"; msg.textContent = "Saving…"; try { const r = await fn(); if (r.error) throw new Error(r.error.message); msg.className = "msg ok"; msg.textContent = `Saved ${r.data.saved} line${r.data.saved === 1 ? "" : "s"}${r.data.skipped ? `; ${r.data.skipped} could not be read (check the date and amount)` : ""}.`; refresh(); } catch (x) { msg.textContent = x.message; } };
    $("#fnMe").onclick = () => { const t = $("#fnTo"), cur = t.value.split(/[,;\s]+/).filter(Boolean); if (!cur.includes(g.me)) { cur.push(g.me); t.value = cur.join(", "); } };
    $("#fnSave").onclick = async () => {
      const msg = $("#fnMsg"); msg.className = "msg"; msg.textContent = "Saving…";
      const sections = {}; document.querySelectorAll("[data-fsec]").forEach((x) => { if (!x.checked) sections[x.dataset.fsec] = false; });
      const targets = { dso_target: +$("#fnDso").value, overdue_pct_target: +$("#fnOd").value }; if ($("#fnEx").value !== "") targets.expense_pct_target = +$("#fnEx").value; if ($("#fnMa").value !== "") targets.material_pct_target = +$("#fnMa").value;
      const r = await sb.rpc("kmr_fin_save", { p_slug: SLUG, p: { enabled: $("#fnOn").value, send_days: $("#fnDays").value, recipients: $("#fnTo").value, source: $("#fnSrc").value, sections, targets } });
      if (r.error) { msg.textContent = r.error.message; return; }
      msg.className = "msg ok"; msg.textContent = "Saved."; if ($("#fnSrc").value !== src) financeView("Saved. The page now shows the data screens for the chosen source.");
    };
    $("#fnTestBtn").onclick = async (e) => {
      const b = e.currentTarget, msg = $("#fnTMsg"); b.disabled = true; msg.className = "msg"; msg.textContent = "Sending…";
      try {
        const ss = await sb.auth.getSession(), tk = ss && ss.data && ss.data.session && ss.data.session.access_token;
        const r = await fetch("/it/console/api/finance/test", { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + (tk || "") }, body: JSON.stringify({ slug: SLUG, to: $("#fnTest").value }) });
        const j = await r.json().catch(() => ({}));
        if (!r.ok || !j.ok) throw new Error(j.error || "The test mail could not be sent.");
        msg.className = "msg ok"; msg.textContent = `Test mail sent to ${j.to}: ${j.act} area${j.act === 1 ? "" : "s"} need action, ${j.watch} to watch.`;
      } catch (x) { msg.textContent = x.message; }
      b.disabled = false;
    };
    $("#fnBgBtn").onclick = () => run("#fnBgMsg", () => {
      const rows = fnRows($("#fnBg").value).filter((r) => !fnIsHead(r)).map((r) => ({ head: r[0], amount: r[1], month: r[2] || "*" }));
      return sb.rpc("kmr_fin_import", { p_slug: SLUG, p_kind: "budget", p_rows: rows });
    });
    if (own) {
      $("#fnObBtn").onclick = () => run("#fnObMsg", () => {
        const rows = fnRows($("#fnOb").value).filter((r) => !fnIsHead(r)).map((r) => ({ party: r[0], ref_no: r[1], doc_date: fnDate(r[2]), due_date: fnDate(r[3]), amount: r[4] }));
        if (!confirm(`Replace the whole ${$("#fnObK").value === "recv" ? "receivable" : "payable"} list with these ${rows.length} bills?`)) return Promise.resolve({ error: { message: "Not saved." } });
        return sb.rpc("kmr_fin_import", { p_slug: SLUG, p_kind: $("#fnObK").value, p_rows: rows });
      });
      $("#fnEBtn").onclick = () => run("#fnEMsg", () => sb.rpc("kmr_fin_import", { p_slug: SLUG, p_kind: "entry", p_rows: [{ kind: $("#fnEk").value, entry_date: $("#fnEd").value, party: $("#fnEp").value, head: $("#fnEh").value, amount: $("#fnEa").value }] }));
      $("#fnEBtn2").onclick = () => run("#fnEMsg", () => {
        const rows = fnRows($("#fnEp2").value).filter((r) => !fnIsHead(r)).map((r) => ({ kind: r[0], entry_date: fnDate(r[1]), party: r[2], head: r[3], amount: r[4] }));
        return sb.rpc("kmr_fin_import", { p_slug: SLUG, p_kind: "entry", p_rows: rows });
      });
    }
  }
  const nfmt = (n) => Number(n || 0).toLocaleString("en-IN");

  async function usersView(note) {
    setView("users");
    const m = mainEl(); m.innerHTML = adminHead("Users & access", "One list for all your KMR apps. Choose what each person may do in each app.") + `<p class="msg">Loading…</p>`; bindBack();
    const [{ data: list, error }, { data: c }] = await Promise.all([sb.rpc("kmr_admin_users", { p_slug: SLUG }), sb.rpc("kmr_admin_company", { p_slug: SLUG })]);
    if (error) { m.querySelector(".msg").textContent = error.message; return; }
    const tools = [...((c && c.tools) || []), { code: "ops", name: "Operations Master" }].filter((t) => t.code !== "pnl" || DEV);   // Profit & Loss is set by KMR only, so company administrators do not see it here
    const label = (code, v) => (ROLE_OPTS.other.find((o) => o[0] === v) || ["", "—"])[1];
    m.innerHTML = adminHead("Users & access", "One list for all your KMR apps. Choose what each person may do in each app.") + `
      ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:14px">${note}</div>` : ""}
      <p><button class="btn" id="addU">+ Add a person</button></p>
      <div class="card" style="padding:0;overflow:auto"><table style="width:100%;border-collapse:collapse;font-size:14px">
        <thead><tr style="background:#F5F7FB;text-align:left"><th style="padding:10px 12px">Person</th>${tools.map((t) => `<th style="padding:10px 12px">${esc(t.name)}</th>`).join("")}<th style="padding:10px 12px">Last sign-in</th><th></th></tr></thead>
        <tbody>${(list || []).map((u) => `<tr style="border-top:1px solid var(--line)">
          <td style="padding:10px 12px"><b>${esc(u.name || u.email.split("@")[0])}</b>${u.is_admin ? ' <span class="pill ok">Admin</span>' : ""}<br><small style="color:var(--muted)">${esc(u.email)}</small></td>
          ${tools.map((t) => `<td style="padding:10px 12px">${u.roles && u.roles[t.code] ? `<span class="pill">${esc(label(t.code, u.roles[t.code]))}</span>` : '<small style="color:var(--muted)">No access</small>'}</td>`).join("")}
          <td style="padding:10px 12px"><small>${u.last_sign_in ? esc(new Date(u.last_sign_in).toLocaleDateString()) : u.has_login ? "Never" : "No login yet"}</small></td>
          <td style="padding:10px 12px;white-space:nowrap;text-align:right"><button class="btn ghost" data-edit="${esc(u.email)}" style="height:34px">Edit</button></td></tr>`).join("")}</tbody></table></div>`;
    bindBack();
    const edit = (u) => {
      const isNew = !u; u = u || { email: "", name: "", is_admin: false, roles: {} };
      dialog(isNew ? "Add a person" : `Edit ${u.name || u.email}`, `
        <div class="ug"><label class="f">Email<div class="in"><input id="uE" type="email" value="${esc(u.email)}"></div></label>
        <label class="f">Name<div class="in"><input id="uN" value="${esc(u.name || "")}"></div></label>
        ${tools.map((t) => `<label class="f">${esc(t.name)}${t.code === "pnl" && !DEV ? " (given by KMR only)" : ""}<div class="in"><select id="uR_${t.code}"${t.code === "pnl" && !DEV ? " disabled title='Profit & Loss access is given by KMR only'" : ""}>${ROLE_OPTS.other.map((o) => `<option value="${o[0]}" ${((u.roles || {})[t.code] || "") === o[0] ? "selected" : ""}>${o[1]}</option>`).join("")}</select></div></label>`).join("")}
        </div>
        <label style="display:flex;gap:8px;align-items:center;margin:4px 0 12px"><input type="checkbox" id="uA" ${u.is_admin ? "checked" : ""}> Company administrator (Administration pages, users, company details)</label>
        ${isNew || u.has_login === false ? `<label class="f">Password for a new login<div class="in"><input id="uP" type="text" placeholder="${isNew ? "At least 8 characters — only if this email has no KMR login yet" : "This person has no login yet — set a password (at least 8 characters)"}"></div></label>` : (u.login_owned ? `<label class="f">New password (optional)<div class="in"><input id="uP" type="text" placeholder="Leave empty to keep the current password. If you change the e-mail, this is the password for the new e-mail's login (only if it has none yet)"></div></label>` : `<label class="f">Password (only if you change the e-mail)<div class="in"><input id="uP" type="text" placeholder="Needed only when the new e-mail has no KMR login yet"></div></label>`)}
        <span class="msg" id="uM"></span>`,
        `<button class="btn" id="uSave">Save</button>${isNew ? "" : `<button class="btn ghost" id="uDel" style="color:#B00E28">Remove from all apps</button>`}`);
      const dl = document.querySelector(".veil .dlg"); if (dl) dl.classList.add("wide");
      $("#uSave").onclick = async () => {
        const msg = $("#uM"); msg.className = "msg"; msg.textContent = "Saving…";
        const roles = {}; tools.forEach((t) => (roles[t.code] = $("#uR_" + t.code).value));
        const pw = $("#uP") ? $("#uP").value.trim() : "", newE = $("#uE").value.trim(), changed = !isNew && newE.toLowerCase() !== String(u.email).toLowerCase();
        if (changed && !confirm(`Change the e-mail from ${u.email} to ${newE}?\n\nThe person will sign in with the new e-mail. Their access moves to it, and ${u.email} is removed from all apps.`)) { msg.textContent = ""; return; }
        const r = await sb.rpc("kmr_admin_save_user", { p_slug: SLUG, p: { email: newE, name: $("#uN").value.trim(), is_admin: $("#uA").checked, roles, password: isNew || u.has_login === false || changed ? pw : "" } });
        if (r.error) { msg.textContent = r.error.message; return; }
        if (changed) { const rm = await sb.rpc("kmr_admin_remove_user", { p_slug: SLUG, p_email: u.email }); if (rm.error) { msg.textContent = "The new e-mail was added, but the old one could not be removed: " + rm.error.message; return; } }
        if (!changed && !isNew && u.has_login !== false && u.login_owned && pw) { const rp = await sb.rpc("kmr_admin_reset_password", { p_slug: SLUG, p_email: u.email, p_password: pw }); if (rp.error) { msg.textContent = rp.error.message; return; } }
        document.querySelector(".veil")?.remove();
        const em = esc($("#uE") ? $("#uE").value : u.email);
        usersView(r.data && r.data.new_login ? `<b>Saved.</b> Send this person the link <b>${esc(location.origin + "/it/app/" + SLUG)}</b>, their email and the password you set. They can change it under "Change password".` : `<b>Saved.</b> Access updated in every app.${isNew ? " This email already had a KMR login — they use their existing password." : ""}`);
      };
      if ($("#uDel")) $("#uDel").onclick = async () => {
        if (!confirm(`Remove ${u.email} from all your KMR apps?`)) return;
        const r = await sb.rpc("kmr_admin_remove_user", { p_slug: SLUG, p_email: u.email });
        if (r.error) { $("#uM").textContent = r.error.message; return; }
        document.querySelector(".veil")?.remove(); usersView("<b>Removed.</b> Their access to every app was switched off.");
      };
    };
    $("#addU").onclick = () => edit(null);
    document.querySelectorAll("[data-edit]").forEach((b) => (b.onclick = () => edit((list || []).find((x) => x.email === b.dataset.edit))));
  }

  function plantPickView(pl) {
    const open = OPEN ? "?open=" + encodeURIComponent(OPEN) : "";
    $("#root").innerHTML = `<div class="split" style="grid-template-columns:1fr"><section class="panel" style="border:0"><div class="form">
      <div class="co" style="margin-bottom:14px">${logo(brand)}<div>${esc(brand.name)}<small>${esc(user.email)}</small></div></div>
      <h1>Choose your plant</h1><p class="sub">Each plant has its own apps and data.</p>
      ${pl.map((x) => `<p><a class="btn block" href="/it/app/${encodeURIComponent(x.slug)}${open}">${esc(x.plant_code ? x.plant_code + " · " : "")}${esc(String(x.name).split(" – ").pop())}</a></p>`).join("")}
      ${pl[0].is_all ? `<p><a class="btn block ghost" href="/it/app/${encodeURIComponent(pl[0].slug)}#plants">★ All plants · dashboard</a></p>` : ""}
      <p><button class="btn ghost block" id="pkOut">Sign out</button></p></div></section></div>`;
    $("#pkOut").onclick = async () => { await sb.auth.signOut(); try { localStorage.removeItem("kmr-portal"); } catch (e) {} loginView(); };
  }

  async function start() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) return loginView();
    if (!SLUG) {   // signed in at the general address: go to this person's own company page
      const { data } = await sb.rpc("kmr_my_portals");
      if (data && data.length === 1) { location.replace(`/it/app/${data[0].slug}${OPEN ? "?open=" + OPEN : ""}`); return; }
      if (data && data.length > 1) { $("#root").innerHTML = `<div class="split" style="grid-template-columns:1fr"><section class="panel" style="border:0"><div class="form"><h1>Choose your company</h1><p class="sub">Your login belongs to more than one company.</p>${data.map((d) => `<p><a class="btn block" href="/it/app/${esc(d.slug)}${OPEN ? "?open=" + esc(OPEN) : ""}">${esc(d.name)}</a></p>`).join("")}</div></section></div>`; return; }
      await sb.auth.signOut(); return loginView("This login is not linked to any company's KMR Apps. Please use the link and login sent to you by KMR.");
    }
    user = session.user;
    // Company link of a customer with plants: after signing in the person chooses a plant (only the plants they may open)
    try {
      const pr = await sb.rpc("kmr_plants", { p_slug: SLUG });
      const pl = !pr.error && Array.isArray(pr.data) ? pr.data : [];
      if (pl.length && pl[0].at_parent && HASH !== "plants") {
        if (pl.length === 1 && !pl[0].is_all) { location.replace(`/it/app/${encodeURIComponent(pl[0].slug)}${OPEN ? "?open=" + encodeURIComponent(OPEN) : ""}`); return; }
        return plantPickView(pl);
      }
      if (pl.length && pl[0].at_parent && HASH === "plants") { location.replace(`/it/app/${encodeURIComponent(pl[0].slug)}#plants`); return; }
    } catch (e) { /* 0061/0063 not applied yet: behave as before */ }
    const { data, error } = await sb.rpc("kmr_portal", { p_slug: SLUG });
    if (error) return loginView("Could not load your apps right now. Please try again.");
    if (!data || !data.length) { await sb.auth.signOut(); return loginView(`This login does not belong to ${brand.name}. Use the email your company's apps were set up with.`); }
    rows = data.filter((r) => r.product_code !== "pnl" || r.has_access || DEV); brand = { name: data[0].customer_name, logo_url: data[0].logo_url };
    try { const pr = await sb.rpc("kmr_plants", { p_slug: SLUG }); plants = !pr.error && Array.isArray(pr.data) ? pr.data : []; } catch (e) { plants = []; }   // empty until 0061_plants.sql is run
    try { localStorage.setItem("kmr-portal", JSON.stringify({ slug: SLUG, name: brand.name, logo: brand.logo_url || null, plants: plants.map((x) => ({ slug: x.slug, name: x.name, code: x.plant_code, main: x.is_main })), all: !!(plants[0] && plants[0].is_all) })); } catch (e) {}
    setIcon(brand.logo_url);
    const st = await sb.rpc("kmr_portal_stats", { p_slug: SLUG }); stats = (st && st.data) || {};
    // the app photo set in KMR Console › Website CMS › KMR Apps on the website (videos are website-only)
    try { const cat = await sb.rpc("kmr_software_catalog"); (cat.data || []).forEach((a) => { media[a.code] = { img: a.image_url }; }); } catch (e) {}
    const ar = await sb.rpc("kmr_admin_role", { p_slug: SLUG }); isAdmin = !ar.error && ar.data === "admin";
    const oc = await sb.rpc("kmr_ops_context", { p_slug: SLUG }); ops = !oc.error && oc.data ? oc.data : null;
    appView();
    try { const k = "kmr-drn-" + user.id; if (!OPEN && !HASH && !sessionStorage.getItem(k)) { sessionStorage.setItem(k, "1"); digitalNotice(); } } catch (e) {}
    if (OPEN && rows.some((r) => r.product_code === OPEN)) { setView(""); open(OPEN); }
    else if ((HASH === "users" || HASH === "admin") && isAdmin) usersView();
    else if (HASH === "company" && isAdmin) companyView();
    else if (HASH === "invoices" && isAdmin) invoicesView();
    else if (HASH === "digest" && isAdmin) digestView();
    else if (HASH === "wa" && isAdmin) waView();
    else if (HASH === "backup" && isAdmin) backupView();
    else if (HASH === "finance" && isAdmin) financeView();
    else if (HASH === "plants" && plants.length > 1 && plants[0].is_all) plantsView();
    else if (HASH === "grand" && isAdmin) grandView();
    else if (HASH === "data" && isAdmin) dataView();
    else if (HASH === "yearbackup" && isAdmin && window.KMR_YB) { setView("yearbackup"); window.KMR_YB.open(ctxOf(), { back: "grand" }); }
    else if (/^ops(\/|$)/.test(HASH) && ops) opsView(HASH.split("/")[1] || "");
  }

  (async () => {
    try { const d = await sb.rpc("kmr_is_staff"); DEV = !d.error && d.data === true; } catch (e) { DEV = false; }
    if (SLUG) { const { data } = await sb.rpc("kmr_portal_brand", { p_slug: SLUG }); if (data && data[0]) brand = data[0];
      try { const w = await sb.rpc("kmr_workspace_info", { p_slug: SLUG }); if (!w.error && w.data && w.data.kind) SAMPLE_OK = w.data.kind === "demo" && DEV; } catch (e) { /* 0049 not applied yet */ } }
    if (SLUG) { try { const t = await sb.rpc("kmr_portal_theme", { p_slug: SLUG }); if (!t.error && typeof t.data === "string") THEME = t.data; } catch (e) { /* 0068 not applied yet: standard look */ } }
    if (brand.logo_url) setIcon(brand.logo_url);
    else { const k = await sb.rpc("kmr_platform_brand"); if (k.data && k.data.logo_url) { setIcon(k.data.logo_url); if (!SLUG) brand = { name: brand.name, logo_url: k.data.logo_url }; } }
    document.title = `${brand.name} · KMR Apps`;
    start();
  })();
})();
