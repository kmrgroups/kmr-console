import { requireStaff, isManager } from "@/lib/auth";
import { platformBrand } from "@/lib/brand";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { saveKmrLogo } from "@/app/actions";

export const metadata = { title: "KMR branding" };

export default async function Branding() {
  const staff = await requireStaff();
  const b = await platformBrand();
  return (
    <AppShell staff={staff} active="/branding">
      <div className="pagehead"><div><h1>KMR branding</h1><p>KMR Group of Companies&apos; own logo — shown on the Console sign-in, the main screen, the browser tab and the general KMR Apps page. Customers&apos; logos are set on each customer.</p></div></div>
      <div className="card" style={{ maxWidth: 640 }}>
        <div className="row" style={{ gap: 18, alignItems: "center" }}>
          <div style={{ width: 120, height: 120, borderRadius: 18, border: "1px solid var(--border)", display: "grid", placeItems: "center", background: "#fff", overflow: "hidden" }}>
            {b.logo_url ? <img src={b.logo_url} alt="KMR logo" style={{ maxWidth: 108, maxHeight: 108, objectFit: "contain" }} /> : <small className="muted">No logo yet</small>}
          </div>
          {isManager(staff) ? (
            <ActionForm action={saveKmrLogo} submitLabel={b.logo_url ? "Replace logo" : "Upload logo"}>
              <input type="file" name="logo" accept="image/png,image/jpeg,image/webp,image/svg+xml" required />
              <small className="muted">PNG with a transparent background works best. Square logos make the best browser-tab icon.</small>
            </ActionForm>
          ) : <p className="muted">Only owners and administrators can change the KMR logo.</p>}
        </div>
      </div>
    </AppShell>
  );
}
