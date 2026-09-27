import { notFound } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { fmtDateTime, one } from "@/components/ui";
import { p } from "@/lib/base-path";
import { PRIORITY_TONE, TICKET_LABEL, TICKET_TONE } from "@/lib/tickets";
import { replyTicket } from "@/app/actions";

export const metadata = { title: "Ticket" };

export default async function TicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const staff = await requireStaff();
  const supabase = await createClient();
  const [{ data: t }, { data: msgs }, { data: team }] = await Promise.all([
    supabase.from("tickets").select("*,customer:customers(id,name,code)").eq("id", id).maybeSingle(),
    supabase.from("ticket_messages").select("*").eq("ticket_id", id).order("created_at"),
    supabase.from("staff").select("user_id,full_name").eq("active", true).order("full_name"),
  ]);
  if (!t) notFound();
  const c = one(t.customer);
  return (
    <AppShell staff={staff} active="/tickets">
      <div className="pagehead"><div>
        <h1>{t.subject}</h1>
        <p><span className="mono">{t.number}</span> · {t.product_code.toUpperCase()} · {c ? <a href={p(`/customers/${c.id}`)}>{c.name}</a> : t.raised_by_email} · <span className={`badge ${TICKET_TONE[t.status]}`}>{TICKET_LABEL[t.status]}</span> <span className={`badge ${PRIORITY_TONE[t.priority]}`}>{t.priority}</span></p>
      </div></div>
      <div className="grid two" style={{ gridTemplateColumns: "minmax(0,1.6fr) minmax(0,1fr)" }}>
        <div className="card">
          <h2>Conversation</h2>
          <div className="stack">
            {(msgs ?? []).map((m) => (
              <div key={m.id} style={{ padding: "12px 14px", borderRadius: 12, background: m.author_kind === "kmr" ? "rgba(11,42,111,.06)" : "var(--surface-2)", borderLeft: `3px solid ${m.author_kind === "kmr" ? "var(--kmr-navy)" : "var(--kmr-gold)"}` }}>
                <div className="spread"><b>{m.author_name}{m.author_kind === "kmr" ? " · KMR" : ""}</b><small className="muted">{fmtDateTime(m.created_at)}</small></div>
                <div style={{ whiteSpace: "pre-wrap", marginTop: 6 }}>{m.body}</div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 16 }}>
            <ActionForm action={replyTicket} submitLabel="Send reply" hidden={{ id: t.id }} resetOnSuccess>
              <label className="field">Reply to {t.raised_by_name}<textarea name="body" rows={4} placeholder="Write your reply…" /></label>
              <label className="field">Set status<select name="status" defaultValue={t.status === "open" ? "in_progress" : t.status}>{Object.entries(TICKET_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
            </ActionForm>
          </div>
        </div>
        <div className="card">
          <h2>Details</h2>
          <dl className="kv">
            <dt>Raised by</dt><dd>{t.raised_by_name}<br /><small className="muted">{t.raised_by_email}</small></dd>
            <dt>Raised</dt><dd>{fmtDateTime(t.created_at)}</dd>
            <dt>First reply</dt><dd>{t.first_reply_at ? fmtDateTime(t.first_reply_at) : "—"}</dd>
            <dt>App version</dt><dd className="mono">{t.app_version ?? "—"}</dd>
            <dt>Page</dt><dd><small className="mono" style={{ wordBreak: "break-all" }}>{t.page_url ?? "—"}</small></dd>
          </dl>
          <ActionForm action={replyTicket} submitLabel="Save" variant="secondary" hidden={{ id: t.id }} className="formgrid">
            <label className="field">Priority<select name="priority" defaultValue={t.priority}>{["low", "normal", "high", "urgent"].map((x) => <option key={x}>{x}</option>)}</select></label>
            <label className="field">Assigned to<select name="assigned_to" defaultValue={t.assigned_to ?? "none"}><option value="none">Nobody</option>{(team ?? []).map((s) => <option key={s.user_id} value={s.user_id}>{s.full_name}</option>)}</select></label>
          </ActionForm>
        </div>
      </div>
    </AppShell>
  );
}
