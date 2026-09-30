import { requireStaff, isManager } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { listBackups } from "@/lib/backups";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDateTime } from "@/components/ui";
import { p } from "@/lib/base-path";

export const metadata = { title: "System health" };
export const dynamic = "force-dynamic";

type Err = { id: number; first_at: string; last_at: string; app: string; path: string | null; message: string; count: number };
type Mail = { id: number; at: string; app: string; kind: string; to_addr: string; subject: string | null; status: string; error: string | null };
type Block = { key: string; last_at: string; blocked: number };

const Light = ({ ok, warn, label, note }: { ok: boolean; warn?: boolean; label: string; note: string }) => (
  <div className="card" style={{ display: "flex", gap: 14, alignItems: "flex-start" }}>
    <span aria-hidden style={{ width: 14, height: 14, borderRadius: 99, marginTop: 5, flexShrink: 0, background: ok ? "#16a34a" : warn ? "#d97706" : "#dc2626" }} />
    <div><h3 style={{ margin: 0 }}>{label}</h3><p className="muted" style={{ margin: "4px 0 0" }}>{note}</p></div>
  </div>
);

export default async function HealthPage() {
  const staff = await requireStaff();
  if (!isManager(staff)) return <AppShell staff={staff} active="/health"><div className="card"><p>Only owners and administrators see system health.</p></div></AppShell>;
  const db = createAdminClient();
  const day = new Date(Date.now() - 864e5).toISOString();
  const [errs, mails, blocks, backups] = await Promise.all([
    db.from("app_errors").select("id,first_at,last_at,app,path,message,count").order("last_at", { ascending: false }).limit(30),
    db.from("email_log").select("id,at,app,kind,to_addr,subject,status,error").order("at", { ascending: false }).limit(40),
    db.from("rate_blocks").select("key,last_at,blocked").gte("last_at", new Date(Date.now() - 7 * 864e5).toISOString()).order("last_at", { ascending: false }).limit(20),
    listBackups().catch(() => []),
  ]);
  const E = (errs.data ?? []) as Err[], M = (mails.data ?? []) as Mail[], B = (blocks.data ?? []) as Block[];
  const errs24 = E.filter((e) => e.last_at > day).length;
  const failed24 = M.filter((m) => m.at > day && m.status === "failed").length;
  const emailOn = !!(process.env.RESEND_API_KEY && process.env.EMAIL_FROM);
  const last = backups[0]?.date;
  const backupOk = !!last && Date.now() - Date.parse(last) < 2.2 * 864e5;
  return (
    <AppShell staff={staff} active="/health">
      <div className="pagehead"><div><h1>System health</h1><p>Errors, emails, blocked attempts and backups — green is good, amber needs a look, red needs action.</p></div></div>
      <div className="grid two" style={{ marginBottom: 18 }}>
        <Light ok={errs24 === 0} warn={errs24 < 5} label="Errors" note={errs24 ? `${errs24} different errors in the last 24 hours — see below.` : "No server errors in the last 24 hours."} />
        <Light ok={emailOn && failed24 === 0} warn={!emailOn} label="Emails" note={!emailOn ? "Email is off: set RESEND_API_KEY and EMAIL_FROM in Vercel (Console and website)." : failed24 ? `${failed24} emails failed in the last 24 hours.` : "Emails are being sent."} />
        <Light ok={backupOk} label="Nightly backup" note={last ? `Last backup: ${last}.${backupOk ? "" : " It is overdue — check CRON_SECRET in Vercel, then take one in Data & backups."}` : "No backup yet. Set CRON_SECRET in Vercel; take one now in Data & backups."} />
        <Light ok={!!process.env.CRON_SECRET} label="Scheduled jobs" note={process.env.CRON_SECRET ? "CRON_SECRET is set." : "CRON_SECRET is not set, so the nightly backup cannot run."} />
      </div>

      <div className="card">
        <h2>Recent errors</h2>
        {E.length === 0 ? <Empty>No errors recorded.</Empty> : (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>Last seen</th><th>App</th><th>Page</th><th>Error</th><th>Times</th></tr></thead>
            <tbody>{E.map((e) => <tr key={e.id}><td>{fmtDateTime(e.last_at)}</td><td>{e.app}</td><td style={{ wordBreak: "break-all" }}>{e.path}</td><td>{e.message.slice(0, 200)}</td><td>{e.count}</td></tr>)}</tbody>
          </table></div>)}
      </div>

      <div className="card">
        <h2>Emails sent</h2>
        {M.length === 0 ? <Empty>No emails yet.</Empty> : (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>When</th><th>From</th><th>Type</th><th>To</th><th>Subject</th><th>Status</th></tr></thead>
            <tbody>{M.map((m) => <tr key={m.id}><td>{fmtDateTime(m.at)}</td><td>{m.app}</td><td>{m.kind.replace(/_/g, " ")}</td><td>{m.to_addr}</td><td>{m.subject}</td>
              <td><span className={`badge ${m.status === "sent" ? "ok" : m.status === "failed" ? "danger" : ""}`} title={m.error ?? ""}>{m.status}</span></td></tr>)}</tbody>
          </table></div>)}
      </div>

      <div className="grid two">
        <div className="card">
          <h2>Blocked attempts (7 days)</h2>
          <p className="muted">Too many sign-ins, orders or form posts from one place are refused for a while.</p>
          {B.length === 0 ? <Empty>Nothing blocked.</Empty> : <ul>{B.map((b) => <li key={b.key}><b>{b.key.split(":")[0]}</b> — {b.key.split(":").slice(1).join(":")} · {b.blocked}× · {fmtDateTime(b.last_at)}</li>)}</ul>}
        </div>
        <div className="card">
          <h2>Backups</h2>
          <p className="muted">{backups.length} daily backups kept (30 days).</p>
          <a className="btn secondary" href={p("/data")}>Open Data &amp; backups</a>
        </div>
      </div>
    </AppShell>
  );
}
