import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import type { InvoiceData, LineData, Party } from "@/components/InvoiceDoc";

/** One invoice with the seller / buyer shown on it: drafts use today's details, issued invoices what was frozen on them. */
export async function loadInvoice(by: { id?: string; token?: string }) {
  const db = createAdminClient();
  let q = db.from("invoices").select("*");
  q = by.id ? q.eq("id", by.id) : q.eq("pay_token", by.token!);
  const { data: inv } = await q.maybeSingle();
  if (!inv) return null;
  const [{ data: lines }, { data: c }, { data: s }] = await Promise.all([
    db.from("invoice_lines").select("*").eq("invoice_id", inv.id).order("sort").order("id"),
    db.from("customers").select("*").eq("id", inv.customer_id).maybeSingle(),
    db.from("billing_settings").select("*").eq("id", true).maybeSingle(),
  ]);
  const draft = inv.status === "draft";
  const seller: Party = draft ? { ...(s ?? {}), state_code: s?.state_code ?? s?.gstin?.slice(0, 2) } : inv.seller;
  const buyer: Party = draft && c ? { code: c.code, name: c.legal_name || c.name, tax_id: c.tax_id, address: c.address, city: c.city, state: c.state, postal_code: c.postal_code, country: c.country, contact_name: c.contact_name, contact_email: c.contact_email } : inv.buyer;
  return { inv: inv as InvoiceData & { id: string; pay_token: string }, lines: (lines ?? []) as LineData[], seller, buyer };
}
