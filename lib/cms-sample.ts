/**
 * Sample content for the website — loaded and removed from Website CMS › Overview.
 * Every sample row is marked sample = true; "Remove sample content" deletes exactly those rows and clears the
 * sample photos it filled in (your own photos and records are never touched). Photos are served by the website
 * itself from /sample/… and come in different shapes, to show that nothing is cropped.
 */
export const SAMPLE_TABLES = ["hero_slides", "site_stats", "products", "job_openings", "leaders", "gallery_items"] as const;

export function sampleRows(site: string) {
  const img = (f: string) => `${site}/sample/${f}`;
  const today = new Date(), inDays = (n: number) => new Date(today.getTime() + n * 864e5).toISOString().slice(0, 10);
  return {
    hero_slides: [
      { eyebrow: "Sample slide", title: "Precision in everything we do", subtitle: "Manufacturing discipline applied to supply, software and skills — one trusted group.", image_url: img("hero-1.jpg"), cta_label: "Explore our businesses", cta_link: "/businesses", cta2_label: "Contact us", cta2_link: "/contact", sort_order: 1 },
      { eyebrow: "Sample slide", title: "Software built for the shop floor", subtitle: "HRM, Balloon Inspector, Process Documents and Capacity Planner.", image_url: img("hero-2.jpg"), cta_label: "See the solutions", cta_link: "/software", sort_order: 2 },
      { eyebrow: "Sample slide", title: "Training that builds capability", subtitle: "Quality systems and core tools, taught by practitioners.", image_url: img("hero-3.jpg"), cta_label: "View programmes", cta_link: "/training", sort_order: 3 },
    ],
    site_stats: [
      { value: "18+", label: "Years of industry experience (sample)", sort_order: 1 }, { value: "6", label: "Business verticals (sample)", sort_order: 2 },
      { value: "500+", label: "Customers served (sample)", sort_order: 3 }, { value: "24 h", label: "Reply to every enquiry (sample)", sort_order: 4 },
    ],
    products: [
      { name: "Sample — Digital Vernier Caliper 150 mm", category: "Metrology", business: "shop", kind: "goods", price: 1850, mrp: 2400, stock_quantity: 12, unit: "nos", image_url: img("p-square.jpg"), featured: true, sort_order: 1, description: "Sample product. Stainless steel, 0.01 mm resolution, SPC output.\n\n- Square photo — shown whole" },
      { name: "Sample — Safety Shoes, Steel Toe", category: "Safety", business: "shop", kind: "goods", price: 1299, mrp: 1599, stock_quantity: 25, unit: "pair", image_url: img("p-portrait.jpg"), featured: true, sort_order: 2, description: "Sample product with a tall photo — shown whole, not cropped." },
      { name: "Sample — Torque Wrench Set", category: "Tools", business: "shop", kind: "goods", price: 4200, stock_quantity: 5, unit: "set", image_url: img("p-wide.jpg"), sort_order: 3, description: "Sample product with a wide photo." },
      { name: "Sample — IATF 16949 Core Tools (2 days)", category: "Quality", business: "training", kind: "course", price: 6500, stock_quantity: 0, unit: "seat", image_url: img("course.jpg"), featured: true, sort_order: 1, details: { duration: "2 days", mode: "On site / online" }, description: "Sample programme: APQP, PPAP, FMEA, SPC and MSA with shop-floor case studies." },
      { name: "Sample — ERP set-up & data migration", category: "Implementation", business: "software", kind: "service", price: 0, enquiry_only: true, stock_quantity: 0, image_url: img("v-software.jpg"), sort_order: 1, description: "Sample solution: we configure your ERP and move your masters and opening balances." },
      { name: "Sample — Turmeric (bulk export)", category: "Agro", business: "import_export", kind: "goods", price: 0, enquiry_only: true, stock_quantity: 0, unit: "tonne", image_url: img("v-trade.jpg"), sort_order: 1, description: "Sample trade item, quoted on request." },
    ],
    job_openings: [
      { title: "Sample — Quality Engineer", department: "Quality", location: "Puducherry", employment_type: "Full-time", experience: "3–5 years", summary: "Sample opening: own inspection, calibration and supplier quality.", description: "This is a sample job opening.\n\nReplace it with your real openings in Website CMS › Job openings.", requirements: "Diploma / B.E. Mechanical\nKnowledge of core tools\nGood written English", posted_on: inDays(0), closes_on: inDays(45), sort_order: 1 },
      { title: "Sample — Sales Executive (B2B)", department: "Sales", location: "Chennai / Bengaluru", employment_type: "Full-time", experience: "1–3 years", summary: "Sample opening: grow our industrial supply and software customers.", requirements: "Graduate\nTwo-wheeler and licence", posted_on: inDays(0), sort_order: 2 },
    ],
    leaders: [
      { name: "Sample Person", designation: "Head of Operations (sample)", bio: "Sample profile with a portrait photo. Replace it in Website CMS › Leadership team.", photo_url: img("person-1.jpg"), sort_order: 50 },
      { name: "Sample Colleague", designation: "Head of Software (sample)", bio: "Sample profile with a square photo.", photo_url: img("person-2.jpg"), sort_order: 51 },
    ],
    gallery_items: [
      { title: "Sample — wide photo", media_type: "photo", media_url: img("g-1.jpg"), sort_order: 50 },
      { title: "Sample — tall photo", media_type: "photo", media_url: img("g-2.jpg"), sort_order: 51 },
      { title: "Sample — square photo", media_type: "photo", media_url: img("g-3.jpg"), sort_order: 52 },
    ],
    // photos filled in only where you have none yet (removed again with the sample content)
    company: { about_image_url: img("about.jpg"), founder_photo_url: img("person-1.jpg") },
    verticals: { shop: img("v-shop.jpg"), software: img("v-software.jpg"), training: img("v-training.jpg"), import_export: img("v-trade.jpg"), trading: img("v-trade.jpg"), distribution: img("v-shop.jpg") } as Record<string, string>,
  };
}
