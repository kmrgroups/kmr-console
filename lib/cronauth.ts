import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

/**
 * Who may start a scheduled job: Vercel's own scheduler (Authorization: Bearer CRON_SECRET) or the database's exact-time
 * scheduler (header x-kmr-trigger, checked against the private key kept in the database).
 * Returns null when allowed, otherwise the error answer to send back.
 */
export async function cronDenied(req: Request): Promise<{ error: string; status: number } | null> {
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get("authorization") === `Bearer ${secret}`) return null;
  const k = req.headers.get("x-kmr-trigger");
  if (k && k.length >= 32) {
    const { data } = await createAdminClient().schema("public").rpc("kmr_trigger_ok", { p: k });
    if (data === true) return null;
  }
  return secret ? { error: "unauthorized", status: 401 } : { error: "CRON_SECRET is not set", status: 503 };
}
