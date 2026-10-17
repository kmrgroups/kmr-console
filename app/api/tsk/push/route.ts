import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";
import { deliverPending } from "@/lib/tsk-push";

/** ActionTrack calls this right after a task is given, commented or changed, so the alert reaches the phone straight away.
 *  The caller must be signed in (their access token); the work itself only sends alerts that are already waiting. */
export const dynamic = "force-dynamic";
export const maxDuration = 30;
export async function POST(req: Request) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ ok: false }, { status: 401 });
  const { data, error } = await createClient(env.supabaseUrl, env.supabaseAnonKey, { auth: { persistSession: false } }).auth.getUser(token);
  if (error || !data.user) return NextResponse.json({ ok: false }, { status: 401 });
  try { return NextResponse.json({ ok: true, ...(await deliverPending(100)) }); }
  catch (e) { return NextResponse.json({ ok: false, error: (e as Error).message }, { status: 500 }); }
}
