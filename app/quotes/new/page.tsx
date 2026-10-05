import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { QuoteBuilder } from "@/components/QuoteBuilder";
import { quoteData } from "@/lib/quote-data";
import { p } from "@/lib/base-path";

export const metadata = { title: "New quotation" };

export default async function NewQuote({ searchParams }: { searchParams: Promise<{ lead?: string }> }) {
  const staff = await requireStaff();
  const { lead } = await searchParams;
  const { setup, ...d } = await quoteData();
  return (
    <AppShell staff={staff} active="/billing?tab=quotes">
      <div className="pagehead"><div><p className="muted"><a href={p("/billing?tab=quotes")}>← Quotations</a></p><h1>New quotation</h1><p>Draft it manually, or against a website enquiry (the customer, subject and opening fill in). Pick the apps and the costing, scope and terms fill in. The PDF is printed on your letterhead.</p></div></div>
      {setup && <div className="alert warn">Quotations are not set up in the database yet. In Supabase → SQL Editor run <b>{setup}</b>, then refresh this page.</div>}
      <QuoteBuilder {...d} startLead={lead && /^[0-9a-f-]{36}$/i.test(lead) ? lead : null} />
    </AppShell>
  );
}
