import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { listBackups } from "@/lib/backups";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { AutoBackupToggle } from "@/components/AutoBackup";
import { Empty, fmtDate } from "@/components/ui";
import { p } from "@/lib/base-path";
import { flushConsoleSample, loadConsoleSample } from "@/app/actions";

export const metadata = { title: "Data & backups" };

export default async function DataPage() {
  const staff = await requireStaff();
  const manager = isManager(staff);
  const supabase = await createClient();
  const [{ count }, backups] = await Promise.all([
    supabase.from("customers").select("id", { count: "exact", head: true }).eq("source", "KMR demo data"),
    manager ? listBackups() : Promise.resolve([]),
  ]);
  return (
    <AppShell staff={staff} active="/data">
      <div className="pagehead"><div><h1>Data &amp; backups</h1><p>Sample data for demos, a JSON copy of all Console data, and the nightly backups.</p></div></div>
      {!manager ? <div className="card"><p>Only owners and administrators manage data and backups.</p></div> : (<>
        <div className="grid two">
          <div className="card">
            <h2>Sample data</h2>
            <p className="muted">6 sample customers in India, Germany, the USA and the UAE with licences, 2 support tickets and 2 pilot requests. Flush removes exactly these; real customers are untouched.</p>
            <p><span className={`badge ${count ? "info" : ""}`}>{count ? `${count} sample customers loaded` : "No sample data loaded"}</span></p>
            <div className="row" style={{ gap: 10 }}>
              <ActionForm action={loadConsoleSample} submitLabel="Load sample data" pendingLabel="Loading…" />
              <ActionForm action={flushConsoleSample} submitLabel="Flush sample data" variant="secondary" confirm="Remove all sample customers, their licences, tickets and requests?" />
            </div>
          </div>
          <div className="card">
            <h2>JSON download</h2>
            <p className="muted">Everything in the Console — customers, licences and their history, releases, tickets, pilot requests and staff — as one JSON file.</p>
            <a className="btn" href={p("/api/data/export")}>Download JSON now</a>
          </div>
        </div>
        <div className="card" style={{ marginTop: 16 }}>
          <h2>Nightly backups</h2>
          <p className="muted">Saved automatically every night at 12 AM (India time) and kept for 30 days — one file for the Console and website, one for the customers’ app data (Operations Master, Balloon, Process Documents, Capacity).</p>
          <AutoBackupToggle />
          {backups.length ? (
            <div className="tablewrap" style={{ marginTop: 12 }}><table>
              <thead><tr><th>Date</th><th className="num">Size</th><th></th></tr></thead>
              <tbody>{backups.map((b) => <tr key={b.date}><td>{fmtDate(b.date)}</td><td className="num">{b.size ? `${Math.round(b.size / 1024)} KB` : ""}</td><td style={{ textAlign: "right" }}><a className="btn ghost small" href={p(`/api/data/backup?date=${b.date}`)}>Download</a></td></tr>)}</tbody>
            </table></div>
          ) : <Empty>The first backup is saved tonight at 12 AM.</Empty>}
        </div>
      </>)}
    </AppShell>
  );
}
