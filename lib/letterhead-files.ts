import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import type { SignArt } from "@/lib/letterhead-pdf";

async function file(path: unknown): Promise<Uint8Array | null> {
  if (typeof path !== "string" || !path) return null;
  const { data } = await createAdminClient().storage.from("kmr-billing").download(path);
  return data ? new Uint8Array(await data.arrayBuffer()) : null;
}

/** the uploaded letterhead (Prices & invoices › Seller & letterhead), or null for the built-in one */
export async function letterheadBytes(): Promise<Uint8Array | null> {
  const { data } = await createAdminClient().from("billing_settings").select("letterhead_path").eq("id", true).maybeSingle();
  return file(data?.letterhead_path);
}

/** seal + signature for a document; issued invoices pass their frozen seller, which carries the paths they were issued with */
export async function signArt(seller: Record<string, unknown> | null | undefined): Promise<SignArt> {
  if (!seller || seller.show_seal === false) return {};
  const [seal, signature] = await Promise.all([file(seller.seal_path), file(seller.signature_path)]);
  return { seal, signature };
}

/** address of the letterhead image for on-screen documents: the uploaded one (short-lived link) or the built-in one */
export async function letterheadUrl(builtIn: string): Promise<string> {
  const { data } = await createAdminClient().from("billing_settings").select("letterhead_path").eq("id", true).maybeSingle();
  if (data?.letterhead_path) {
    const { data: u } = await createAdminClient().storage.from("kmr-billing").createSignedUrl(data.letterhead_path, 3600);
    if (u?.signedUrl) return u.signedUrl;
  }
  return builtIn;
}
