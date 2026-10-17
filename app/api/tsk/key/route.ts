import { NextResponse } from "next/server";

/** The public half of the alert key, so a browser can ask for alerts. Safe to publish; the private half never leaves the server. */
export const dynamic = "force-dynamic";
export async function GET() {
  return NextResponse.json({ key: process.env.VAPID_PUBLIC_KEY || null }, { headers: { "Cache-Control": "no-store" } });
}
