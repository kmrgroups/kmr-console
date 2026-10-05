import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { Empty } from "@/components/ui";
import { p } from "@/lib/base-path";
import { DEMO, FLUSH_PARTS, demoStatus, listFullBackups } from "@/lib/test-data";
import { createClient } from "@/lib/supabase/server";
import { cleanOut, loadDemo, purgeAllSample, purgeSample, removeDemo, resetDemo, takeFullBackup, uploadSettings } from "./actions";

export const metadata = { title: "Test data" };
export const dynamic = "force-dynamic";

const APPS = [
  ["Console", "6 sample customers in India, Germany, the USA and the UAE, licences, enquiries"],
  ["Website", "sample slides, shop products, training programmes, a job opening, people and gallery photos (marked “sample”)"],
  ["HRM", "demo company with 24 employees in two plants, a month of attendance, leave balances and pending requests"],
  ["Balloon Inspector", "demo workspace — open it and click “Try the sample”"],
  ["Process Documents", "demo workspace — open it and click “Try the sample”"],
  ["Capacity Planner", "demo workspace with the sample plan (12 machines, 43 operations)"],
  ["Operations Master", "sample machines, parts, routings, gauges and plant standards for the demo customer"],
];

export default async function TestDataPage() {
  const staff = await requireStaff();
  if (staff.role !== "owner") return <AppShell staff={staff} active="/test-data"><div className="card"><p>Only the owner can use Test data.</p></div></AppShell>;
  const [st, backups] = await Promise.all([demoStatus(), listFullBackups()]);
  const loaded = !!st.demo;
  const sb = await createClient();
  const rep = await sb.schema("public").rpc("kmr_sample_report");
  const report = (rep.data ?? []) as { name: string; slug: string; code: string | null; kind: string; counts: Record<string, number>; total: number }[];
  const dirty = report.filter((r) => r.kind !== "demo" && r.total > 0), demos = report.filter((r) => r.kind === "demo" && r.slug === DEMO.slug);
  const { data: purged } = await sb.from("sample_purge_log").select("customer_name,purged_at,counts").order("purged_at", { ascending: false }).limit(5);
  const said = (c: Record<string, number>) => Object.entries(c).filter(([, v]) => v > 0).map(([k, v]) => `${k} ${v}`).join(" · ");
  return (
    <AppShell staff={staff} active="/test-data">
      <div className="pagehead"><div><h1>Test data</h1>
        <p>For testing before going live: keep a copy of KMR’s settings, load demo data into every app with one click, and clean everything out when you are done.</p></div></div>

      {/* 0. Sample data belongs in the demo workspace only */}
      <div className="card" style={{ borderLeft: `4px solid ${rep.error ? "var(--warn,#f59e0b)" : dirty.length ? "var(--danger,#dc2626)" : "var(--ok,#16a34a)"}` }}>
        <h2>Sample data in real companies</h2>
        <p className="muted" style={{ marginTop: 0 }}>Sample data is for testing and demos only, and now lives in the <b>KMR demo workspace</b>. New sample data can no longer be loaded into a real company. This lists any that is already there; removing it saves a copy of exactly those records first.</p>
        {rep.error ? <div className="alert warn">This needs the database update <b>0049_demo_workspace.sql</b>. Run it in Supabase, then refresh. ({rep.error.message})</div>
          : dirty.length ? (
            <>
              <div className="tablewrap"><table><thead><tr><th>Company</th><th>Sample records found</th><th>Remove</th></tr></thead><tbody>{dirty.map((r) => (
                <tr key={r.slug}><td><b>{r.name}</b> <small className="muted mono">{r.code}</small></td><td><small>{said(r.counts)}</small></td>
                  <td><ActionForm action={purgeSample} submitLabel="Remove" variant="danger" hidden={{ slug: r.slug }}><input name="confirm" placeholder="Type PURGE SAMPLE DATA" style={{ maxWidth: 230 }} /></ActionForm></td></tr>))}</tbody></table></div>
              <div style={{ marginTop: 12 }}><ActionForm action={purgeAllSample} submitLabel={`Remove from all ${dirty.length} companies`} variant="danger"><input name="confirm" placeholder="Type PURGE SAMPLE DATA" style={{ maxWidth: 260 }} /></ActionForm></div>
            </>
          ) : <div className="alert ok">✓ No sample data in any real company.</div>}
        {!!purged?.length && <p className="muted" style={{ fontSize: 12.5, marginBottom: 0 }}>Last clean-ups: {purged.map((x) => `${x.customer_name} (${new Date(x.purged_at).toLocaleDateString("en-IN")})`).join(" · ")}. Copies are in the purge log (database table <span className="mono">console.sample_purge_log</span>).</p>}
      </div>

      <div className="card">
        <h2>Demo workspace</h2>
        <p className="muted" style={{ marginTop: 0 }}>One company, <b>{DEMO.name}</b>, with a workspace in every app and the only login that has sample data ({DEMO.email}). It reloads itself every night at 12:40 AM India time, and you can reload it now. “Try with sample data” inside customers’ own screens never touches their data: it runs in the browser only.</p>
        {demos.length ? <><p>Sample records now: <b>{demos[0].total}</b> <small className="muted">({said(demos[0].counts)})</small></p><ActionForm action={resetDemo} submitLabel="Reset demo data now" variant="secondary" /></>
          : <p className="muted">The demo workspace is not set up yet — use “Load demo data” below.</p>}
      </div>

      {/* 1. Backups */}
      <div className="card">
        <h2>1 · Keep a copy of KMR’s settings</h2>
        <p className="muted" style={{ marginTop: 0 }}>The <b>settings file</b> holds what KMR itself needs to work: KMR products and versions, prices, seller details (GSTIN, bank, UPI, seal), platform settings and all
          website content (company profile, founder, banners, businesses, home page, policies, people, registrations, gallery, shop products, programmes and job openings). Uploaded photos stay where they are.</p>
        <div className="grid two">
          <div>
            <a className="btn" href={p("/api/test-data/settings")}>Download settings (.json)</a>
            <p className="muted" style={{ fontSize: 13 }}>Keep this file safe. Staff logins are listed in it for reference but are never changed by an upload.</p>
          </div>
          <ActionForm action={uploadSettings} submitLabel="Upload and restore settings" pendingLabel="Restoring…" confirm="Replace the current settings and website content with the ones in this file?">
            <label className="field">Settings file<input type="file" name="file" accept="application/json,.json" required /></label>
          </ActionForm>
        </div>
      </div>

      {/* 2. Demo */}
      <div className="card">
        <h2>2 · Demo data in every app</h2>
        <p className="muted" style={{ marginTop: 0 }}>Creates the demo customer <b>{DEMO.name}</b> with a working workspace in every app and <b>one login for all of them</b>
          ({DEMO.email} — the password is shown once after loading).</p>
        <div className="tablewrap" style={{ border: 0 }}><table><tbody>
          {APPS.map(([a, what]) => <tr key={a}><td style={{ width: 190, fontWeight: 600 }}>{a}</td><td>{what}</td></tr>)}
        </tbody></table></div>
        <p><span className={`badge ${loaded ? "ok" : ""}`}>{loaded ? "Demo data is loaded" : "No demo data loaded"}</span>
          {st.websiteSample && !loaded ? <span className="badge info" style={{ marginLeft: 8 }}>Website sample content is loaded</span> : null}</p>
        <div className="row" style={{ gap: 10 }}>
          {!loaded && <ActionForm action={loadDemo} submitLabel="Load demo data everywhere" pendingLabel="Loading into every app… (up to a minute)" />}
          <ActionForm action={removeDemo} submitLabel="Remove demo data" variant="secondary" confirm="Remove all demo data from every app? Your own data is not touched." pendingLabel="Removing…" />
        </div>
      </div>

      {/* 3. Clean out */}
      <div className="card" style={{ borderColor: "var(--danger)" }}>
        <h2>3 · Clean out everything (before going live)</h2>
        <p className="muted" style={{ marginTop: 0 }}>A <b>full backup of every app is saved first</b>, automatically. Always kept: KMR staff and their logins, KMR products and prices, seller details,
          platform settings, all website content, and KMR’s own HRM company settings.</p>
        <ActionForm action={cleanOut} submitLabel="Clean out now" variant="danger" pendingLabel="Backing up, then cleaning out…" confirm="This permanently removes the ticked data from every app (a full backup is saved first). Continue?">
          <div style={{ display: "grid", gap: 8, margin: "4px 0 12px" }}>
            {FLUSH_PARTS.map((f) => <label key={f.key} className="check" style={{ fontWeight: 400 }}><input type="checkbox" name={f.key} defaultChecked={f.default} /> {f.label}</label>)}
          </div>
          <label className="field" style={{ maxWidth: 320 }}>Type FLUSH to confirm<input name="confirm" autoComplete="off" placeholder="FLUSH" required /></label>
        </ActionForm>
      </div>

      {/* 4. Full backups */}
      <div className="card">
        <h2>Full backups</h2>
        <p className="muted" style={{ marginTop: 0 }}>Every table of every app in one file — taken automatically before each clean-out, or by hand. Kept in the private backup store; links work for 10 minutes. The file contains employee and customer records, so store it carefully.</p>
        <ActionForm action={takeFullBackup} submitLabel="Take a full backup now" variant="secondary" pendingLabel="Saving…" />
        {backups.length ? (
          <div className="tablewrap" style={{ marginTop: 12 }}><table>
            <thead><tr><th>File</th><th className="num">Size</th><th></th></tr></thead>
            <tbody>{backups.map((b) => <tr key={b.name}><td>{b.name}</td><td className="num">{b.size ? `${Math.round(b.size / 1024)} KB` : ""}</td>
              <td style={{ textAlign: "right" }}>{b.url ? <a className="btn ghost small" href={b.url}>Download</a> : null}</td></tr>)}</tbody>
          </table></div>
        ) : <Empty>No full backups yet.</Empty>}
      </div>
    </AppShell>
  );
}
