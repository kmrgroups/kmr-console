import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Staff } from "@/lib/auth";
import type { Resource } from "@/lib/manage";

/** The website's tables (public schema), used by the Console server only after the staff member's role is checked. */
export const web = () => createAdminClient().schema("public");

export const canEdit = (r: Resource, staff: Staff) => r.roles.includes(staff.role);

export const MEDIA_BUCKET = "media";            // public: product photos, banners, logos (shown on the website)
export const RECORDS_BUCKET = "kmr-records";    // private: compliance documents
export const PRIVATE_PREFIX = "private:";       // stored as private:<path> in document fields

/** A short-lived link to a private compliance document (older records may still hold a public URL). */
export async function documentLink(value: string | null | undefined): Promise<string | null> {
  if (!value) return null;
  if (!value.startsWith(PRIVATE_PREFIX)) return value;
  const { data } = await createAdminClient().storage.from(RECORDS_BUCKET).createSignedUrl(value.slice(PRIVATE_PREFIX.length), 600);
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
