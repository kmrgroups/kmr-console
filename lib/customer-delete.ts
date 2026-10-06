import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { saveFullBackup } from "@/lib/test-data";

/**
 * Deleting a customer (Console › Customers › the customer › Delete this customer).
 * Safe by design:
 *  • invoices and payments are tax records — a customer that has any issued / paid / cancelled invoice or any payment is NOT deleted
 *    (set it to Inactive instead); draft invoices are not records yet and go with the customer;
 *  • KMR's own company and "internal" companies are never deleted;
 *  • a full backup is saved before anything is removed.
 */
/** Testing mode (default): test invoices and payments may be deleted with their customer. "Go live" locks them for good-practice tax record keeping. */
export async function isTestingMode(): Promise<boolean> {
  try {
    const { data } = await createAdminClient().from("platform_settings").select("value").eq("key", "mode").maybeSingle();
    return (data?.value as { live?: boolean } | null)?.live !== true;
  } catch { return true; }
}

export type DeleteInfo = {
  customer: { id: string; name: string; code: string | null; slug: string | null; kind: string | null } | null;
  blockers: string[];
  drafts: number;
  workspaces: number;
  members: number;
};

export async function checkCustomerDelete(id: string): Promise<DeleteInfo> {
  const d = createAdminClient();
  const testing = await isTestingMode();
  const { data: c } = await d.from("customers").select("id,name,code,slug,kind").eq("id", id).maybeSingle();
  if (!c) return { customer: null, blockers: ["This company no longer exists."], drafts: 0, workspaces: 0, members: 0 };
  const blockers: string[] = [];
  if (c.kind === "internal") blockers.push("This is an internal KMR company and cannot be deleted.");

  const { data: invs } = await d.from("invoices").select("id,status").eq("customer_id", id);
  const all = (invs ?? []) as { id: string; status: string }[];
  const kept = all.filter((i) => i.status !== "draft");
  if (!testing && kept.length) blockers.push(`It has ${kept.length} issued, paid or cancelled invoice${kept.length > 1 ? "s" : ""}. Invoices are tax records and must be kept — set the company to Inactive instead.`);
  if (!testing && all.length) {
    const { count } = await d.from("payments").select("id", { count: "exact", head: true }).in("invoice_id", all.map((i) => i.id));
    if (count) blockers.push(`It has ${count} recorded payment${count > 1 ? "s" : ""}, which must be kept.`);
  }

  const { data: lic } = await d.from("licences").select("product_code,product_ref").eq("customer_id", id);
  const ws = ((lic ?? []) as { product_code: string; product_ref: string | null }[]).filter((l) => l.product_ref && l.product_ref !== id && ["hrm", "balloon", "pd", "capacity"].includes(l.product_code));
  // KMR's own HRM company is never deleted
  const own = process.env.KMR_HRM_SLUG || "kmr";
  for (const l of ws.filter((x) => x.product_code === "hrm")) {
    try {
      const { data: t } = await d.schema("hrm").from("tenants").select("slug").eq("id", l.product_ref).maybeSingle();
      if (t?.slug === own) blockers.push("This company owns KMR's own HRM company and cannot be deleted.");
    } catch { /* HRM not set up */ }
  }
  const { count: members } = await d.from("customer_members").select("email", { count: "exact", head: true }).eq("customer_id", id);
  return { customer: c, blockers, drafts: all.length - kept.length, workspaces: ws.length, members: members ?? 0 };
}

export type DeleteStep = { part: string; ok: boolean; note: string };

export async function deleteCustomer(id: string, typed: string, opts: { skipConfirm?: boolean; skipBackup?: boolean } = {}): Promise<DeleteStep[]> {
  const info = await checkCustomerDelete(id);
  const c = info.customer;
  if (!c) throw new Error("This company no longer exists.");
  if (info.blockers.length) throw new Error(info.blockers[0]);
  const t = typed.trim().toLowerCase();
  if (!opts.skipConfirm && (!t || (t !== c.name.trim().toLowerCase() && t !== (c.code ?? "").toLowerCase()))) throw new Error("The name you typed does not match. Type the company name exactly to confirm.");

  const d = createAdminClient(), steps: DeleteStep[] = [];
  // 1. a copy first — if this fails nothing is deleted
  if (!opts.skipBackup) {
    const bk = await saveFullBackup(`before-delete-${c.code ?? c.slug ?? "customer"}`);
    steps.push({ part: "Backup", ok: true, note: `full backup saved (${Math.round(bk.bytes / 1024)} KB)` });
  }

  const { data: mem } = await d.from("customer_members").select("email").eq("customer_id", id);
  const emails = new Set(((mem ?? []) as { email: string }[]).map((m) => m.email.toLowerCase()));

  // 2. draft invoices (not yet tax records)
  const testing = await isTestingMode();
  let q = d.from("invoices").select("id").eq("customer_id", id);
  if (!testing) q = q.eq("status", "draft");
  const { data: drafts } = await q;
  const dids = ((drafts ?? []) as { id: string }[]).map((x) => x.id);
  if (dids.length) {
    if (testing) { const pr = await d.from("payments").delete().in("invoice_id", dids); if (pr.error) throw new Error(`Could not remove the payments: ${pr.error.message}`); }
    await d.from("invoice_lines").delete().in("invoice_id", dids);
    const r = await d.from("invoices").delete().in("id", dids);
    if (r.error) throw new Error(`Could not remove the draft invoices: ${r.error.message}`);
    steps.push({ part: testing ? "Test invoices" : "Draft invoices", ok: true, note: `${dids.length} removed` });
  }

  // 3. the company's workspaces in the apps
  const { data: lic } = await d.from("licences").select("product_code,product_ref").eq("customer_id", id);
  let ws = 0;
  for (const l of (lic ?? []) as { product_code: string; product_ref: string | null }[]) {
    if (!l.product_ref || l.product_ref === id) continue;
    const r = l.product_code === "hrm" ? await d.rpc("hrm_delete_company", { p_tenant: l.product_ref })
      : ["balloon", "pd", "capacity"].includes(l.product_code) ? await d.rpc("workspace_delete", { p_product: l.product_code, p_id: l.product_ref }) : null;
    if (!r) continue;
    if (r.error) throw new Error(`Could not remove the ${l.product_code} workspace (${r.error.message}). Nothing else was deleted; the backup is saved.`);
    if (r.data) ws++;
  }
  steps.push({ part: "App workspaces", ok: true, note: `${ws} removed` });

  // 4. the company itself — licences, members, Operations Master, Sales Flow, Calibration, APQP, PPAP and the rest follow it
  const del = await d.from("customers").delete().eq("id", id);
  if (del.error) throw new Error(`Could not delete the company: ${del.error.message}. The app workspaces were already removed; the backup is saved.`);
  steps.push({ part: "Company", ok: true, note: `${c.name} deleted with its licences, users list and Operations Master data` });

  // 5. logins that belonged only to this company
  let gone = 0;
  const { data: orphans } = await d.rpc("orphan_logins");
  for (const u of ((orphans ?? []) as { user_id: string; email: string | null }[]).filter((x) => x.email && emails.has(x.email.toLowerCase()))) {
    const { error } = await d.auth.admin.deleteUser(u.user_id);
    if (!error) gone++;
  }
  steps.push({ part: "Logins", ok: true, note: gone ? `${gone} unused login${gone > 1 ? "s" : ""} removed` : "none to remove" });
  return steps;
}

/** Remove several test customers in one go: one full backup, then each company in turn. Blocked ones are skipped and reported. */
export async function deleteCustomers(ids: string[]): Promise<{ done: string[]; skipped: { name: string; why: string }[]; backup: string }> {
  const done: string[] = [], skipped: { name: string; why: string }[] = [];
  const checks = await Promise.all(ids.map((i) => checkCustomerDelete(i)));
  const ok = checks.filter((c) => c.customer && !c.blockers.length);
  for (const c of checks) if (c.customer && c.blockers.length) skipped.push({ name: c.customer.name, why: c.blockers[0] });
  if (!ok.length) return { done, skipped, backup: "none needed" };
  const bk = await saveFullBackup(`before-delete-${ok.length}-customers`);
  for (const c of ok) {
    try { await deleteCustomer(c.customer!.id, "", { skipConfirm: true, skipBackup: true }); done.push(c.customer!.name); }
    catch (e) { skipped.push({ name: c.customer!.name, why: (e as Error).message }); }
  }
  return { done, skipped, backup: `${Math.round(bk.bytes / 1024)} KB` };
}
