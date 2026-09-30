// Server errors are recorded in Console › System health; the first time an error appears (or again after an hour)
// an alert email goes to ALERT_EMAIL. Nothing here may throw.
export async function register() {}

export async function onRequestError(err: unknown, request: { path: string; method: string }, context: { routerKind: string; routePath: string; routeType: string }) {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;
  try {
    const e = err as Error & { digest?: string };
    if (/NEXT_REDIRECT|NEXT_NOT_FOUND|DYNAMIC_SERVER_USAGE/.test(`${e?.message} ${e?.digest}`)) return;
    const { reportError } = await import("./lib/errors");
    await reportError("console", `${request.method} ${request.path}`, e, `${context.routeType} ${context.routePath}`);
  } catch { /* never throw from error reporting */ }
}
