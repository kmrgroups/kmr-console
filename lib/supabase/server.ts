import "server-only";
import { createServerClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { authCookieOptions } from "./cookie-options";
import { env } from "@/lib/env";

/** Client acting as the signed-in KMR staff member (row-level security applies), bound to the "console" schema. */
export async function createClient(): Promise<SupabaseClient> {
  const store = await cookies();
  return createServerClient(env.supabaseUrl, env.supabaseAnonKey, {
    cookieOptions: authCookieOptions,
    db: { schema: "console" },
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => { try { list.forEach(({ name, value, options }) => store.set(name, value, options)); } catch { /* server component */ } },
    },
  }) as unknown as SupabaseClient;
}
