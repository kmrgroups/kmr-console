import { requireStaff, isManager } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDateTime } from "@/components/ui";
import { p } from "@/lib/base-path";

export const metadata = { title: "Activity log" };
export const dynamic = "force-dynamic";

const NAMES: Record<string, string> = {
  "console.staff": "KMR staff", "console.customers": "Customers", "console.licences": "Licences", "console.prices": "Prices",
  "console.billing_settings": "Seller details", "console.invoices": "Invoices", "console.invoice_lines": "Invoice lines", "console.payments": "Payments",
  "console.platform_settings": "Platform settings", "public.orders": "Shop orders", "public.products": "Website products",
  "public.company_info": "Company profile", "public.legal_pages": "Policies", "public.site_settings": "Site settings",
  "public.verticals": "Business verticals", "public.hero_slides": "Banner slides", "public.site_stats": "Highlight numbers",
  "public.home_points": "Home page points", "public.product_benefits": "Product benefits", "public.job_openings": "Job openings",
  "public.job_applications": "Job applications", "public.leaders": "Leadership", "public.gallery_items": "Gallery", "public.compliance_records": "Registrations",
};
const HIDE = /password|secret|token|_key|api_key|account_no|account_number|ifsc|(^|_)pan($|_)|aadhaar/i;
type Row = { id: number; at: string; actor: string | null; tbl: string; row_id: string | null; action: string; changes: Record<string, unknown> | null };

function summary(r: Row) {
  const c = r.changes ?? {};
  if (r.action !== "update") {
    const label = ["name", "title", "number", "order_no", "full_name", "product_name", "description", "slug", "reference", "product_code"].map((k) => c[k]).find((v) => typeof v === "string");
    return label ? String(label) : "";
  }
  return Object.entries(c).filter(([k]) => !["buyer", "seller", "search"].includes(k)).slice(0, 6).map(([k, v]) => {
    if (HIDE.test(k)) return `${k} changed`;
    const [a, b] = Array.isArray(v) ? v : [null, v];
    const s = (x: unknown) => { const t = x === null || x === undefined ? "—" : typeof x === "object" ? JSON.stringify(x) : String(x); return t.length > 40 ? t.slice(0, 40) + "…" : t; };
    return `${k}: ${s(a)} → ${s(b)}`;
  }).join(" · ");
}

export default async function ActivityPage({ searchParams }: { searchParams: Promise<{ t?: string; page?: string }> }) {
  const staff = await requireStaff();
  if (!isManager(staff)) return <AppShell staff={staff} active="/activity"><div className="card"><p>Only owners and administrators see the activity log.</p></div></AppShell>;
  const { t, page } = await searchParams;
  const pg = Math.max(0, Number(page) || 0), size = 100;
  let q = createAdminClient().from("audit_log").select("id,at,actor,tbl,row_id,action,changes").order("at", { ascending: false }).range(pg * size, pg * size + size - 1);
  if (t && NAMES[t]) q = q.eq("tbl", t);
  const { data } = await q;
  const rows = (data ?? []) as Row[];
  const link = (o: { t?: string; page?: number }) => p(`/activity?${new URLSearchParams(Object.entries(o).filter(([, v]) => v !== undefined && v !== "").map(([k, v]) => [k, String(v)]))}`);
  return (
    <AppShell staff={staff} active="/activity">
      <div className="pagehead"><div><h1>Activity log</h1><p>Who added, changed or deleted invoices, payments, prices, staff, licences, orders and website content — and when.</p></div></div>
      <div className="card">
        <form className="row" style={{ gap: 10, marginBottom: 12 }} action={p("/activity")}>
          <select name="t" defaultValue={t ?? ""} style={{ maxWidth: 260 }}>
            <option value="">Everything</option>
            {Object.entries(NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <button className="btn secondary">Show</button>
        </form>
        {rows.length === 0 ? <Empty>No activity recorded yet.</Empty> : (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr><th>When</th><th>Who</th><th>What</th><th>Action</th><th>Details</th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.id}>
                <td style={{ whiteSpace: "nowrap" }}>{fmtDateTime(r.at)}</td>
                <td>{r.actor === "service_role" ? "System / website" : r.actor ?? "—"}</td>
                <td>{NAMES[r.tbl] ?? r.tbl}</td>
                <td><span className={`badge ${r.action === "delete" ? "danger" : r.action === "insert" ? "ok" : "info"}`}>{({ insert: "added", update: "changed", delete: "deleted" } as Record<string, string>)[r.action]}</span></td>
                <td style={{ fontSize: 13 }}>{summary(r)}</td>
              </tr>))}</tbody>
          </table></div>)}
        <div className="row" style={{ gap: 10, marginTop: 12 }}>
          {pg > 0 && <a className="btn secondary" href={link({ t, page: pg - 1 })}>← Newer</a>}
          {rows.length === size && <a className="btn secondary" href={link({ t, page: pg + 1 })}>Older →</a>}
        </div>
      </div>
    </AppShell>
  );
}
