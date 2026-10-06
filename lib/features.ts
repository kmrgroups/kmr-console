/** App features and their prices — shared by the Prices screen, the quotation builder and the invoice form. */
export type Feature = {
  id: string; product_code: string; name: string; detail: string | null; is_core: boolean;
  price_month: number; price_year: number; setup_fee: number; sort_order: number; active: boolean;
};
export const featurePrice = (f: Pick<Feature, "price_month" | "price_year">, period: "month" | "year") => Number(period === "year" ? f.price_year : f.price_month) || 0;
/** the price per user for a set of chosen features (core features are always included) */
export function appPrice(features: Feature[], chosen: Set<string>, period: "month" | "year") {
  return features.filter((f) => f.active && (f.is_core || chosen.has(f.id))).reduce((a, f) => a + featurePrice(f, period), 0);
}
