"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager, assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { ensureLogin, provisionHrm } from "@/lib/provision";
import { env } from "@/lib/env";
import type { ActionState } from "@/lib/action-state";

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
    const { data, error } = await supabase.from("customers").insert({ ...parsed.data, created_by: staff.user_id }).select("id").single();
    if (error) return { error: error.message };
    id = data.id;
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
