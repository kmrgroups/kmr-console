/* KMR report frame — every report printed or saved as PDF from any KMR app gets the same frame (automatic, nothing to do on the screen):
     top left   the customer's own logo (company name when no logo is set)
     top centre report title (and document number when the report has one)
     top right  an automatically generated, unique report reference number
     bottom     report-format revision control: format number · revision · revision date, printed on, by whom, and "Page x of y" — on every page
   It is built from @page margin boxes while the browser prints, so it repeats on every page and never changes the screen or the report layout.
   Apps with several reports tell it which one is on screen:  KMRReport.set({ title, doc, format, rev, date })
   Revision control: when the layout of a report format changes, raise its rev and date in FORMATS below (one place for all apps). */
(function () {
  "use strict";
  if (window.KMRReport) return;
  const P = location.pathname;
  const TOOL = /balloon/.test(P) ? "balloon" : /pd\.html/.test(P) ? "pd" : /capacity/.test(P) ? "capacity" : /sales\.html/.test(P) ? "sales" : /calibration/.test(P) ? "calib" : /apqp\.html/.test(P) ? "apqp" : /ppap\.html/.test(P) ? "ppap" : /rmp\.html/.test(P) ? "rmp" : /mmd\.html/.test(P) ? "mmd" : /mnt\.html/.test(P) ? "mnt" : /mom\.html/.test(P) ? "mom" : /cad\.html/.test(P) ? "cad" : /hrm(-me)?\.html/.test(P) ? "hrms" : /tasks\.html/.test(P) ? "tsk" : /dwm\.html/.test(P) ? "dwm" : /layout\.html/.test(P) ? "layout" : /dcg\.html/.test(P) ? "dcg" : /msa\.html/.test(P) ? "msa" : /spc\.html/.test(P) ? "spc" : /crm\.html/.test(P) ? "crm" : /d8\.html/.test(P) ? "d8" : /qms\.html/.test(P) ? "qms" : /aud\.html/.test(P) ? "aud" : /office\.html/.test(P) ? "off" : "";
  const NAMES = { balloon: "Balloon Inspector", pd: "Process Documents", capacity: "Capacity Planner", sales: "Sales Flow", calib: "Calibration Hub", apqp: "APQP", ppap: "PPAP", rmp: "Raw Material & Packing", mmd: "Machines, Moulds & Dies", mnt: "Maintenance", mom: "MoM", hrms: "HRM", tsk: "ActionTrack", msa: "MSA Studies", spc: "SPC Charts", crm: "CRM & RFQ", d8: "8D Problem Solving", qms: "QMS Learning Guide", aud: "Internal Audit", off: "KMR Office Suite", layout: "Factory & Office Layout", dwm: "Daily Work Management", dcg: "Delivery Challan & GRN" };
  const CODE = { balloon: "BAL", pd: "PD", capacity: "CAP", sales: "SAL", calib: "CAL", apqp: "APQP", ppap: "PPAP", rmp: "RMP", mmd: "MMD", mnt: "MNT", mom: "MOM", hrms: "HRM", tsk: "TSK", msa: "MSA", spc: "SPC", crm: "CRM", d8: "8D", qms: "QMS", aud: "AUD", off: "OFF", layout: "LAY", dwm: "DWM", dcg: "DCG" };
  /* format register: one line per report format. Format no. = KMR/<app>/F-nn. Raise rev + date whenever that report's layout changes. */
  const FORMATS = {
    sales: { allplants: { no: 1, rev: "01", date: "2026-11-02", name: "Sales Flow — all-plants dashboard (plan, actual, loss)" }, loss: { no: 2, rev: "01", date: "2026-11-02", name: "Sales Flow — sales loss and reasons" }, concl: { no: 3, rev: "01", date: "2026-11-02", name: "Sales Flow — conclusion and action plan" } },
    dwm: { sheet: { no: 1, rev: "01", date: "2026-11-02", name: "Daily Work Management — employee monthly plan, status and adherence" }, dash: { no: 2, rev: "01", date: "2026-11-02", name: "Daily Work Management — dashboard (all employees)" } },
    calib: { due: { no: 1, rev: "01", date: "2026-11-14", name: "Calibration due list (gauges going to overdue)" } },
    dcg: { dc: { no: 1, rev: "01", date: "2026-11-14", name: "Delivery Challan" }, grn: { no: 2, rev: "01", date: "2026-11-14", name: "Goods Receipt Note" }, pending: { no: 3, rev: "01", date: "2026-11-14", name: "Pending returns (returnable challans)" }, register: { no: 4, rev: "01", date: "2026-11-14", name: "Delivery challan and GRN register" } },
    layout: { report: { no: 1, rev: "01", date: "2026-10-29", name: "Factory & Office Layout Report" } },
    capacity: { workout: { no: 2, rev: "01", date: "2026-10-23", name: "Capacity workout — takt, throughput, load balance" } },
    off: { document: { no: 1, rev: "01", date: "2026-10-23", name: "Document" }, sheet: { no: 2, rev: "01", date: "2026-10-23", name: "Spreadsheet" }, slides: { no: 3, rev: "01", date: "2026-10-23", name: "Presentation" } },
    aud: { plan: { no: 1, rev: "01", date: "2026-10-22", name: "Internal audit plan" }, report: { no: 2, rev: "01", date: "2026-10-22", name: "Internal audit report" }, register: { no: 3, rev: "01", date: "2026-10-22", name: "Internal audit programme" }, actions: { no: 4, rev: "01", date: "2026-10-22", name: "Audit findings and actions list" } },
    qms: { manual: { no: 1, rev: "01", date: "2026-10-22", name: "Standards learning manual" }, coverage: { no: 2, rev: "01", date: "2026-10-22", name: "Standards coverage analysis" } },
    d8: { report: { no: 1, rev: "01", date: "2026-10-22", name: "8D problem solving report" }, register: { no: 2, rev: "01", date: "2026-10-22", name: "8D register" }, actions: { no: 3, rev: "01", date: "2026-10-22", name: "8D action list" } },
    crm: { quote: { no: 1, rev: "01", date: "2026-10-20", name: "Quotation" }, costing: { no: 2, rev: "01", date: "2026-10-20", name: "RFQ costing sheet (internal)" }, compare: { no: 3, rev: "01", date: "2026-10-20", name: "Supplier price comparison" }, rfqs: { no: 4, rev: "01", date: "2026-10-20", name: "RFQ register" }, leads: { no: 5, rev: "01", date: "2026-10-20", name: "Lead and pipeline list" } },
    spc: { chart: { no: 1, rev: "01", date: "2026-10-18", name: "SPC study report — control charts" }, cap: { no: 2, rev: "01", date: "2026-10-18", name: "SPC capability study report (Cp, Cpk)" } },
    msa: { grr: { no: 1, rev: "01", date: "2026-10-18", name: "MSA — Gage R&R study report" }, bias: { no: 2, rev: "01", date: "2026-10-18", name: "MSA — bias study report" }, linearity: { no: 3, rev: "01", date: "2026-10-18", name: "MSA — linearity study report" }, stability: { no: 4, rev: "01", date: "2026-10-18", name: "MSA — stability study report" }, attribute: { no: 5, rev: "01", date: "2026-10-18", name: "MSA — attribute agreement study report" } }
  };
  const DEFAULT = { rev: "01", date: "2026-10-18" };
  const st = { over: {}, refs: {}, logo: null, logoRaw: null };
  const portal = () => { try { return JSON.parse(localStorage.getItem("kmr-portal") || "null") || {}; } catch (e) { return {}; } };
  const loginId = () => { try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (/^sb-.+-auth-token$/.test(k)) { const v = JSON.parse(localStorage.getItem(k)); const u = v && (v.user || (v.currentSession && v.currentSession.user)); if (u && u.email) return u.email; } } } catch (e) { /* ignore */ } return ""; };
  const z = (n, l) => String(n).padStart(l || 2, "0");
  const dmy = (d) => z(d.getDate()) + "-" + z(d.getMonth() + 1) + "-" + d.getFullYear();
  const fmtIso = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s || ""); return m ? m[3] + "-" + m[2] + "-" + m[1] : s || ""; };
  const q = (s) => JSON.stringify(String(s == null ? "" : s)).replace(/\\n/g, "\\A ");   // safe CSS string
  const coCode = () => { const p = portal(); const s = String(p.slug || (window.QP && QP.slug) || "KMR").replace(/[^A-Za-z0-9]/g, "").toUpperCase(); return (s || "KMR").slice(0, 6); };

  const heading = () => { try { const h = [...document.querySelectorAll("main h1, main h2, .panel h1, .panel h2, section h2, h2")].find((e) => e.offsetParent && !e.closest("header,nav,.kmr-foot,.kmr-demo,.noprint") && e.textContent.trim()); return h ? h.textContent.trim().replace(/\s+/g, " ").slice(0, 60) : ""; } catch (e) { return ""; } };
  /* the report on screen: set by the app (title/doc/format) or worked out from the tool */
  function info() {
    const p = portal(), o = st.over, now = new Date();
    const fam = FORMATS[TOOL] || {}, f = (o.key && fam[o.key]) || null;
    const no = o.format || (f ? "KMR/" + CODE[TOOL] + "/F-" + z(f.no) : "KMR/" + (CODE[TOOL] || "APP") + "/F-01");
    const rev = o.rev || (f && f.rev) || DEFAULT.rev, date = o.date || (f && f.date) || DEFAULT.date;
    const title = o.title || (f && f.name) || ((NAMES[TOOL] || "KMR") + (heading() ? " — " + heading() : " report"));
    const key = TOOL + "|" + (o.doc || "") + "|" + title;
    if (!st.refs[key]) st.refs[key] = coCode() + "/" + (CODE[TOOL] || "APP") + "/" + String(now.getFullYear()).slice(2) + z(now.getMonth() + 1) + z(now.getDate()) + "-" + z(now.getHours()) + z(now.getMinutes()) + z(now.getSeconds()) + "-" + Math.random().toString(36).slice(2, 5).toUpperCase();
    return { company: (window.QP && QP.ctx && QP.ctx.company) || p.name || "", logo: p.logo || null, title, doc: o.doc || "", format: no, rev, date: fmtIso(date), ref: st.refs[key], by: loginId(), printed: dmy(now) + " " + z(now.getHours()) + ":" + z(now.getMinutes()) };
  }

  /* the logo as a fixed-size picture the page margin can hold (height 13 mm) */
  async function prepLogo() {
    const url = portal().logo; if (!url || st.logoRaw === url) return; st.logoRaw = url; st.logo = null;
    try {
      const r = await fetch(url, { mode: "cors" }); const b = await r.blob();
      const data = await new Promise((ok, no) => { const fr = new FileReader(); fr.onload = () => ok(fr.result); fr.onerror = no; fr.readAsDataURL(b); });
      const dim = await new Promise((ok) => { const im = new Image(); im.onload = () => ok([im.naturalWidth || 150, im.naturalHeight || 50]); im.onerror = () => ok([150, 50]); im.src = data; });
      const h = 50, w = Math.max(30, Math.min(190, Math.round((h * dim[0]) / (dim[1] || 1))));
      st.logo = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><image href="${data}" xlink:href="${data}" x="0" y="0" width="${w}" height="${h}" preserveAspectRatio="xMinYMid meet"/></svg>`);
    } catch (e) { st.logo = null; }
  }

  function css() {
    const i = info(), L = st.logo || i.logo, o = st.over;
    if (o.inForm) return `@page{${o.land ? "size:A4 landscape;" : ""}margin:10mm 10mm 14mm;@bottom-right{content:"Page " counter(page) " of " counter(pages);font:500 8px Arial,sans-serif;color:#333;vertical-align:bottom;text-align:right}}`;   // header and footer are printed inside the form itself
    const box = (n, body) => `@${n}{${body}}`;
    const txt = "font:600 9px 'Segoe UI',Arial,sans-serif;color:#111;white-space:normal;line-height:1.3;";
    const left = L ? box("top-left", `content:url(${q(L)});vertical-align:middle;text-align:left;width:34%;`) : box("top-left", `content:${q(i.company)};${txt}font-size:12px;font-weight:700;vertical-align:middle;text-align:left;width:34%;`);
    return `@page{${o.land ? "size:A4 landscape;" : ""}margin:25mm 10mm 17mm;
      ${left}
      ${box("top-center", `content:${q(i.title + (i.doc ? "\n" + i.doc : ""))};${txt}font-size:11px;font-weight:700;vertical-align:middle;text-align:center;white-space:pre-line;width:36%;`)}
      ${box("top-right", `content:${q("Report ref. no.\n" + i.ref)};${txt}vertical-align:middle;text-align:right;white-space:pre-line;width:30%;`)}
      ${box("bottom-left", `content:${q("Format no. " + i.format + "  ·  Rev. " + i.rev + "  ·  Rev. date " + i.date)};${txt}font-weight:500;font-size:8px;vertical-align:top;text-align:left;padding-top:3mm;border-top:0.5pt solid #777;width:42%;`)}
      ${box("bottom-center", `content:${q("Printed " + i.printed + (i.by ? " by " + i.by : "") + (i.company ? "\n" + i.company : ""))};${txt}font-weight:500;font-size:8px;vertical-align:top;text-align:center;white-space:pre-line;padding-top:3mm;border-top:0.5pt solid #777;width:36%;`)}
      ${box("bottom-right", `content:"Page " counter(page) " of " counter(pages);${txt}font-weight:500;font-size:8px;vertical-align:top;text-align:right;padding-top:3mm;border-top:0.5pt solid #777;width:22%;`)}}`;
  }
  const mount = () => { if (TOOL === "cad") return; unmount(); const s = document.createElement("style"); s.id = "kmr-report-frame"; s.media = "print"; s.textContent = css(); document.head.append(s); };
  const unmount = () => { const s = document.getElementById("kmr-report-frame"); if (s) s.remove(); };
  window.addEventListener("beforeprint", mount); window.addEventListener("afterprint", unmount);
  prepLogo(); window.addEventListener("storage", (e) => { if (e.key === "kmr-portal") prepLogo(); });
  window.KMRReport = { logoSrc() { return st.logo || portal().logo || null; }, set(o) { st.over = Object.assign({}, o || {}); }, info, formats: FORMATS, tool: TOOL, refresh: prepLogo };
})();
