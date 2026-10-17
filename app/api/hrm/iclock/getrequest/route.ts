import { NextResponse } from "next/server";
export const dynamic = "force-dynamic";
/** Machine asks whether there is a command for it. There never is: the app only receives. */
export async function GET() { return new NextResponse("OK", { headers: { "content-type": "text/plain" } }); }
