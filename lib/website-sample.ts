import "server-only";
import { web } from "@/lib/cms-server";
import { SAMPLE_TABLES, sampleRows } from "@/lib/cms-sample";
import { env } from "@/lib/env";

/** Loads the website's sample content (every row marked sample = true). Returns the number of rows added. */
export async function loadWebsiteSample(): Promise<number> {
  const db = web(); const rows = sampleRows(env.platformUrl);
  const { count } = await db.from("hero_slides").select("id", { count: "exact", head: true }).eq("sample", true);
  if (count) throw new Error("Sample content is already loaded. Remove it first to load it again.");
  let n = 0;
  for (const t of SAMPLE_TABLES) {
    for (const r of rows[t] as Record<string, unknown>[]) {          // one at a time: each row sets only its own fields
      const { error } = await db.from(t).insert({ ...r, sample: true, is_active: true });
      if (error) throw new Error(`${t}: ${/column .*sample/.test(error.message) ? "run the website's supabase/add-cms-update.sql first" : error.message}`);
      n++;
    }
  }
  // photos only where there is none yet
  const { data: c } = await db.from("company_info").select("id,about_image_url,founder_photo_url").limit(1).maybeSingle();
  if (c) {
    const patch: Record<string, string> = {};
    if (!c.about_image_url) patch.about_image_url = rows.company.about_image_url;
    if (!c.founder_photo_url) patch.founder_photo_url = rows.company.founder_photo_url;
    if (Object.keys(patch).length) await db.from("company_info").update(patch).eq("id", c.id);
  }
  const { data: vs } = await db.from("verticals").select("id,slug,image_url");
  for (const v of vs ?? []) if (!v.image_url && v.slug && rows.verticals[v.slug]) await db.from("verticals").update({ image_url: rows.verticals[v.slug] }).eq("id", v.id);
  return n;
}

/** Removes exactly the sample rows and sample photos; your own content is never touched. */
export async function removeWebsiteSample(): Promise<{ removed: number; hidden: number }> {
  const db = web(); const site = `${env.platformUrl}/sample/`;
  let removed = 0, hidden = 0;
  for (const t of SAMPLE_TABLES) {
    const { data, error } = await db.from(t).delete().eq("sample", true).select("id");
    if (!error) { removed += data?.length ?? 0; continue; }
    // a sample product that already has an order cannot be deleted — hide it instead
    const { data: left } = await db.from(t).select("id").eq("sample", true);
    for (const r of left ?? []) {
      const { error: e2 } = await db.from(t).delete().eq("id", r.id);
      if (e2) { await db.from(t).update({ is_active: false }).eq("id", r.id); hidden++; } else removed++;
    }
  }
  const { data: c } = await db.from("company_info").select("id,about_image_url,founder_photo_url").limit(1).maybeSingle();
  if (c) {
    const patch: Record<string, null> = {};
    if (c.about_image_url?.startsWith(site)) patch.about_image_url = null;
    if (c.founder_photo_url?.startsWith(site)) patch.founder_photo_url = null;
    if (Object.keys(patch).length) await db.from("company_info").update(patch).eq("id", c.id);
  }
  await db.from("verticals").update({ image_url: null }).like("image_url", `${site}%`);
  return { removed, hidden };
}
