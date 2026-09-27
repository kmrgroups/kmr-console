import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { Empty, one } from "@/components/ui";
import { p } from "@/lib/base-path";
import { PRIORITY_TONE, TICKET_LABEL, TICKET_TONE, age } from "@/lib/tickets";

export const metadata = { title: "Support tickets" };

export default async function Tickets({ searchParams }: { searchParams: Promise<{ view?: string }> }) {
  const staff = await requireStaff();
  const { view = "active" } = await searchParams;
  const supabase = await createClient();
  let q = supabase.from("tickets").select("id,number,subject,priority,status,product_code,raised_by_name,raised_by_email,created_at,updated_at,first_reply_at,customer:customers(id,name)").order("updated_at", { ascending: false }).limit(300);
  if (view === "active") q = q.in("status", ["open", "in_progress", "waiting_on_customer"]);
  if (view === "mine") q = q.eq("assigned_to", staff.user_id).in("status", ["open", "in_progress", "waiting_on_customer"]);
  const { data } = await q;
  const tab = (k: string, label: string) => <a href={p(`/tickets?view=${k}`)} className={`btn ${view === k ? "" : "secondary"} small`}>{label}</a>;
  return (
    <AppShell staff={staff} active="/tickets">
      <div className="pagehead"><div><h1>Support tickets</h1><p>Raised by customers from inside the products. Replies appear in their Help &amp; support screen.</p></div>
        <div className="row" style={{ gap: 6 }}>{tab("active", "Active")}{tab("mine", "Assigned to me")}{tab("all", "All")}</div></div>
      <div className="card" style={{ padding: 0 }}>
        {data?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>Ticket</th><th>Customer</th><th>Product</th><th>Priority</th><th>Status</th><th>Waiting</th></tr></thead>
            <tbody>{data.map((t) => { const c = one(t.customer); return (
              <tr key={t.id}>
                <td><a href={p(`/tickets/${t.id}`)}><b>{t.subject}</b></a><br /><small className="mono muted">{t.number}</small> <small className="muted">· {t.raised_by_name}</small></td>
                <td>{c ? <a href={p(`/customers/${c.id}`)}>{c.name}</a> : <small className="muted">{t.raised_by_email}</small>}</td>
                <td>{t.product_code.toUpperCase()}</td>
                <td><span className={`badge ${PRIORITY_TONE[t.priority]}`}>{t.priority}</span></td>
                <td><span className={`badge ${TICKET_TONE[t.status]}`}>{TICKET_LABEL[t.status]}</span>{!t.first_reply_at && t.status === "open" && <><br /><small style={{ color: "var(--warn)" }}>No reply yet</small></>}</td>
                <td>{age(t.updated_at)}</td>
              </tr>); })}</tbody>
          </table></div>
        ) : <Empty>{view === "all" ? "No tickets yet." : "Nothing waiting. 🎉"}</Empty>}
      </div>
    </AppShell>
  );
}
