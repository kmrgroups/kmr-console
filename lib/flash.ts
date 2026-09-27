import "server-only";
import { cookies } from "next/headers";
import { COOKIE_PATH } from "@/lib/base-path";

export interface FlashMessage { ok?: string; error?: string; link?: string }
const NAME = "hrm_flash";

/**
 * One-time message shown at the top of the next page render. Used when an action
 * changes a record's status, so the panel holding the form disappears along with
 * its inline result (e.g. approve, send back, deactivate).
 */
export async function setFlash(msg: FlashMessage) {
  const jar = await cookies();
  jar.set(NAME, Buffer.from(JSON.stringify(msg)).toString("base64url"), {
    path: COOKIE_PATH, maxAge: 60, sameSite: "strict", httpOnly: true, secure: process.env.NODE_ENV === "production",
  });
}

export async function readFlash(): Promise<FlashMessage | null> {
  const raw = (await cookies()).get(NAME)?.value;
  if (!raw) return null;
  try {
    return JSON.parse(Buffer.from(raw, "base64url").toString()) as FlashMessage;
  } catch {
    return null;
  }
}
