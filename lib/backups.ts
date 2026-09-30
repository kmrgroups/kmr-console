import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

// Nightly backups (kept 30 days) in the private bucket kmr-backups:
//   console/<date>.json — Console, billing and website data;  apps/<date>.json — the customers' app data
const B = "kmr-backups", DIR = "console", APPS = "apps", KEEP = 30;
export const today = () => new Date(Date.now() + 330 * 6e4).toISOString().slice(0, 10);   // India date

export async function exportConsole() {
  const { data, error } = await createAdminClient().rpc("console_export");
  if (error) throw new Error(`Export failed: ${error.message}`);
  return data as Record<string, unknown>;
}
export async function listBackups(): Promise<{ date: string; size: number }[]> {
  const { data } = await createAdminClient().storage.from(B).list(DIR, { limit: 60, sortBy: { column: "name", order: "desc" } });
  return (Array.isArray(data) ? data : []).filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f.name)).map((f) => ({ date: f.name.slice(0, 10), size: Number((f.metadata as { size?: number } | null)?.size ?? 0) }));
}
export async function saveBackup(date = today()) {
  const db = createAdminClient();
  const json = JSON.stringify(await exportConsole());
  const { error } = await db.storage.from(B).upload(`${DIR}/${date}.json`, new Blob([json], { type: "application/json" }), { upsert: true, contentType: "application/json" });
  if (error) throw new Error(error.message);
  const cutoff = new Date(Date.parse(date) - KEEP * 864e5).toISOString().slice(0, 10);
  const old = (await listBackups()).filter((b) => b.date < cutoff).map((b) => `${DIR}/${b.date}.json`);
  if (old.length) await db.storage.from(B).remove(old);
  return json.length + (await saveAppsBackup(date, cutoff));
}
/** Second file: Operations Master, Balloon Inspector, Process Documents and Capacity Planner data. */
async function saveAppsBackup(date: string, cutoff: string) {
  const db = createAdminClient();
  const { data, error } = await db.rpc("apps_export");
  if (error) throw new Error(`Apps export failed: ${error.message}`);
  const json = JSON.stringify(data);
  const up = await db.storage.from(B).upload(`${APPS}/${date}.json`, new Blob([json], { type: "application/json" }), { upsert: true, contentType: "application/json" });
  if (up.error) throw new Error(up.error.message);
  const { data: files } = await db.storage.from(B).list(APPS, { limit: 100, sortBy: { column: "name", order: "asc" } });
  const old = (Array.isArray(files) ? files : []).filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f.name) && f.name.slice(0, 10) < cutoff).map((f) => `${APPS}/${f.name}`);
  if (old.length) await db.storage.from(B).remove(old);
  return json.length;
}
export async function readBackup(date: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const { data } = await createAdminClient().storage.from(B).download(`${DIR}/${date}.json`);
  return data ?? null;
}
