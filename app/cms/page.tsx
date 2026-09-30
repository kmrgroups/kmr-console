import { requireStaff } from "@/lib/auth";
import { GROUPS, SECTIONS, EXTRA, type Section } from "@/lib/cms";
import { gatewayStatus, web } from "@/lib/cms-server";
import { createClient } from "@/lib/supabase/server";
import { p } from "@/lib/base-path";
import { env } from "@/lib/env";

export const metadata = { title: "Website CMS" };

async function counts(s: Section): Promise<{ total: number; shown: number | null }> {
  if (s.single) return { total: 1, shown: null };
  const base = () => {
    let q = web().from(s.table).select("id", { count: "exact", head: true });
    for (const [k, v] of Object.entries(s.scope ?? {})) q = q.eq(k, v);
    if (s.filter?.restrict) q = q.in(s.filter.k, s.filter.opts.map((o) => o[0]));
    return q;
  };
  const [{ count: total }, shown] = await Promise.all([base(), s.visible ? base().eq(s.visible, true) : Promise.resolve({ count: null })]);
  return { total: total ?? 0, shown: shown.count };
}

/** Overview: every section of the website at a glance. */
export default async function CmsHome() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const [all, { data: settings }, { count: awaiting }, { count: reported }, { count: apps }, { count: leads }, { data: seller }] = await Promise.all([
    Promise.all(SECTIONS.map(async (s) => [s.key, await counts(s)] as const)),
    web().from("site_settings").select("online_payment,bank_transfer").maybeSingle(),
    web().from("orders").select("id", { count: "exact", head: true }).eq("status", "awaiting_payment"),
    web().from("orders").select("id", { count: "exact", head: true }).eq("status", "payment_reported"),
    web().from("job_applications").select("id", { count: "exact", head: true }).eq("status", "new"),
    supabase.from("leads").select("id", { count: "exact", head: true }).eq("status", "new"),
    supabase.from("billing_settings").select("bank_account_no,upi_id").maybeSingle(),
  ]);
  const c = Object.fromEntries(all);
  const keyConfigured = (await gatewayStatus(env.platformUrl)).configured;
  const payOk = Boolean(seller?.bank_account_no || seller?.upi_id);

  return (
    <>
      <div className="pagehead">
        <div><h1>Website CMS</h1><p>Everything on {env.platformUrl.replace(/^https?:\/\//, "")} — add, edit, hide or delete. Changes appear on the website within a minute.</p></div>
        <a className="btn secondary" href={env.platformUrl} target="_blank" rel="noopener">Open the website ↗</a>
      </div>

      <div className="grid four" style={{ marginBottom: 18 }}>
        <a className="card stat accent" href={p("/cms/orders?s=payment_reported")}><div className="label">Payments to confirm</div><div className="value">{reported ?? 0}</div><div className="hint">{awaiting ?? 0} orders awaiting payment</div></a>
        <a className="card stat" href={p("/cms/applications?f=new")}><div className="label">New job applications</div><div className="value">{apps ?? 0}</div></a>
        <a className="card stat" href={p("/leads")}><div className="label">New enquiries</div><div className="value">{leads ?? 0}</div></a>
        <a className="card stat" href={p("/cms/payments")}><div className="label">Payments</div>
          <div className="value" style={{ fontSize: "1.05rem", marginTop: 10 }}>{[settings?.online_payment && (keyConfigured ? "Online ✓" : "Online — keys missing"), settings?.bank_transfer && (payOk ? "Bank / UPI ✓" : "Bank / UPI — account missing")].filter(Boolean).join(" · ") || "Off"}</div>
          <div className="hint">Paid into the account in Seller details</div></a>
      </div>

      <div className="cmstiles">
        {GROUPS.map((g) => (
          <div key={g.key} className="cmstile">
            <h3>{g.label}</h3><p>{g.hint}</p>
            <ul>
              {SECTIONS.filter((s) => s.group === g.key).map((s) => {
                const n = c[s.key];
                return <li key={s.key}><a href={p(`/cms/${s.key}`)}>{s.label}</a>
                  <small className="muted">{s.single ? "edit" : n.shown !== null ? `${n.shown} shown · ${n.total - n.shown} hidden` : `${n.total}`}</small></li>;
              })}
              {EXTRA.filter((x) => x.group === g.key && x.roles.includes(staff.role)).map((x) => <li key={x.href}><a href={p(x.href)}>{x.label}</a><small className="muted">open</small></li>)}
            </ul>
          </div>
        ))}
      </div>
    </>
  );
}
