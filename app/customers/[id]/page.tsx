import { notFound } from "next/navigation";
import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { CustomerFields } from "@/components/CustomerFields";
import { fmtDate, fmtDateTime } from "@/components/ui";
import { env } from "@/lib/env";
import { CUSTOMER_TONE, LICENCE_TONE, addDays, effectiveStatus, today } from "@/lib/view";
import { enableHrm, enableTool, saveCustomer, saveLicence } from "@/app/actions";
import { isTool, toolUsage } from "@/lib/provision";

export const metadata = { title: "Customer" };

type Licence = { id: string; product_code: string; status: string; starts_on: string; valid_until: string | null; seats: number | null; product_ref: string | null; product_slug: string | null; notes: string | null };

export default async function CustomerPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const staff = await requireStaff();
  const manager = isManager(staff);
  const supabase = await createClient();
  const [{ data: c }, { data: products }, { data: licences }] = await Promise.all([
    supabase.from("customers").select("*").eq("id", id).maybeSingle(),
    supabase.from("products").select("code,name,description,app_path,seat_label").eq("active", true).order("sort_order"),
    supabase.from("licences").select("*").eq("customer_id", id),
  ]);
  if (!c) notFound();
  const ids = (licences ?? []).map((l) => l.id);
  const { data: events } = ids.length
    ? await supabase.from("licence_events").select("licence_id,action,detail,created_at").in("licence_id", ids).order("created_at", { ascending: false }).limit(30)
    : { data: [] };

  // Usage inside the HRM (read with the service key after the staff check above)
  const hrmLic = (licences ?? []).find((l) => l.product_code === "hrm") as Licence | undefined;
  let hrmUsage: { employees: number; users: number } | null = null;
  if (hrmLic?.product_ref) {
    const hrm = createAdminClient().schema("hrm");
    const [{ count: employees }, { count: users }] = await Promise.all([
      hrm.from("employees").select("id", { count: "exact", head: true }).eq("tenant_id", hrmLic.product_ref).in("status", ["draft", "invited", "submitted", "active"]),
      hrm.from("app_users").select("id", { count: "exact", head: true }).eq("tenant_id", hrmLic.product_ref).eq("active", true),
    ]);
    hrmUsage = { employees: employees ?? 0, users: users ?? 0 };
  }
  const toolUse: Record<string, { users: number; items: number }> = {};
  for (const l of (licences ?? []) as Licence[]) if (isTool(l.product_code) && l.product_ref) toolUse[l.product_code] = await toolUsage(l.product_code, l.product_ref);
  const suggestedSlug = c.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "company";
  const suggestedPrefix = c.name.replace(/[^A-Za-z]/g, "").slice(0, 3).toUpperCase() || "EMP";

  return (
    <AppShell staff={staff} active="/customers">
      <div className="pagehead">
        <div><h1>{c.name}</h1><p><span className="mono">{c.code}</span> · {c.country} · {c.currency} · <span className={`badge ${CUSTOMER_TONE[c.status]}`}>{c.status}</span></p></div>
      </div>

      <div className="card">
        <h2>Products</h2>
        <div className="stack">
          {(products ?? []).map((pr) => {
            const l = (licences ?? []).find((x) => x.product_code === pr.code) as Licence | undefined;
            const st = l ? effectiveStatus(l) : null;
            return (
              <div key={pr.code} style={{ border: "1px solid var(--border)", borderRadius: 10, padding: 16 }}>
                <div className="spread" style={{ alignItems: "flex-start" }}>
                  <div><b>{pr.name}</b> {st && <span className={`badge ${LICENCE_TONE[st]}`}>{st}</span>}<br /><small className="muted">{pr.description}</small></div>
                  {l && <div style={{ textAlign: "right", fontSize: 13 }}>
                    {l.valid_until ? <>Until <b>{fmtDate(l.valid_until)}</b></> : "No end date"}<br />
                    {l.seats ? <>Limit {l.seats} {pr.seat_label}</> : `Unlimited ${pr.seat_label}`}
                    {pr.code === "hrm" && hrmUsage && <><br />Using {hrmUsage.employees} employees · {hrmUsage.users} logins</>}
                    {toolUse[pr.code] && <><br />Using {toolUse[pr.code].users} users · {toolUse[pr.code].items} {pr.code === "balloon" ? "reports" : "projects"}</>}
                  </div>}
                </div>

                {l && (
                  <>
                    {l.product_slug && pr.code !== "hrm" && <p style={{ fontSize: 13, margin: "8px 0 0" }}>Workspace <b>{l.product_slug}</b> · sign-in <a href={`${env.platformUrl}${pr.app_path}`} target="_blank" rel="noopener" className="mono">{env.platformUrl}{pr.app_path}</a></p>}
                    {l.product_slug && pr.code === "hrm" && <p style={{ fontSize: 13, margin: "8px 0 0" }}>Sign-in: <a href={`${env.platformUrl}${pr.app_path}${pr.code === "hrm" ? `/login?co=${l.product_slug}` : ""}`} target="_blank" rel="noopener" className="mono">{env.platformUrl}{pr.app_path}{pr.code === "hrm" ? `/login?co=${l.product_slug}` : ""}</a></p>}
                    {manager && (
                      <details style={{ marginTop: 10 }}>
                        <summary className="btn secondary small">Change licence</summary>
                        <div style={{ marginTop: 10 }}>
                          <ActionForm action={saveLicence} submitLabel="Save licence" className="formgrid" hidden={{ customer_id: c.id, product_code: pr.code }}>
                            <label className="field">Status<select name="status" defaultValue={l.status}>{["trial", "pilot", "active", "suspended", "expired", "cancelled"].map((s) => <option key={s}>{s}</option>)}</select></label>
                            <label className="field">Valid until<input type="date" name="valid_until" defaultValue={l.valid_until ?? ""} /><span className="help">Empty = no end date</span></label>
                            <label className="field">Limit ({pr.seat_label})<input type="number" name="seats" min={1} defaultValue={l.seats ?? ""} placeholder="Unlimited" /></label>
                            <label className="field full">Notes<input name="notes" defaultValue={l.notes ?? ""} /></label>
                          </ActionForm>
                          <p className="muted" style={{ fontSize: 12.5 }}>Suspended, expired or cancelled stops the customer&apos;s access within a minute. Their data is kept.</p>
                        </div>
                      </details>
                    )}
                  </>
                )}

                {!l && pr.code === "hrm" && manager && (
                  <details style={{ marginTop: 10 }}>
                    <summary className="btn small">Switch on HRM</summary>
                    <div style={{ marginTop: 10 }}>
                      <p className="muted" style={{ fontSize: 13 }}>Creates the company inside the HRM with default departments, shifts and leave types, and its first administrator login.</p>
                      <ActionForm action={enableHrm} submitLabel="Create HRM company" pendingLabel="Setting up…" className="formgrid" hidden={{ customer_id: c.id }}>
                        <label className="field">Short name<input name="slug" defaultValue={suggestedSlug} required /><span className="help">Used in the sign-in link</span></label>
                        <label className="field">Employee code prefix<input name="prefix" defaultValue={suggestedPrefix} maxLength={5} required /><span className="help">Codes like {suggestedPrefix}-0001</span></label>
                        <label className="field">Administrator name<input name="admin_name" defaultValue={c.contact_name ?? ""} required /></label>
                        <label className="field">Administrator email<input name="admin_email" type="email" defaultValue={c.contact_email ?? ""} required /></label>
                        <label className="field">Licence<select name="status" defaultValue="trial"><option value="trial">Trial</option><option value="pilot">Pilot</option><option value="active">Active</option></select></label>
                        <label className="field">Valid until<input type="date" name="valid_until" defaultValue={addDays(today(), 30)} /></label>
                        <label className="field">Employee limit<input type="number" name="seats" min={1} placeholder="Unlimited" defaultValue={50} /></label>
                      </ActionForm>
                    </div>
                  </details>
                )}
                {!l && pr.code !== "hrm" && manager && (
                  <details style={{ marginTop: 10 }}>
                    <summary className="btn small">Switch on {pr.name}</summary>
                    <div style={{ marginTop: 10 }}>
                      <p className="muted" style={{ fontSize: 13 }}>Creates the company&apos;s workspace and its first administrator. The same email and password work in every KMR app.</p>
                      <ActionForm action={enableTool} submitLabel={`Create ${pr.name} workspace`} pendingLabel="Setting up…" className="formgrid" hidden={{ customer_id: c.id, product_code: pr.code }}>
                        <label className="field">Workspace name<input name="workspace" defaultValue={c.name} required /></label>
                        <label className="field">Administrator name<input name="admin_name" defaultValue={c.contact_name ?? ""} required /></label>
                        <label className="field">Administrator email<input name="admin_email" type="email" defaultValue={c.contact_email ?? ""} required /></label>
                        <label className="field">Licence<select name="status" defaultValue="trial"><option value="trial">Trial</option><option value="pilot">Pilot</option><option value="active">Active</option></select></label>
                        <label className="field">Valid until<input type="date" name="valid_until" defaultValue={addDays(today(), 30)} /></label>
                        <label className="field">User limit<input type="number" name="seats" min={1} placeholder="Unlimited" defaultValue={5} /></label>
                      </ActionForm>
                    </div>
                  </details>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="grid two">
        <div className="card">
          <h2>Company details</h2>
          <ActionForm action={saveCustomer} submitLabel="Save" className="formgrid" hidden={{ id: c.id }}><CustomerFields c={c} /></ActionForm>
        </div>
        <div className="card">
          <h2>Licence history</h2>
          {events?.length ? (
            <ul className="timeline">
              {events.map((e, i) => {
                const l = (licences ?? []).find((x) => x.id === e.licence_id);
                const d = e.detail as Record<string, unknown>;
                const text = e.action === "created" ? `created as ${d.status}` : Object.entries(d).filter(([, v]) => Array.isArray(v) && v[0] !== v[1]).map(([k, v]) => `${k.replace("_", " ")} ${(v as unknown[])[0] ?? "—"} → ${(v as unknown[])[1] ?? "—"}`).join(", ");
                return <li key={i}><span><b>{l?.product_code.toUpperCase()}</b> {text}</span><small>{fmtDateTime(e.created_at)}</small></li>;
              })}
            </ul>
          ) : <p className="muted">No licences yet.</p>}
        </div>
      </div>
    </AppShell>
  );
}
