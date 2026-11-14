/* KMR Apps — Grand Master (company administrators): three cards for the whole company.
   1. Real Data       — every app's real data (not sample): one JSON download, upload (restore), flush (backup first)
   2. Sample Data     — every app's sample data: load all, flush all
   3. Administration  — company details & logo, users & access, invoices & payments: download, upload, flush (backup first) */
(function () {
  "use strict";
  const APP = { hrms: "HRM & Payroll", tsk: "ActionTrack", msa: "MSA Studies", spc: "SPC Charts", crm: "CRM & RFQ", d8: "8D Problem Solving", aud: "Internal Audit", off: "KMR Office Suite", balloon: "Balloon Inspector", pd: "Process Documents", capacity: "Capacity Planner", sales: "Sales Flow", calib: "Calibration Hub", apqp: "APQP Planner", ppap: "PPAP Submissions", rmp: "Raw Material Planning", mmd: "Material Movement", mnt: "Maintenance", ops: "Operations Master" };
  const UNIT = { hrms: "employees", tsk: "tasks", msa: "studies", spc: "charts", crm: "companies", d8: "reports", aud: "audits", off: "files", balloon: "reports", pd: "records", capacity: "records", sales: "plan lines", calib: "instruments", apqp: "programmes", ppap: "submissions", rmp: "records", mmd: "records", mnt: "records", mom: "records", cad: "drawings", ops: "records" };
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const stamp = () => { const d = new Date(), z = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}`; };
  function save(json, name) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([JSON.stringify(json)], { type: "application/json" }));
    a.download = name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  }
  const sum = (o) => Object.values(o || {}).reduce((s, v) => s + (Number(v) || 0), 0);
  const rows = (o, unit) => Object.keys(APP).filter((k) => o && o[k] !== undefined)
    .map((k) => `<tr><td>${APP[k]}</td><td style="text-align:right"><b>${o[k]}</b> <small>${unit ? unit[k] : ""}</small></td></tr>`).join("");
  const btn = (id, label, opts = {}) => `<button class="btn ghost" id="${id}" style="height:38px${opts.red ? ";color:#B00E28" : ""}" ${opts.off ? "disabled" : ""}>${label}</button>`;
  const upl = (id, label) => `<label class="btn ghost" style="height:38px;cursor:pointer">${label}<input type="file" accept=".json,application/json" id="${id}" hidden></label>`;

  window.KMR_GRAND = {
    /** ctx: { sb, slug, main, dialog } */
    async overview(ctx, note) {
      const head = `<h1>Grand Master</h1><p class="sub">The whole company in three cards: real data, sample data and administration. Every flush downloads a JSON backup first; uploading that file brings everything back.</p>`;
      ctx.main.innerHTML = head + `<p class="msg">Loading…</p>`;
      const { data: o, error } = await ctx.sb.rpc("kmr_grand_overview", { p_slug: ctx.slug });
      if (error) { ctx.main.querySelector(".msg").textContent = error.message; return; }
      this.o = o;
      const A = o.admin || {}, nReal = sum(o.real), nSample = sum(o.sample);
      ctx.main.innerHTML = head + `
        ${note ? `<div class="card" style="border-color:#1E7B4A;background:#E7F8EF;margin-bottom:14px">${note}</div>` : ""}
        <div class="cards">
          <div class="card" style="--c:#1E7B4A"><div style="font-size:26px;line-height:1">🗄</div><h3>Real Data Master</h3>
            <p>Everything your team created in every app — not the sample data.</p>
            <table class="gm">${rows(o.real, UNIT)}</table>
            <div class="gm-btns">${btn("gmRealDl", "Download JSON")}${upl("gmRealUp", "Upload JSON")}${btn("gmRealFl", "Flush real data", { red: 1, off: !nReal })}</div></div>
          <div class="card" style="--c:#4F46E5"><div style="font-size:26px;line-height:1">🧪</div><h3>Sample Data Master</h3>
            <p>${nSample ? `<b>${nSample}</b> sample records are still in your apps.` : "No sample data is in your apps."} <b>Remove sample data</b> deletes only the sample records from every app. Your own data is never touched; a copy is kept first.</p>
            <table class="gm">${rows(o.sample, { msa: "sample MSA studies", spc: "sample charts & readings", crm: "sample customers, leads, RFQs & quotations", d8: "sample 8D reports, actions & log", aud: "sample audits, findings, actions & log", tsk: "sample tasks & comments", hrms: "sample employees, punches & leave", balloon: "sample drawing", sales: "sample plan lines", calib: "sample instruments", apqp: "sample programmes", rmp: "sample materials & orders", mmd: "sample route sheets & tags", mnt: "sample breakdowns & PM", mom: "sample meetings & points", cad: "sample drawings", ppap: "sample submissions", ops: "sample records" })}</table>
            <p style="font-size:12px;color:var(--muted)">HRM &amp; Payroll gets 24 sample employees on two shifts, two sample fingerprint / face machines with punches for the last month and this month, leave requests and holidays; open Attendance and press <i>Work out attendance</i>, then make a payroll. Process Documents and Capacity Planner use the Operations Master lists, so they get the sample too. Sales Flow gets last month’s and this month’s plan for every sample part (prices from the sample rate contracts) with daily despatch, loss reasons and action plans; Calibration Hub gets every sample gauge as an instrument with its calibration history, an out-of-tolerance case and an MSA study. APQP Planner gets three programmes (built from the sample parts and CFT team) at different phases, and PPAP Submissions two Level 3 submissions linked to them.</p>
            <div class="gm-btns">${ctx.dev && ctx.sampleOk ? btn("gmSmpLd", "Load sample data") : ""}${btn("gmSmpFl", "Remove sample data from all apps", { red: 1, off: !nSample })}</div></div>
          <div class="card" style="--c:#B45309"><div style="font-size:26px;line-height:1">🏢</div><h3>Administration Data</h3>
            <p>Company details &amp; logo, users &amp; access, invoices &amp; payments.</p>
            <table class="gm">
              <tr><td>Company details &amp; logo</td><td style="text-align:right"><b>${A.details || 0}</b> <small>details</small>${A.logo ? " · logo" : ""}</td></tr>
              <tr><td>Users &amp; access</td><td style="text-align:right"><b>${A.users || 0}</b> <small>users</small></td></tr>
              <tr><td>Invoices &amp; payments</td><td style="text-align:right"><b>${A.invoices || 0}</b> <small>invoices</small> · <b>${A.payments || 0}</b> <small>payments</small></td></tr>
            </table>
            ${o.staff ? "" : `<p style="font-size:12px;color:var(--muted)">Invoices and payments are KMR’s tax records: you can download them; only KMR can flush or restore them.</p>`}
            <div class="gm-btns">${btn("gmAdmDl", "Download JSON")}${upl("gmAdmUp", "Upload JSON")}${btn("gmAdmFl", "Flush admin data", { red: 1 })}</div></div>
        </div>
        <style>.gm{width:100%;border-collapse:collapse;font-size:13px;margin:4px 0 10px}.gm td{padding:5px 0;border-bottom:1px solid var(--line,#E5E7EB)}
          .gm small{color:var(--muted)}.gm-btns{display:flex;gap:8px;flex-wrap:wrap;margin-top:auto}</style>`;
      const $ = (id) => ctx.main.querySelector("#" + id);
      $("gmRealDl").onclick = () => this.download(ctx, "real", $("gmRealDl"));
      $("gmRealUp").onchange = (e) => this.upload(ctx, "real", e.target.files[0], e.target);
      $("gmRealFl").onclick = () => this.confirmReal(ctx);
      if ($("gmSmpLd")) $("gmSmpLd").onclick = () => this.sample(ctx, "load", $("gmSmpLd"));
      if ($("gmSmpFl")) $("gmSmpFl").onclick = () => this.sample(ctx, "flush", $("gmSmpFl"));
      $("gmAdmDl").onclick = () => this.download(ctx, "admin", $("gmAdmDl"));
      $("gmAdmUp").onchange = (e) => this.upload(ctx, "admin", e.target.files[0], e.target);
      $("gmAdmFl").onclick = () => this.confirmAdmin(ctx);
      window.scrollTo(0, 0);
    },

    async backup(ctx, kind) {
      const { data, error } = await ctx.sb.rpc(kind === "real" ? "kmr_grand_real_export" : "kmr_grand_admin_export", { p_slug: ctx.slug });
      if (error) throw error;
      const name = `${ctx.slug}-${kind === "real" ? "real-data" : "admin-data"}-${stamp()}.json`;
      save(data, name);
      return name;
    },
    async download(ctx, kind, b) {
      const t = b.textContent; b.disabled = true; b.textContent = "Preparing…";
      try { await this.backup(ctx, kind); } catch (e) { alert(e.message || e); }
      b.disabled = false; b.textContent = t;
    },

    /** type FLUSH, backup downloads, then the flush runs */
    flushDialog(ctx, title, body, run) {
      ctx.dialog(title, `${body}
        <label class="f">Type FLUSH to confirm<div class="in"><input id="gmConfirm" autocomplete="off" placeholder="FLUSH"></div></label><span class="msg" id="gmMsg"></span>`,
        `<button class="btn" id="gmGo" style="background:#B00E28">Download backup &amp; flush</button>`);
      const go = document.getElementById("gmGo");
      go.onclick = async () => {
        const m = document.getElementById("gmMsg");
        if ((document.getElementById("gmConfirm").value || "").trim().toUpperCase() !== "FLUSH") { m.textContent = "Type FLUSH to confirm."; return; }
        go.disabled = true;
        try { await run(go, m); } catch (e) { go.disabled = false; go.textContent = "Download backup & flush"; m.textContent = e.message || String(e); }
      };
    },
    confirmReal(ctx) {
      const o = this.o;
      this.flushDialog(ctx, "Flush real data — every app", `
        <p>Removes your team’s data from every app: <b>${Object.keys(APP).filter((k) => o.real[k]).map((k) => `${esc(APP[k])} (${o.real[k]})`).join(", ") || "nothing yet"}</b>.
        Sample data, company setup, logins and access stay.</p>
        <p>First a JSON backup is <b>downloaded to this computer</b>; then the data is removed. Keep the file — <b>Upload JSON</b> on this card restores everything.</p>`,
        async (go) => {
          go.textContent = "Downloading backup…";
          let file; try { file = await this.backup(ctx, "real"); } catch (e) { throw new Error(`Backup failed, nothing was removed: ${e.message || e}`); }
          go.textContent = "Flushing…";
          const { data, error } = await ctx.sb.rpc("kmr_grand_real_flush", { p_slug: ctx.slug });
          if (error) throw new Error(`Backup saved (${file}), but the flush failed: ${error.message}`);
          document.querySelectorAll(".veil").forEach((v) => v.remove());
          this.overview(ctx, `<b>Real data flushed.</b> Removed: ${Object.keys(APP).filter((k) => data[k] !== undefined).map((k) => `${esc(APP[k])} ${data[k]} ${UNIT[k]}`).join(" · ")}. Backup downloaded: <b>${esc(file)}</b> — upload it on the Real Data card to restore.`);
        });
    },
    confirmAdmin(ctx) {
      const A = this.o.admin || {}, staff = this.o.staff;
      this.flushDialog(ctx, "Flush administration data", `
        <p>Choose what to clear:</p>
        <label style="display:flex;gap:8px;margin:6px 0"><input type="checkbox" class="gmPart" value="company" checked> <span><b>Company details &amp; logo</b> — legal name, GSTIN, address, phone and logo (the company name stays).</span></label>
        <label style="display:flex;gap:8px;margin:6px 0"><input type="checkbox" class="gmPart" value="users" checked> <span><b>Users &amp; access</b> — everyone except you and the main contact loses access to every app (${Math.max(0, (A.users || 0) - 1)} at most). Logins themselves stay.</span></label>
        <label style="display:flex;gap:8px;margin:6px 0;${staff ? "" : "opacity:.55"}"><input type="checkbox" class="gmPart" value="invoices" ${staff ? "" : "disabled"}> <span><b>Invoices &amp; payments</b> (${A.invoices || 0} / ${A.payments || 0})${staff ? "" : " — only KMR can flush these"}.</span></label>
        <p>A JSON backup of all administration data is <b>downloaded first</b>; <b>Upload JSON</b> on this card restores it.</p>`,
        async (go) => {
          const parts = [...document.querySelectorAll(".gmPart:checked")].map((x) => x.value);
          if (!parts.length) throw new Error("Tick at least one part.");
          go.textContent = "Downloading backup…";
          let file; try { file = await this.backup(ctx, "admin"); } catch (e) { throw new Error(`Backup failed, nothing was removed: ${e.message || e}`); }
          go.textContent = "Flushing…";
          const { data, error } = await ctx.sb.rpc("kmr_grand_admin_flush", { p_slug: ctx.slug, p_parts: parts });
          if (error) throw new Error(`Backup saved (${file}), but the flush failed: ${error.message}`);
          document.querySelectorAll(".veil").forEach((v) => v.remove());
          const done = [data.company ? "company details & logo cleared" : "", data.users !== undefined ? `${data.users} users removed` : "",
            data.invoices !== undefined ? `${data.invoices} invoices and ${data.payments} payments removed` : ""].filter(Boolean).join(" · ");
          this.overview(ctx, `<b>Administration data flushed:</b> ${esc(done)}. Backup downloaded: <b>${esc(file)}</b> — upload it on the Administration card to restore.`);
        });
    },

    async upload(ctx, kind, file, input) {
      if (!file) return;
      try {
        let j; try { j = JSON.parse(await file.text()); } catch { throw new Error("That file is not valid JSON."); }
        const want = kind === "real" ? "kmr-real-data" : "kmr-admin-data";
        if (!j || j.format !== want) throw new Error(kind === "real" ? "This is not a Real Data backup (download one from this card first)." : "This is not an Administration Data backup (download one from this card first).");
        const when = String(j.exported_at || "").slice(0, 16).replace("T", " ");
        const msg = kind === "real"
          ? `Put every app back as it was in the backup from ${when}?\n\nThe current real data is replaced. Operations Master sample records and the sample drawing are not touched; HRM & Payroll goes back as it was then.`
          : `Restore company details & logo and users & access from the backup of ${when}?${this.o.staff ? "\nInvoices and payments that are missing are added back." : ""}`;
        if (!confirm(msg)) { input.value = ""; return; }
        const { data, error } = await ctx.sb.rpc(kind === "real" ? "kmr_grand_real_import" : "kmr_grand_admin_import", { p_slug: ctx.slug, p_data: j });
        if (error) throw error;
        let note;
        if (kind === "real") {
          const n = (v, k) => (v && typeof v === "object" ? (v.employees !== undefined ? `${v.employees} employees with their records` : sum(v)) : `${v} ${UNIT[k]}`);
          note = `<b>Real data restored</b> from ${esc(file.name)}: ${Object.keys(APP).filter((k) => data[k] !== undefined).map((k) => `${esc(APP[k])} ${n(data[k], k)}`).join(" · ")}.`;
        } else {
          note = `<b>Administration data restored</b> from ${esc(file.name)}: ${data.company ? "company details & logo · " : ""}${data.users} users${data.invoices !== undefined ? ` · ${data.invoices} invoices, ${data.payments} payments` : ""}.`
            + (data.invoices_skipped ? " Invoices and payments were not changed (only KMR can restore them)." : "")
            + (data.users_partly ? ` ${data.users_partly} users could not get all their app access — check Users & access.` : "");
        }
        this.overview(ctx, note);
      } catch (e) { alert(e.message || e); }
      if (input) input.value = "";
    },

    async sample(ctx, act, b) {
      if (act === "flush" && !confirm("Remove the sample data from every app?\n\nSample employees, the sample drawing, the sample Sales Flow plan, the sample Calibration Hub instruments and the sample Operations Master records go. Your real data is not touched.")) return;
      const t = b.textContent; b.disabled = true; b.textContent = act === "load" ? "Loading…" : "Flushing…";
      const { data, error } = await ctx.sb.rpc("kmr_grand_sample", { p_slug: ctx.slug, p_action: act });
      if (error) { b.disabled = false; b.textContent = t; alert(error.message); return; }
      let extra = "";
      const parts = Object.keys(APP).filter((k) => data[k] !== undefined).map((k) => `${esc(APP[k])} ${data[k]}`).join(" · ");
      this.overview(ctx, act === "load"
        ? `<b>Sample data loaded</b> — ${parts}.${extra} Lists already holding sample data are left as they are.`
        : `<b>Sample data flushed</b> — ${parts}. Your real data is unchanged.`);
    },
  };
})();
