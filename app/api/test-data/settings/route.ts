import { NextResponse } from "next/server";
import { requireStaff } from "@/lib/auth";
import { settingsJson } from "@/lib/test-data";

export const dynamic = "force-dynamic";
/** Download KMR's settings and website content as one JSON file (Console › Test data). Owner only. */
export async function GET() {
  const s = await requireStaff();
  if (s.role !== "owner") return NextResponse.json({ error: "Only the owner can download settings." }, { status: 403 });
  const data = await settingsJson();
  const day = new Date(Date.now() + 330 * 6e4).toISOString().slice(0, 10);
  return new NextResponse(JSON.stringify(data, null, 1), {
    headers: { "content-type": "application/json", "content-disposition": `attachment; filename="KMR-settings-${day}.json"`, "cache-control": "no-store" },
  });
}
