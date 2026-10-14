import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type StaffRole = "owner" | "admin" | "sales" | "support";
export interface Staff { user_id: string; full_name: string; email: string; role: StaffRole }
export const ROLE_LABELS: Record<StaffRole, string> = { owner: "Owner", admin: "Administrator", sales: "Sales", support: "Support" };

/** The signed-in KMR staff member, or null (anyone else — customers, website editors — gets nothing here). */
export const getStaff = cache(async (): Promise<Staff | null> => {
  const supabase = await createClient();
  // The sign-in was already verified by the middleware for this request; read it from the token locally instead of another round trip to Supabase
  let uid: string | null = null;
  try { const { data } = await supabase.auth.getClaims(); uid = (data?.claims?.sub as string | undefined) ?? null; } catch { /* fall back below */ }
  if (!uid) { const { data: { user } } = await supabase.auth.getUser(); uid = user?.id ?? null; }
  if (!uid) return null;
  const { data } = await supabase.from("staff").select("user_id,full_name,email,role,active").eq("user_id", uid).maybeSingle();
  return data && data.active ? (data as Staff) : null;
});

export async function requireStaff(): Promise<Staff> {
  const s = await getStaff();
  if (!s) redirect("/login");
  return s;
}

/** For server actions: owners and administrators manage licences, products and staff. */
export async function assertManager(): Promise<Staff> {
  const s = await getStaff();
  if (!s) throw new Error("Please sign in again.");
  if (s.role !== "owner" && s.role !== "admin") throw new Error("Only an owner or administrator can do this.");
  return s;
}
export async function assertStaff(): Promise<Staff> {
  const s = await getStaff();
  if (!s) throw new Error("Please sign in again.");
  return s;
}
export const isManager = (s: Staff) => s.role === "owner" || s.role === "admin";
