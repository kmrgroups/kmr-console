import { NextResponse } from "next/server";
export const dynamic = "force-dynamic";
export async function POST() { return new NextResponse("OK", { headers: { "content-type": "text/plain" } }); }
export async function GET() { return new NextResponse("OK", { headers: { "content-type": "text/plain" } }); }
