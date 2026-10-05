import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Cost, Customer, Lead, Paper, Product } from "@/components/QuoteBuilder";
import { billingImageUrls } from "@/lib/billing-files";
import { letterheadUrl } from "@/lib/letterhead-files";
import { p } from "@/lib/base-path";

/** Everything the quotation builder needs: customers, apps with prices and features, the costing catalogue, defaults. */
export async function quoteData() {
  const supabase = await createClient();
  const [{ data: customers }, { data: products }, { data: prices }, { data: costs }, { data: s }, { data: listings }] = await Promise.all([
    supabase.from("customers").select("id,name,legal_name,contact_name,contact_email,contact_phone,address,city,state,postal_code,tax_id").order("name"),
    supabase.from("products").select("code,name,seat_label,description,sort_order").eq("active", true).neq("code", "console").order("sort_order"),
    supabase.from("prices").select("product_code,period,unit_amount,min_seats").eq("active", true).eq("currency", "INR"),
    supabase.from("cost_items").select("*").order("sort_order").order("name"),
    supabase.from("billing_settings").select("gst_rate,quote_validity_days,quote_includes,quote_terms,trade_name,legal_name,signatory_name,signatory_title,seal_path,signature_path").eq("id", true).maybeSingle(),
    supabase.schema("public").from("app_listings").select("code,tagline,features"),
  ]);
  const { data: leads } = await supabase.from("leads").select("id,name,company,email,phone,country,business,product_name,quantity,message,status,customer_id,created_at")
    .in("status", ["new", "contacted", "quoted"]).order("created_at", { ascending: false }).limit(200);
  const lst = Object.fromEntries((listings ?? []).map((l) => [l.code, l]));
  const prods: Product[] = (products ?? []).map((x) => ({
    code: x.code, name: x.name, seat_label: x.seat_label, description: x.description,
    prices: (prices ?? []).filter((r) => r.product_code === x.code).map((r) => ({ period: r.period, unit_amount: Number(r.unit_amount), min_seats: r.min_seats })),
    tagline: lst[x.code]?.tagline ?? null,
    features: String(lst[x.code]?.features ?? "").split("\n").map((f: string) => f.trim()).filter(Boolean),
  }));
  // quotations need migrations 0045 (and 0047 for enquiries); say so instead of failing on save
  const { error: qErr } = await supabase.from("quotes").select("id", { count: "exact", head: true });
  const { error: lErr } = await supabase.from("quotes").select("lead_id", { count: "exact", head: true });
  const setup = qErr ? "0045_media_costing_quotes.sql, 0046_gallery_video_library.sql and 0047_quote_from_enquiry.sql" : lErr ? "0047_quote_from_enquiry.sql" : null;
  const today = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
  const [img, lh] = await Promise.all([billingImageUrls({ ...(s ?? {}), show_seal: true }), letterheadUrl(p("/letterhead.jpg"))]);
  const paper: Paper = { letterhead: lh, seal: img.seal, signature: img.signature, company: s?.trade_name || s?.legal_name || "KMR Group of Companies",
    signatory: s?.signatory_name ? `${s.signatory_name}${s.signatory_title ? `, ${s.signatory_title}` : ""}` : null };
  return {
    setup, paper, customers: (customers ?? []) as Customer[], leads: (leads ?? []) as Lead[], products: prods, costs: (costs ?? []) as Cost[],
    defaults: { includes: s?.quote_includes ?? "", terms: s?.quote_terms ?? "", validity: s?.quote_validity_days ?? 30, gst: Number(s?.gst_rate ?? 18), today },
  };
}
