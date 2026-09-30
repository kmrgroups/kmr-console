import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

/** Short-lived links to the private seal / signature images (only after the page decided to show them). */
export async function billingImageUrls(seller: Record<string, unknown> | null | undefined): Promise<{ seal: string | null; signature: string | null }> {
  if (!seller || seller.show_seal === false) return { seal: null, signature: null };
  const paths = [seller.seal_path, seller.signature_path].map((x) => (typeof x === "string" && x ? x : null));
  const store = createAdminClient().storage.from("kmr-billing");
  const [seal, signature] = await Promise.all(paths.map(async (path) => {
    if (!path) return null;
    const { data } = await store.createSignedUrl(path, 3600);
    return data?.signedUrl ?? null;
  }));
  return { seal, signature };
}
