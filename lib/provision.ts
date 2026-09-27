import "server-only";
import { randomBytes } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";

/** Temporary password shown once to KMR staff, e.g. "k7Qm-4Rt9-Xw2p" */
export function tempPassword(): string {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const b = randomBytes(12);
  const s = Array.from(b, (x) => a[x % a.length]).join("");
  return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
}

/** Finds an existing login by email, or creates one. Returns the user id and a temporary password when newly created. */
export async function ensureLogin(email: string, fullName: string): Promise<{ id: string; password: string | null }> {
  const db = createAdminClient();
  const { data: existing } = await db.rpc("user_id_by_email", { p_email: email });
  if (existing) return { id: existing as string, password: null };
  const password = tempPassword();
  const { data, error } = await db.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName } });
  if (error || !data.user) throw new Error(`Could not create the login: ${error?.message ?? "unknown error"}`);
  return { id: data.user.id, password };
}

export interface HrmSetup {
  customerName: string; legalName: string | null; slug: string; prefix: string;
  adminName: string; adminEmail: string; phone: string | null; email: string | null; address: string | null;
}

/**
 * Creates the customer's company inside the HRM (schema "hrm"): the company, its default departments,
 * designations, shifts and leave types, and its first administrator login. Returns the HRM company id.
 */
export async function provisionHrm(s: HrmSetup): Promise<{ tenantId: string; password: string | null; existingLogin: boolean }> {
  const db = createAdminClient();
  const hrm = db.schema("hrm");
  const { data: taken } = await hrm.from("tenants").select("id").eq("slug", s.slug).maybeSingle();
  if (taken) throw new Error(`The short name "${s.slug}" is already used by another company in the HRM. Choose another.`);

  const login = await ensureLogin(s.adminEmail, s.adminName);
  const { data: already } = await hrm.from("app_users").select("tenant_id").eq("id", login.id).maybeSingle();
  if (already) throw new Error(`${s.adminEmail} is already an HRM user of another company. Use a different email for this company's administrator.`);

  const { data: tenant, error } = await hrm.from("tenants").insert({
    slug: s.slug, name: s.customerName, legal_name: s.legalName, emp_code_prefix: s.prefix,
    phone: s.phone, email: s.email, address: s.address,
  }).select("id").single();
  if (error || !tenant) throw new Error(`Could not create the company in the HRM: ${error?.message}`);

  const rollback = async () => { await hrm.from("tenants").delete().eq("id", tenant.id); };
  const seed = await hrm.rpc("seed_tenant_defaults", { p_tenant: tenant.id });
  if (seed.error) { await rollback(); throw new Error(`Could not add default settings: ${seed.error.message}`); }
  const { error: uErr } = await hrm.from("app_users").insert({
    id: login.id, tenant_id: tenant.id, role: "company_admin", full_name: s.adminName, email: s.adminEmail,
    must_change_password: !!login.password,
  });
  if (uErr) { await rollback(); throw new Error(`Could not create the administrator: ${uErr.message}`); }
  return { tenantId: tenant.id, password: login.password, existingLogin: !login.password };
}
