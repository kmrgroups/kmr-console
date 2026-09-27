// Lets the app run under a sub-path of another site, e.g. https://www.kmr-groups.com/it/hrm
// Set NEXT_PUBLIC_BASE_PATH=/it/hrm at build time. Empty = served from the root of its own domain.
//
// Next.js adds the base path automatically to redirect(), <Link> and middleware redirects.
// Plain <a href>, fetch() and cookie paths need it added by hand — use p() for those.

export const BASE_PATH = (process.env.NEXT_PUBLIC_BASE_PATH || "").replace(/\/+$/, "");

/** Prefix an app-relative path ("/app/employees") with the base path. */
export function p(path: string): string {
  if (!path.startsWith("/") || path.startsWith("//")) return path;
  return BASE_PATH + path;
}

/** Cookie path for this app: its own sub-path, so it never collides with the host site's cookies. */
export const COOKIE_PATH = BASE_PATH || "/";
