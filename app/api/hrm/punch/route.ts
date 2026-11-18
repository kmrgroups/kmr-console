import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { parseJsonPunches } from "@/lib/hrms-punch";

export const dynamic = "force-dynamic";

/** Any machine or bridge program that can send JSON: POST with header x-device-key (the key shown on the Machines screen). */
export async function POST(req: Request) {
  const key = req.headers.get("x-device-key") || new URL(req.url).searchParams.get("key") || "";
  if (!key) return NextResponse.json({ ok: false, error: "device key missing" }, { status: 401 });
  let body: unknown; try { body = await req.json(); } catch { return NextResponse.json({ ok: false, error: "body must be JSON" }, { status: 400 }); }
  const rows = parseJsonPunches(body);
  // names enrolled on the machine: { users: [{ bio_id, name }] } - fills "New employee …" records
  const users = (body as { users?: unknown } | null)?.users;
  let names: unknown = null;
  if (Array.isArray(users) && users.length) {
    const r = await createAdminClient().rpc("hrms_ingest_users", { p_mode: "key", p_id: key, p_users: users.slice(0, 5000) });
    if (r.error || (r.data as { ok?: boolean } | null)?.ok === false) return NextResponse.json({ ok: false, error: "device not recognised" }, { status: 403 });
    names = r.data;
    if (!rows.length) return NextResponse.json({ ok: true, result: names });
  }
  const { data, error } = await createAdminClient().rpc("hrms_ingest", { p_mode: "key", p_id: key, p_rows: rows });
  if (error || (data as { ok?: boolean } | null)?.ok === false) return NextResponse.json({ ok: false, error: "device not recognised" }, { status: 403 });
  return NextResponse.json({ ok: true, result: names ? { ...(data as object), names } : data });
}
