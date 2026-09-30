import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { RESOURCES } from "@/lib/manage";
import { p } from "@/lib/base-path";

export const metadata = { title: "Operations" };

export default async function OperationsHub() {
  const staff = await requireStaff();
  const cards: [string, string, string][] = [
    ...RESOURCES.filter((r) => r.section === "operations").map((r) => [`/manage/${r.key}`, r.label, r.intro] as [string, string, string]),
    ["/operations/stock", "Stock", "Stock on hand per item and warehouse; record receipts, dispatches and adjustments."],
  ];
  return (
    <AppShell staff={staff} active="/operations">
      <div className="pagehead"><div><h1>Operations</h1><p>KMR&apos;s own trading records: customers, vendors, inventory, warehouses, stock and staff register (moved from the website admin).</p></div></div>
      <div className="grid three">
        {cards.map(([href, title, sub]) => (
          <a key={href} href={p(href)} className="card" style={{ display: "block", textDecoration: "none", color: "inherit" }}>
            <h2 style={{ marginBottom: 4 }}>{title}</h2><p className="muted" style={{ margin: 0, fontSize: 13.5 }}>{sub}</p>
          </a>))}
      </div>
    </AppShell>
  );
}
