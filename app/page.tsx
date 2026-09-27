import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDate, one } from "@/components/ui";
import { p } from "@/lib/base-path";
import { LICENCE_TONE, addDays, effectiveStatus, today } from "@/lib/view";

export const metadata = { title: "Dashboard" };

export default async function Dashboard() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const [{ count: openTickets }, { count: newLeads }] = await Promise.all([
    supabase.from("tickets").select("id", { count: "exact", head: true }).in("status", ["open", "in_progress"]),
    supabase.from("leads").select("id", { count: "exact", head: true }).eq("status", "new"),
  ]);
  const [{ data: customers }, { data: licences }, { data: products }] = await Promise.all([
    supabase.from("customers").select("id,status"),
    supabase.from("licences").select("id,status,valid_until,seats,product_code,customer:customers(id,name,code)"),
    supabase.from("products").select("code,name,current_version").eq("active", true).order("sort_order"),
  ]);
  const count = (s: string) => (customers ?? []).filter((c) => c.status === s).length;
  const soon = (licences ?? []).filter((l) => l.valid_until && l.valid_until >= today() && l.valid_until <= addDays(today(), 30) && ["trial", "pilot", "active"].includes(l.status))
    .sort((a, b) => (a.valid_until! < b.valid_until! ? -1 : 1));

  return (
    <AppShell staff={staff} active="/">
      <div className="pagehead"><div><h1>Dashboard</h1><p>Customers and licences across all KMR products.</p></div>
        <a className="btn" href={p("/customers/new")}>+ New customer</a></div>
      <div className="grid four">
        <div className="card stat"><div className="label">Active customers</div><div className="value" style={{ color: "var(--ok)" }}>{count("active")}</div></div>
        <div className="card stat"><div className="label">In pilot</div><div className="value">{count("pilot")}</div></div>
        <div className="card stat"><div className="label">Leads</div><div className="value">{count("lead")}</div></div>
        <div className="card stat"><div className="label">Ending in 30 days</div><div className="value" style={{ color: soon.length ? "var(--warn)" : undefined }}>{soon.length}</div></div>
      </div>
      <div className="grid two" style={{ marginTop: 16 }}>
        <a className="card stat" href={p("/tickets")}><div className="label">Open support tickets</div><div className="value" style={{ color: openTickets ? "var(--warn)" : undefined }}>{openTickets ?? 0}</div><div className="hint">Open or in progress</div></a>
        <a className="card stat" href={p("/leads")}><div className="label">New pilot requests</div><div className="value">{newLeads ?? 0}</div><div className="hint">From www.kmr-groups.com/it</div></a>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h2>Licences by product</h2>
        <div className="tablewrap">
          <table>
            <thead><tr><th>Product</th><th>Version</th><th className="num">Trial</th><th className="num">Pilot</th><th className="num">Active</th><th className="num">Suspended / expired</th></tr></thead>
            <tbody>
              {(products ?? []).map((pr) => {
                const ls = (licences ?? []).filter((l) => l.product_code === pr.code).map(effectiveStatus);
                const n = (s: string[]) => ls.filter((x) => s.includes(x)).length;
                return <tr key={pr.code}><td><b>{pr.name}</b></td><td className="mono">{pr.current_version ?? "—"}</td><td className="num">{n(["trial"])}</td><td className="num">{n(["pilot"])}</td><td className="num">{n(["active"])}</td><td className="num">{n(["suspended", "expired"])}</td></tr>;
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h2>Ending soon</h2>
        {soon.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Customer</th><th>Product</th><th>Status</th><th>Ends</th></tr></thead>
            <tbody>{soon.map((l) => { const c = one(l.customer); return (
              <tr key={l.id}><td><a href={p(`/customers/${c?.id}`)}>{c?.name}</a> <small className="mono muted">{c?.code}</small></td><td>{l.product_code.toUpperCase()}</td>
                <td><span className={`badge ${LICENCE_TONE[l.status]}`}>{l.status}</span></td><td>{fmtDate(l.valid_until)}</td></tr>); })}</tbody>
          </table></div>
        ) : <Empty>Nothing ends in the next 30 days.</Empty>}
      </div>
    </AppShell>
  );
}
