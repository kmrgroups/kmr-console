import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { CustomerFields } from "@/components/CustomerFields";
import { saveCustomer } from "@/app/actions";

export const metadata = { title: "New customer" };

export default async function NewCustomer() {
  const staff = await requireStaff();
  return (
    <AppShell staff={staff} active="/customers">
      <div className="pagehead"><div><h1>New customer</h1><p>After saving, switch products on from the customer&apos;s page.</p></div></div>
      <div className="card"><ActionForm action={saveCustomer} submitLabel="Save customer" className="formgrid"><CustomerFields /></ActionForm></div>
    </AppShell>
  );
}
