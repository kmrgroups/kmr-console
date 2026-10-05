import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { QuoteBuilder } from "@/components/QuoteBuilder";
import { quoteData } from "@/lib/quote-data";
import { p } from "@/lib/base-path";

export const metadata = { title: "New quotation" };

export default async function NewQuote() {
  const staff = await requireStaff();
  const d = await quoteData();
  return (
    <AppShell staff={staff} active="/billing">
      <div className="pagehead"><div><p className="muted"><a href={p("/billing?tab=quotes")}>← Quotations</a></p><h1>New quotation</h1><p>Pick the customer and the apps; the costing, scope and terms fill in. The PDF is printed on your letterhead.</p></div></div>
      <QuoteBuilder {...d} />
    </AppShell>
  );
}
