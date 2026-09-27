import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDateTime } from "@/components/ui";
import { convertLead, setLeadStatus } from "@/app/actions";

export const metadata = { title: "Pilot requests" };
const TONE: Record<string, string> = { new: "warn", contacted: "info", converted: "ok", dropped: "" };

export default async function Leads() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const { data } = await supabase.from("leads").select("*").order("created_at", { ascending: false }).limit(300);
  return (
    <AppShell staff={staff} active="/leads">
      <div className="pagehead"><div><h1>Pilot requests</h1><p>Requests from the KMR Apps page on www.kmr-groups.com/it. Convert one to open it as a customer.</p></div></div>
      <div className="card" style={{ padding: 0 }}>
        {data?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>Company</th><th>Contact</th><th>Interested in</th><th>Message</th><th>Status</th><th></th></tr></thead>
            <tbody>{data.map((l) => (
              <tr key={l.id}>
                <td><b>{l.company}</b><br /><small className="muted">{l.country ?? ""} · {fmtDateTime(l.created_at)}</small></td>
                <td>{l.name}<br /><small className="muted">{l.email}{l.phone ? ` · ${l.phone}` : ""}</small></td>
                <td>{(l.products ?? []).map((x: string) => <span key={x} className="badge" style={{ marginRight: 4 }}>{x.toUpperCase()}</span>)}</td>
                <td style={{ maxWidth: 280 }}><small>{l.message}</small></td>
                <td><span className={`badge ${TONE[l.status]}`}>{l.status}</span></td>
                <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                  {l.status === "new" && <form action={setLeadStatus} style={{ display: "inline" }}><input type="hidden" name="id" value={l.id} /><input type="hidden" name="status" value="contacted" /><button className="btn ghost small">Mark contacted</button></form>}
                  {l.status !== "dropped" && <form action={convertLead} style={{ display: "inline" }}><input type="hidden" name="id" value={l.id} /><button className="btn small">{l.customer_id ? "Open customer" : "Convert to customer"}</button></form>}
                  {!["converted", "dropped"].includes(l.status) && <form action={setLeadStatus} style={{ display: "inline" }}><input type="hidden" name="id" value={l.id} /><input type="hidden" name="status" value="dropped" /><button className="btn ghost small">Drop</button></form>}
                </td>
              </tr>))}</tbody>
          </table></div>
        ) : <Empty>No pilot requests yet. They arrive from the form on www.kmr-groups.com/it.</Empty>}
      </div>
    </AppShell>
  );
}
