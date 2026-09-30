import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { CmsNav, type CmsGroup } from "@/components/CmsNav";
import { EXTRA, GROUPS, SECTIONS } from "@/lib/cms";
import { web } from "@/lib/cms-server";
import { env } from "@/lib/env";

/** Website CMS: its own menu beside every page. */
export default async function CmsLayout({ children }: { children: React.ReactNode }) {
  const staff = await requireStaff();
  const [{ count: reported }, { count: fresh }] = await Promise.all([
    web().from("orders").select("id", { count: "exact", head: true }).eq("status", "payment_reported"),
    web().from("job_applications").select("id", { count: "exact", head: true }).eq("status", "new"),
  ]);
  const badge: Record<string, number | null> = { "/cms/orders": reported, "/cms/applications": fresh };
  const groups: CmsGroup[] = GROUPS.map((g) => ({
    label: g.label,
    links: [
      ...SECTIONS.filter((s) => s.group === g.key).map((s) => ({ href: `/cms/${s.key}`, label: s.label })),
      ...EXTRA.filter((x) => x.group === g.key && x.roles.includes(staff.role)).map((x) => ({ href: x.href, label: x.label })),
    ].map((l) => ({ ...l, count: badge[l.href] ?? null })),
  }));
  return (
    <AppShell staff={staff} active="/cms">
      <div className="cms"><CmsNav groups={groups} site={env.platformUrl} /><div>{children}</div></div>
    </AppShell>
  );
}
