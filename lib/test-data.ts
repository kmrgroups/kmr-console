import "server-only";
import { createHash } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { ensureLogin, provisionHrm, provisionWorkspace, tempPassword, type ToolCode } from "@/lib/provision";
import { loadWebsiteSample, removeWebsiteSample } from "@/lib/website-sample";
import { env } from "@/lib/env";

/**
 * Console › Test data. One demo customer with a live workspace in every KMR app and one login for all of them,
 * plus the Console's demo customers and the website's sample content. Everything demo is marked "KMR demo data"
 * (or sample = true on the website) so "Remove demo data" takes out exactly that.
 */
export const DEMO = {
  slug: "kmr-demo",
  name: "KMR Demo Manufacturing",
  legal: "KMR Demo Manufacturing Pvt Ltd",
  email: "demo@kmr-demo.test",
  person: "Demo Administrator",
  prefix: "DEMO",
  source: "KMR demo data",
};
const B = "kmr-backups";
type Step = { part: string; ok: boolean; note: string };
const db = () => createAdminClient();

// ------------------------------------------------------------------ backups
export async function settingsJson() {
  const { data, error } = await db().rpc("settings_export");
  if (error) throw new Error(error.message);
  return data as Record<string, unknown>;
}
export async function restoreSettings(json: unknown) {
  const { data, error } = await db().rpc("settings_import", { p_data: json });
  if (error) throw new Error(error.message);
  return data as Record<string, number>;
}
/** Every table of every app, saved to kmr-backups/full/<time>.json (too big to send through the page itself). */
export async function saveFullBackup(label: string) {
  const { data, error } = await db().rpc("full_export");
  if (error) throw new Error(`Full backup failed: ${error.message}`);
  const json = JSON.stringify(data);
  const at = new Date(Date.now() + 330 * 6e4).toISOString().slice(0, 16).replace(/[:T]/g, "-");
  const path = `full/${at}-${label}.json`;
  const up = await db().storage.from(B).upload(path, new Blob([json], { type: "application/json" }), { upsert: true, contentType: "application/json" });
  if (up.error) throw new Error(`Full backup could not be saved: ${up.error.message}`);
  return { path, bytes: json.length };
}
export async function listFullBackups() {
  const { data } = await db().storage.from(B).list("full", { limit: 30, sortBy: { column: "name", order: "desc" } });
  const files = (Array.isArray(data) ? data : []).filter((f) => f.name.endsWith(".json"));
  return Promise.all(files.map(async (f) => {
    const { data: s } = await db().storage.from(B).createSignedUrl(`full/${f.name}`, 600, { download: f.name });
    return { name: f.name, size: Number((f.metadata as { size?: number } | null)?.size ?? 0), url: s?.signedUrl ?? null };
  }));
}

// ------------------------------------------------------------------ demo
export async function demoStatus() {
  const d = db();
  const [{ count: demoCustomers }, { data: demo }, { count: sample }] = await Promise.all([
    d.from("customers").select("id", { count: "exact", head: true }).eq("source", DEMO.source),
    d.from("customers").select("id,licences(product_code,product_ref)").eq("slug", DEMO.slug).maybeSingle(),
    d.schema("public").from("hero_slides").select("id", { count: "exact", head: true }).eq("sample", true),
  ]);
  return { demoCustomers: demoCustomers ?? 0, demo: demo as { id: string; licences: { product_code: string; product_ref: string | null }[] } | null, websiteSample: (sample ?? 0) > 0 };
}

async function hrmAttendance(tenant: string) {
  const key = createHash("sha256").update(`kmr-internal:${env.serviceRoleKey}`).digest("hex");
  const hrmUrl = (process.env.HRM_INTERNAL_URL || `${env.platformUrl}/it/hrm`).replace(/\/+$/, "");
  const r = await fetch(`${hrmUrl}/api/internal/demo-attendance`, {
    method: "POST", headers: { "content-type": "application/json", "x-kmr-key": key }, body: JSON.stringify({ tenant }), signal: AbortSignal.timeout(55_000),
  });
  if (!r.ok) throw new Error(`HRM replied ${r.status}`);
}

export async function loadDemoEverywhere(): Promise<{ steps: Step[]; password: string | null }> {
  const d = db(), steps: Step[] = [];
  const step = async (part: string, fn: () => Promise<string>) => {
    try { steps.push({ part, ok: true, note: await fn() }); } catch (e) { steps.push({ part, ok: false, note: (e as Error).message }); }
  };
  const st = await demoStatus();
  if (st.demo) throw new Error("Demo data is already loaded. Remove it first to load it again.");

  await step("Console customers", async () => {
    if (st.demoCustomers) return "already there";
    const { data, error } = await d.rpc("demo_load"); if (error) throw new Error(error.message);
    return `${data} sample customers in 4 countries with licences and 2 enquiries`;
  });
  await step("Website", async () => (st.websiteSample ? "sample content already there" : `${await loadWebsiteSample()} sample items (slides, products, programmes, jobs, gallery)`));

  // the demo customer and its one login
  const { data: cust, error: cErr } = await d.from("customers").insert({
    name: DEMO.name, legal_name: DEMO.legal, country: "IN", currency: "INR", city: "Bengaluru", state: "Karnataka",
    contact_name: DEMO.person, contact_email: DEMO.email, contact_phone: "+91 90000 00000", status: "active", source: DEMO.source,
    slug: DEMO.slug, notes: "Demo customer with a live workspace in every KMR app (Console › Test data).",
  }).select("id").single();
  if (cErr || !cust) throw new Error(`Could not create the demo customer: ${cErr?.message}`);
  const login = await ensureLogin(DEMO.email, DEMO.person);
  const password = tempPassword();
  const { error: pErr } = await d.auth.admin.updateUserById(login.id, { password });
  if (pErr) throw new Error(`Could not set the demo password: ${pErr.message}`);
  await d.from("customer_members").upsert({ customer_id: cust.id, email: DEMO.email, full_name: DEMO.person, is_admin: true, roles: {}, login_owned: true, created_by: DEMO.source });

  await step("HRM", async () => {
    const r = await provisionHrm({ customerName: DEMO.name, legalName: DEMO.legal, slug: DEMO.slug, prefix: DEMO.prefix, adminName: DEMO.person, adminEmail: DEMO.email,
      phone: "+91 90000 00000", email: DEMO.email, address: "Plot 12, Bommasandra Industrial Area, Bengaluru 560099" });
    await d.from("licences").insert({ customer_id: cust.id, product_code: "hrm", status: "active", valid_until: null, seats: 200, product_ref: r.tenantId, product_slug: DEMO.slug, notes: DEMO.source });
    const hrm = d.schema("hrm");
    await hrm.from("app_users").update({ must_change_password: false }).eq("id", login.id);
    const { data: n, error } = await hrm.rpc("demo_load", { p_tenant: r.tenantId });
    if (error) throw new Error(error.message);
    const pay = await hrm.rpc("demo_payroll", { p_tenant: r.tenantId });           // salaries + two loans (HRM 0005)
    let att = " with a month of attendance";
    try { await hrmAttendance(r.tenantId); } catch { att = " (attendance is filled in by the HRM's nightly job, or HRM › Attendance › Recalculate)"; }
    return `${n} employees in two plants, leave and pending requests${att}${pay.error ? "" : ", salaries and two loans for payroll"}`;
  });
  for (const [code, label, ws] of [["balloon", "Balloon Inspector", "KMR Demo – Quality"], ["pd", "Process Documents", "KMR Demo – APQP"], ["capacity", "Capacity Planner", "KMR Demo – Planning"]] as [ToolCode, string, string][]) {
    await step(label, async () => {
      const id = crypto.randomUUID();
      const { error } = await d.from("licences").insert({ customer_id: cust.id, product_code: code, status: "active", valid_until: null, seats: 10, product_ref: id, product_slug: ws, notes: DEMO.source });
      if (error) throw new Error(error.message);
      await provisionWorkspace(code, id, ws, DEMO.person, DEMO.email);
      return code === "capacity" ? "workspace with the sample plan (12 machines, 43 operations)" : "workspace ready — open it and click “Try the sample”";
    });
  }
  await step("Operations Master", async () => {
    const { data, error } = await d.rpc("ops_demo_load", { p_customer: cust.id }); if (error) throw new Error(error.message);
    return `${data} sample records (machines, parts, routings, gauges…)`;
  });
  return { steps, password };
}

export async function removeDemoEverywhere(): Promise<Step[]> {
  const d = db(), steps: Step[] = [];
  const { data: custs } = await d.from("customers").select("id,licences(product_code,product_ref)").eq("source", DEMO.source);
  let ws = 0;
  for (const c of (custs ?? []) as { id: string; licences: { product_code: string; product_ref: string | null }[] }[]) {
    for (const l of c.licences) {
      if (!l.product_ref) continue;
      const r = l.product_code === "hrm"
        ? await d.rpc("hrm_delete_company", { p_tenant: l.product_ref })
        : await d.rpc("workspace_delete", { p_product: l.product_code, p_id: l.product_ref });
      if (r.error) steps.push({ part: l.product_code, ok: false, note: r.error.message }); else if (r.data) ws++;
    }
  }
  steps.push({ part: "App workspaces", ok: true, note: `${ws} removed` });
  const { data: n, error } = await d.rpc("demo_flush");
  steps.push({ part: "Console customers", ok: !error, note: error ? error.message : `${n} demo customers removed (with licences and Operations Master records)` });
  try { const r = await removeWebsiteSample(); steps.push({ part: "Website", ok: true, note: `${r.removed} sample items removed` }); }
  catch (e) { steps.push({ part: "Website", ok: false, note: (e as Error).message }); }
  const gone = await deleteOrphanLogins((u) => u.email?.endsWith("kmr-demo.test") ?? false);
  steps.push({ part: "Demo login", ok: true, note: gone ? "removed" : "none left" });
  return steps;
}

// ------------------------------------------------------------------ clean out
export const FLUSH_PARTS = [
  { key: "customers", label: "Customers and their licences, invoices, payments, support tickets, enquiries and Operations Master data", default: true },
  { key: "apps", label: "App data: every HRM company (KMR’s own keeps its settings and admins), Balloon, Process Documents and Capacity workspaces", default: true },
  { key: "shop", label: "Website orders and job applications (with résumés)", default: true },
  { key: "logs", label: "Activity log, email log, error log", default: true },
  { key: "logins", label: "Customer and employee logins nobody uses any more (KMR staff logins are always kept)", default: true },
  { key: "catalogue", label: "Website shop products, training programmes and job openings (normally kept — they are website content)", default: false },
] as const;

async function deleteOrphanLogins(filter?: (u: { user_id: string; email: string | null }) => boolean) {
  const d = db();
  const { data } = await d.rpc("orphan_logins");
  let n = 0;
  for (const u of ((data ?? []) as { user_id: string; email: string | null }[]).filter(filter ?? (() => true))) {
    const { error } = await d.auth.admin.deleteUser(u.user_id);
    if (!error) n++;
  }
  return n;
}

async function emptyBucket(bucket: string, keep: (path: string) => boolean = () => false, prefix = ""): Promise<number> {
  const s = db().storage.from(bucket);
  const { data } = await s.list(prefix, { limit: 1000 });
  let n = 0;
  for (const f of Array.isArray(data) ? data : []) {
    const path = prefix ? `${prefix}/${f.name}` : f.name;
    if (keep(path)) continue;
    if (f.id === null) n += await emptyBucket(bucket, keep, path);                 // a folder
    else { const { error } = await s.remove([path]); if (!error) n++; }
  }
  return n;
}

export async function flushPlatform(parts: string[]): Promise<{ backup: string; result: Record<string, unknown> }> {
  const d = db();
  const backup = await saveFullBackup("before-clean-out");            // never clean out without a backup
  const sqlParts = parts.filter((p) => p !== "logins");
  const { data, error } = await d.rpc("platform_flush", { p_parts: sqlParts, p_keep_hrm: process.env.KMR_HRM_SLUG || "kmr" });
  if (error) throw new Error(`Nothing was removed: ${error.message}`);
  const result = { ...(data as Record<string, unknown>) };
  if (parts.includes("shop")) result.resumes = await emptyBucket("kmr-careers");
  if (parts.includes("apps")) {
    const { data: kept } = await d.schema("hrm").from("tenants").select("id");
    const keep = new Set((kept ?? []).map((t) => t.id as string));
    result.hrm_files = await emptyBucket("hrm-docs", (p) => keep.has(p.split("/")[0]));
  }
  if (parts.includes("logins")) result.logins = await deleteOrphanLogins();
  return { backup: backup.path, result };
}
