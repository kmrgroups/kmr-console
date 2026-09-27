import { requireStaff, ROLE_LABELS, type StaffRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { addStaff, setStaffActive } from "@/app/actions";

export const metadata = { title: "KMR staff" };

export default async function StaffPage() {
  const me = await requireStaff();
  const supabase = await createClient();
  const { data } = await supabase.from("staff").select("*").order("full_name");
  return (
    <AppShell staff={me} active="/staff">
      <div className="pagehead"><div><h1>KMR staff</h1><p>People at KMR who can use this Console. Owners and administrators manage licences; sales and support manage customers.</p></div></div>
      <div className="card" style={{ padding: 0 }}>
        <div className="tablewrap" style={{ border: 0 }}><table>
          <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th></th></tr></thead>
          <tbody>{(data ?? []).map((s) => (
            <tr key={s.user_id} style={{ opacity: s.active ? 1 : 0.55 }}>
              <td><b>{s.full_name}</b></td><td>{s.email}</td><td>{ROLE_LABELS[s.role as StaffRole]}</td>
              <td><span className={`badge ${s.active ? "ok" : ""}`}>{s.active ? "active" : "disabled"}</span></td>
              <td style={{ textAlign: "right" }}>{me.role === "owner" && s.user_id !== me.user_id && (
                <form action={setStaffActive}><input type="hidden" name="user_id" value={s.user_id} /><input type="hidden" name="active" value={s.active ? "0" : "1"} /><button className="btn ghost small">{s.active ? "Disable" : "Enable"}</button></form>)}</td>
            </tr>))}</tbody>
        </table></div>
      </div>
      {me.role === "owner" && (
        <div className="card" style={{ marginTop: 16 }}>
          <h2>Add staff</h2>
          <ActionForm action={addStaff} submitLabel="Add" className="formgrid" resetOnSuccess>
            <label className="field">Name<input name="full_name" required /></label>
            <label className="field">Email<input name="email" type="email" required /></label>
            <label className="field">Role<select name="role" defaultValue="support">{Object.entries(ROLE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
          </ActionForm>
        </div>
      )}
    </AppShell>
  );
}
