import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * Machine capture for the Material Movement app.
 * The gateway program (or any PLC / IoT box that can send JSON) POSTs with header x-device-key:
 *   { rows: [ { machine, at?, good_total?, rej_total?, good?, rej?, state?, alarm?, cycle_s? } ] }
 * GET with the same key (rows empty) returns which machine tags the gateway should read.
 */
function keyOf(req: Request) {
  return req.headers.get("x-device-key") || new URL(req.url).searchParams.get("key") || "";
}
async function run(req: Request, rows: unknown[]) {
  const key = keyOf(req);
  if (!key) return NextResponse.json({ ok: false, error: "gateway key missing" }, { status: 401 });
  const { data, error } = await createAdminClient().rpc("mmd_feed_ingest", { p_key: key, p_rows: rows.slice(0, 2000) });
  const d = data as { ok?: boolean } | null;
  if (error || !d || d.ok === false) return NextResponse.json({ ok: false, error: "gateway not recognised" }, { status: 403 });
  return NextResponse.json(d);
}
export async function POST(req: Request) {
  let body: unknown; try { body = await req.json(); } catch { return NextResponse.json({ ok: false, error: "body must be JSON" }, { status: 400 }); }
  const rows = Array.isArray(body) ? body : Array.isArray((body as { rows?: unknown })?.rows) ? (body as { rows: unknown[] }).rows : [];
  return run(req, rows);
}
export async function GET(req: Request) { return run(req, []); }
