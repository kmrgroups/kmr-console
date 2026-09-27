import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";

/**
 * Service-role client (bypasses row-level security). Used only after the caller is checked to be KMR staff,
 * to set up a customer's company inside a product. Use .schema("hrm") etc. for product schemas.
 */
export function createAdminClient(): SupabaseClient {
  return createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "console" },
  }) as unknown as SupabaseClient;
}
