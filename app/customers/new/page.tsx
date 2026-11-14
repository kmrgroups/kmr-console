import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { CustomerFields } from "@/components/CustomerFields";
import { AppsPanel, type PanelFeature } from "@/components/AppsPanel";
import { saveSetup } from "@/app/setup-actions";
import { today } from "@/lib/view";

export const metadata = { title: "New customer" };

export default async function NewCustomer() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const [{ data: products }, { data: feats }] = await Promise.all([
    supabase.from("products").select("code,name,description,seat_label").eq("active", true).order("sort_order"),
    supabase.from("app_features").select("product_code,key,name,detail,is_core").eq("active", true).order("sort_order").order("name"),
  ]);
  return (
    <AppShell staff={staff} active="/customers">
      <div className="pagehead"><div><h1>New customer</h1><p>Everything on one screen: company details, the apps to switch on, how long each runs, and which features it may use. Press Save once at the bottom.</p></div></div>
      <ActionForm action={saveSetup} submitLabel="Save customer and apps" pendingLabel="Saving…" className="stack">
        <div className="card"><h2>1. Company</h2><div className="formgrid"><CustomerFields /></div></div>
        <div className="card"><h2>2. Apps, subscription and features</h2>
          <p className="muted" style={{ marginTop: 0 }}>Choose a status to switch an app on. The end date is the subscription end; the Renew buttons add time. The contact email above becomes each app&apos;s administrator.</p>
          <AppsPanel products={(products ?? []) as never[]} features={(feats ?? []) as PanelFeature[]} licences={[]} today={today()} />
        </div>
      </ActionForm>
    </AppShell>
  );
}
