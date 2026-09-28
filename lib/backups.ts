import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

// Console nightly backups (kept 7 days) in the private bucket kmr-backups/console/<date>.json
const B = "kmr-backups", DIR = "console", KEEP = 7;
export const today = () => new Date(Date.now() + 330 * 6e4).toISOString().slice(0, 10);   // India date

export async function exportConsole() {
  const { data, error } = await createAdminClient().rpc("console_export");
  if (error) throw new Error(`Export failed: ${error.message}`);
  return data as Record<string, unknown>;
}
export async function listBackups(): Promise<{ date: string; size: number }[]> {
  const { data } = await createAdminClient().storage.from(B).list(DIR, { limit: 60, sortBy: { column: "name", order: "desc" } });
  return (data ?? []).filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f.name)).map((f) => ({ date: f.name.slice(0, 10), size: Number((f.metadata as { size?: number } | null)?.size ?? 0) }));
}
export async function saveBackup(date = today()) {
  const db = createAdminClient();
  const json = JSON.stringify(await exportConsole());
  const { error } = await db.storage.from(B).upload(`${DIR}/${date}.json`, new Blob([json], { type: "application/json" }), { upsert: true, contentType: "application/json" });
  if (error) throw new Error(error.message);
  const cutoff = new Date(Date.parse(date) - KEEP * 864e5).toISOString().slice(0, 10);
  const old = (await listBackups()).filter((b) => b.date < cutoff).map((b) => `${DIR}/${b.date}.json`);
  if (old.length) await db.storage.from(B).remove(old);
  return json.length;
}
export async function readBackup(date: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const { data } = await createAdminClient().storage.from(B).download(`${DIR}/${date}.json`);
  return data ?? null;
}
