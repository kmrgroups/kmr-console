import { NextResponse } from "next/server";
import { gunzipSync } from "node:zlib";
import { createAdminClient } from "@/lib/supabase/admin";
import { chunk, Tables } from "@/lib/erp-bridge/common";
import { buildInvoices } from "@/lib/erp-bridge/invoices";
import { buildProduction } from "@/lib/erp-bridge/production";
import { buildDcg } from "@/lib/erp-bridge/dcg";
import { buildCalibration } from "@/lib/erp-bridge/calib";
import { buildOpsMaster } from "@/lib/erp-bridge/opsmaster";
import { buildMasters } from "@/lib/erp-bridge/masters";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/** The universal ERP bridge posts raw ERP tables here (gzip JSON). Header x-sync-key = the plant's sync key (Sales Flow › Daily despatch › New key).
 *  Body: { kind: "invoices" | "production" | "purchase" | "opsmaster" | "calibration", unit: "Unit-2", dryRun?: boolean, tables: { name: { c: [...], r: [[...]] } } }.
 *  Every import function skips what is already loaded, so sending the same data again never duplicates it. See migration 0123. */
export async function POST(req: Request) {
  const key = req.headers.get("x-sync-key") || "";
  if (!key) return NextResponse.json({ ok: false, error: "sync key missing" }, { status: 401 });
  let body: { kind?: string; unit?: string; dryRun?: boolean; tables?: Tables; stage?: { id: string; n: number; of: number } };
  try {
    let buf = Buffer.from(await req.arrayBuffer());
    if (req.headers.get("x-body-gzip") === "1") buf = gunzipSync(buf);
    body = JSON.parse(buf.toString("utf8"));
  } catch { return NextResponse.json({ ok: false, error: "body must be JSON (gzip allowed)" }, { status: 400 }); }
  const kind = String(body.kind || ""), unit = String(body.unit || "").slice(0, 40) || "Unit", dry = !!body.dryRun; let t: Tables = body.tables || {};
  const db = createAdminClient().schema("public");
  const who = await db.rpc("kmr_bridge_whoami", { p_key: key });
  if (who.error) return NextResponse.json({ ok: false, error: who.error.code === "KM403" ? who.error.message : "could not check the key" }, { status: who.error.code === "KM403" ? 403 : 500 });

  // A big upload comes in small parts (one request is limited to about 4 MB): each part is kept until the last one arrives, then all are joined
  const st = body.stage;
  if (st && /^[A-Za-z0-9-]{8,64}$/.test(String(st.id)) && Number.isInteger(st.n) && Number.isInteger(st.of) && st.of >= 1 && st.of <= 200) {
    const bucket = "bridge-stage", dir = `${who.data?.slug || "plant"}/${st.id}`;
    const sb = createAdminClient();
    try {
      let up = await sb.storage.from(bucket).upload(`${dir}/${st.n}.json`, JSON.stringify(body.tables || {}), { contentType: "application/json", upsert: true });
      if (up.error && /not found|bucket/i.test(up.error.message)) { await sb.storage.createBucket(bucket, { public: false }); up = await sb.storage.from(bucket).upload(`${dir}/${st.n}.json`, JSON.stringify(body.tables || {}), { contentType: "application/json", upsert: true }); }
      if (up.error) throw new Error(up.error.message);
      if (st.n < st.of - 1) return NextResponse.json({ ok: true, part: st.n + 1, of: st.of });
      const joined: Tables = {};
      for (let i = 0; i < st.of; i++) {
        const f = await sb.storage.from(bucket).download(`${dir}/${i}.json`);
        if (f.error || !f.data) throw new Error(`part ${i + 1} of ${st.of} is missing - the bridge will send it again`);
        const part = JSON.parse(await f.data.text()) as Tables;
        for (const [name, tb] of Object.entries(part)) { if (!tb) continue; const j = joined[name]; if (!j) joined[name] = { c: tb.c, r: tb.r.slice() }; else for (const r of tb.r) j.r.push(r); }
      }
      await sb.storage.from(bucket).remove(Array.from({ length: st.of }, (_, i) => `${dir}/${i}.json`));
      t = joined;
    } catch (e) { return NextResponse.json({ ok: false, error: (e as Error).message.slice(0, 300) }, { status: 500 }); }
  }

  const run = async (fn: string, args: unknown, label: string, n: number) => {
    if (dry) return { dry: true };
    const r = await db.rpc("kmr_bridge_run", { p_key: key, p_fn: fn, p_args: args, p_kind: label, p_rows: n });
    if (r.error) throw new Error(label + ": " + r.error.message);
    return r.data;
  };
  const add = (a: Record<string, number>, d: unknown) => {
    if (typeof d === "number") { a.n = (a.n || 0) + d; return; }
    if (d && typeof d === "object") for (const [k, v] of Object.entries(d as Record<string, unknown>)) if (typeof v === "number") a[k] = (a[k] || 0) + v;
  };

  try {
    const out: Record<string, unknown> = { ok: true, kind, plant: who.data };
    if (kind === "ping") return NextResponse.json(out);
    if (kind === "invoices") {
      const inv = buildInvoices(t).invoices; const a: Record<string, number> = {};
      for (const c of chunk(inv, 200)) add(a, await run("kmr_inv_import", { invoices: c }, "invoices", c.length));
      Object.assign(out, { invoices: inv.length, result: a });
    } else if (kind === "production") {
      const h = buildProduction(t); const a: Record<string, number> = {};
      for (const c of chunk(h, 1000)) add(a, await run("kmr_mmd_hist_import", c, "production", c.length));
      Object.assign(out, { rows: h.length, result: a });
    } else if (kind === "purchase") {
      const d = buildDcg(t); const a: Record<string, number> = {};
      for (const c of chunk(d.pos, 150)) add(a, await run("kmr_dcg_import", { pos: c }, "purchase", c.length));
      for (const c of chunk(d.dcs, 150)) add(a, await run("kmr_dcg_import", { dcs: c }, "purchase", c.length));
      for (const c of chunk(d.grns, 150)) add(a, await run("kmr_dcg_import", { grns: c }, "purchase", c.length));
      const m = buildMasters(t); const b: Record<string, number> = {};
      for (const c of chunk(m, 200)) add(b, await run("kmr_ops_bulk", c, "masters", c.length));
      Object.assign(out, { pos: d.pos.length, dcs: d.dcs.length, grns: d.grns.length, masters: m.length, result: a, masters_result: b });
    } else if (kind === "opsmaster") {
      const m = buildOpsMaster(t, new Date().toISOString().slice(0, 10)); const a: Record<string, number> = {};
      for (const c of chunk(m, 200)) add(a, await run("kmr_ops_bulk", c, "opsmaster", c.length));
      const n: Record<string, number> = {}; for (const r of m) n[r.kind] = (n[r.kind] || 0) + 1;
      Object.assign(out, { masters: m.length, by_kind: n, result: a });
    } else if (kind === "calibration") {
      const g = buildCalibration(t, unit); const a: Record<string, number> = {};
      for (const c of chunk(g, 100)) add(a, await run("kmr_cal_import_erp", c, "calibration", c.length));
      Object.assign(out, { gauges: g.length, result: a });
    } else return NextResponse.json({ ok: false, error: "unknown kind" }, { status: 400 });
    return NextResponse.json(out);
  } catch (e) {
    return NextResponse.json({ ok: false, error: (e as Error).message.slice(0, 400) }, { status: 500 });
  }
}
