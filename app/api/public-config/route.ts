import { NextResponse } from "next/server";
import { env } from "@/lib/env";

/** Public (browser-safe) Supabase settings for the KMR app pages (/it/*.html). The anon / publishable key is public by design; never expose the service key here. */
export async function GET() {
  return NextResponse.json({ url: env.supabaseUrl, key: env.supabaseAnonKey }, { headers: { "Cache-Control": "public, max-age=300" } });
}
