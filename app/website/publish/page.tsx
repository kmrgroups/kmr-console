import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { Empty } from "@/components/ui";
import { BUSINESSES } from "@/lib/manage";
import { web } from "@/lib/manage-server";
import { p } from "@/lib/base-path";
import { publishFromOps } from "@/app/website-actions";

export const metadata = { title: "Publish from Operations Master" };

/** Pick a company's Operations Master (normally KMR's own), tick parts, publish them as website products. */
export default async function Publish({ searchParams }: { searchParams: Promise<{ c?: string }> }) {
  const staff = await requireStaff();
  const { c } = await searchParams;
  const supabase = await createClient();
  const { data: withParts } = await supabase.from("ops_records").select("customer_id").eq("kind", "parts").limit(5000);
  const ids = [...new Set((withParts ?? []).map((r) => r.customer_id))];
  const { data: companies } = ids.length ? await supabase.from("customers").select("id,name").in("id", ids).order("name") : { data: [] };
  const cid = c && ids.includes(c) ? c : (companies?.find((x) => /kmr/i.test(x.name)) ?? companies?.[0])?.id;
  const [{ data: parts }, { data: prices }, { data: published }] = cid ? await Promise.all([
    supabase.from("ops_records").select("code,name,data,active").eq("customer_id", cid).eq("kind", "parts").order("code"),
    supabase.from("ops_records").select("data").eq("customer_id", cid).eq("kind", "rate_contracts").eq("active", true),
    web().from("products").select("id,ops_code,is_active,price").eq("ops_customer_id", cid),
  ]) : [{ data: [] }, { data: [] }, { data: [] }];
  const rate = (code: string) => (prices ?? []).map((x) => x.data as Record<string, string>).find((d) => d.party_type === "Customer" && d.item === code && (d.currency ?? "INR") === "INR")?.rate;
  const pub = Object.fromEntries((published ?? []).map((x) => [x.ops_code, x]));

  return (
    <AppShell staff={staff} active="/website">
      <div className="pagehead"><div><p style={{ margin: 0 }}><a href={p("/manage/products")} className="muted">← Products</a></p><h1>Publish from Operations Master</h1>
        <p>Tick parts to put on the website. They start <b>hidden</b>, with the customer rate-contract price when there is one — then set price, stock and photo in Products and tick “Show on the website”. Publishing a part again refreshes its name and description only.</p></div></div>
      {!companies?.length ? <div className="card"><Empty>No company has parts in its Operations Master yet. Add parts (or load the sample data) in KMR Apps › Operations Master.</Empty></div> : (
        <>
          <form className="row" style={{ marginBottom: 12 }}>
            <label className="row" style={{ gap: 8 }}>Operations Master of<select name="c" defaultValue={cid} style={{ maxWidth: 320 }}>{companies.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label>
            <button className="btn secondary">Show parts</button>
          </form>
          <div className="card">
            {!isManager(staff) && <div className="alert warn">Only an owner or administrator can publish.</div>}
            {parts?.length ? (
              <ActionForm action={publishFromOps} submitLabel="Publish ticked parts" pendingLabel="Publishing…" hidden={{ customer_id: cid! }}>
                <label className="field" style={{ maxWidth: 320 }}>Publish to<select name="business" defaultValue="shop">{BUSINESSES.map(([k, l]) => <option key={k} value={k}>{l}{k === "shop" || k === "training" ? "" : " (enquiry only)"}</option>)}</select></label>
                <div className="tablewrap"><table>
                  <thead><tr><th style={{ width: 36 }} /><th>Part</th><th>Name</th><th>Customer</th><th>Material</th><th style={{ textAlign: "right" }}>Rate (₹)</th><th>On the website</th></tr></thead>
                  <tbody>{parts.map((x) => {
                    const d = x.data as Record<string, string>; const w = pub[x.code];
                    return (<tr key={x.code}>
                      <td><input type="checkbox" name="code" value={x.code} style={{ width: "auto" }} /></td>
                      <td className="mono"><b>{x.code}</b></td><td>{x.name}</td><td>{d.customer ?? "—"}</td><td>{d.material ?? "—"}</td>
                      <td style={{ textAlign: "right" }}>{rate(x.code) ?? <small className="muted">—</small>}</td>
                      <td>{w ? <a href={p(`/manage/products/${w.id}`)}><span className={`badge ${w.is_active ? "ok" : ""}`}>{w.is_active ? `shown · ₹${w.price}` : "hidden"}</span></a> : <small className="muted">not yet</small>}</td>
                    </tr>);
                  })}</tbody>
                </table></div>
              </ActionForm>
            ) : <Empty>This company has no parts yet.</Empty>}
          </div>
        </>
      )}
    </AppShell>
  );
}
