import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

/** The website's tables (public schema). Used by the Console server only, after the staff member's role is checked. */
export const web = () => createAdminClient().schema("public");

export const MEDIA_BUCKET = "media";                                   // public: photos shown on the website
export const PRIVATE_BUCKETS = { records: "kmr-records", careers: "kmr-careers" } as const;
export const PRIVATE_PREFIX = "private:";                              // stored as private:<path> (records)

/** A short-lived link to a private file: compliance documents (private:<path>) or résumés (plain path in kmr-careers). */
export async function privateLink(value: string | null | undefined, bucket: "records" | "careers" = "records"): Promise<string | null> {
  if (!value) return null;
  if (/^https?:\/\//.test(value)) return value;                         // very old public links
  const path = value.startsWith(PRIVATE_PREFIX) ? value.slice(PRIVATE_PREFIX.length) : value;
  const { data } = await createAdminClient().storage.from(PRIVATE_BUCKETS[bucket]).createSignedUrl(path, 600);
  return data?.signedUrl ?? null;
}

export async function uploadFile(bucket: string, folder: string, file: File): Promise<string> {
  const ext = (file.name.split(".").pop() || "bin").toLowerCase().replace(/[^a-z0-9]/g, "");
  const path = `${folder}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const store = createAdminClient().storage.from(bucket);
  const { error } = await store.upload(path, file, { contentType: file.type || "application/octet-stream" });
  if (error) throw new Error(`Upload failed: ${error.message}`);
  return bucket === MEDIA_BUCKET ? store.getPublicUrl(path).data.publicUrl : PRIVATE_PREFIX + path;
}

export type GatewayStatus = { reachable: boolean; configured: boolean; mode?: "test" | "live"; key?: string; webhook?: boolean };
/** Asks the website whether its Razorpay keys are set (the keys live only in the website's server environment). */
export async function gatewayStatus(site: string): Promise<GatewayStatus> {
  try {
    const r = await fetch(`${site}/api/pay/status`, { cache: "no-store", signal: AbortSignal.timeout(4000) });
    if (!r.ok) return { reachable: false, configured: false };
    return { reachable: true, ...(await r.json()) };
  } catch { return { reachable: false, configured: false }; }
}
