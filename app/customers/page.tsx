import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDate } from "@/components/ui";
import { p } from "@/lib/base-path";
import { CUSTOMER_TONE, LICENCE_TONE, effectiveStatus } from "@/lib/view";

export const metadata = { title: "Customers" };

export default async function Customers({ searchParams }: { searchParams: Promise<{ q?: string; status?: string; demo?: string }> }) {
  const staff = await requireStaff();
  const { q = "", status = "", demo = "" } = await searchParams;
  const supabase = await createClient();
  let query = supabase.from("customers").select("id,code,name,country,status,contact_name,contact_email,created_at,licences(product_code,status,valid_until)").order("name").limit(500);
  if (status) query = query.eq("status", status);
  if (q) { const s = q.replace(/[%,()]/g, " ").trim(); query = query.or(`name.ilike.%${s}%,code.ilike.%${s}%,contact_email.ilike.%${s}%`); }
  // KMR demo workspaces are not customers: hidden unless asked for (before migration 0049 there is no "kind", so nothing is hidden)
  // "Show demo workspaces" shows ONLY demo workspaces; the normal view shows only real customers
  let { data, error } = demo ? await query.eq("kind", "demo") : await query.neq("kind", "demo");
  if (error) ({ data } = demo ? { data: [] as NonNullable<typeof data> } : await query);
  return (
    <AppShell staff={staff} active="/customers">
      <div className="pagehead"><div><h1>Customers</h1><p>Companies using, piloting or interested in KMR products.</p></div>
        <a className="btn" href={p("/customers/new")}>+ New customer</a></div>
      <form className="toolbar" method="get">
        <input name="q" defaultValue={q} placeholder="Search name, code or email" />
        <select name="status" defaultValue={status}><option value="">All statuses</option>{["lead", "pilot", "active", "inactive"].map((s) => <option key={s}>{s}</option>)}</select>
        <button className="btn secondary small">Search</button>
        <a className="btn ghost small" href={p(demo ? "/customers" : "/customers?demo=1")}>{demo ? "Back to real customers" : "Show demo workspaces"}</a>
      </form>
      <div className="card" style={{ padding: 0 }}>
        {data?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>Customer</th><th>Country</th><th>Contact</th><th>Products</th><th>Status</th><th>Since</th></tr></thead>
            <tbody>{data.map((c) => (
              <tr key={c.id}>
                <td><a href={p(`/customers/${c.id}`)}><b>{c.name}</b></a><br /><small className="mono muted">{c.code}</small></td>
                <td>{c.country}</td>
                <td>{c.contact_name ?? "—"}<br /><small className="muted">{c.contact_email ?? ""}</small></td>
                <td>{(c.licences as { product_code: string; status: string; valid_until: string | null }[]).map((l) => { const st = effectiveStatus(l); return <span key={l.product_code} className={`badge ${LICENCE_TONE[st]}`} style={{ marginRight: 4 }}>{l.product_code.toUpperCase()} · {st}</span>; })}</td>
                <td><span className={`badge ${CUSTOMER_TONE[c.status]}`}>{c.status}</span></td>
                <td>{fmtDate(c.created_at)}</td>
              </tr>))}</tbody>
          </table></div>
        ) : <Empty>{q || status ? "No customers match." : demo ? "No demo workspace yet. Set it up under Test data." : "No customers yet. Add the first one."}</Empty>}
      </div>
    </AppShell>
  );
}
