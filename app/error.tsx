"use client";
import { useEffect } from "react";

/**
 * Friendly error screen. After a new version is published, a page that was already open can no longer reach
 * the old version's server actions ("Failed to find Server Action") — that case reloads the page automatically.
 */
export default function ErrorScreen({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const stale = /server action|failed to fetch dynamically imported|loading chunk|ChunkLoadError/i.test(error?.message || "");
  useEffect(() => {
    if (stale && !sessionStorage.getItem("kmr-auto-reload")) { sessionStorage.setItem("kmr-auto-reload", "1"); location.reload(); }
    else sessionStorage.removeItem("kmr-auto-reload");
  }, [stale]);
  return (
    <div style={{ minHeight: "60vh", display: "grid", placeItems: "center", padding: 24 }}>
      <div className="card" style={{ maxWidth: 440, textAlign: "center" }}>
        <h2 style={{ justifyContent: "center" }}>{stale ? "Updating to the latest version…" : "Something went wrong"}</h2>
        <p className="muted">{stale ? "A newer version was just published. The page is reloading." : "Please try again. If it keeps happening, reload the page."}</p>
        <div className="row" style={{ justifyContent: "center", gap: 8 }}>
          <button className="btn" onClick={() => location.reload()}>Reload page</button>
          {!stale && <button className="btn secondary" onClick={() => reset()}>Try again</button>}
        </div>
        {error?.digest && <p className="muted" style={{ fontSize: 12, marginTop: 12 }}>Reference: {error.digest}</p>}
      </div>
    </div>
  );
}
