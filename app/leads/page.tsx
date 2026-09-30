import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDateTime } from "@/components/ui";
import { convertLead, setLeadStatus } from "@/app/actions";

export const metadata = { title: "Enquiries" };
const TONE: Record<string, string> = { new: "warn", contacted: "info", quoted: "info", converted: "ok", dropped: "" };
const BUSINESS: [string, string][] = [["software", "Software"], ["shop", "Shop"], ["training", "Training"], ["import_export", "Import & Export"], ["trading", "Trading"], ["distribution", "Distribution"], ["general", "General"]];
const BL = Object.fromEntries(BUSINESS);

export default async function Leads({ searchParams }: { searchParams: Promise<{ b?: string; s?: string }> }) {
  const staff = await requireStaff();
  const { b, s } = await searchParams;
  const supabase = await createClient();
  let q = supabase.from("leads").select("*").order("created_at", { ascending: false }).limit(300);
  if (b) q = q.eq("business", b);
  if (s) q = q.eq("status", s);
  const { data } = await q;
  const btn = (id: string, status: string, label: string) => (
    <form action={setLeadStatus} style={{ display: "inline" }}><input type="hidden" name="id" value={id} /><input type="hidden" name="status" value={status} /><button className="btn ghost small">{label}</button></form>);
  return (
    <AppShell staff={staff} active="/leads">
      <div className="pagehead"><div><h1>Enquiries</h1><p>Every enquiry from www.kmr-groups.com — software pilots, shop questions, training, import &amp; export, trading and distribution quotes. Convert one to open it as a customer.</p></div></div>
      <form className="row" style={{ marginBottom: 12 }}>
        <select name="b" defaultValue={b ?? ""} style={{ maxWidth: 220 }}><option value="">All businesses</option>{BUSINESS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        <select name="s" defaultValue={s ?? ""} style={{ maxWidth: 180 }}><option value="">Any status</option>{Object.keys(TONE).map((k) => <option key={k}>{k}</option>)}</select>
        <button className="btn secondary">Show</button>
      </form>
      <div className="card" style={{ padding: 0 }}>
        {data?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>From</th><th>Business</th><th>About</th><th>Message</th><th>Status</th><th></th></tr></thead>
            <tbody>{data.map((l) => (
              <tr key={l.id}>
                <td><b>{l.company || l.name}</b><br /><small className="muted">{l.company ? `${l.name} · ` : ""}{l.email}{l.phone ? ` · ${l.phone}` : ""}<br />{l.country ? `${l.country} · ` : ""}{fmtDateTime(l.created_at)}</small></td>
                <td><span className="badge">{BL[l.business] ?? l.business}</span></td>
                <td>{l.product_name && <b>{l.product_name}</b>}{l.quantity && <><br /><small>Qty: {l.quantity}</small></>}
                  {(l.products ?? []).map((x: string) => <span key={x} className="badge" style={{ marginRight: 4 }}>{x.toUpperCase()}</span>)}</td>
                <td style={{ maxWidth: 280 }}><small style={{ whiteSpace: "pre-line" }}>{l.message}</small></td>
                <td><span className={`badge ${TONE[l.status]}`}>{l.status}</span></td>
                <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                  {l.status === "new" && btn(l.id, "contacted", "Contacted")}
                  {["new", "contacted"].includes(l.status) && l.business !== "software" && btn(l.id, "quoted", "Quoted")}
                  {l.status !== "dropped" && <form action={convertLead} style={{ display: "inline" }}><input type="hidden" name="id" value={l.id} /><button className="btn small">{l.customer_id ? "Open customer" : "Convert to customer"}</button></form>}
                  {!["converted", "dropped"].includes(l.status) && btn(l.id, "dropped", "Drop")}
                </td>
              </tr>))}</tbody>
          </table></div>
        ) : <Empty>No enquiries{b || s ? " match" : " yet. They arrive from the forms on www.kmr-groups.com"}.</Empty>}
      </div>
    </AppShell>
  );
}
