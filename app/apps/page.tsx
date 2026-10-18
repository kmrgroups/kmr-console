import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { DEMO } from "@/lib/test-data";
import { env } from "@/lib/env";
import { reloadDemoApps } from "./actions";

export const metadata = { title: "KMR Apps" };
export const dynamic = "force-dynamic";

type Prod = { code: string; name: string; description: string | null; app_path: string | null; current_version: string | null; active: boolean; sort_order: number | null };
type Lic = { product_code: string; status: string; features: string[] | null };

/** Console › KMR Apps: every app, opened with full access and sample data in the KMR demo workspace, to check that each one works. */
export default async function KmrAppsPage() {
  const staff = await requireStaff();
  const a = createAdminClient();
  const [{ data: prods }, { data: demo }] = await Promise.all([
    a.from("products").select("code,name,description,app_path,current_version,active,sort_order").eq("active", true).order("sort_order"),
    a.from("customers").select("id,licences(product_code,status,features)").eq("slug", DEMO.slug).maybeSingle(),
  ]);
  const products = (prods ?? []) as Prod[];
  const lic = new Map(((demo as { licences?: Lic[] } | null)?.licences ?? []).map((l) => [l.product_code, l]));
  const counts = new Map<string, number>();
  if (demo) {
    const { data } = await (await createClient()).schema("public").rpc("kmr_data_overview", { p_slug: DEMO.slug });
    for (const r of (data ?? []) as { app: string; records: number }[]) counts.set(r.app, Number(r.records));
  }
  const base = env.platformUrl;
  const open = (path: string | null) => `${base}${path || "/it/apps.html"}${(path || "").includes("?") ? "&" : "?"}kmr=1&co=${DEMO.slug}`;
  const sample = (path: string | null, code: string) => `${base}${path || "/it/apps.html"}?demo=1${code === "pd" ? "&sample=1" : ""}`;
  const portal = `${base}/it/app/${DEMO.slug}`;
  const missing = products.filter((p) => !lic.has(p.code));
  return (
    <AppShell staff={staff} active="/apps">
      <div className="pagehead"><div><h1>KMR Apps</h1>
        <p>Every KMR app in one place, opened with <b>full access and no feature restrictions</b> in the KMR demo workspace, with sample data, so you can check that each one works. Nothing here touches a real customer.</p></div></div>

      {!demo ? (
        <div className="card" style={{ borderLeft: "4px solid var(--warn,#f59e0b)" }}>
          <h2>The demo workspace is not set up yet</h2>
          <p className="muted">Load it once under <a href={`${base}/it/console/test-data`}>Test data</a> (“Load demo data into every app”). Then come back here.</p>
        </div>
      ) : (
        <div className="card">
          <div className="row" style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "center" }}>
            <a className="btn" href={portal} target="_blank" rel="noopener">Open all apps (demo portal)</a>
            <ActionForm action={reloadDemoApps} submitLabel="Switch on every app and reload sample data" variant="secondary" confirm="Reload the sample data of every app in the demo workspace? Only the demo workspace is changed." />
          </div>
          <p className="muted" style={{ marginBottom: 0 }}>{missing.length ? <b style={{ color: "var(--warn,#b45309)" }}>{missing.length} app{missing.length > 1 ? "s are" : " is"} not switched on in the demo yet ({missing.map((m) => m.name).join(", ")}). Press the button above.</b> : <>All {products.length} apps are switched on. </>}
            You are signed in as KMR staff, who are administrators in every app. The demo company has no feature limits, so every screen is open.</p>
        </div>
      )}

      <div className="card">
        <h2>All apps ({products.length})</h2>
        <div className="tablewrap"><table>
          <thead><tr><th>App</th><th>Version</th><th>In demo</th><th>Sample records</th><th>Open</th></tr></thead>
          <tbody>{products.map((p) => {
            const l = lic.get(p.code), n = counts.get(p.code);
            return (
              <tr key={p.code}>
                <td><b>{p.name}</b><div className="muted" style={{ fontSize: 12.5, maxWidth: 480 }}>{p.description}</div></td>
                <td className="mono">{p.current_version ?? "—"}</td>
                <td>{l ? <span className={`badge ${l.status === "active" ? "ok" : "warn"}`}>{l.status === "active" ? "on" : l.status}</span> : <span className="badge">not on</span>}{l && l.features ? <div className="muted" style={{ fontSize: 11.5 }}>some features limited</div> : null}</td>
                <td>{n == null ? <span className="muted">—</span> : n > 0 ? <b>{n.toLocaleString("en-IN")}</b> : <span className="muted">none yet</span>}</td>
                <td style={{ whiteSpace: "nowrap" }}>{demo && l ? <a className="btn small" href={open(p.app_path)} target="_blank" rel="noopener">Open with sample data</a> : <span className="muted">switch on first</span>} <a href={sample(p.app_path, p.code)} target="_blank" rel="noopener" className="muted" title="Opens the stand-alone sample, no sign-in">quick sample</a></td>
              </tr>);
          })}
          {demo ? <tr><td><b>Operations Master, Data Master, Grand Master</b><div className="muted" style={{ fontSize: 12.5 }}>Shared masters of the demo company</div></td><td>—</td><td><span className="badge ok">on</span></td><td>{counts.get("ops") ? <b>{counts.get("ops")}</b> : "—"}</td>
            <td style={{ whiteSpace: "nowrap" }}><a className="btn small" href={`${portal}#ops`} target="_blank" rel="noopener">Operations</a> <a className="btn small" href={`${portal}#data`} target="_blank" rel="noopener">Data</a> <a className="btn small" href={`${portal}#grand`} target="_blank" rel="noopener">Grand</a></td></tr> : null}
          </tbody>
        </table></div>
        <p className="muted" style={{ fontSize: 12.5, marginBottom: 0 }}>The sample data is reloaded every night. “Quick sample” is the no-sign-in sample used on the website; it cannot save anything.</p>
      </div>
    </AppShell>
  );
}
