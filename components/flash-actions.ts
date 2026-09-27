"use server";
import { cookies } from "next/headers";
import { COOKIE_PATH } from "@/lib/base-path";

/** Removes the one-time message once it has been shown. */
export async function clearFlash() {
  (await cookies()).delete({ name: "hrm_flash", path: COOKIE_PATH });
}
