import { COOKIE_PATH } from "@/lib/base-path";
/** The Console keeps its own login cookie on its own path, separate from the website and the products. */
export const authCookieOptions = { name: "kmr-console-auth", path: COOKIE_PATH, sameSite: "lax" as const, secure: process.env.NODE_ENV === "production" };
