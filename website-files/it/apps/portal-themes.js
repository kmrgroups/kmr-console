/* KMR Apps portal — home-screen themes.
   Each customer (set in the Console › Customer › Home screen theme) sees one of these. Theme "a" is the standard launcher
   and is drawn by portal.js itself, so a customer without a choice never changes. Every theme draws the same data
   (their apps, plan status, live numbers) and every CSS rule is scoped to .th-<id>, so themes cannot leak into each other. */
(function () {
  "use strict";
  const T = (window.KMR_THEMES = {});
  const FULL = { b: 1, g: 1, l: 1, r: 1 };   // themes without the side menu (a ☰ button brings it back)

  /* ---------- helpers shared by all themes ---------- */
  function H(c) {
    const e = c.esc;
    const img = (r, s, rad) => { const im = c.imgOf(r); s = s || 48; rad = rad == null ? Math.round(s * 0.28) : rad; return im ? `<img class="ic" src="${im}" alt="" loading="lazy" style="width:${s}px;height:${s}px;border-radius:${rad}px">` : `<span class="ic fb" style="width:${s}px;height:${s}px;border-radius:${rad}px">${e((r.product_name || "?")[0])}</span>`; };
    const entries = (r) => Object.entries(c.stats[r.product_code] || {});
    const bad = (r) => entries(r).find(([k, v]) => /overdue|open|due/i.test(k) && Number(v) > 0);
    const isN = ([, v]) => v !== "" && v != null && !isNaN(Number(v)); const num = (r) => entries(r).find((x) => isN(x) && Number(x[1]) > 0 && /overdue|open|due/i.test(x[0])) || entries(r).find((x) => isN(x) && !/user/i.test(x[0])) || entries(r).find(isN);
    const st = (r) => { const l = entries(r).map(([k, v]) => v + " " + k); return l.length ? l.slice(0, 2).join(" · ") : c.sub(r); };
    const bd = (r) => { const b = bad(r); return b ? `<b class="bd">${e(b[1])} ${e(b[0])}</b>` : ""; };
    const hello = () => { const h = new Date().getHours(); return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"; };
    const find = (ph) => `<label class="find"><input id="appFind" type="search" placeholder="${ph || "Find an app…"}" autocomplete="off"></label>`;
    const masters = () => [c.ops ? `<a href="${c.viewHref("ops")}" data-ops="1" data-name="operations master">⚙ Operations Master</a>` : "", c.isAdmin ? `<a href="${c.viewHref("data")}" data-datam="1" data-name="data master">🗄 Data Master</a><a href="${c.viewHref("grand")}" data-grand="1" data-name="grand master">★ Grand Master</a>` : ""].join("");
    const admin = () => c.isAdmin ? `<a href="${c.viewHref("company")}" data-admin="company" data-name="company details">Company</a><a href="${c.viewHref("users")}" data-admin="users" data-name="users and access">Users</a><a href="${c.viewHref("invoices")}" data-admin="invoices" data-name="invoices">Invoices</a>` : "";
    const more = () => c.others.length ? `<section class="grp more"><h2><i></i>Try more of the platform<small>${c.others.length}</small></h2><div class="mchips">${c.others.map((r) => c.link(r, "mc", `${img(r, 26, 8)}<span>${e(r.product_name)}</span><em>Try</em>`, true)).join("")}</div></section>` : "";
    const mrow = () => { const m = masters(); return m ? `<section class="grp more"><h2><i></i>Masters</h2><div class="mchips plain">${m}</div></section>` : ""; };
    const tail = () => mrow() + more();
    const top = (cls) => `<div class="tb ${cls || ""}"><button type="button" id="sbToggle" class="mnu" aria-label="Menu">☰</button><a class="bnd" href="${c.viewHref("")}" data-home="1">${c.logoHtml}<span>${e(c.brand.name)}</span></a><nav>${masters()}${admin()}</nav>${find()}</div>`;
    return { e, img, entries, bad, num, st, bd, hello, find, masters, admin, more, mrow, tail, top };
  }

  /* ---------- B · dark command centre ---------- */
  T.b = { full: true, html(c) { const h = H(c);
    return `${h.top("dk")}<div class="w"><h1>${h.hello()}</h1><p class="s">${h.e(c.brand.name.split(" – ")[0])} · ${c.mine.length} apps in your plan</p>
      ${c.groups.map((g) => `<section class="grp" style="--g:${g.color}"><h2>${g.name}</h2><div class="g">${g.items.map((r) => c.link(r, "t", `${h.bd(r)}${h.img(r, 54, 15)}<div><h3>${h.e(r.product_name)}</h3><p>${h.e(h.st(r))}</p></div><i class="dot"></i>`)).join("")}</div></section>`).join("")}
      ${h.more()}</div>`; },
    css: `.th-b{background:#0B1020;color:#E6EAF5;--c0:#9AA6C4}
.th-b .tb{display:flex;align-items:center;gap:14px;padding:14px 28px;border-bottom:1px solid rgba(255,255,255,.08);flex-wrap:wrap}
.th-b .bnd{display:flex;align-items:center;gap:10px;color:#fff;font-weight:700;text-decoration:none}.th-b .bnd img{height:34px;border-radius:9px;background:#fff;padding:2px}
.th-b nav{display:flex;gap:4px;flex-wrap:wrap}.th-b nav a{padding:7px 13px;border-radius:99px;font-size:13.5px;color:#9AA6C4;text-decoration:none}.th-b nav a:hover{background:rgba(255,255,255,.1);color:#fff}
.th-b .find{margin-left:auto}.th-b .find input{background:rgba(255,255,255,.08);border:0;border-radius:99px;padding:9px 18px;color:#fff;width:240px}
.th-b .w{padding:26px 28px 36px}.th-b h1{margin:0 0 4px;font-size:26px;color:#fff}.th-b .s{color:#8F9BBA;margin:0 0 8px}
.th-b h2{font:700 12px Arial;letter-spacing:.14em;text-transform:uppercase;color:#7C8AB0;margin:24px 0 12px}
.th-b .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px}
.th-b .t{border-radius:20px;padding:18px;background:linear-gradient(160deg,color-mix(in srgb,var(--c) 28%,#141B33),#10162B);border:1px solid color-mix(in srgb,var(--c) 35%,transparent);display:flex;gap:14px;align-items:center;position:relative;text-decoration:none;color:inherit}
.th-b .t .ic{box-shadow:0 0 22px color-mix(in srgb,var(--c) 55%,transparent)}.th-b .t h3{margin:0;font-size:15px;color:#fff}.th-b .t p{margin:2px 0 0;color:#9AA6C4;font-size:12px}
.th-b .bd{position:absolute;top:10px;right:10px;background:#F43F5E;color:#fff;border-radius:99px;font:700 10px Arial;padding:2px 8px}
.th-b .dot{position:absolute;right:14px;bottom:12px;width:8px;height:8px;border-radius:50%;background:#34D399;box-shadow:0 0 10px #34D399}.th-b .t.off{opacity:.5}.th-b .t.lk .dot{background:#64748B;box-shadow:none}
.th-b .more h2,.th-b .grp h2{color:#7C8AB0}.th-b .mc,.th-b .mchips.plain a{background:rgba(255,255,255,.07);border-color:rgba(255,255,255,.12);color:#E6EAF5}` };

  /* ---------- C · list ---------- */
  T.c = { html(c) { const h = H(c);
    return `<h1>Your apps</h1><p class="s">${c.mine.length} apps · click a row to open</p>
      <div class="bar"><button class="on" data-g="">All</button>${c.groups.map((g, i) => `<button data-g="${i}">${g.name}</button>`).join("")}${h.find()}</div>
      <div class="rows"><div class="rh"><span>App</span><span>Group</span><span class="wd">What it does</span><span>Status</span><span>Now</span><span></span></div>
      ${c.groups.map((g, i) => g.items.map((r) => c.link(r, "rw", `<span class="a">${h.img(r, 38, 10)}<b>${h.e(r.product_name)}</b></span><span>${g.name}</span><span class="wd">${h.e((c.META[r.product_code] || {}).desc || "")}</span><span><i class="p">${h.e(c.sub(r))}</i></span><span>${h.bad(r) ? `<b class="rd">${h.e(h.bad(r)[1])} ${h.e(h.bad(r)[0])}</b>` : h.e(h.st(r) === c.sub(r) ? "" : h.st(r))}</span><span class="o">Open →</span>`).replace('class="rw"', `class="rw" data-grp="${i}"`)).join("")).join("")}</div>${h.tail()}`; },
    bind(c, m) { m.querySelectorAll(".bar [data-g]").forEach((b) => b.onclick = () => { m.querySelectorAll(".bar [data-g]").forEach((x) => x.classList.toggle("on", x === b)); m.querySelectorAll(".rw").forEach((r) => { r.style.display = !b.dataset.g || r.dataset.grp === b.dataset.g ? "" : "none"; }); }); },
    css: `.th-c{background:#fff}.th-c .s{color:#5E6B7E;margin:2px 0 14px}.th-c .bar{display:flex;gap:8px;margin-bottom:14px;flex-wrap:wrap;align-items:center}
.th-c .bar button{padding:6px 14px;border:1px solid #E3E8EF;border-radius:99px;font-size:13px;background:#fff;cursor:pointer}.th-c .bar button.on{background:#16233A;color:#fff}.th-c .find{margin-left:auto}.th-c .find input{padding:8px 14px;border:1px solid #E3E8EF;border-radius:99px;width:220px}
.th-c .rh,.th-c .rw{display:grid;grid-template-columns:1.5fr .8fr 2fr 1fr 1fr 80px;gap:12px;align-items:center;padding:10px 12px;border-bottom:1px solid #EEF1F6;font-size:14px}
.th-c .rh{font:700 11px Arial;letter-spacing:.1em;text-transform:uppercase;color:#8A96A8;border-bottom:2px solid #E3E8EF}.th-c .rw{text-decoration:none;color:inherit}.th-c .rw:hover{background:#F8F5FF}.th-c .rw.off{opacity:.55}
.th-c .a{display:flex;align-items:center;gap:12px}.th-c .p{font:700 11px Arial;border-radius:99px;padding:3px 10px;background:#E7F8EF;color:#1E7B4A;font-style:normal}.th-c .rd{color:#E11D48}.th-c .o{border:1px solid #D3DBE6;border-radius:9px;padding:6px 10px;font:700 13px Arial;color:#7C3AED;text-align:center}
@media(max-width:900px){.th-c .rh{display:none}.th-c .rw{grid-template-columns:1fr auto}.th-c .rw .wd,.th-c .rw>span:nth-child(2){display:none}.th-c .rw>span:nth-child(4),.th-c .rw>span:nth-child(5){grid-column:1/-1}.th-c .find{margin-left:0;width:100%}.th-c .find input{width:100%}}` };

  /* ---------- D · bento dashboard ---------- */
  T.d = { html(c) { const h = H(c);
    const withNum = c.mine.filter((r) => h.num(r) && !/user/i.test(h.num(r)[0])).sort((a, b) => (h.bad(b) ? 1 : 0) - (h.bad(a) ? 1 : 0)), big = (withNum.length >= 3 ? withNum : c.mine).slice(0, 3), rest = c.mine.filter((r) => !big.includes(r));
    return `<h1>Welcome back</h1><p class="s">Today across ${h.e(c.brand.name.split(" – ")[0])} — tap a tile to open</p>${h.find()}
      <div class="g">${big.map((r) => { const n = h.num(r) || [c.sub(r), "—"]; return c.link(r, "b big", `<div class="h">${h.img(r, 44, 12)}<h3>${h.e(r.product_name)}</h3></div><div class="k"><b>${h.e(n[1] === "—" ? "" : n[1])}${n[1] === "—" ? h.e(n[0]) : ""}</b><span>${n[1] === "—" ? "" : h.e(n[0])}</span></div><em>Open →</em>`); }).join("")}
      ${rest.map((r) => c.link(r, "b", `${h.img(r, 44, 12)}<div><h3>${h.e(r.product_name)}</h3><small>${h.e(h.st(r))}</small></div>`)).join("")}</div>${h.tail()}`; },
    css: `.th-d{background:#EEF1F8}.th-d .s{color:#5E6B7E;margin:2px 0 12px}.th-d .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:14px}
.th-d .g{display:grid;grid-template-columns:repeat(6,1fr);gap:14px}.th-d .b{grid-column:span 2;background:#fff;border-radius:22px;padding:16px;display:flex;align-items:center;gap:12px;box-shadow:0 4px 18px rgba(20,30,70,.06);border:1px solid #E3E8EF;text-decoration:none;color:inherit}
.th-d .b h3{margin:0;font-size:14.5px}.th-d .b small{color:#6B788C;font-size:12px}.th-d .b.off{opacity:.55}
.th-d .big{grid-row:span 2;flex-direction:column;align-items:stretch;background:linear-gradient(160deg,color-mix(in srgb,var(--c) 14%,#fff),#fff 60%)}.th-d .big .h{display:flex;gap:10px;align-items:center}.th-d .big .k b{font-size:46px;line-height:1;color:var(--c)}.th-d .big .k span{display:block;color:#6B788C;font-size:13px;margin-top:4px}.th-d .big em{font:700 13px Arial;font-style:normal;color:var(--c);margin-top:auto}
@media(max-width:900px){.th-d .g{grid-template-columns:1fr 1fr}.th-d .b,.th-d .big{grid-column:span 1;grid-row:auto}.th-d .big{grid-column:span 2}}` };

  /* ---------- E · three columns ---------- */
  T.e = { html(c) { const h = H(c);
    return `<h1>Welcome back</h1><p class="s">Your apps by area of work</p>${h.find()}<div class="cols">${c.groups.map((g) => `<section class="grp col" style="--g:${g.color}"><h2>${g.name}<span>${g.items.length}</span></h2>${g.items.map((r) => c.link(r, "t", `${h.img(r, 40, 11)}<div><h3>${h.e(r.product_name)}</h3><small>${h.e(h.st(r))}</small></div><span class="a">›</span>`)).join("")}</section>`).join("")}</div>${h.tail()}`; },
    css: `.th-e{background:#F2F4FA}.th-e .s{color:#5E6B7E;margin:2px 0 12px}.th-e .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:14px}
.th-e .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px;align-items:start}.th-e .col{background:#E8ECF6;border-radius:20px;padding:14px}
.th-e .col h2{margin:2px 6px 12px;font:800 12px Arial;letter-spacing:.12em;text-transform:uppercase;color:#46546B;display:flex;justify-content:space-between}.th-e .col h2 span{background:#fff;border-radius:99px;padding:0 9px}
.th-e .t{display:flex;align-items:center;gap:12px;background:#fff;border-radius:14px;padding:11px 12px;margin-bottom:9px;box-shadow:0 2px 6px rgba(20,30,70,.06);border-left:5px solid var(--c);text-decoration:none;color:inherit}.th-e .t.off{opacity:.55}
.th-e .t h3{margin:0;font-size:14px}.th-e .t small{color:#6B788C;font-size:11.5px}.th-e .t .a{margin-left:auto;color:var(--c);font:700 18px Arial}` };

  /* ---------- F · glass ---------- */
  T.f = { html(c) { const h = H(c);
    return `<h1>Welcome back</h1><p class="s">Pick an app to start</p>${h.find()}<div class="g">${c.mine.map((r) => c.link(r, "t", `${h.img(r, 64, 18)}<h3>${h.e(r.product_name)}</h3><p>${h.e((c.META[r.product_code] || {}).desc || "")}</p><div class="f"><span>${h.e(h.st(r))}</span><b>Open</b></div>`)).join("")}</div>${h.tail()}`; },
    css: `.th-f{background:linear-gradient(135deg,#1e1b4b,#312e81 40%,#831843);color:#fff;min-height:100%}.th-f .s{color:#C7C9F0;margin:2px 0 12px}.th-f .find input{padding:9px 16px;border:1px solid rgba(255,255,255,.25);background:rgba(255,255,255,.1);color:#fff;border-radius:99px;width:260px;margin-bottom:14px}
.th-f .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:18px}.th-f .t{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.2);border-radius:24px;padding:20px;backdrop-filter:blur(10px);box-shadow:0 10px 30px rgba(0,0,0,.25);text-decoration:none;color:#fff;display:block}.th-f .t.off{opacity:.55}
.th-f .t .ic{box-shadow:0 8px 24px color-mix(in srgb,var(--c) 70%,transparent)}.th-f .t h3{margin:12px 0 4px;font-size:17px}.th-f .t p{margin:0;color:#D6D8F5;font-size:12.5px;min-height:36px}.th-f .f{display:flex;justify-content:space-between;align-items:center;margin-top:12px;font-size:12px;gap:8px}.th-f .f b{background:var(--c);border-radius:99px;padding:3px 12px}
.th-f .grp h2,.th-f .more h2{color:#C7C9F0}.th-f .mc,.th-f .mchips.plain a{background:rgba(255,255,255,.1);border-color:rgba(255,255,255,.2);color:#fff}` };

  /* ---------- G · desktop icons ---------- */
  T.g = { full: true, html(c) { const h = H(c);
    return `<div class="w"><button type="button" id="sbToggle" class="mnu" aria-label="Menu">☰</button><a class="bnd" href="${c.viewHref("")}" data-home="1">${c.logoHtml}<span>${h.e(c.brand.name)}</span></a><h1>${h.hello()}</h1><p class="s">${c.mine.length} apps in your plan</p>${h.find()}
      <div class="g">${c.mine.map((r) => c.link(r, "i", `${h.bd(r)}${h.img(r, 88, 26)}<h3>${h.e(r.product_name)}</h3>`)).join("")}</div>
      ${c.others.length ? `<h4>Try more</h4><div class="g sm">${c.others.map((r) => c.link(r, "i", `${h.img(r, 56, 16)}<h3>${h.e(r.product_name)}</h3>`, true)).join("")}</div>` : ""}
      <div class="dock">${h.masters()}${h.admin()}</div></div>`; },
    css: `.th-g{background:radial-gradient(1000px 500px at 50% -100px,#E9E4FF,#F6F8FC 60%);min-height:100%}.th-g .w{max-width:1100px;margin:0 auto;padding:30px 24px 50px;text-align:center;position:relative}
.th-g .mnu{position:absolute;left:10px;top:20px}.th-g .bnd{display:inline-flex;align-items:center;gap:10px;color:#16233A;font-weight:700;text-decoration:none}.th-g .bnd img{height:34px}
.th-g h1{margin:10px 0 4px;font-size:32px}.th-g .s{color:#5E6B7E;margin:0 0 16px}.th-g .find input{width:min(420px,100%);padding:12px 20px;background:#fff;border:1px solid #E3E8EF;border-radius:99px;box-shadow:0 6px 20px rgba(20,30,70,.06);margin-bottom:30px}
.th-g .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:26px 12px}.th-g .i{position:relative;text-decoration:none;color:#16233A}.th-g .i .ic{box-shadow:0 12px 24px rgba(20,30,70,.18);margin:0 auto;display:block}.th-g .i h3{margin:10px 0 0;font-size:13.5px;font-weight:600}.th-g .i.off{opacity:.5}
.th-g .bd{position:absolute;top:-4px;right:calc(50% - 56px);background:#E11D48;color:#fff;border-radius:99px;font:700 10px Arial;padding:2px 7px;z-index:1}.th-g h4{margin:34px 0 14px;font:700 12px Arial;letter-spacing:.14em;text-transform:uppercase;color:#8A96A8}.th-g .sm{opacity:.85}
.th-g .dock{margin:46px auto 0;display:inline-flex;flex-wrap:wrap;justify-content:center;gap:6px;background:rgba(255,255,255,.85);border:1px solid #E3E8EF;border-radius:26px;padding:10px 16px;box-shadow:0 12px 30px rgba(20,30,70,.12)}.th-g .dock a{font:700 13px Arial;color:#46546B;padding:8px 14px;text-decoration:none;border-radius:12px}.th-g .dock a:hover{background:#F0EBFF}` };

  /* ---------- H · master and detail ---------- */
  T.h = { html(c) { const h = H(c); const first = c.mine[0];
    const panel = (r) => { const m = c.META[r.product_code] || {}, en = h.entries(r); return `<div class="pv" data-pv="${r.product_code}"${r === first ? "" : " hidden"} style="--c:${m.color}"><div class="hd">${h.img(r, 96, 26)}<div><h2>${h.e(r.product_name)}</h2><p>${h.e(m.desc || "")}</p></div></div>${en.length ? `<div class="k">${en.map(([k, v]) => `<div><b${/overdue/i.test(k) && Number(v) > 0 ? ' class="rd"' : ""}>${h.e(v)}</b><span>${h.e(k)}</span></div>`).join("")}</div>` : `<div class="k"><div><b>${h.e(c.sub(r))}</b><span>Status</span></div></div>`}${c.link(r, "go", `Open ${h.e(r.product_name)} →`)}</div>`; };
    return `<div class="ms"><div class="l"><h1>Your apps</h1>${h.find()}${c.mine.map((r) => `<a class="li${r === first ? " on" : ""}" href="${c.appHref(r.product_code)}" data-sel="${r.product_code}" data-name="${h.e(String(r.product_name).toLowerCase())}">${h.img(r, 32, 9)}${h.e(r.product_name)}<i class="st"></i></a>`).join("")}</div><div class="r">${c.mine.map(panel).join("")}</div></div>${h.tail()}`; },
    bind(c, m) { m.querySelectorAll("[data-sel]").forEach((a) => a.addEventListener("click", (e) => { if (e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey) { e.preventDefault(); m.querySelectorAll("[data-sel]").forEach((x) => x.classList.toggle("on", x === a)); m.querySelectorAll(".pv").forEach((p) => { p.hidden = p.dataset.pv !== a.dataset.sel; }); } })); },
    css: `.th-h{background:#F5F7FB}.th-h .ms{display:grid;grid-template-columns:320px minmax(0,1fr);gap:0;background:#fff;border:1px solid #E3E8EF;border-radius:20px;overflow:hidden;min-height:480px}.th-h .l{border-right:1px solid #E3E8EF;padding:18px 12px}.th-h .l h1{font-size:20px;margin:0 8px 10px}
.th-h .find input{width:calc(100% - 16px);margin:0 8px 10px;padding:8px 12px;border:1px solid #E3E8EF;border-radius:10px}.th-h .li{display:flex;align-items:center;gap:12px;padding:9px 10px;border-radius:12px;font-size:14px;margin-bottom:2px;text-decoration:none;color:inherit}.th-h .li.on{background:#F0EBFF;font-weight:700}.th-h .st{margin-left:auto;width:8px;height:8px;border-radius:50%;background:#10B981}
.th-h .r{padding:34px 40px}.th-h .hd{display:flex;gap:20px;align-items:center}.th-h .hd .ic{box-shadow:0 14px 30px rgba(0,0,0,.18)}.th-h h2{margin:0;font-size:28px}.th-h .hd p{color:#5E6B7E;max-width:560px}.th-h .k{display:flex;gap:14px;margin:24px 0;flex-wrap:wrap}.th-h .k div{background:#fff;border:1px solid #E3E8EF;border-radius:16px;padding:14px 22px}.th-h .k b{display:block;font-size:28px}.th-h .k .rd{color:#E11D48}.th-h .k span{color:#6B788C;font-size:12.5px}
.th-h .go{display:inline-block;background:linear-gradient(90deg,#7C3AED,#DB2777,#F59E0B);color:#fff;font:700 15px Arial;border-radius:12px;padding:14px 28px;text-decoration:none}
@media(max-width:900px){.th-h .ms{grid-template-columns:1fr}.th-h .l{border-right:0;border-bottom:1px solid #E3E8EF}.th-h .r{padding:22px 18px}.th-h .hd{flex-direction:column;align-items:flex-start}}` };

  /* ---------- I · poster cards ---------- */
  T.i = { html(c) { const h = H(c);
    return `<h1>Welcome back</h1><p class="s">Open any app your company uses</p>${h.find()}<div class="g">${c.groups.map((g) => g.items.map((r) => c.link(r, "t", `<div class="hd" style="background:linear-gradient(135deg,var(--c),color-mix(in srgb,var(--c) 55%,#000))"><span>${g.name}</span>${h.img(r, 62, 16)}</div><div class="bo"><h3>${h.e(r.product_name)}</h3><p>${h.e((c.META[r.product_code] || {}).desc || "")}</p><span class="o">${h.bad(r) ? h.e(h.bad(r)[1] + " " + h.bad(r)[0]) + " · " : ""}Open →</span></div>`)).join("")).join("")}</div>${h.tail()}`; },
    css: `.th-i{background:#fff}.th-i .s{color:#5E6B7E;margin:2px 0 12px}.th-i .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:14px}
.th-i .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:16px}.th-i .t{border-radius:20px;overflow:hidden;border:1px solid #E3E8EF;background:#fff;text-decoration:none;color:inherit;display:block}.th-i .t.off{opacity:.55}
.th-i .hd{height:92px;display:flex;align-items:flex-end;padding:0 16px;position:relative}.th-i .hd .ic{margin-bottom:-22px;border:3px solid #fff;box-shadow:0 6px 14px rgba(0,0,0,.2)}.th-i .hd span{position:absolute;right:12px;top:10px;color:#fff;font:700 10.5px Arial;background:rgba(255,255,255,.22);border-radius:99px;padding:2px 9px}
.th-i .bo{padding:30px 16px 14px}.th-i h3{margin:0;font-size:15px}.th-i p{margin:3px 0 10px;color:#6B788C;font-size:12.5px;min-height:34px}.th-i .o{font:700 12.5px Arial;color:var(--c)}` };

  /* ---------- J · search first ---------- */
  T.j = { html(c) { const h = H(c);
    const rec = c.recent().map((k) => c.mine.find((r) => r.product_code === k)).filter(Boolean).slice(0, 3);
    return `<h1>${h.hello()}.</h1><p class="s">What would you like to work on?</p>${h.find("Search apps…")}
      ${rec.length ? `<section class="grp"><h2>Recently used</h2><div class="rec">${rec.map((r) => c.link(r, "rc", `${h.img(r, 40, 11)}<span>${h.e(r.product_name)}<small>${h.e(h.st(r))}</small></span>`)).join("")}</div></section>` : ""}
      ${c.groups.map((g) => `<section class="grp"><h2>${g.name}</h2><div class="ch">${g.items.map((r) => c.link(r, "cp", `${h.img(r, 32, 16)}${h.e(r.product_name)}${h.bd(r)}`)).join("")}</div></section>`).join("")}${h.tail()}`; },
    css: `.th-j{background:#FBFAF7;color:#1F2937}.th-j h1{font:800 34px Georgia,serif}.th-j .s{color:#6B7280;margin:4px 0 20px}.th-j .find input{display:block;width:min(640px,100%);padding:14px 22px;background:#fff;border:1px solid #E5E7EB;border-radius:14px;margin-bottom:22px;font-size:15px}
.th-j .grp h2{font:700 12px Arial;letter-spacing:.14em;text-transform:uppercase;color:#9CA3AF;margin:22px 0 12px}.th-j .rec{display:flex;gap:14px;flex-wrap:wrap}.th-j .rc{background:#1F2937;color:#fff;border-radius:16px;padding:14px 18px;display:flex;gap:12px;align-items:center;min-width:220px;text-decoration:none}.th-j .rc small{display:block;color:#9CA3AF;font-size:11.5px}
.th-j .ch{display:flex;flex-wrap:wrap;gap:10px}.th-j .cp{display:inline-flex;align-items:center;gap:10px;background:#fff;border:1px solid #E5E7EB;border-radius:99px;padding:7px 18px 7px 8px;font-weight:600;font-size:14px;text-decoration:none;color:inherit}.th-j .cp:hover{border-color:#7C3AED}.th-j .cp.off{opacity:.55}.th-j .bd{background:#E11D48;color:#fff;border-radius:99px;font:700 10px Arial;padding:2px 7px}` };

  /* ---------- K · area tabs ---------- */
  T.k = { html(c) { const h = H(c);
    return `<h1>Welcome back</h1><p class="s">Choose an area, then an app</p><div class="tabs"><button class="on" data-t="">All</button>${c.groups.map((g, i) => `<button data-t="${i}">${g.name}</button>`).join("")}${c.ops || c.isAdmin ? `<button data-t="m">Masters</button>` : ""}</div>${h.find()}
      ${c.groups.map((g, i) => `<section class="grp pane" data-p="${i}"><div class="g">${g.items.map((r) => c.link(r, "t", `${h.img(r, 84, 22)}<div><h3>${h.e(r.product_name)}</h3><p>${h.e((c.META[r.product_code] || {}).desc || "")}</p><div class="st"><span>${h.e(h.st(r))}</span><span class="o">Open</span></div></div>`)).join("")}</div></section>`).join("")}
      <section class="grp pane" data-p="m"><div class="mchips plain">${h.masters()}${h.admin()}</div></section>${h.more()}`; },
    bind(c, m) { m.querySelectorAll(".tabs [data-t]").forEach((b) => b.onclick = () => { m.querySelectorAll(".tabs [data-t]").forEach((x) => x.classList.toggle("on", x === b)); m.querySelectorAll(".pane").forEach((p) => { p.style.display = !b.dataset.t ? (p.dataset.p === "m" ? "none" : "") : p.dataset.p === b.dataset.t ? "" : "none"; }); }); m.querySelector('.pane[data-p="m"]').style.display = "none"; },
    css: `.th-k{background:#F4F6FB}.th-k .s{color:#5E6B7E;margin:2px 0 14px}.th-k .tabs{display:flex;gap:4px;border-bottom:2px solid #E3E8EF;margin-bottom:16px;overflow-x:auto}.th-k .tabs button{padding:10px 20px;font:700 14px Arial;color:#6B788C;border:0;background:none;border-bottom:3px solid transparent;margin-bottom:-2px;cursor:pointer;white-space:nowrap}.th-k .tabs button.on{color:#7C3AED;border-color:#7C3AED}
.th-k .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:16px}.th-k .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px;margin-bottom:18px}
.th-k .t{background:#fff;border-radius:22px;padding:22px;display:grid;grid-template-columns:84px 1fr;gap:18px;box-shadow:0 6px 22px rgba(20,30,70,.07);border:1px solid #E3E8EF;text-decoration:none;color:inherit}.th-k .t.off{opacity:.55}.th-k h3{margin:0 0 4px;font-size:17px}.th-k .t p{margin:0 0 10px;font-size:12.5px;color:#6B788C}
.th-k .st{display:flex;justify-content:space-between;align-items:center;font-size:12px;color:#6B788C;gap:8px}.th-k .o{background:var(--c);color:#fff;font:700 12.5px Arial;border-radius:99px;padding:6px 16px}` };

  /* ---------- L · control room ---------- */
  T.l = { full: true, html(c) { const h = H(c);
    return `${h.top("dk")}<div class="w"><div class="hd"><h1>${h.e(c.brand.name.toUpperCase())}</h1><span>${new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }).toUpperCase()} · ${c.mine.length} APPS</span></div>
      <div class="g">${c.mine.map((r) => { const n = h.num(r); return c.link(r, "t", `<span class="z">↗</span><div class="r">${h.img(r, 30, 8)}${h.e(r.product_name)}</div><b>${n ? h.e(n[1]) : "–"}</b><small>${n ? h.e(n[0]) : h.e(c.sub(r))}</small>`); }).join("")}</div>${h.more()}</div>`; },
    css: `.th-l{background:#05070F;color:#D7DEFF}.th-l .tb{display:flex;align-items:center;gap:14px;padding:14px 28px;border-bottom:1px solid #1C2540;flex-wrap:wrap}.th-l .bnd{display:flex;align-items:center;gap:10px;color:#fff;font-weight:700;text-decoration:none}.th-l .bnd img{height:30px;border-radius:8px;background:#fff;padding:2px}
.th-l nav{display:flex;gap:4px;flex-wrap:wrap}.th-l nav a{padding:6px 12px;border-radius:99px;font-size:13px;color:#7C89B0;text-decoration:none}.th-l nav a:hover{color:#fff;background:#101830}.th-l .find{margin-left:auto}.th-l .find input{background:#0B1020;border:1px solid #1C2540;border-radius:99px;padding:8px 16px;color:#fff;width:220px}
.th-l .w{padding:22px 28px 36px}.th-l .hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;gap:10px;flex-wrap:wrap}.th-l h1{margin:0;font-size:20px;letter-spacing:.04em;color:#fff}.th-l .hd span{color:#5EEAD4;font:600 13px monospace}
.th-l .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}.th-l .t{border:1px solid #1C2540;border-radius:14px;padding:16px 16px 14px 20px;background:linear-gradient(180deg,#0B1020,#080C18);position:relative;overflow:hidden;text-decoration:none;color:inherit;display:block}.th-l .t.off{opacity:.5}
.th-l .t::before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--c);box-shadow:0 0 14px var(--c)}.th-l .r{display:flex;align-items:center;gap:10px;color:#fff;font-weight:600;font-size:14px}.th-l .t b{display:block;font:700 38px/1.1 "Segoe UI",Arial;color:var(--c);margin:14px 0 2px;text-shadow:0 0 18px color-mix(in srgb,var(--c) 60%,transparent)}.th-l .t small{color:#7C89B0;font-size:12px}.th-l .z{position:absolute;right:12px;top:14px;color:#3B4668;font-size:18px}
.th-l .grp h2{color:#7C89B0}.th-l .mc{background:#0B1020;border-color:#1C2540;color:#D7DEFF}` };

  /* ---------- M · magazine ---------- */
  T.m = { html(c) { const h = H(c);
    const hero = c.mine.find((r) => h.bad(r)) || c.mine[0]; if (!hero) return "";
    const hb = h.bad(hero), hm = c.META[hero.product_code] || {};
    return `<h1>Welcome back</h1><p class="s">${hb ? "Needs your attention first" : "Continue where you left off"}</p>
      ${c.link(hero, "hero", `${h.img(hero, 110, 28)}<div><h2>${h.e(hero.product_name)}</h2><p>${hb ? `${h.e(hb[1])} ${h.e(hb[0])}. Open it and deal with them.` : h.e(hm.desc || "")}</p><span>${hb ? "Review now →" : "Open →"}</span></div>`)}
      ${h.find()}<div class="g">${c.mine.filter((r) => r !== hero).map((r) => c.link(r, "rr", `${h.img(r, 46, 13)}<div><h3>${h.e(r.product_name)}</h3><p>${h.e(h.st(r))}</p></div><i>›</i>`)).join("")}</div>${h.tail()}`; },
    css: `.th-m{background:#fff}.th-m .s{color:#6B7280;margin:2px 0 14px}.th-m .hero{border-radius:26px;padding:26px 30px;color:#fff;background:linear-gradient(120deg,#4C1D95,#7C3AED 50%,#DB2777);display:flex;align-items:center;gap:26px;margin-bottom:18px;text-decoration:none}.th-m .hero .ic{box-shadow:0 14px 30px rgba(0,0,0,.35)}.th-m .hero h2{margin:0 0 6px;font-size:28px}.th-m .hero p{margin:0 0 14px;opacity:.9;max-width:520px}.th-m .hero span{background:#fff;color:#7C3AED;font:700 14px Arial;border-radius:99px;padding:9px 22px;display:inline-block}
.th-m .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:8px}.th-m .g{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:0 28px}.th-m .rr{display:flex;gap:14px;align-items:center;padding:14px 4px;border-bottom:1px solid #EEF1F6;text-decoration:none;color:inherit}.th-m .rr.off{opacity:.55}.th-m .rr h3{margin:0;font-size:15px}.th-m .rr p{margin:1px 0 0;color:#6B7280;font-size:12.5px}.th-m .rr i{margin-left:auto;color:#9CA3AF;font-style:normal;font-size:20px}
@media(max-width:700px){.th-m .hero{flex-direction:column;align-items:flex-start}}` };

  /* ---------- N · part journey ---------- */
  const STAGES = [["PLAN", "#10B981", ["capacity", "sales", "crm", "rmp", "inv"]], ["DEVELOP", "#A855F7", ["apqp", "cad", "balloon", "pd", "ppap", "layout"]], ["MAKE", "#EA580C", ["mmd", "dcg", "mnt"]], ["CHECK", "#6366F1", ["calib", "msa", "spc", "d8", "aud"]], ["IMPROVE", "#7C3AED", ["mom", "tsk", "qms", "off", "dwm"]], ["PEOPLE", "#0EA5E9", ["hrms"]]];
  T.n = { html(c) { const h = H(c);
    const known = STAGES.flatMap((s) => s[2]), rest = c.mine.filter((r) => !known.includes(r.product_code));
    const st = STAGES.map(([n, col, ks]) => [n, col, c.mine.filter((r) => ks.includes(r.product_code)).sort((a, b) => ks.indexOf(a.product_code) - ks.indexOf(b.product_code))]).concat(rest.length ? [["OTHER", "#64748B", rest]] : []).filter((s) => s[2].length);
    return `<h1>Your plant, start to finish</h1><p class="s">Apps follow the way a part moves through your company</p>${h.find()}
      <div class="flow">${st.map(([n, col, items]) => `<section class="grp st" style="--c:${col}"><div class="hd">${n}</div><div class="cc">${items.map((r) => c.link(r, "a", `${h.bd(r)}${h.img(r, 52, 15)}<h3>${h.e(r.product_name)}</h3><small>${h.e(h.st(r))}</small>`)).join("")}</div></section>`).join("")}</div>
      <p class="note">Plan the month → get the part approved → make it → check it → learn and improve</p>${h.tail()}`; },
    css: `.th-n{background:#F3F5FA}.th-n .s{color:#5E6B7E;margin:2px 0 12px}.th-n .find input{padding:9px 16px;border:1px solid #E3E8EF;border-radius:99px;width:260px;margin-bottom:14px}
.th-n .flow{display:flex;gap:10px;align-items:flex-start}.th-n .st{flex:1;min-width:0}.th-n .st .hd{background:var(--c);color:#fff;font:800 12px Arial;letter-spacing:.14em;padding:12px 16px;clip-path:polygon(0 0,calc(100% - 14px) 0,100% 50%,calc(100% - 14px) 100%,0 100%);border-radius:12px 0 0 12px}
.th-n .cc{margin-top:10px;display:flex;flex-direction:column;gap:10px}.th-n .a{background:#fff;border:1px solid #E3E8EF;border-radius:16px;padding:12px;text-align:center;box-shadow:0 3px 10px rgba(20,30,70,.06);border-top:4px solid var(--c);text-decoration:none;color:inherit;position:relative;display:block}.th-n .a.off{opacity:.55}
.th-n .a .ic{margin:0 auto;display:block}.th-n .a h3{margin:6px 0 0;font-size:13px}.th-n .a small{color:#6B788C;font-size:11px}.th-n .bd{position:absolute;top:6px;right:6px;background:#E11D48;color:#fff;border-radius:99px;font:700 9.5px Arial;padding:2px 6px}.th-n .note{margin-top:22px;color:#6B788C;font-size:13px}
@media(max-width:900px){.th-n .flow{flex-direction:column}.th-n .st{width:100%}.th-n .cc{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}}` };

  /* ---------- O · plant floor map ---------- */
  const ZONES = [["OFFICE · PLANNING", "#10B981", ["capacity", "sales", "crm", "rmp", "inv", "apqp", "ppap", "cad", "layout"]], ["QUALITY LAB", "#6366F1", ["balloon", "pd", "calib", "msa", "spc", "d8"]], ["SHOP FLOOR", "#EA580C", ["mmd", "dcg", "mnt"]], ["MEETING ROOM", "#7C3AED", ["mom", "tsk", "qms", "dwm"]], ["HR OFFICE", "#0EA5E9", ["hrms"]]];
  T.o = { html(c) { const h = H(c);
    const known = ZONES.flatMap((z) => z[2]), rest = c.mine.filter((r) => !known.includes(r.product_code));
    const zs = ZONES.map(([n, col, ks]) => [n, col, c.mine.filter((r) => ks.includes(r.product_code))]).concat(rest.length ? [["OTHER", "#64748B", rest]] : []).filter((z) => z[2].length);
    return `<h1>Plant floor</h1><p class="s">Walk to the area you need — click a station to open the app</p>${h.find()}<div class="floor">${zs.map(([n, col, items]) => `<section class="grp z" style="--c:${col}"><span>${n}</span>${items.map((r) => c.link(r, "n", `${h.bd(r)}${h.img(r, 62, 18)}<b>${h.e(r.product_name)}</b>`)).join("")}</section>`).join("")}</div>${h.tail()}`; },
    css: `.th-o{background:#0F172A;color:#fff}.th-o .s{color:#94A3B8;margin:2px 0 12px}.th-o .find input{padding:9px 16px;border:1px solid #243352;background:#162036;color:#fff;border-radius:99px;width:260px;margin-bottom:14px}
.th-o .floor{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:30px 22px;padding:30px 22px;border-radius:24px;background:#162036 linear-gradient(#1E2A44 1px,transparent 1px),linear-gradient(90deg,#1E2A44 1px,transparent 1px);background-size:40px 40px;border:1px solid #243352}
.th-o .z{position:relative;border:2px dashed color-mix(in srgb,var(--c) 70%,transparent);border-radius:18px;background:color-mix(in srgb,var(--c) 8%,transparent);padding:26px 14px 16px;display:flex;flex-wrap:wrap;gap:14px;align-content:flex-start;min-height:150px}.th-o .z>span{position:absolute;top:-11px;left:16px;background:#0F172A;color:var(--c);font:800 11px Arial;letter-spacing:.14em;padding:0 8px}
.th-o .n{text-align:center;width:104px;position:relative;text-decoration:none;color:#fff;display:block}.th-o .n.off{opacity:.5}.th-o .n .ic{margin:0 auto;display:block;box-shadow:0 0 0 3px #0F172A,0 0 22px color-mix(in srgb,var(--c) 60%,transparent)}.th-o .n b:not(.bd){display:block;font-size:12px;margin-top:8px;font-weight:600}
.th-o .bd{position:absolute;top:-6px;right:6px;background:#F43F5E;border-radius:99px;font:700 10px Arial;padding:2px 7px;color:#fff;z-index:1}.th-o .grp h2{color:#94A3B8}.th-o .mc,.th-o .mchips.plain a{background:#162036;border-color:#243352;color:#fff}` };

  /* ---------- P · radial hub ---------- */
  T.p = { html(c) { const h = H(c);
    const inner = c.mine.filter((r) => ["capacity", "sales", "rmp", "mmd", "mnt"].includes(r.product_code)), outer = c.mine.filter((r) => !inner.includes(r));
    // build nodes explicitly (position + colour)
    const node = (r, rad, a) => { const m = c.META[r.product_code] || {}; return c.link(r, "n", `${h.img(r, 64, 20)}<b>${h.e(r.product_name)}</b>`).replace('style="--c:', `style="left:${(50 + rad * Math.cos(a)).toFixed(2)}%;top:${(50 + rad * Math.sin(a)).toFixed(2)}%;--c:`); };
    const place = (list, rad, off) => list.map((r, i) => node(r, rad, -Math.PI / 2 + 2 * Math.PI * i / list.length + off)).join("");
    return `<h1>Your company at the centre</h1>${h.find()}<div class="hub"><i class="rg r1"></i><i class="rg r2"></i><div class="core">${h.e(c.brand.name.split(" – ").join("<br>"))}</div>${place(inner, 23, 0)}${place(outer, 40, 0.3)}</div>${h.tail()}`; },
    css: `.th-p{background:radial-gradient(circle at 50% 50%,#2A1B5E,#0B0820 75%);color:#fff}.th-p h1{margin:0 0 8px;font-size:24px}.th-p .find input{padding:9px 16px;border:1px solid rgba(255,255,255,.25);background:rgba(255,255,255,.1);color:#fff;border-radius:99px;width:260px}
.th-p .hub{position:relative;width:min(100%,780px);aspect-ratio:1/1;margin:8px auto 0}.th-p .rg{position:absolute;border:1px dashed rgba(255,255,255,.18);border-radius:50%;left:50%;top:50%;transform:translate(-50%,-50%)}.th-p .r1{width:46%;height:46%}.th-p .r2{width:80%;height:80%}
.th-p .core{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:19%;aspect-ratio:1/1;border-radius:50%;background:linear-gradient(135deg,#22D3EE,#7C3AED 55%,#EC4899);display:grid;place-items:center;text-align:center;font:800 clamp(9px,1.6vw,14px) Arial;box-shadow:0 0 60px rgba(168,85,247,.6);padding:6px}
.th-p .n{position:absolute;transform:translate(-50%,-50%);width:clamp(66px,13%,100px);text-align:center;text-decoration:none;color:#fff}.th-p .n.off{opacity:.5}.th-p .n .ic{margin:0 auto;display:block;width:clamp(44px,70%,64px)!important;height:auto!important;aspect-ratio:1/1;box-shadow:0 0 24px color-mix(in srgb,var(--c) 70%,transparent)}.th-p .n b{display:block;font-size:clamp(9.5px,1.4vw,11.5px);margin-top:5px;font-weight:600}
.th-p .grp h2{color:#C7C9F0}
@media(max-width:700px){.th-p .hub{aspect-ratio:auto;display:grid;grid-template-columns:repeat(3,1fr);gap:16px 6px}.th-p .rg{display:none}.th-p .core{position:static;transform:none;grid-column:1/-1;width:auto;aspect-ratio:auto;border-radius:18px;padding:16px;font-size:14px}.th-p .n{position:static!important;transform:none;width:auto}}.th-p .mc,.th-p .mchips.plain a{background:rgba(255,255,255,.1);border-color:rgba(255,255,255,.2);color:#fff}` };

  /* ---------- Q · today board ---------- */
  T.q = { html(c) { const h = H(c);
    const items = []; c.mine.forEach((r) => h.entries(r).forEach(([k, v]) => { if (Number(v) > 0 && /overdue|open|due|pending|late/i.test(k)) items.push([r, k, v, /overdue|late/i.test(k) ? "red" : "amb"]); }));
    items.sort((a, b) => (a[3] === "red" ? 0 : 1) - (b[3] === "red" ? 0 : 1));
    return `<h1>${h.hello()}</h1><p class="s">${new Date().toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })} · here is what needs you today</p>
      <div class="cols"><div class="card"><h2>Needs your attention</h2>${items.length ? items.map(([r, k, v, t]) => c.link(r, "it", `${h.img(r, 38, 10)}<div><b>${h.e(v)} ${h.e(k)}</b><small>${h.e(r.product_name)}</small></div><span class="tag ${t}">${t === "red" ? "Overdue" : "Open"}</span><span class="go">Open →</span>`)).join("") : `<p class="clear">✔ Nothing is waiting for you today.</p>`}</div>
      <div class="card"><h2>All apps</h2>${h.find()}<div class="ap">${c.mine.map((r) => c.link(r, "x", `${h.img(r, 46, 13)}${h.e(String(r.product_name).split(" —")[0])}`)).join("")}</div></div></div>${h.tail()}`; },
    css: `.th-q{background:#F5F7FB}.th-q .s{color:#5E6B7E;margin:2px 0 18px}.th-q .cols{display:grid;grid-template-columns:1.25fr 1fr;gap:20px;align-items:start}.th-q .card{background:#fff;border:1px solid #E3E8EF;border-radius:20px;padding:18px 20px;box-shadow:0 4px 16px rgba(20,30,70,.05)}
.th-q h2{margin:0 0 12px;font:800 12px Arial;letter-spacing:.12em;text-transform:uppercase;color:#46546B}.th-q .find input{width:100%;padding:8px 14px;border:1px solid #E3E8EF;border-radius:10px;margin-bottom:12px}
.th-q .it{display:flex;gap:12px;align-items:center;padding:11px 0;border-bottom:1px solid #EEF1F6;text-decoration:none;color:inherit;flex-wrap:wrap}.th-q .it:last-child{border:0}.th-q .it b{display:block;font-size:14px}.th-q .it small{color:#6B788C;font-size:12px}.th-q .tag{margin-left:auto;font:700 11px Arial;border-radius:99px;padding:3px 10px}.th-q .red{background:#FFE4E8;color:#BE123C}.th-q .amb{background:#FFF4E0;color:#9A5B00}.th-q .go{color:#7C3AED;font:700 12.5px Arial}.th-q .clear{color:#1E7B4A;font-weight:600;margin:6px 0}
.th-q .ap{display:grid;grid-template-columns:repeat(auto-fill,minmax(84px,1fr));gap:12px}.th-q .x{text-align:center;font-size:11.5px;font-weight:600;text-decoration:none;color:inherit}.th-q .x .ic{display:block;margin:0 auto 4px}.th-q .x.off{opacity:.55}
@media(max-width:900px){.th-q .cols{grid-template-columns:1fr}}` };

  /* ---------- R · spotlight ---------- */
  T.r = { full: true, html(c) { const h = H(c);
    const acts = []; if (c.ops) acts.push(`<a class="r2" href="${c.viewHref("ops")}" data-ops="1" data-name="operations master gauges parts machines masters"><span class="em">⚙</span><div><b>Operations Master</b><small>Machines, parts, gauges, tools</small></div></a>`);
    if (c.isAdmin) acts.push(`<a class="r2" href="${c.viewHref("data")}" data-datam="1" data-name="data master import export"><span class="em">🗄</span><div><b>Data Master</b><small>Import, export, backup</small></div></a>`, `<a class="r2" href="${c.viewHref("grand")}" data-grand="1" data-name="grand master"><span class="em">★</span><div><b>Grand Master</b><small>Every record of the company</small></div></a>`, `<a class="r2" href="${c.viewHref("users")}" data-admin="users" data-name="users access people"><span class="em">👥</span><div><b>Users &amp; access</b><small>Who can open what</small></div></a>`, `<a class="r2" href="${c.viewHref("company")}" data-admin="company" data-name="company details logo"><span class="em">🏢</span><div><b>Company details &amp; logo</b><small>Administration</small></div></a>`);
    return `<div class="bgw"><button type="button" id="sbToggle" class="mnu" aria-label="Menu">☰</button><div class="p"><div class="q">🔍<input id="appFind" type="search" placeholder="Type to find any app or action…" autocomplete="off"><kbd>/</kbd></div>
      <div class="h">Apps</div>${c.mine.map((r) => c.link(r, "r2", `${h.img(r, 34, 9)}<div><b>${h.e(r.product_name)}</b><small>${h.e(h.st(r))}</small></div><span class="rt">↵</span>`)).join("")}
      ${acts.length ? `<div class="h">Jump to</div>${acts.join("")}` : ""}
      ${c.others.length ? `<div class="h">Other apps</div>${c.others.map((r) => c.link(r, "r2", `${h.img(r, 30, 8)}<div><b>${h.e(r.product_name)}</b><small>Try with sample data</small></div>`, true)).join("")}` : ""}
      <div class="ft"><span>↑↓ move</span><span>↵ open</span><span>/ search</span><span class="rt">${h.e(c.brand.name)}</span></div></div></div>`; },
    bind(c, m) { const inp = m.querySelector("#appFind"), list = () => [...m.querySelectorAll(".r2")].filter((x) => x.style.display !== "none");
      const mark = (i) => { const l = list(); m.querySelectorAll(".r2.on").forEach((x) => x.classList.remove("on")); if (l[i]) { l[i].classList.add("on"); l[i].scrollIntoView({ block: "nearest" }); } return i; };
      let at = 0; mark(0);
      inp.addEventListener("input", () => { setTimeout(() => { m.querySelectorAll(".h").forEach((hd) => { let n = hd.nextElementSibling, any = false; while (n && n.classList.contains("r2")) { if (n.style.display !== "none") any = true; n = n.nextElementSibling; } hd.style.display = any ? "" : "none"; }); at = mark(0); }, 0); });
      document.addEventListener("keydown", function kd(e) { if (!document.body.contains(inp)) return document.removeEventListener("keydown", kd);
        if (e.key === "/" && document.activeElement !== inp && !/input|textarea|select/i.test(document.activeElement.tagName)) { e.preventDefault(); inp.focus(); }
        else if (e.key === "ArrowDown") { e.preventDefault(); at = mark(Math.min(list().length - 1, at + 1)); }
        else if (e.key === "ArrowUp") { e.preventDefault(); at = mark(Math.max(0, at - 1)); }
        else if (e.key === "Enter" && document.activeElement === inp) { const l = list(); if (l[at]) { e.preventDefault(); l[at].click(); } } }); },
    css: `.th-r{background:linear-gradient(135deg,#C7D2FE,#FBCFE8 50%,#FDE68A);min-height:100%}.th-r .bgw{min-height:calc(100vh - 44px);display:grid;place-items:start center;padding:6vh 14px 40px;position:relative}.th-r .mnu{position:absolute;left:14px;top:14px}
.th-r .p{width:min(760px,100%);background:rgba(255,255,255,.93);backdrop-filter:blur(20px);border-radius:26px;box-shadow:0 40px 90px rgba(30,20,80,.35);overflow:hidden}.th-r .q{display:flex;gap:14px;align-items:center;padding:20px 26px;border-bottom:1px solid #E5E7EB;font-size:20px;color:#6B7280}.th-r .q input{flex:1;border:0;background:none;font-size:20px;outline:0;color:#16233A;min-width:0}.th-r kbd{font:600 12px Arial;border:1px solid #D1D5DB;border-radius:6px;padding:2px 8px}
.th-r .h{padding:14px 26px 6px;font:700 11px Arial;letter-spacing:.12em;color:#9CA3AF;text-transform:uppercase}.th-r .r2{display:flex;align-items:center;gap:14px;padding:10px 26px;text-decoration:none;color:inherit}.th-r .r2.on,.th-r .r2:hover{background:#F0EBFF}.th-r .r2.off{opacity:.55}.th-r .r2 b{font-size:15px;display:block}.th-r .r2 small{color:#6B7280}.th-r .em{font-size:20px;width:34px;text-align:center}.th-r .rt{margin-left:auto;font:600 12px Arial;color:#9CA3AF}
.th-r .ft{display:flex;gap:18px;padding:12px 26px;background:#F9FAFB;border-top:1px solid #E5E7EB;font-size:12px;color:#6B7280;margin-top:8px;flex-wrap:wrap}` };

  /* ---------- shared look (all themes) ---------- */
  const BASE = `.main.th{padding:26px 34px 40px}.main.th-full{padding:0}.th .ic{object-fit:cover;flex:none}.th .fb{display:inline-grid;place-items:center;background:#E5E7EB;color:#374151;font-weight:800}
.th h1{margin:0}.th .mchips{display:flex;flex-wrap:wrap;gap:10px}.th .mc,.th .mchips.plain a{display:inline-flex;align-items:center;gap:8px;background:#fff;border:1px solid #E3E8EF;border-radius:99px;padding:5px 14px 5px 6px;font:600 13px "Segoe UI",Arial;text-decoration:none;color:#16233A}.th .mc em{font-style:normal;color:#7C3AED;font-size:11px}.th .mchips.plain a{padding:7px 14px}
.th .grp.more{margin-top:26px}.th .grp.more h2{font:800 12px Arial;letter-spacing:.12em;text-transform:uppercase;margin:0 0 10px;display:flex;gap:8px;align-items:center}.th .grp.more h2 i{display:none}.th .grp.more small{opacity:.6}
.th .mnu{display:none;border:1px solid rgba(120,120,140,.4);background:rgba(255,255,255,.7);border-radius:10px;padding:6px 12px;font-size:18px;cursor:pointer}.th-full .mnu{display:inline-block}
.app.nosb{grid-template-columns:minmax(0,1fr)}.app.nosb .side{display:none}.app.nosb.sb .side{display:flex;position:fixed;left:0;top:0;bottom:0;width:270px;z-index:60;overflow:auto;box-shadow:0 0 60px rgba(0,0,0,.5)}
@media(max-width:900px){.main.th{padding:18px 14px 30px}.app.nosb.sb .side{flex-direction:column!important;flex-wrap:nowrap!important;overflow:auto;padding:22px 14px!important;align-items:stretch!important}.app.nosb.sb .side h4,.app.nosb.sb .side .lock{display:block}.app.nosb.sb .side a:not(.who),.app.nosb.sb .side button{width:100%!important;background:none;border-radius:10px;padding:9px 10px;white-space:normal}.app.nosb.sb .side .who{width:100%!important}}`;
  const st = document.createElement("style"); st.id = "kmr-themes"; st.textContent = BASE + Object.values(T).map((t) => t.css).join("\n"); document.head.appendChild(st);
})();
