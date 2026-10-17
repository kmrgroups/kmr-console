import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { admsOptions, parseAttLog } from "@/lib/hrms-punch";

export const dynamic = "force-dynamic";
const text = (s: string, status = 200) => new NextResponse(s, { status, headers: { "content-type": "text/plain" } });

/** Machine asks for its settings (and says hello). Unknown machines still get a normal answer; their punches are simply refused later. */
export async function GET(req: Request) {
  const sn = new URL(req.url).searchParams.get("SN") || "";
  if (!sn) return text("ERROR", 400);
  await createAdminClient().rpc("hrms_ingest", { p_mode: "serial", p_id: sn, p_rows: [] });
  return text(admsOptions(sn));
}

/** Machine pushes attendance lines (table=ATTLOG). Other tables (user data, photos) are acknowledged and ignored. */
export async function POST(req: Request) {
  const u = new URL(req.url); const sn = u.searchParams.get("SN") || ""; const table = (u.searchParams.get("table") || "").toUpperCase();
  if (!sn) return text("ERROR", 400);
  const body = await req.text();
  if (table !== "ATTLOG") return text("OK");
  const { punches } = parseAttLog(body);
  if (!punches.length) return text("OK: 0");
  const { data, error } = await createAdminClient().rpc("hrms_ingest", { p_mode: "serial", p_id: sn, p_rows: punches });
  // a failure is answered with an error so the machine keeps the records and sends them again later
  if ((data as { ok?: boolean } | null)?.ok === false) return text("ERROR", 403);
  return error ? text("ERROR", 500) : text(`OK: ${punches.length}`);
}
