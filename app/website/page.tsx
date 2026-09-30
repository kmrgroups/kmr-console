import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { RESOURCES } from "@/lib/manage";
import { web } from "@/lib/manage-server";
import { createClient } from "@/lib/supabase/server";
import { env } from "@/lib/env";
import { p } from "@/lib/base-path";

export const metadata = { title: "Website" };

/** Everything that was the website's /admin, now in the Console. */
export default async function WebsiteHub() {
  const staff = await requireStaff();
  const db = web();
  const supabase = await createClient();
  const [prod, hidden, orders, reported, leads] = await Promise.all([
    db.from("products").select("id", { count: "exact", head: true }).eq("is_active", true),
    db.from("products").select("id", { count: "exact", head: true }).eq("is_active", false),
    db.from("orders").select("id", { count: "exact", head: true }).in("status", ["awaiting_payment", "payment_reported"]),
    db.from("orders").select("id", { count: "exact", head: true }).eq("status", "payment_reported"),
    supabase.from("leads").select("id", { count: "exact", head: true }).eq("status", "new"),
  ]);
  const cards: [string, string, string, string?][] = [
    ["/manage/products", "Products", `${prod.count ?? 0} on the website · ${hidden.count ?? 0} hidden`],
    ["/website/orders", "Shop orders", `${orders.count ?? 0} unpaid${reported.count ? ` · ${reported.count} payment${reported.count > 1 ? "s" : ""} to verify` : ""}`, reported.count ? "warn" : undefined],
    ["/leads", "Enquiries", `${leads.count ?? 0} new — shop, software, training and trade`, leads.count ? "warn" : undefined],
    ["/website/publish", "Publish from Operations Master", "Turn parts into website products"],
    ...RESOURCES.filter((r) => r.section === "website" && r.key !== "products").map((r) => [`/manage/${r.key}`, r.label, r.intro] as [string, string, string]),
    ["/billing", "Software prices", "The Software page shows the Console's INR price list"],
  ];
  return (
    <AppShell staff={staff} active="/website">
      <div className="pagehead"><div><h1>Website</h1><p>Manage <a href={env.platformUrl} target="_blank" rel="noopener">{env.platformUrl.replace(/^https?:\/\//, "")}</a>: products, orders, enquiries and every page. Changes appear on the website within a minute.</p></div></div>
      <div className="grid three">
        {cards.map(([href, title, sub, tone]) => (
          <a key={href} href={p(href)} className="card" style={{ display: "block", textDecoration: "none", color: "inherit", borderTop: tone ? "3px solid var(--warn)" : undefined }}>
            <h2 style={{ marginBottom: 4 }}>{title}</h2><p className="muted" style={{ margin: 0, fontSize: 13.5 }}>{sub}</p>
          </a>))}
      </div>
    </AppShell>
  );
}
