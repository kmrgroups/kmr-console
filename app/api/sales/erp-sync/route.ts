import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** The ERP sync program at a plant posts its invoices here. Header x-sync-key = the key from Sales Flow › Daily despatch.
 *  Body: { from: "YYYY-MM-DD", rows: [...] | null, dryRun?: boolean, force?: boolean }. See migration 0097. */
export async function POST(req: Request) {
  const key = req.headers.get("x-sync-key") || "";
  if (!key) return NextResponse.json({ ok: false, error: "sync key missing" }, { status: 401 });
  let body: { from?: string; rows?: unknown[] | null; dryRun?: boolean; force?: boolean };
  try { body = await req.json(); } catch { return NextResponse.json({ ok: false, error: "body must be JSON" }, { status: 400 }); }
  const { data, error } = await createAdminClient().schema("public").rpc("kmr_sf_erp_ingest", {
    p_key: key, p_from: body.from ?? null, p_rows: body.rows ?? null, p_dry: !!body.dryRun, p_force: !!body.force,
  });
  if (error) {
    const status = error.code === "KM403" ? 403 : error.code === "KM409" ? 409 : error.code === "KM400" ? 400 : 500;
    return NextResponse.json({ ok: false, error: status === 500 ? "could not save" : error.message }, { status });
  }
  return NextResponse.json(data);
}
