import "server-only";
import { unstable_cache } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";

/** KMR's own logo (Console → KMR branding); cached 5 minutes, refreshed on save */
export const platformBrand = unstable_cache(async (): Promise<{ logo_url?: string }> => {
  try {
    const { data } = await createAdminClient().from("platform_settings").select("value").eq("key", "brand").maybeSingle();
    return (data?.value as { logo_url?: string }) ?? {};
  } catch { return {}; }
}, ["kmr-platform-brand"], { revalidate: 300, tags: ["brand"] });
