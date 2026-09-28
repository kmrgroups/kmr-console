"use client";
// Last-resort screen when even the layout fails; stale-version errors reload once automatically.
export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
  if (typeof window !== "undefined" && /server action|chunk/i.test(error?.message || "") && !sessionStorage.getItem("kmr-auto-reload")) {
    sessionStorage.setItem("kmr-auto-reload", "1"); location.reload();
  }
  return (
    <html lang="en"><body style={{ fontFamily: "Segoe UI, Arial, sans-serif", display: "grid", placeItems: "center", minHeight: "100vh", margin: 0, background: "#f5f7fb" }}>
      <div style={{ textAlign: "center", padding: 24 }}>
        <h2>Something went wrong</h2>
        <p style={{ color: "#5e6b7e" }}>Please reload the page.</p>
        <button onClick={() => location.reload()} style={{ padding: "10px 20px", borderRadius: 10, border: 0, background: "#7c3aed", color: "#fff", fontWeight: 700, cursor: "pointer" }}>Reload page</button>
        {error?.digest && <p style={{ color: "#8a96a8", fontSize: 12 }}>Reference: {error.digest}</p>}
      </div>
    </body></html>
  );
}
