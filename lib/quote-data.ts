import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Cost, Customer, Lead, Product } from "@/components/QuoteBuilder";

/** Everything the quotation builder needs: customers, apps with prices and features, the costing catalogue, defaults. */
export async function quoteData() {
  const supabase = await createClient();
  const [{ data: customers }, { data: products }, { data: prices }, { data: costs }, { data: s }, { data: listings }] = await Promise.all([
    supabase.from("customers").select("id,name,legal_name,contact_name,contact_email,contact_phone,address,city,state,postal_code,tax_id").order("name"),
    supabase.from("products").select("code,name,seat_label,description,sort_order").eq("active", true).neq("code", "console").order("sort_order"),
    supabase.from("prices").select("product_code,period,unit_amount,min_seats").eq("active", true).eq("currency", "INR"),
    supabase.from("cost_items").select("*").order("sort_order").order("name"),
    supabase.from("billing_settings").select("gst_rate,quote_validity_days,quote_includes,quote_terms").eq("id", true).maybeSingle(),
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
  const today = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
  return {
    customers: (customers ?? []) as Customer[], leads: (leads ?? []) as Lead[], products: prods, costs: (costs ?? []) as Cost[],
    defaults: { includes: s?.quote_includes ?? "", terms: s?.quote_terms ?? "", validity: s?.quote_validity_days ?? 30, gst: Number(s?.gst_rate ?? 18), today },
  };
}
