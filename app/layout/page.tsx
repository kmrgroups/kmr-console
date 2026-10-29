import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { createAdminClient } from "@/lib/supabase/admin";
import { DEMO } from "@/lib/test-data";
import { env } from "@/lib/env";

export const metadata = { title: "Factory & Office Layout Studio — KMR Console" };
export const dynamic = "force-dynamic";

export default async function LayoutStudioPage() {
  const staff = await requireStaff();
  const a = createAdminClient();

  const { data: customers } = await a
    .from("customers")
    .select("id,name,slug,kind,status")
    .eq("status", "active")
    .order("name");

  const base = env.platformUrl || "https://www.kmr-groups.com";
  const demoUrl = `${base}/it/layout.html?kmr=1&co=${DEMO.slug}&demo=1`;
  const sampleUrl = `${base}/it/layout.html?demo=1`;

  return (
    <AppShell staff={staff} active="/layout">
      <div className="pagehead">
        <div>
          <h1>Factory &amp; Office Layout Studio</h1>
          <p>
            1:1 metric scale layout generator for manufacturing floors and corporate offices.
            Upload CAD files (DXF/DWG), civil PDFs, or JPEG architectural blueprints, convert traditional machine lines into Lean Cellular units, and generate 1:1 scale layout options with AutoCAD DXF export.
          </p>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <a href={demoUrl} target="_blank" rel="noopener" className="btn">
            Open Layout Studio
          </a>
          <a href={sampleUrl} target="_blank" rel="noopener" className="btn secondary">
            Quick Sample (No Sign-in)
          </a>
        </div>
      </div>

      <div className="grid two" style={{ marginBottom: 20 }}>
        <div className="card">
          <h2>Core Capabilities</h2>
          <ul style={{ margin: "10px 0 0 18px", lineHeight: 1.7, color: "var(--ink,#16233a)" }}>
            <li><b>1:1 Metric True Scale Engine:</b> Exact 1.0m = 40px rendering of Plot 51 Kiadb Bommasandra envelope (20m × 30m, 600 m²).</li>
            <li><b>Line-to-Cellular Transformation:</b> Converts 62 CNC, VMC, MSA, and Conventional machines from linear bottlenecks to dual U-cells and flow workcenters.</li>
            <li><b>Office Ergonomic Generator:</b> Automatic generation of cubicles, executive cabins, conference suites, and ADA-compliant corridors.</li>
            <li><b>Lean Factory KPIs:</b> Instant scoring of material travel distance, WIP reduction %, floor utilization %, and safety aisle clearances.</li>
            <li><b>Direct CAD Export:</b> One-click AutoCAD DXF export with layers (<code>WALLS</code>, <code>MACHINES</code>, <code>AISLES</code>, <code>ZONES</code>, <code>ANNOTATIONS</code>) and KMR CAD linkage.</li>
          </ul>
        </div>

        <div className="card">
          <h2>Launch by Customer Workspace</h2>
          <p className="muted">Select any active company to open their layout projects with live multi-tenant RLS security:</p>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", maxHeight: 220, overflowY: "auto", padding: "4px 0" }}>
            <a href={demoUrl} target="_blank" rel="noopener" className="badge ok" style={{ padding: "8px 12px", textDecoration: "none" }}>
              ★ KMR Demo Workspace ({DEMO.slug})
            </a>
            {(customers ?? []).map((c) => (
              <a
                key={c.id}
                href={`${base}/it/layout.html?kmr=1&co=${c.slug}`}
                target="_blank"
                rel="noopener"
                className="badge"
                style={{ padding: "6px 10px", textDecoration: "none", background: "var(--bg,#f5f7fb)", color: "var(--ink,#16233a)", border: "1px solid var(--line,#e3e8ef)" }}
              >
                {c.name}
              </a>
            ))}
          </div>
        </div>
      </div>

      <div className="card" style={{ padding: 0, overflow: "hidden", minHeight: 680, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "14px 20px", background: "#0e1726", color: "#fff", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <b style={{ fontSize: 15, letterSpacing: "0.03em" }}>Interactive 1:1 Scale Studio Preview</b>
            <span className="muted" style={{ marginLeft: 12, fontSize: 13, color: "#94a3b8" }}>Embedded live instance — Plot 51 Bommasandra 62-Machine Cellular Layout</span>
          </div>
          <a href={demoUrl} target="_blank" rel="noopener" style={{ color: "#38bdf8", fontSize: 13, textDecoration: "none", fontWeight: 600 }}>
            Open Full Screen ↗
          </a>
        </div>
        <iframe
          src={`${base}/it/layout.html?demo=1`}
          style={{ width: "100%", height: "760px", border: "none", background: "#0b1020" }}
          title="KMR Factory & Office Layout Studio"
        />
      </div>
    </AppShell>
  );
}
