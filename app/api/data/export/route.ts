import { NextResponse } from "next/server";
import { getStaff } from "@/lib/auth";
import { exportConsole, today } from "@/lib/backups";
export async function GET() {
  const s = await getStaff();
  if (!s || (s.role !== "owner" && s.role !== "admin")) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  return new NextResponse(JSON.stringify(await exportConsole(), null, 1), { headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "Content-Disposition": `attachment; filename="kmr-console-${today()}.json"` } });
}
