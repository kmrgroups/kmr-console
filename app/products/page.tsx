import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { fmtDate } from "@/components/ui";
import { addRelease } from "@/app/actions";

export const metadata = { title: "Products & versions" };

export default async function Products() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const [{ data: products }, { data: releases }] = await Promise.all([
    supabase.from("products").select("*").order("sort_order"),
    supabase.from("releases").select("*").order("released_on", { ascending: false }).order("created_at", { ascending: false }),
  ]);
  return (
    <AppShell staff={staff} active="/products">
      <div className="pagehead"><div><h1>Products &amp; versions</h1><p>Every customer runs the current version of each product. Record each release here.</p></div></div>
      <div className="grid three">
        {(products ?? []).map((pr) => (
          <div key={pr.code} className="card">
            <h2><span>{pr.name}</span><span className="badge ok mono">v{pr.current_version}</span></h2>
            <p className="muted" style={{ marginTop: -6 }}>{pr.description}</p>
            <ul className="timeline">
              {(releases ?? []).filter((r) => r.product_code === pr.code).slice(0, 6).map((r) => (
                <li key={r.id}><span><b className="mono">{r.version}</b> — {r.notes}</span><small>{fmtDate(r.released_on)}</small></li>
              ))}
            </ul>
            {isManager(staff) && (
              <details style={{ marginTop: 10 }}>
                <summary className="btn secondary small">Record a release</summary>
                <div style={{ marginTop: 10 }}>
                  <ActionForm action={addRelease} submitLabel="Save" hidden={{ product_code: pr.code }} resetOnSuccess>
                    <label className="field">Version<input name="version" placeholder="2.1.0" required /></label>
                    <label className="field">What changed<textarea name="notes" rows={3} required /></label>
                  </ActionForm>
                </div>
              </details>
            )}
          </div>
        ))}
      </div>
    </AppShell>
  );
}
