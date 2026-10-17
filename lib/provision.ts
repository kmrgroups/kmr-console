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

const TOOL = {
  balloon: { orgs: "bi_orgs", members: "bi_members", settings: (_n: string) => ({ gen: "m", grid: "iso", cols: 8, rows: 6 }) },
  pd: { orgs: "pd_orgs", members: "pd_members", settings: (n: string) => ({ companyName: n }) },
  capacity: { orgs: "cp_orgs", members: "cp_members", settings: (_n: string) => ({}) },
} as const;
export type ToolCode = keyof typeof TOOL;
export const isTool = (c: string): c is ToolCode => c in TOOL;

/**
 * Creates a Balloon Inspector / Process Documents workspace with its first administrator.
 * The licence row must already exist with product_ref = workspaceId (so the tools' own
 * "new workspace = 30-day trial" rule does not add a second licence).
 */
export async function provisionWorkspace(product: ToolCode, workspaceId: string, name: string, adminName: string, adminEmail: string): Promise<{ password: string | null }> {
  const t = TOOL[product];
  const pub = createAdminClient().schema("public");
  const login = await ensureLogin(adminEmail, adminName);
  const { error } = await pub.from(t.orgs).insert({ id: workspaceId, name, settings: t.settings(name) });
  if (error) throw new Error(`Could not create the workspace: ${error.message}`);
  const member: Record<string, unknown> = { org_id: workspaceId, email: adminEmail.toLowerCase(), role: "admin" };
  if (product === "capacity") Object.assign(member, { display_name: adminName, created_by: "KMR Console", login_owned: !!login.password });
  const { error: mErr } = await pub.from(t.members).upsert(member);
  if (mErr) { await pub.from(t.orgs).delete().eq("id", workspaceId); throw new Error(`Could not add the administrator: ${mErr.message}`); }
  return { password: login.password };
}

/** Members and saved work in a tool workspace, for the Console's usage display */
export async function toolUsage(product: ToolCode, workspaceId: string): Promise<{ users: number; items: number }> {
  const pub = createAdminClient().schema("public");
  const [{ count: users }, { count: items }] = await Promise.all([
    pub.from(TOOL[product].members).select("org_id", { count: "exact", head: true }).eq("org_id", workspaceId),
    pub.from(product === "balloon" ? "bi_reports" : product === "pd" ? "pd_projects" : "cp_history").select("id", { count: "exact", head: true }).eq("org_id", workspaceId),
  ]);
  return { users: users ?? 0, items: items ?? 0 };
}
