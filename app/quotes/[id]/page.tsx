import { notFound } from "next/navigation";
import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { QuoteBuilder } from "@/components/QuoteBuilder";
import { quoteData } from "@/lib/quote-data";
import { deleteQuote, setQuoteStatus } from "@/app/quote-actions";
import { fmtDate } from "@/components/ui";
import { p } from "@/lib/base-path";
import type { QuoteInput } from "@/lib/quote";

export const metadata = { title: "Quotation" };
const NEXT: Record<string, [string, string][]> = {
  draft: [["sent", "Mark as sent"]], sent: [["accepted", "Customer accepted"], ["declined", "Customer declined"], ["expired", "Lapsed"]],
  accepted: [["sent", "Back to sent"]], declined: [["sent", "Back to sent"]], expired: [["sent", "Back to sent"]],
};

export default async function QuotePage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ saved?: string }> }) {
  const staff = await requireStaff();
  const { id } = await params; const { saved } = await searchParams;
  const supabase = await createClient();
  const { data: q } = await supabase.from("quotes").select("*").eq("id", id).maybeSingle();
  if (!q) notFound();
  const { setup, ...d } = await quoteData();
  const initial: QuoteInput & { number: string | null } = {
    id: q.id, number: q.number, customer_id: q.customer_id, lead_id: q.lead_id ?? null, to_name: q.to_name, to_attn: q.to_attn ?? "", to_address: q.to_address ?? "", to_gstin: q.to_gstin ?? "",
    to_email: q.to_email ?? "", to_phone: q.to_phone ?? "", subject: q.subject, intro: q.intro ?? "", scope: q.scope ?? [], lines: q.lines ?? [],
    includes: q.includes ?? "", terms: q.terms ?? "", discount_pct: Number(q.discount_pct), gst_rate: Number(q.gst_rate),
    quote_date: q.quote_date, valid_until: q.valid_until, notes: q.notes ?? "",
  };
  return (
    <AppShell staff={staff} active="/billing?tab=quotes">
      <div className="pagehead">
        <div><p className="muted"><a href={p("/billing?tab=quotes")}>← Quotations</a></p>
          <h1 className="mono">{q.number}</h1>
          <p>{q.to_name} · {fmtDate(q.quote_date)} · <span className="badge">{q.status}</span>{q.lead_id && <> · <a href={p(`/leads`)}>against an enquiry</a></>}{q.updated_by && <small className="muted"> · last saved by {q.updated_by}</small>}</p></div>
      </div>
      {saved && <div className="alert ok">Quotation {q.number} saved.</div>}
      {setup && <div className="alert warn">Quotations are not set up in the database yet. In Supabase → SQL Editor run <b>{setup}</b>, then refresh this page.</div>}
      <QuoteBuilder initial={initial} status={q.status} {...d}>
        <div className="card">
          <h2>Status: <span className="badge">{q.status}</span></h2>
          <div style={{ display: "grid", gap: 8 }}>
            {(NEXT[q.status] ?? []).map(([s, l]) => <ActionForm key={s} action={setQuoteStatus} submitLabel={l} variant="secondary" hidden={{ id: q.id, status: s }} />)}
            {isManager(staff) && <ActionForm action={deleteQuote} submitLabel="Delete quotation" variant="danger" confirm={`Delete quotation ${q.number}? This cannot be undone.`} hidden={{ id: q.id }} />}
          </div>
        </div>
      </QuoteBuilder>
    </AppShell>
  );
}
