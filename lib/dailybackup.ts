import "server-only";
import { zipSync, strToU8 } from "fflate";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendMail, type Brand } from "@/lib/mail";
import { today } from "@/lib/backups";

/**
 * Daily backup of every company / plant: all app data, settings and masters, one zip per app, kept in the private bucket
 *   kmr-backups/customers/<slug>/<date>/<app>.zip  (+ _manifest.json), then one mail to the people chosen for that plant.
 * Runs in several passes through the night (each pass has a time budget); a finished company is skipped by the next pass.
 */
const B = "kmr-backups", PAGE = 4000, LINK_SECS = 7 * 86400;
type Scan = { customer_id: string; slug: string; name: string; brand: Brand | null; enabled: boolean; recipients: string; keep_days: number };
type Plan = { app: string; tables: { t: string; rows: number }[] }[];
type Item = { app: string; rows: number; bytes: number; file: string };
type Manifest = { date: string; items: Item[]; complete: boolean; mailed: boolean; issues: string[] };
const NAMES: Record<string, string> = { settings: "Settings, users and masters", pnl: "Profit & Loss", hrm: "HRM", mmd: "Machine maintenance", sf: "Sales Flow", rmp: "Raw material planning", cal: "Calibration Hub" };
const label = (a: string) => NAMES[a] || a.toUpperCase();
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const mb = (n: number) => (n / 1048576).toFixed(n > 1048576 * 10 ? 0 : 1) + " MB";

async function readManifest(path: string, date: string): Promise<Manifest> {
  const { data } = await createAdminClient().storage.from(B).download(path);
  if (data) { try { const m = JSON.parse(await data.text()) as Manifest; if (m.date === date) return m; } catch { /* start again */ } }
  return { date, items: [], complete: false, mailed: false, issues: [] };
}
const saveManifest = (path: string, m: Manifest) => createAdminClient().storage.from(B).upload(path, new Blob([JSON.stringify(m)], { type: "application/json" }), { upsert: true, contentType: "application/json" });

async function backupApp(cid: string, dir: string, app: string, tables: Plan[number]["tables"]): Promise<Item> {
  const db = createAdminClient(); const files: Record<string, Uint8Array> = {}; let rows = 0;
  for (const t of tables) {
    const parts: string[] = [];
    for (let off = 0; off < t.rows; off += PAGE) {
      const { data, error } = await db.schema("public").rpc("kmr_bk_page", { p_cid: cid, p_app: app, p_table: t.t, p_offset: off, p_limit: PAGE });
      if (error) throw new Error(`${label(app)} › ${t.t}: ${error.message}`);
      const arr = Array.isArray(data) ? data : []; if (!arr.length) break;
      rows += arr.length; parts.push(arr.map((r) => JSON.stringify(r)).join("\n"));
    }
    files[`${t.t}.jsonl`] = strToU8(parts.join("\n"));
  }
  const zip = zipSync(files, { level: 6 });
  const file = `${dir}/${app}.zip`;
  const up = await db.storage.from(B).upload(file, new Blob([zip as BlobPart], { type: "application/zip" }), { upsert: true, contentType: "application/zip" });
  if (up.error) throw new Error(`${label(app)}: ${up.error.message}`);
  return { app, rows, bytes: zip.length, file };
}

async function prune(slug: string, keep: number, date: string) {
  const db = createAdminClient(); const cutoff = new Date(Date.parse(date) - keep * 864e5).toISOString().slice(0, 10);
  const { data } = await db.storage.from(B).list(`customers/${slug}`, { limit: 400 });
  for (const f of (Array.isArray(data) ? data : []).filter((x) => /^\d{4}-\d{2}-\d{2}$/.test(x.name) && x.name < cutoff)) {
    const { data: inner } = await db.storage.from(B).list(`customers/${slug}/${f.name}`, { limit: 200 });
    const paths = (Array.isArray(inner) ? inner : []).map((x) => `customers/${slug}/${f.name}/${x.name}`);
    if (paths.length) await db.storage.from(B).remove(paths);
  }
}

async function mailIt(c: Scan, m: Manifest, date: string, dir: string) {
  const db = createAdminClient(); const to = c.recipients.split(/[,;\s]+/).filter((e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e));
  if (!to.length) return 0;
  const links: Record<string, string> = {};
  for (const i of m.items) { const { data } = await db.storage.from(B).createSignedUrl(i.file, LINK_SECS, { download: `${c.slug}-${date}-${i.app}.zip` }); if (data?.signedUrl) links[i.app] = data.signedUrl; }
  const th = "padding:8px 10px;border-bottom:1px solid #eee;text-align:left;font-size:13px", total = m.items.reduce((a, i) => a + i.rows, 0);
  const html = `<table style="width:100%;border-collapse:collapse;margin:14px 0"><tr style="background:#f4f1ea"><th style="${th}">Data</th><th style="${th};text-align:right">Records</th><th style="${th};text-align:right">Size</th><th style="${th}">Download</th></tr>${
    m.items.map((i) => `<tr><td style="${th}">${esc(label(i.app))}</td><td style="${th};text-align:right">${i.rows.toLocaleString("en-IN")}</td><td style="${th};text-align:right">${mb(i.bytes)}</td><td style="${th}">${links[i.app] ? `<a href="${esc(links[i.app])}">Download</a>` : "—"}</td></tr>`).join("")}</table>`;
  const ok = m.complete && !m.issues.length, plant = c.brand?.plant || c.name;
  let sent = 0;
  for (const e of to) {
    const r = await sendMail({ to: e, kind: "daily_backup", ref: `${c.slug}-${date}`, brand: c.brand ?? { name: c.name }, customerId: c.customer_id,
      subject: `${ok ? "Daily backup completed" : "Daily backup — please check"} · ${plant} · ${date}`, heading: ok ? "Your daily data backup is complete" : "Your daily data backup needs attention",
      paragraphs: [`Backup date: ${date}. All app data, settings and masters of ${plant} were saved (${total.toLocaleString("en-IN")} records in ${m.items.length} groups). Each file is a zip with one data file per table. The download links work for 7 days; older backups stay in the KMR Console.`, ...m.issues.slice(0, 5)],
      html, refNo: `KMR-BKP-${c.slug.slice(-5).toUpperCase()}-${date.replace(/-/g, "")}`, revision: "Backup report format BKP-01 · Rev 00" });
    if (r === "sent") sent++;
  }
  return sent;
}

/** One pass: works through the companies until the time budget is used. Returns what is still open (for the failure alert). */
export async function runDailyBackup(budgetMs: number) {
  const t0 = Date.now(), db = createAdminClient(), date = today(), open: string[] = [], done: string[] = [];
  const { data: scan, error } = await db.schema("public").rpc("kmr_bk_scan");
  if (error) throw new Error(`Company list failed: ${error.message}`);
  for (const c of (scan as Scan[]) ?? []) {
    if (!c.enabled) continue;
    const dir = `customers/${c.slug}/${date}`, mp = `${dir}/_manifest.json`;
    const m = await readManifest(mp, date);
    if (m.complete && m.mailed) { done.push(c.slug); continue; }
    try {
      if (!m.complete) {
        const { data: plan, error: pe } = await db.schema("public").rpc("kmr_bk_plan", { p_cid: c.customer_id });
        if (pe) throw new Error(`Plan: ${pe.message}`);
        const have = new Set(m.items.map((i) => i.app)); m.issues = [];
        for (const g of (plan as Plan) ?? []) {
          if (have.has(g.app)) continue;
          if (Date.now() - t0 > budgetMs) break;
          try { m.items.push(await backupApp(c.customer_id, dir, g.app, g.tables)); await saveManifest(mp, m); }
          catch (e) { m.issues.push((e as Error).message); }
        }
        const need = ((plan as Plan) ?? []).map((g) => g.app);
        m.complete = need.every((a) => m.items.some((i) => i.app === a));
        await saveManifest(mp, m);
      }
      if (m.complete) {
        await mailIt(c, m, date, dir); m.mailed = true; await saveManifest(mp, m);
        await db.schema("public").rpc("kmr_bk_mark", { p_cid: c.customer_id, p_status: m.issues.length ? "issues" : "ok", p_detail: { date, groups: m.items.length, records: m.items.reduce((a, i) => a + i.rows, 0), bytes: m.items.reduce((a, i) => a + i.bytes, 0), issues: m.issues } });
        await prune(c.slug, c.keep_days, date); done.push(c.slug);
      } else open.push(`${c.name}${m.issues.length ? ` (${m.issues[0]})` : ""}`);
    } catch (e) { open.push(`${c.name}: ${(e as Error).message}`); }
    if (Date.now() - t0 > budgetMs) { for (const x of ((scan as Scan[]) ?? [])) if (x.enabled && !done.includes(x.slug) && !open.some((o) => o.startsWith(x.name))) open.push(x.name); break; }
  }
  return { date, done, open };
}
