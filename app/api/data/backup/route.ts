import { NextResponse } from "next/server";
import { getStaff } from "@/lib/auth";
import { listBackups, readBackup } from "@/lib/backups";
export async function GET(req: Request) {
  const s = await getStaff();
  if (!s || (s.role !== "owner" && s.role !== "admin")) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const u = new URL(req.url);
  if (u.searchParams.get("latest")) return NextResponse.json({ date: (await listBackups())[0]?.date ?? null });
  const date = u.searchParams.get("date") ?? "", blob = await readBackup(date);
  if (!blob) return NextResponse.json({ error: "No backup for that date." }, { status: 404 });
  return new NextResponse(blob, { headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "Content-Disposition": `attachment; filename="kmr-console-backup-${date}.json"` } });
}
