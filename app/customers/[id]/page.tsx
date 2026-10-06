import { notFound } from "next/navigation";
import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { CustomerFields } from "@/components/CustomerFields";
import { fmtDate, fmtDateTime } from "@/components/ui";
import { env } from "@/lib/env";
import { CUSTOMER_TONE, INVOICE_TONE, LICENCE_TONE, addDays, effectiveStatus, today } from "@/lib/view";
import { fmtMoney } from "@/lib/money";
import { p } from "@/lib/base-path";
import { createInvoice } from "@/app/billing-actions";
import { enableHrm, enableTool, portalLogin, repairAccess, saveCustomer, saveCustomerSlug, saveLicence, uploadCustomerLogo } from "@/app/actions";
import { isTool, toolUsage } from "@/lib/provision";
import { checkCustomerDelete } from "@/lib/customer-delete";
import { deleteCustomerAction } from "./delete-action";

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
  const isOwner = staff.role === "owner";
  const del = isOwner ? await checkCustomerDelete(c.id) : null;
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
  const [{ data: invoices }, { data: prices }] = await Promise.all([
    supabase.from("invoices").select("id,number,status,currency,total,issue_date,due_date,created_at").eq("customer_id", c.id).order("created_at", { ascending: false }),
    supabase.from("prices").select("product_code,period,currency,unit_amount,min_seats").eq("active", true).eq("currency", c.currency),
  ]);
  // A renewal starts the day after the earliest current licence ends; otherwise today
  const ends = ((licences ?? []) as Licence[]).map((l) => l.valid_until).filter((d): d is string => !!d && d >= today()).sort();
  const billFrom = ends.length ? addDays(ends[0], 1) : today();
  const priceOf = (code: string, period: string) => (prices ?? []).find((x) => x.product_code === code && x.period === period);
  const { data: members } = await supabase.from("customer_members").select("email,full_name,is_admin,roles").eq("customer_id", c.id).order("is_admin", { ascending: false }).order("email");
  const prodName: Record<string, string> = Object.fromEntries(((products ?? []) as { code: string; name: string }[]).map((x) => [x.code, x.name]));
  const suggestedSlug = c.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "company";
  const suggestedPrefix = c.name.replace(/[^A-Za-z]/g, "").slice(0, 3).toUpperCase() || "EMP";

  return (
    <AppShell staff={staff} active="/customers">
      <div className="pagehead">
        <div><h1>{c.name}</h1><p><span className="mono">{c.code}</span> · {c.country} · {c.currency} · <span className={`badge ${CUSTOMER_TONE[c.status]}`}>{c.status}</span></p></div>
      </div>

      <div className="card">
        <h2>Customer portal</h2>
        {!("slug" in c) && <div className="alert warn">The customer portal is not set up in the database yet. In Supabase → SQL Editor run <b>supabase/migrations/0004_portal.sql</b> (and 0005_data_tools.sql), then refresh this page.</div>}
        {("slug" in c) && <div className="grid two">
          <div>
            <p className="muted" style={{ marginTop: 0 }}>One link for everything this customer has bought. After signing in they see their apps; the rest can be tried with sample data.</p>
            <p style={{ margin: "6px 0 12px" }}><a className="mono" href={`${env.platformUrl}/it/app/${c.slug}`} target="_blank" rel="noopener">{env.platformUrl}/it/app/{c.slug}</a></p>
            <ActionForm action={saveCustomerSlug} submitLabel="Change link name" variant="secondary" hidden={{ id: c.id }} className="row">
              <input name="slug" defaultValue={c.slug ?? ""} style={{ maxWidth: 260 }} />
            </ActionForm>
            <div style={{ marginTop: 14, paddingTop: 12, borderTop: "1px solid var(--border)" }}>
              <b style={{ fontSize: 14 }}>Portal login</b>
              <p className="muted" style={{ margin: "4px 0 8px", fontSize: 13 }}>For the contact person ({c.contact_email || "add a contact email in Company details"}). The same login opens every app they bought.</p>
              {manager && <div className="row" style={{ gap: 8 }}>
                <ActionForm action={portalLogin} submitLabel="Create portal login" hidden={{ id: c.id }} />
                <ActionForm action={portalLogin} submitLabel="Reset password" variant="secondary" hidden={{ id: c.id, reset: "1" }} confirm="Give the contact person a new temporary password?" />
              </div>}
            </div>
          </div>
          <div className="row" style={{ alignItems: "flex-start", gap: 16 }}>
            <div style={{ width: 96, height: 96, borderRadius: 16, border: "1px solid var(--border)", display: "grid", placeItems: "center", background: "#fff", overflow: "hidden", flex: "none" }}>
              {c.logo_url ? <img src={c.logo_url} alt="" style={{ maxWidth: 84, maxHeight: 84, objectFit: "contain" }} /> : <small className="muted">No logo</small>}
            </div>
            <ActionForm action={uploadCustomerLogo} submitLabel={c.logo_url ? "Replace logo" : "Upload logo"} variant="secondary" hidden={{ id: c.id }}>
              <input type="file" name="logo" accept="image/png,image/jpeg,image/webp,image/svg+xml" required />
              <small className="muted">PNG, JPG, WebP or SVG, under 1 MB. Square logos look best.</small>
            </ActionForm>
          </div>
        </div>}
      </div>

      <div className="card">
        <div className="spread"><h2>Users &amp; access</h2>
          <ActionForm action={repairAccess} submitLabel="Repair access" variant="secondary" hidden={{ id: c.id }} /></div>
        <p className="muted" style={{ marginTop: 0 }}>The customer manages this list in KMR Apps › Administration › Users &amp; access. <b>Repair access</b> gives the main contact and company administrators access in every tool.</p>
        {members?.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Person</th>{(licences ?? []).filter((l: Licence) => l.product_ref).map((l: Licence) => <th key={l.product_code}>{prodName[l.product_code] ?? l.product_code}</th>)}</tr></thead>
            <tbody>{members.map((m) => (
              <tr key={m.email}><td><b>{m.full_name || m.email}</b>{m.is_admin && <span className="badge ok" style={{ marginLeft: 6 }}>admin</span>}<br /><small className="muted">{m.email}</small></td>
                {(licences ?? []).filter((l: Licence) => l.product_ref).map((l: Licence) => <td key={l.product_code}>{(m.roles as Record<string, string>)?.[l.product_code] ? <span className="badge info">{(m.roles as Record<string, string>)[l.product_code]}</span> : <small className="muted">—</small>}</td>)}</tr>))}
            </tbody></table></div>
        ) : <p className="muted">Nobody yet — the list fills when tools are switched on or the customer adds people.</p>}
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
                    {toolUse[pr.code] && <><br />Using {toolUse[pr.code].users} users · {toolUse[pr.code].items} {pr.code === "balloon" ? "reports" : pr.code === "pd" ? "projects" : "saved versions"}</>}
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


      <div className="card">
        <div className="spread"><h2>Billing</h2>{manager && <a className="btn secondary small" href={p("/billing")}>Price list</a>}</div>
        {invoices?.length ? (
          <div className="tablewrap" style={{ marginBottom: 14 }}><table>
            <thead><tr><th>Invoice</th><th>Date</th><th style={{ textAlign: "right" }}>Total</th><th>Status</th></tr></thead>
            <tbody>{invoices.map((i) => {
              const late = i.status === "issued" && i.due_date && i.due_date < today();
              return <tr key={i.id}><td><a className="mono" href={p(`/invoices/${i.id}`)}><b>{i.number ?? "Draft"}</b></a></td><td>{fmtDate(i.issue_date ?? i.created_at)}</td>
                <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{fmtMoney(i.total, i.currency)}</td><td><span className={`badge ${late ? "danger" : INVOICE_TONE[i.status]}`}>{late ? "overdue" : i.status}</span></td></tr>;
            })}</tbody></table></div>
        ) : <p className="muted">No invoices yet.</p>}
        {manager && (
          <details>
            <summary className="btn small">Create invoice</summary>
            <div style={{ marginTop: 10 }}>
              <p className="muted" style={{ fontSize: 13 }}>Billed in <b>{c.currency}</b> from the price list, with GST worked out from {c.country === "IN" ? <>the customer&apos;s {c.tax_id ? "GSTIN" : "state"}</> : "their country (export, no GST)"}. You get a draft to check before issuing. When it is paid, the ticked products&apos; licences renew for the period.</p>
              <ActionForm action={createInvoice} submitLabel="Create draft invoice" pendingLabel="Creating…" hidden={{ customer_id: c.id }}>
                <div className="row">
                  <label className="field" style={{ flex: 1, minWidth: 160 }}>Billing<select name="period" defaultValue="month"><option value="month">Monthly</option><option value="year">Yearly</option></select></label>
                  <label className="field" style={{ flex: 1, minWidth: 160 }}>Period starts<input type="date" name="from" defaultValue={billFrom} required /></label>
                </div>
                <div className="stack" style={{ gap: 6 }}>
                  {(products ?? []).map((pr) => {
                    const l = (licences ?? []).find((x) => x.product_code === pr.code) as Licence | undefined;
                    const m = priceOf(pr.code, "month"), y = priceOf(pr.code, "year");
                    return (
                      <div key={pr.code} className="row" style={{ border: "1px solid var(--border)", borderRadius: 8, padding: "8px 12px", justifyContent: "space-between" }}>
                        <label style={{ display: "flex", gap: 8, alignItems: "center", flex: 1, minWidth: 200 }}>
                          <input type="checkbox" name="product" value={pr.code} defaultChecked={!!l && ["trial", "pilot", "active"].includes(l.status)} />
                          <span><b>{pr.name}</b><br /><small className="muted">{m ? `${fmtMoney(m.unit_amount, c.currency)}/month` : "no monthly price"} · {y ? `${fmtMoney(y.unit_amount, c.currency)}/year` : "no yearly price"} per {pr.seat_label.replace(/s$/, "")}{(m ?? y) ? `, min ${(m ?? y)!.min_seats}` : ""}</small></span>
                        </label>
                        <label className="row" style={{ gap: 6, fontSize: 13 }}>{pr.seat_label}<input type="number" name={`seats_${pr.code}`} min={1} defaultValue={l?.seats ?? (m ?? y)?.min_seats ?? 1} style={{ width: 90 }} /></label>
                      </div>);
                  })}
                </div>
                <label className="field">Note on the invoice (optional)<input name="notes" placeholder="e.g. PO 4500012345" /></label>
              </ActionForm>
            </div>
          </details>
        )}
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

      {isOwner && del && (
        <div className="card" style={{ borderLeft: "4px solid var(--danger,#dc2626)" }}>
          <h2>Delete this customer</h2>
          {del.blockers.length ? (
            <>
              <p className="muted" style={{ marginTop: 0 }}>This company cannot be deleted:</p>
              <ul>{del.blockers.map((b) => <li key={b}>{b}</li>)}</ul>
              <p className="muted" style={{ fontSize: 13 }}>To stop them using the apps without losing any records, set the status to <b>Inactive</b> under Company details above.</p>
            </>
          ) : (
            <>
              <p className="muted" style={{ marginTop: 0 }}>Permanently removes <b>{c.name}</b> with its licences, its users list, its Operations Master data and its workspaces in the apps ({del.workspaces} workspace{del.workspaces === 1 ? "" : "s"}, {del.members} user{del.members === 1 ? "" : "s"}{del.drafts ? `, ${del.drafts} draft invoice${del.drafts === 1 ? "" : "s"}` : ""}). A full backup is saved first. Support tickets and enquiries stay, without the link to this company. This cannot be undone from the Console.</p>
              <ActionForm action={deleteCustomerAction} submitLabel="Delete this customer" variant="danger" hidden={{ id: c.id }} confirm={`Delete ${c.name} permanently? A backup is saved first, but this cannot be undone from the Console.`}>
                <label className="field">Type the company name to confirm<input name="confirm" placeholder={c.name} autoComplete="off" /></label>
              </ActionForm>
            </>
          )}
        </div>
      )}
    </AppShell>
  );
}
