import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { env } from "@/lib/env";
import { BASE_PATH } from "@/lib/base-path";
import { alertEmail, sendMail } from "@/lib/mail";

/** Business emails. Each one is best-effort: a failed email never undoes the action that triggered it. */

const money = (n: number, cur = "INR") => {
  try { return new Intl.NumberFormat("en-IN", { style: "currency", currency: cur }).format(Number(n) || 0); } catch { return `${cur} ${n}`; }
};
const day = (d?: string | null) => (d ? new Date(d).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const payLink = (token: string) => `${env.platformUrl}${BASE_PATH}/pay/${token}`;

type Inv = { id: string; number: string | null; total: number; currency: string; due_date: string | null; pay_token: string | null; status: string;
  customers: { name: string | null; contact_email: string | null; contact_name: string | null } | null };

async function invoice(id: string): Promise<Inv | null> {
  const { data } = await createAdminClient().from("invoices")
    .select("id,number,total,currency,due_date,pay_token,status,customers(name,contact_email,contact_name)").eq("id", id).maybeSingle();
  return (data as unknown as Inv) ?? null;
}
const hello = (i: Inv) => `Dear ${i.customers?.contact_name || i.customers?.name || "customer"},`;

export async function mailInvoiceIssued(id: string) {
  const i = await invoice(id); if (!i?.customers?.contact_email) return;
  await sendMail({
    kind: "invoice_issued", ref: i.number ?? id, to: i.customers.contact_email,
    subject: `Invoice ${i.number} — ${money(i.total, i.currency)}`, heading: `Invoice ${i.number}`,
    paragraphs: [hello(i), "Your invoice is ready. You can view it, download the PDF and pay online or by bank transfer / UPI from the link below."],
    rows: [["Invoice", i.number ?? ""], ["Amount", money(i.total, i.currency)], ["Due date", day(i.due_date)]],
    button: i.pay_token ? { label: "View and pay", url: payLink(i.pay_token) } : undefined,
  });
}

export async function mailPaymentReceived(id: string) {
  const i = await invoice(id); if (!i?.customers?.contact_email) return;
  await sendMail({
    kind: "payment_receipt", ref: i.number ?? id, to: i.customers.contact_email,
    subject: `Payment received — invoice ${i.number}`, heading: "Thank you — payment received",
    paragraphs: [hello(i), `We have received your payment for invoice ${i.number}. Your licences are renewed for the paid period.`],
    rows: [["Invoice", i.number ?? ""], ["Amount", money(i.total, i.currency)], ["Status", "Paid"]],
    button: i.pay_token ? { label: "View receipt", url: payLink(i.pay_token) } : undefined,
  });
}

export async function mailPaymentRejected(id: string, reason: string) {
  const i = await invoice(id); if (!i?.customers?.contact_email) return;
  await sendMail({
    kind: "payment_rejected", ref: i.number ?? id, to: i.customers.contact_email,
    subject: `We could not match your payment — invoice ${i.number}`, heading: "We could not match your payment",
    paragraphs: [hello(i), "We checked our bank statement but could not find the payment you reported.", `Reason: ${reason || "not given"}`,
      "Please check the reference (UTR) and report it again from the link below, or reply to this email."],
    button: i.pay_token ? { label: "Open the pay link", url: payLink(i.pay_token) } : undefined,
  });
}

/** The customer reported a bank / UPI payment: tell KMR so someone checks the bank statement. */
export async function mailPaymentReported(token: string, amount: number, reference: string, payer?: string | null) {
  const { data } = await createAdminClient().from("invoices").select("id,number,currency,customers(name)").eq("pay_token", token).maybeSingle();
  const i = data as unknown as { id: string; number: string; currency: string; customers: { name: string } | null } | null;
  if (!i) return;
  await sendMail({
    kind: "payment_reported", ref: i.number, to: await alertEmail(),
    subject: `Payment reported — ${i.number} (${money(amount, i.currency)})`, heading: "A customer reported a payment",
    paragraphs: ["Check the bank statement, then confirm or reject it in the Console."],
    rows: [["Customer", i.customers?.name ?? ""], ["Invoice", i.number], ["Amount", money(amount, i.currency)], ["Reference (UTR)", reference], ["Paid by", payer || "—"]],
    button: { label: "Open the invoice", url: `${env.platformUrl}${BASE_PATH}/invoices/${i.id}` },
  });
}

export async function mailTicketReply(ticketId: string, body: string, status: string) {
  const { data } = await createAdminClient().from("tickets").select("number,subject,raised_by_email,raised_by_name").eq("id", ticketId).maybeSingle();
  const t = data as { number: string; subject: string; raised_by_email: string; raised_by_name: string } | null;
  if (!t?.raised_by_email) return;
  const label = ({ resolved: "Resolved", closed: "Closed", waiting_on_customer: "Waiting for your reply" } as Record<string, string>)[status];
  await sendMail({
    kind: "ticket_reply", ref: t.number, to: t.raised_by_email,
    subject: `[${t.number}] ${t.subject}`, heading: `Reply to your request ${t.number}`,
    paragraphs: [`Dear ${t.raised_by_name || "customer"},`, ...body.split(/\n{2,}/).map((p) => p.trim()).filter(Boolean).slice(0, 20),
      "You can reply from Help & support inside the app."],
    rows: label ? [["Status", label]] : undefined,
  });
}

/** Website order confirmed / rejected by staff in Website CMS › Orders. */
export async function mailOrderUpdate(orderId: string, ok: boolean, reason?: string) {
  const { data } = await createAdminClient().schema("public").from("orders")
    .select("order_no,customer_name,customer_email,amount,currency,order_token").eq("id", orderId).maybeSingle();
  const o = data as { order_no: string | null; customer_name: string | null; customer_email: string | null; amount: number | null; currency: string | null; order_token: string | null } | null;
  if (!o?.customer_email) return;
  const site = process.env.WEBSITE_URL || "https://www.kmr-groups.com";
  await sendMail({
    kind: ok ? "order_paid" : "order_payment_rejected", ref: o.order_no ?? orderId, to: o.customer_email,
    subject: ok ? `Payment received — order ${o.order_no ?? ""}` : `We could not match your payment — order ${o.order_no ?? ""}`,
    heading: ok ? "Thank you — your order is confirmed" : "We could not match your payment",
    paragraphs: [`Dear ${o.customer_name || "customer"},`, ok
      ? "We have received your payment. We will be in touch about delivery."
      : `We checked our bank statement but could not find the payment you reported. Reason: ${reason || "not given"}. Please check the reference and report it again.`],
    rows: [["Order", o.order_no ?? ""], ["Amount", money(o.amount ?? 0, o.currency || "INR")]],
    button: o.order_token ? { label: "View your order", url: `${site}/order/${o.order_token}` } : undefined,
  });
}
