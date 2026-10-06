"use server";
import { revalidatePath, revalidateTag } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager, assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { ensureLogin, isTool, provisionHrm, provisionWorkspace, tempPassword } from "@/lib/provision";
import { randomUUID } from "node:crypto";
import { env } from "@/lib/env";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";
import { mailTicketReply } from "@/lib/notify";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const opt = z.string().trim().max(300).optional().transform((v) => v || null);

const customerSchema = z.object({
  name: z.string().trim().min(2, "Company name is required").max(120),
  legal_name: opt, tax_id: opt, address: opt, city: opt, state: opt, postal_code: opt, source: opt, notes: z.string().trim().max(2000).optional().transform((v) => v || null),
  country: z.string().trim().toUpperCase().regex(/^[A-Z]{2}$/, "Country: 2-letter code, e.g. IN, US, DE"),
  currency: z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/, "Currency: 3-letter code, e.g. INR, USD"),
  time_zone: z.string().trim().min(3).max(60),
  contact_name: opt, contact_phone: opt,
  contact_email: z.string().trim().toLowerCase().email("Enter a valid contact email").or(z.literal("")).transform((v) => v || null),
  status: z.enum(["lead", "pilot", "active", "inactive"]),
});

export async function saveCustomer(_: ActionState, form: FormData): Promise<ActionState> {
  let id = String(form.get("id") ?? "");
  try {
    const staff = await assertStaff();
    const parsed = customerSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const supabase = await createClient();
    if (id) {
      const { error } = await supabase.from("customers").update({ ...parsed.data, updated_at: new Date().toISOString() }).eq("id", id);
      if (error) return { error: error.message };
      revalidatePath(`/customers/${id}`);
      return { ok: "Customer saved." };
    }
    const { data, error } = await supabase.from("customers").insert({ ...parsed.data, created_by: staff.user_id }).select("id,slug").single();
    if (error) return { error: error.message };
    id = data.id;
    // First-time portal login for the contact person, created straight away and shown once on the next screen
    const email = parsed.data.contact_email;
    const url = `${env.platformUrl}/it/app/${data.slug ?? ""}`;
    if (email) {
      try {
        const login = await ensureLogin(email, parsed.data.contact_name || parsed.data.name);
        await setFlash(login.password
          ? { ok: `Customer created. Send these to ${parsed.data.contact_name || email} — Link: ${url} · Email: ${email} · Temporary password: ${login.password} (shown only now; they can change it in the portal under "Change password").` }
          : { ok: `Customer created. ${email} already has a KMR login — they sign in at ${url} with their existing password (use "Reset password" below if they don't know it).` });
      } catch (e) {
        await setFlash({ error: `Customer created, but the portal login could not be made: ${(e as Error).message}. Use "Create portal login" below.` });
      }
    } else {
      await setFlash({ ok: `Customer created. Add a contact email under Company details, then click "Create portal login" to give them their password.` });
    }
  } catch (e) { return fail(e); }
  redirect(`/customers/${id}`);
}

const licenceSchema = z.object({
  customer_id: z.string().uuid(),
  product_code: z.string().min(2),
  status: z.enum(["trial", "pilot", "active", "suspended", "expired", "cancelled"]),
  valid_until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).transform((v) => v || null),
  seats: z.string().trim().optional().transform((v) => (v ? Number(v) : null)).refine((v) => v === null || (Number.isInteger(v) && v > 0 && v <= 100000), "Limit must be a whole number"),
  notes: z.string().trim().max(1000).optional().transform((v) => v || null),
});

/** Change a licence's status, end date or limit (takes effect in the product within a minute). */
export async function saveLicence(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = licenceSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const { customer_id, product_code, ...rest } = parsed.data;
    const supabase = await createClient();
    const { error } = await supabase.from("licences").update(rest).eq("customer_id", customer_id).eq("product_code", product_code);
    if (error) return { error: error.message };
    revalidatePath(`/customers/${customer_id}`);
    return { ok: "Licence updated. The product applies it within a minute." };
  } catch (e) { return fail(e); }
}

/** Which features of an app the customer may use: none ticked + "all" = no restriction; otherwise only the ticked ones (core features are always kept). */
export async function saveLicenceFeatures(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const customer = String(form.get("customer_id") ?? ""), product = String(form.get("product_code") ?? "");
    const supabase = await createClient();
    let features: string[] | null = null;
    if (form.get("scope") === "only") {
      const keys = form.getAll("feature").map(String);
      const { data: core } = await supabase.from("app_features").select("key").eq("product_code", product).eq("is_core", true).eq("active", true);
      features = Array.from(new Set([...keys, ...((core ?? []) as { key: string }[]).map((x) => x.key)]));
    }
    const { error } = await supabase.from("licences").update({ features, updated_at: new Date().toISOString() }).eq("customer_id", customer).eq("product_code", product);
    if (error) return { error: error.message.includes("features") ? "This needs the database update 0051_feature_access.sql — run it in Supabase, then try again." : error.message };
    revalidatePath(`/customers/${customer}`);
    return { ok: features ? `Saved: the customer can use ${features.length} feature${features.length === 1 ? "" : "s"} of this app. The rest are locked.` : "Saved: the customer can use every feature of this app." };
  } catch (e) { return fail(e); }
}

const hrmSchema = z.object({
  customer_id: z.string().uuid(),
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9-]{1,29}$/, "Short name: 2–30 lowercase letters, digits or dashes"),
  prefix: z.string().trim().toUpperCase().regex(/^[A-Z]{2,5}$/, "Employee code prefix: 2–5 letters"),
  admin_name: z.string().trim().min(2, "Administrator's name is required").max(80),
  admin_email: z.string().trim().toLowerCase().email("Enter the administrator's email"),
  status: z.enum(["trial", "pilot", "active"]),
  valid_until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).transform((v) => v || null),
  seats: z.string().trim().optional().transform((v) => (v ? Number(v) : null)),
});

/** Switch the HRM on for a customer: creates their company and administrator inside the HRM, and the licence. */
export async function enableHrm(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = hrmSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const d = parsed.data;
    const db = createAdminClient();
    const { data: c } = await db.from("customers").select("*").eq("id", d.customer_id).single();
    if (!c) return { error: "Customer not found." };
    const { data: had } = await db.from("licences").select("id").eq("customer_id", c.id).eq("product_code", "hrm").maybeSingle();
    if (had) return { error: "This customer already has an HRM licence." };

    const r = await provisionHrm({
      customerName: c.name, legalName: c.legal_name, slug: d.slug, prefix: d.prefix,
      adminName: d.admin_name, adminEmail: d.admin_email, phone: c.contact_phone, email: c.contact_email,
      address: [c.address, c.city, c.state, c.postal_code].filter(Boolean).join(", ") || null,
    });
    const supabase = await createClient();
    const { error } = await supabase.from("licences").insert({
      customer_id: c.id, product_code: "hrm", status: d.status, valid_until: d.valid_until, seats: d.seats,
      product_ref: r.tenantId, product_slug: d.slug,
    });
    if (error) return { error: `The HRM company was created, but the licence could not be saved: ${error.message}` };
    if (c.status === "lead") await supabase.from("customers").update({ status: d.status === "active" ? "active" : "pilot" }).eq("id", c.id);
    revalidatePath(`/customers/${c.id}`);
    const url = `${env.platformUrl}/it/hrm/login?co=${d.slug}`;
    return {
      ok: r.password
        ? `HRM is on. Send the administrator: sign-in ${url} · email ${d.admin_email} · temporary password ${r.password} (shown only now; they must change it at first sign-in).`
        : `HRM is on. ${d.admin_email} already has a KMR login and uses their existing password at ${url}.`,
    };
  } catch (e) { return fail(e); }
}

export async function addRelease(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const product_code = String(form.get("product_code") ?? "");
    const version = String(form.get("version") ?? "").trim();
    const notes = String(form.get("notes") ?? "").trim() || null;
    if (!/^\d+\.\d+\.\d+$/.test(version)) return { error: "Version looks like 2.1.0" };
    const supabase = await createClient();
    const { error } = await supabase.from("releases").insert({ product_code, version, notes });
    if (error) return { error: /duplicate/.test(error.message) ? "That version is already recorded." : error.message };
    await supabase.from("products").update({ current_version: version }).eq("code", product_code);
    revalidatePath("/products");
    return { ok: `${product_code.toUpperCase()} ${version} recorded as the current version.` };
  } catch (e) { return fail(e); }
}

export async function addStaff(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const me = await assertManager();
    if (me.role !== "owner") return { error: "Only the owner can add Console staff." };
    const email = String(form.get("email") ?? "").trim().toLowerCase();
    const full_name = String(form.get("full_name") ?? "").trim();
    const role = String(form.get("role") ?? "support");
    if (!z.string().email().safeParse(email).success || full_name.length < 2) return { error: "Enter a name and a valid email." };
    if (!["owner", "admin", "sales", "support"].includes(role)) return { error: "Choose a role." };
    const login = await ensureLogin(email, full_name);
    const supabase = await createClient();
    const { error } = await supabase.from("staff").upsert({ user_id: login.id, full_name, email, role, active: true });
    if (error) return { error: error.message };
    revalidatePath("/staff");
    return { ok: login.password ? `${full_name} added. Temporary password (shown only now): ${login.password}` : `${full_name} added; they sign in with their existing KMR password.` };
  } catch (e) { return fail(e); }
}

export async function setStaffActive(form: FormData) {
  const me = await assertManager();
  if (me.role !== "owner") return;
  const id = String(form.get("user_id") ?? "");
  if (id === me.user_id) return;
  const supabase = await createClient();
  await supabase.from("staff").update({ active: form.get("active") === "1" }).eq("user_id", id);
  revalidatePath("/staff");
}

const toolSchema = z.object({
  customer_id: z.string().uuid(),
  product_code: z.string(),
  workspace: z.string().trim().min(2, "Workspace name is required").max(80),
  admin_name: z.string().trim().min(2, "Administrator's name is required").max(80),
  admin_email: z.string().trim().toLowerCase().email("Enter the administrator's email"),
  status: z.enum(["trial", "pilot", "active"]),
  valid_until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).transform((v) => v || null),
  seats: z.string().trim().optional().transform((v) => (v ? Number(v) : null)),
});

/** Switch on Sales Flow: one Sales Flow per customer (licence product_ref = the customer's id); access follows the customer's user list. */
async function enableSales(d: { product_code: string; customer_id: string; workspace: string; admin_name: string; admin_email: string; status: "trial" | "pilot" | "active"; valid_until: string | null; seats: number | null }): Promise<ActionState> {
  const supabase = await createClient();
  const { data: c } = await supabase.from("customers").select("id,status").eq("id", d.customer_id).single();
  if (!c) return { error: "Customer not found." };
  const login = await ensureLogin(d.admin_email, d.admin_name);
  // the administrator is a member (admin) of the customer first, so the licence trigger gives them the "sales" admin role
  const members = createAdminClient().schema("console").from("customer_members");
  const { error: mErr } = await members.upsert(
    { customer_id: c.id, email: d.admin_email, full_name: d.admin_name, is_admin: true, login_owned: !!login.password, created_by: "KMR Console" },
    { onConflict: "customer_id,email", ignoreDuplicates: true });
  if (mErr) return { error: `Could not add the administrator: ${mErr.message}` };
  const { error } = await supabase.from("licences").insert({
    customer_id: c.id, product_code: d.product_code, status: d.status, valid_until: d.valid_until, seats: d.seats,
    product_ref: c.id, product_slug: d.workspace,
  });
  if (error) return { error: /duplicate|unique/.test(error.message) ? "This customer already has this app." : error.message };
  if (c.status === "lead") await supabase.from("customers").update({ status: d.status === "active" ? "active" : "pilot" }).eq("id", c.id);
  revalidatePath(`/customers/${c.id}`);
  const url = `${env.platformUrl}/it/${({ calib: "calibration", apqp: "apqp", ppap: "ppap", rmp: "rmp", mmd: "mmd", mnt: "mnt" } as Record<string, string>)[d.product_code] ?? "sales"}.html`;
  return {
    ok: login.password
      ? `Switched on. Send the administrator: sign-in ${url} · email ${d.admin_email} · temporary password ${login.password} (shown only now). They add colleagues under Administration › Users & access.`
      : `Switched on. ${d.admin_email} already has a KMR login and signs in at ${url} with their existing password.`,
  };
}

/** Switch on Balloon Inspector or Process Documents: licence first, then the workspace and its administrator. */
export async function enableTool(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = toolSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const d = parsed.data;
    if (["sales", "calib", "apqp", "ppap", "rmp", "mmd", "mnt"].includes(d.product_code)) return await enableSales(d);   // company-level apps: one per customer, access follows the user list
    if (!isTool(d.product_code)) return { error: "Unknown product." };
    const supabase = await createClient();
    const { data: c } = await supabase.from("customers").select("id,status").eq("id", d.customer_id).single();
    if (!c) return { error: "Customer not found." };
    const workspaceId = randomUUID();
    const { error } = await supabase.from("licences").insert({
      customer_id: c.id, product_code: d.product_code, status: d.status, valid_until: d.valid_until, seats: d.seats,
      product_ref: workspaceId, product_slug: d.workspace,
    });
    if (error) return { error: /duplicate|unique/.test(error.message) ? "This customer already has this product." : error.message };
    let r: { password: string | null };
    try { r = await provisionWorkspace(d.product_code, workspaceId, d.workspace, d.admin_name, d.admin_email); }
    catch (e) { await supabase.from("licences").delete().eq("customer_id", c.id).eq("product_code", d.product_code); throw e; }
    if (c.status === "lead") await supabase.from("customers").update({ status: d.status === "active" ? "active" : "pilot" }).eq("id", c.id);
    revalidatePath(`/customers/${c.id}`);
    const url = `${env.platformUrl}/it/${({ balloon: "balloon", pd: "pd", capacity: "capacity" } as Record<string, string>)[d.product_code]}.html`;
    return {
      ok: r.password
        ? `Switched on. Send the administrator: sign-in ${url} · email ${d.admin_email} · temporary password ${r.password} (shown only now). They add their colleagues under Admin → Users.`
        : `Switched on. ${d.admin_email} already has a KMR login and signs in at ${url} with their existing password.`,
    };
  } catch (e) { return fail(e); }
}

// ---------------------------------------------------------------- Milestone 3: tickets and leads
export async function replyTicket(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const staff = await assertStaff();
    const id = String(form.get("id") ?? "");
    const body = String(form.get("body") ?? "").trim();
    const status = String(form.get("status") ?? "");
    const supabase = await createClient();
    if (body) {
      const { error } = await supabase.from("ticket_messages").insert({ ticket_id: id, author_kind: "kmr", author_name: staff.full_name, body: body.slice(0, 5000) });
      if (error) return { error: error.message };
    }
    if (["open", "in_progress", "waiting_on_customer", "resolved", "closed"].includes(status)) {
      await supabase.from("tickets").update({ status, updated_at: new Date().toISOString(), resolved_at: ["resolved", "closed"].includes(status) ? new Date().toISOString() : null }).eq("id", id);
    }
    const priority = String(form.get("priority") ?? "");
    if (["low", "normal", "high", "urgent"].includes(priority)) await supabase.from("tickets").update({ priority }).eq("id", id);
    const assignee = String(form.get("assigned_to") ?? "");
    if (assignee) await supabase.from("tickets").update({ assigned_to: assignee === "none" ? null : assignee }).eq("id", id);
    if (body) await mailTicketReply(id, body, status);
    revalidatePath(`/tickets/${id}`);
    return { ok: body ? "Reply sent — the customer sees it under Help & support." : "Ticket updated." };
  } catch (e) { return fail(e); }
}

export async function setLeadStatus(form: FormData) {
  await assertStaff();
  const status = String(form.get("status") ?? "");
  if (!["new", "contacted", "quoted", "converted", "dropped"].includes(status)) return;
  const supabase = await createClient();
  await supabase.from("leads").update({ status }).eq("id", String(form.get("id") ?? ""));
  revalidatePath("/leads");
}

/** Turn a pilot request into a Console customer (status lead) and open it */
export async function convertLead(form: FormData) {
  const staff = await assertStaff();
  const supabase = await createClient();
  const { data: l } = await supabase.from("leads").select("*").eq("id", String(form.get("id") ?? "")).single();
  if (!l) return;
  let customerId = l.customer_id as string | null;
  if (!customerId) {
    const country = /^[A-Z]{2}$/.test(String(l.country ?? "").toUpperCase()) ? String(l.country).toUpperCase() : "IN";
    const { data: c, error } = await supabase.from("customers").insert({
      name: l.company || l.name, country, currency: country === "IN" ? "INR" : "USD", contact_name: l.name, contact_email: l.email,
      contact_phone: l.phone, status: "lead", source: l.business === "software" ? "Website pilot request" : `Website enquiry (${l.business})`,
      notes: [l.products?.length ? `Interested in: ${l.products.join(", ")}` : "", l.product_name ? `Enquiry about: ${l.product_name}${l.quantity ? ` · qty ${l.quantity}` : ""}` : "", l.message ?? ""].filter(Boolean).join("\n"), created_by: staff.user_id,
    }).select("id").single();
    if (error || !c) return;
    customerId = c.id;
    await supabase.from("leads").update({ status: "converted", customer_id: customerId }).eq("id", l.id);
  }
  redirect(`/customers/${customerId}`);
}

// ---------------------------------------------------------------- customer portal: logo and link
export async function uploadCustomerLogo(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const id = String(form.get("id") ?? "");
    const file = form.get("logo");
    if (!(file instanceof File) || !file.size) return { error: "Choose a logo image (PNG, JPG, WebP or SVG)." };
    if (file.size > 5 * 1024 * 1024) return { error: "The logo must be under 5 MB. Save it smaller (e.g. 600×600 px) and try again." };
    const ext = ({ "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/svg+xml": "svg" } as Record<string, string>)[file.type];
    if (!ext) return { error: "Use a PNG, JPG, WebP or SVG image." };
    const db = createAdminClient();
    const path = `customers/${id}/logo-${Date.now()}.${ext}`;
    const { error } = await db.storage.from("kmr-public").upload(path, file, { contentType: file.type, upsert: true });
    if (error) return { error: `Upload failed: ${error.message}` };
    const url = db.storage.from("kmr-public").getPublicUrl(path).data.publicUrl;
    const supabase = await createClient();
    const { error: uErr } = await supabase.from("customers").update({ logo_url: url }).eq("id", id);
    if (uErr) return { error: uErr.message };
    revalidatePath(`/customers/${id}`);
    return { ok: "Logo saved. It appears on the customer's portal sign-in and header." };
  } catch (e) { return fail(e); }
}

export async function saveCustomerSlug(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const id = String(form.get("id") ?? "");
    const slug = String(form.get("slug") ?? "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9-]{1,60}$/.test(slug)) return { error: "Link name: lowercase letters, digits and dashes (2–60)." };
    const supabase = await createClient();
    const { error } = await supabase.from("customers").update({ slug }).eq("id", id);
    if (error) return { error: /unique|duplicate/.test(error.message) ? "That link name is already used by another customer." : error.message };
    revalidatePath(`/customers/${id}`);
    return { ok: "Portal link updated. Send the new link to the customer." };
  } catch (e) { return fail(e); }
}

// ---------------------------------------------------------------- data tools (sample data)
export async function loadConsoleSample(_: ActionState): Promise<ActionState> {
  try {
    await assertManager();
    const { data, error } = await createAdminClient().rpc("demo_load");
    if (error) return { error: error.message };
    revalidatePath("/", "layout");
    return { ok: `Sample data loaded: ${data} customers in 4 countries with licences, 2 support tickets and 2 pilot requests.` };
  } catch (e) { return fail(e); }
}
export async function flushConsoleSample(_: ActionState): Promise<ActionState> {
  try {
    await assertManager();
    const { data, error } = await createAdminClient().rpc("demo_flush");
    if (error) return { error: error.message };
    revalidatePath("/", "layout");
    return { ok: `Sample data removed (${data} sample customers with their licences, tickets and requests). Real customers are untouched.` };
  } catch (e) { return fail(e); }
}

/** Portal login for the customer's contact person: creates it (or resets its password) and shows a temporary password once. */
export async function portalLogin(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const id = String(form.get("id") ?? "");
    const reset = form.get("reset") === "1";
    const supabase = await createClient();
    const { data: c } = await supabase.from("customers").select("name,slug,contact_name,contact_email").eq("id", id).single();
    if (!c?.contact_email) return { error: "Add the customer's contact email in Company details first — that becomes their login." };
    const email = String(c.contact_email).toLowerCase();
    const login = await ensureLogin(email, c.contact_name || c.name);
    let password = login.password;
    if (!password && reset) {
      password = tempPassword();
      const { error } = await createAdminClient().auth.admin.updateUserById(login.id, { password });
      if (error) return { error: `Could not reset the password: ${error.message}` };
    }
    const url = `${env.platformUrl}/it/app/${c.slug}`;
    return password
      ? { ok: `Send to ${c.contact_name || email}: link ${url} · email ${email} · temporary password ${password} (shown only now — they can change it under "Change password" in the portal).` }
      : { ok: `${email} already has a KMR login; they sign in at ${url} with their existing password. Use "Reset password" if they don't know it.` };
  } catch (e) { return fail(e); }
}

// ---------------------------------------------------------------- KMR branding (KMR's own logo)
export async function saveKmrLogo(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const file = form.get("logo");
    if (!(file instanceof File) || !file.size) return { error: "Choose a logo image." };
    if (file.size > 5 * 1024 * 1024) return { error: "The logo must be under 5 MB." };
    const ext = ({ "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/svg+xml": "svg" } as Record<string, string>)[file.type];
    if (!ext) return { error: "Use a PNG, JPG, WebP or SVG image." };
    const db = createAdminClient();
    const path = `kmr/logo-${Date.now()}.${ext}`;
    const { error } = await db.storage.from("kmr-public").upload(path, file, { contentType: file.type, upsert: true });
    if (error) return { error: `Upload failed: ${error.message}` };
    const logo_url = db.storage.from("kmr-public").getPublicUrl(path).data.publicUrl;
    const { error: e2 } = await db.from("platform_settings").upsert({ key: "brand", value: { logo_url }, updated_at: new Date().toISOString() });
    if (e2) return { error: e2.message };
    revalidateTag("brand"); revalidatePath("/", "layout");
    return { ok: "KMR logo saved. It now shows on the Console sign-in, the main screen and the browser tab." };
  } catch (e) { return fail(e); }
}

/** Console: give the main contact and company administrators access in every tool of this customer */
export async function repairAccess(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const id = String(form.get("id") ?? "");
    const supabase = await createClient();
    const { error } = await supabase.schema("public").rpc("kmr_console_repair_access", { p_customer: id });
    if (error) return { error: error.message };
    revalidatePath(`/customers/${id}`);
    return { ok: "Access repaired: the main contact and company administrators now have access in every tool." };
  } catch (e) { return fail(e); }
}
