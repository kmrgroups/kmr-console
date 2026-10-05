/**
 * Website CMS — every section of www.kmr-groups.com, managed from the KMR Console.
 * One definition per section drives its list (add / edit / hide / delete), its form and saving.
 * Writes go through the Console server with the service key after the staff member's role is checked.
 */
export type FieldType = "text" | "textarea" | "longtext" | "number" | "money" | "bool" | "date" | "select" | "image" | "document" | "url" | "email";
export interface Field {
  k: string; label: string; type?: FieldType; required?: boolean; help?: string; wide?: boolean; readonly?: boolean;
  opts?: [string, string][];
  bucket?: "records" | "careers";        // document fields: which private bucket
}
export type Role = "owner" | "admin" | "sales" | "support";
export interface Section {
  key: string; table: string; group: GroupKey; label: string; singular: string; intro: string;
  fields: Field[]; list: string[]; order: [string, boolean]; search?: string[];
  filter?: { k: string; label: string; opts: [string, string][]; restrict?: boolean };   // restrict: list only these values
  scope?: Record<string, string>;        // fixed filter, also written on save (e.g. business = software)
  visible?: string;                      // the show / hide column
  single?: boolean; noCreate?: boolean; noDelete?: boolean; roles: Role[];
  defaults?: Record<string, string | number | boolean>;
  preview?: (row: Record<string, unknown>) => string | null;   // path on the website
  titleOf?: string[];                   // columns used as the record title
  sitePath?: string;                    // where this section appears on the website (list page "View on website")
}
export type GroupKey = "brand" | "home" | "businesses" | "shop" | "software" | "training" | "trade" | "careers" | "about" | "policies";
export const GROUPS: { key: GroupKey; label: string; hint: string }[] = [
  { key: "brand", label: "Brand & company", hint: "Logo, GST, address, contacts, social links, founder" },
  { key: "home", label: "Home page", hint: "Banner, numbers, who we serve, why KMR, product benefits, how it works" },
  { key: "businesses", label: "Business verticals", hint: "The businesses of the group" },
  { key: "shop", label: "Online shop", hint: "Products, orders and payments" },
  { key: "software", label: "Software solutions", hint: "KMR Apps on the website (pictures, features, order), solutions and services" },
  { key: "training", label: "Training & development", hint: "Programmes and courses" },
  { key: "trade", label: "Import, export & trading", hint: "Items quoted on request" },
  { key: "careers", label: "Careers", hint: "Job openings and applications" },
  { key: "about", label: "About us", hint: "Leadership team and gallery" },
  { key: "policies", label: "Policies & records", hint: "Company policies and private registrations" },
];

const ALL: Role[] = ["owner", "admin"];
const SALES: Role[] = ["owner", "admin", "sales"];
const on = { is_active: true };
const POINT_ICONS: [string, string][] = [["bag", "Shopping bag"], ["code", "Software"], ["cap", "Training"], ["globe", "Globe / export"], ["truck", "Delivery"], ["shield", "Shield / quality"], ["lock", "Lock / secure"], ["users", "People"], ["clock", "Clock / speed"], ["chart", "Chart / cost"], ["briefcase", "Briefcase"], ["file", "Document"], ["check", "Tick"]];

const productFields = (kinds: [string, string][], extra: Field[] = []): Field[] => [
  { k: "name", label: "Name", required: true, wide: true },
  { k: "kind", label: "Type", type: "select", opts: kinds, required: true },
  { k: "category", label: "Category" }, { k: "sku", label: "Code / SKU" },
  { k: "price", label: "Price (₹, incl. GST)", type: "money", required: true, help: "0 = price on request" }, { k: "mrp", label: "MRP / list price (₹)", type: "money" },
  ...extra,
  { k: "hsn_code", label: "HSN / SAC" },
  { k: "is_active", label: "Show on the website", type: "bool" }, { k: "featured", label: "Feature on the home page", type: "bool" },
  { k: "sort_order", label: "Order in lists", type: "number" },
  { k: "image_url", label: "Photo", type: "image" },
  { k: "video_url", label: "Promo video (Instagram-reel size 9:16)", type: "image", help: "Any phone video up to 3 minutes — it is resized to 720 × 1280 and made web-ready before upload (keep the screen open while it prepares). Shown on the public website only (home, Software and Gallery pages) — never in the customer KMR Apps panel." }, { k: "video_poster", label: "Video thumbnail (9:16 photo — 1080 × 1920 best)", type: "image", help: "Shown on the card with a ▶ play button" },
  { k: "description", label: "Description", type: "longtext", wide: true },
];
const POINT_FIELDS: Field[] = [
  { k: "title", label: "Title", required: true, wide: true }, { k: "text", label: "Text", type: "textarea", wide: true },
  { k: "icon", label: "Icon", type: "select", opts: POINT_ICONS },
  { k: "link", label: "Link (optional)", help: "/shop, /software, /contact …" }, { k: "link_label", label: "Link text" },
  { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
];
const productList = ["image_url", "name", "category", "price", "is_active"];
const productPreview = (r: Record<string, unknown>) => `/products/${r.id}`;

export const SECTIONS: Section[] = [
  // ---------------- Brand & company (one row: company_info) ----------------
  { key: "company", table: "company_info", group: "brand", label: "Company profile", singular: "company profile", roles: ALL, single: true, noDelete: true,
    intro: "Name, logo, registrations and the About text. Shown in the header, footer and About page — it is public, so never put Aadhaar, PAN or bank numbers here.",
    list: [], order: ["updated_at", false],
    fields: [
      { k: "trade_name", label: "Company name (trade name)", required: true, wide: true }, { k: "brand_name", label: "Short brand name" }, { k: "legal_name", label: "Legal name" },
      { k: "tagline", label: "Tagline" }, { k: "slogan", label: "Slogan" },
      { k: "gstin", label: "GSTIN", help: "Shown in the footer and on About" }, { k: "udyam_number", label: "Udyam registration no." },
      { k: "msme_category", label: "MSME category" }, { k: "cin", label: "CIN / LLPIN" }, { k: "constitution", label: "Constitution" },
      { k: "founded_year", label: "Founded (year)", type: "number" }, { k: "trademark_status", label: "Trademark", wide: true },
      { k: "logo_url", label: "Company logo", type: "image", help: "Shown in the header and footer. A PNG with a transparent background looks best." },
      { k: "about_image_url", label: "About section photo", type: "image", help: "Beside “About” on the home page — your office, team or plant." },
      { k: "short_about", label: "Short introduction (footer, home page)", type: "textarea", wide: true },
      { k: "about_story", label: "Our story (About page)", type: "longtext", wide: true },
      { k: "vision", label: "Vision", type: "textarea", wide: true }, { k: "mission", label: "Mission", type: "textarea", wide: true },
      { k: "core_values", label: "Core values", type: "textarea", wide: true, help: "One per line, e.g. “Integrity — we do what we say”" },
    ] },
  { key: "contact", table: "company_info", group: "brand", label: "Contact & social links", singular: "contact details", roles: ALL, single: true, noDelete: true,
    intro: "Address, phone, email, WhatsApp, map and social media links — shown on Contact, in the footer and the header.",
    list: [], order: ["updated_at", false],
    fields: [
      { k: "registered_address", label: "Address (street)", wide: true, help: "The GST registered address" }, { k: "city", label: "City / town" }, { k: "state", label: "State" }, { k: "postal_code", label: "PIN code" },
      { k: "email", label: "Email", type: "email" }, { k: "careers_email", label: "Careers email", type: "email" }, { k: "phone", label: "Phone" }, { k: "alt_phone", label: "Second phone" },
      { k: "whatsapp_number", label: "WhatsApp (country code + number, no +)", help: "e.g. 919876543210" }, { k: "website_url", label: "Website", type: "url" },
      { k: "business_hours", label: "Business hours", wide: true, help: "e.g. Mon – Sat, 9:30 am – 6:30 pm" },
      { k: "map_lat", label: "Map latitude", type: "number" }, { k: "map_lng", label: "Map longitude", type: "number" },
      { k: "map_embed_url", label: "Google Maps link (optional)", wide: true, help: "Paste any Google Maps link for your location (Share › Copy link), or the “Embed a map” code. Without it, the map uses the latitude / longitude, else the address." },
      { k: "linkedin_url", label: "LinkedIn", type: "url" }, { k: "facebook_url", label: "Facebook", type: "url" }, { k: "instagram_url", label: "Instagram", type: "url" },
      { k: "youtube_url", label: "YouTube", type: "url" }, { k: "twitter_url", label: "X (Twitter)", type: "url" },
    ] },
  { key: "founder", table: "company_info", group: "brand", label: "Founder & message", singular: "founder", roles: ALL, single: true, noDelete: true,
    intro: "The founder’s photo and message on the home page and About page.",
    list: [], order: ["updated_at", false],
    fields: [
      { k: "founder_name", label: "Founder name" }, { k: "founder_title", label: "Title", help: "e.g. Founder & Managing Director" },
      { k: "proprietor_name", label: "Proprietor / director (legal)", help: "Used on invoices and legal pages" }, { k: "proprietor_title", label: "Their legal title" },
      { k: "founder_photo_url", label: "Founder photo", type: "image" }, { k: "founder_signature_url", label: "Signature (optional, transparent PNG)", type: "image" },
      { k: "founder_message", label: "Founder’s message", type: "longtext", wide: true, help: "Blank lines start a new paragraph. The first paragraph appears on the home page." },
    ] },
  // ---------------- Home page ----------------
  { key: "slides", table: "hero_slides", group: "home", label: "Hero slides", singular: "slide", roles: ALL, visible: "is_active",
    sitePath: "/", titleOf: ["title"],
    intro: "The large rotating banner at the very top of the home page — the first thing a visitor sees. The background photo sits behind the title and buttons (shown whole, never cropped). Use wide photos, ideally 1920 × 1000. Speak to the customer: what you offer them, not about us.",
    list: ["image_url", "title", "eyebrow", "cta_link", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10 },
    fields: [
      { k: "eyebrow", label: "Small line above the title" }, { k: "title", label: "Title", required: true, wide: true },
      { k: "subtitle", label: "Text", type: "textarea", wide: true },
      { k: "cta_label", label: "Main button text" }, { k: "cta_link", label: "Main button link", help: "/shop, /software, /contact …" },
      { k: "cta2_label", label: "Second button text" }, { k: "cta2_link", label: "Second button link" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "image_url", label: "Background photo", type: "image" },
    ] },
  { key: "stats", table: "site_stats", group: "home", label: "Highlight numbers", singular: "number", roles: ALL, visible: "is_active",
    sitePath: "/", intro: "The row of numbers just under the banner, e.g. “18+ — Years of experience”. Use only numbers you can prove.", list: ["value", "label", "sort_order", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10 },
    fields: [{ k: "value", label: "Number", required: true }, { k: "label", label: "Label", required: true, wide: true }, { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" }] },
  { key: "audience", table: "home_points", group: "home", label: "Who we serve", singular: "customer group", roles: ALL, visible: "is_active", scope: { section: "audience" }, sitePath: "/#who",
    intro: "Home page: “Who can use our products & services” — one card per kind of customer, each with a link to what fits them.",
    list: ["title", "link", "sort_order", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10, icon: "briefcase" },
    fields: POINT_FIELDS },
  { key: "why", table: "home_points", group: "home", label: "Why choose KMR", singular: "reason", roles: ALL, visible: "is_active", scope: { section: "why" }, sitePath: "/#why",
    intro: "Home page: the reasons a customer should trust and buy from KMR.",
    list: ["title", "text", "sort_order", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10, icon: "shield" },
    fields: POINT_FIELDS },
  { key: "benefits", table: "product_benefits", group: "home", label: "Product benefits (P·Q·C·D)", singular: "product", roles: ALL, visible: "is_active", sitePath: "/#benefits",
    intro: "Home page: what each product does for the customer’s Productivity, Quality, Cost and Delivery. Keep each line short and true — avoid numbers you cannot prove.",
    list: ["product", "tagline", "sort_order", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10 },
    fields: [
      { k: "product", label: "Product / service", required: true }, { k: "tagline", label: "One-line description" },
      { k: "link", label: "Link", help: "/software, /shop, /training …" }, { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "productivity", label: "Productivity — how it saves time or effort", type: "textarea", wide: true },
      { k: "quality", label: "Quality — how it improves quality or compliance", type: "textarea", wide: true },
      { k: "cost", label: "Cost — how it saves money", type: "textarea", wide: true },
      { k: "delivery", label: "Delivery — how it helps deliver on time", type: "textarea", wide: true },
    ] },
  { key: "process", table: "home_points", group: "home", label: "How it works", singular: "step", roles: ALL, visible: "is_active", scope: { section: "process" }, sitePath: "/#how",
    intro: "Home page: the simple steps from enquiry to delivery (3–5 steps read best).",
    list: ["sort_order", "title", "text", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10, icon: "check" },
    fields: POINT_FIELDS },
  { key: "settings", table: "site_settings", group: "home", label: "Header & announcement", singular: "settings", roles: ALL, single: true, noDelete: true,
    intro: "The button in the header and an optional announcement bar above it (leave empty to hide).", list: [], order: ["updated_at", false],
    fields: [
      { k: "header_cta_label", label: "Header button text" }, { k: "header_cta_link", label: "Header button link" },
      { k: "announcement", label: "Announcement bar text", wide: true }, { k: "announcement_link", label: "Announcement link" },
    ] },
  // ---------------- Businesses ----------------
  { key: "verticals", table: "verticals", group: "businesses", label: "Business verticals", singular: "business", roles: ALL, visible: "is_active",
    intro: "The businesses of the group, on the home page and the Businesses page. The link decides where each card goes: /shop, /software, /training, /trade#import_export, /contact …",
    list: ["image_url", "title", "code", "link", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10 },
    fields: [
      { k: "title", label: "Name", required: true }, { k: "code", label: "Short label", help: "e.g. SOFTWARE" }, { k: "link", label: "Link" }, { k: "slug", label: "Key (optional)" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "image_url", label: "Photo", type: "image" }, { k: "icon_url", label: "Icon", type: "image" },
      { k: "video_url", label: "Promo video (Instagram-reel size 9:16)", type: "image", help: "Any phone video up to 3 minutes — it is resized to 720 × 1280 and made web-ready before upload (keep the screen open while it prepares). Shown on the public website only (home, Software and Gallery pages) — never in the customer KMR Apps panel." }, { k: "video_poster", label: "Video thumbnail (9:16 photo — 1080 × 1920 best)", type: "image", help: "Shown on the card with a ▶ play button" },
      { k: "description", label: "Description", type: "textarea", wide: true },
    ] },
  // ---------------- Shop ----------------
  { key: "products", table: "products", group: "shop", label: "Shop products", singular: "product", roles: SALES, visible: "is_active", scope: { business: "shop" }, preview: productPreview,
    intro: "Goods sold online. Customers pay online (UPI, cards, net banking) or by bank transfer; stock goes down when an order is paid.",
    list: [...productList.slice(0, 4), "stock_quantity", "is_active"], order: ["sort_order", true], search: ["name", "sku", "category"],
    defaults: { ...on, kind: "goods", price: 0, stock_quantity: 0, sort_order: 100, unit: "nos" },
    fields: productFields([["goods", "Goods"], ["service", "Service"]], [
      { k: "stock_quantity", label: "In stock", type: "number" }, { k: "unit", label: "Unit", help: "nos, kg, set …" },
      { k: "enquiry_only", label: "Enquiry only (no online order)", type: "bool" },
    ]) },
  // ---------------- Software ----------------
  { key: "apps", table: "app_listings", group: "software", label: "KMR Apps on the website", singular: "app listing", roles: SALES, visible: "is_active", noCreate: true, noDelete: true,
    sitePath: "/software", titleOf: ["name"], preview: (r) => `/software#${r.code}`,
    intro: "How each KMR App appears on the home page and the Software page: picture, one-line benefit, key features, order and show / hide. Every app under Products & versions is listed here automatically. Prices come from Billing › Price list (per user / employee, monthly and yearly). The photo is also shown on each customer’s KMR Apps panel. A short promo video (Instagram-reel size, 9:16) with its thumbnail plays on the public website only — it is never shown in the customer panel. Without a photo, a simple illustration is shown.",
    list: ["image_url", "name", "tagline", "sort_order", "is_active"], order: ["sort_order", true], search: ["name", "tagline"],
    fields: [
      { k: "name", label: "App", readonly: true }, { k: "code", label: "Code", readonly: true },
      { k: "tagline", label: "One-line benefit", wide: true, help: "What the customer gets, in one sentence (shown on the cards)" },
      { k: "features", label: "Key features — one per line", type: "textarea", wide: true, help: "Three or four lines read best" },
      { k: "image_url", label: "Photo", type: "image", help: "A real photo or screenshot, 16:10 looks best (shown when there is no video)" },
      { k: "video_url", label: "Promo video (Instagram-reel size 9:16)", type: "image", help: "Any phone video up to 3 minutes — it is resized to 720 × 1280 and made web-ready before upload (keep the screen open while it prepares). Shown on the public website only (home, Software and Gallery pages) — never in the customer KMR Apps panel." }, { k: "video_poster", label: "Video thumbnail (9:16 photo — 1080 × 1920 best)", type: "image", help: "Shown on the card with a ▶ play button" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show on the website", type: "bool" },
    ] },
  { key: "solutions", table: "products", group: "software", label: "Software solutions", singular: "solution", roles: SALES, visible: "is_active", scope: { business: "software" }, preview: productPreview,
    intro: "Solutions and services on the Software page (custom software, ERP set-up, AI projects …). KMR Apps are edited under “KMR Apps on the website”; their prices under Billing › Price list.",
    list: productList, order: ["sort_order", true], search: ["name", "category"], defaults: { ...on, kind: "service", price: 0, enquiry_only: true, sort_order: 100 },
    fields: productFields([["service", "Service / project"], ["goods", "Licence / package"]], [{ k: "enquiry_only", label: "Enquiry only (request a demo / quote)", type: "bool" }]) },
  // ---------------- Training ----------------
  { key: "programmes", table: "products", group: "training", label: "Programmes", singular: "programme", roles: SALES, visible: "is_active", scope: { business: "training" }, preview: productPreview,
    intro: "Courses and training programmes. With a price, participants enrol and pay online; with price 0 or “enquiry only”, they send an enquiry.",
    list: productList, order: ["sort_order", true], search: ["name", "category"], defaults: { ...on, kind: "course", price: 0, sort_order: 100, unit: "seat" },
    fields: productFields([["course", "Course"], ["service", "Corporate training"]], [{ k: "enquiry_only", label: "Enquiry only", type: "bool" }]) },
  // ---------------- Trade ----------------
  { key: "trade", table: "products", group: "trade", label: "Trade items", singular: "item", roles: SALES, visible: "is_active", preview: productPreview,
    intro: "Import & export, trading and distribution items. Always quoted on request.",
    list: ["image_url", "name", "business", "category", "is_active"], order: ["sort_order", true], search: ["name", "sku", "category"],
    filter: { k: "business", label: "Business", opts: [["import_export", "Import & Export"], ["trading", "Trading & Retail"], ["distribution", "Distribution"]], restrict: true },
    defaults: { ...on, business: "import_export", kind: "goods", price: 0, enquiry_only: true, sort_order: 100, unit: "nos" },
    fields: [
      { k: "business", label: "Business", type: "select", required: true, opts: [["import_export", "Import & Export"], ["trading", "Trading & Retail"], ["distribution", "Distribution"]] },
      ...productFields([["goods", "Goods"], ["service", "Service"]], [{ k: "unit", label: "Unit" }]),
    ] },
  // ---------------- Careers ----------------
  { key: "jobs", table: "job_openings", group: "careers", label: "Job openings", singular: "opening", roles: ALL, visible: "is_active", preview: (r) => `/careers/${r.id}`,
    intro: "Openings on the Careers page. An opening disappears from the website when hidden or after its closing date.",
    list: ["title", "department", "location", "employment_type", "closes_on", "is_active"], order: ["sort_order", true], search: ["title", "department", "location"],
    defaults: { ...on, employment_type: "Full-time", sort_order: 10 },
    fields: [
      { k: "title", label: "Job title", required: true, wide: true }, { k: "department", label: "Department" }, { k: "location", label: "Location" },
      { k: "employment_type", label: "Type", type: "select", opts: [["Full-time", "Full-time"], ["Part-time", "Part-time"], ["Contract", "Contract"], ["Internship", "Internship"], ["Apprentice", "Apprentice"]] },
      { k: "experience", label: "Experience", help: "e.g. 3–5 years" }, { k: "salary_range", label: "Salary (optional)" },
      { k: "posted_on", label: "Posted on", type: "date" }, { k: "closes_on", label: "Closes on (optional)", type: "date" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show on the website", type: "bool" },
      { k: "summary", label: "One-line summary", wide: true }, { k: "description", label: "About the role", type: "longtext", wide: true },
      { k: "requirements", label: "Requirements", type: "textarea", wide: true, help: "One per line" },
    ] },
  { key: "applications", table: "job_applications", group: "careers", label: "Applications", singular: "application", roles: ALL, noCreate: true,
    intro: "Applications sent from the Careers page. Résumés are stored privately and open with a link that expires.",
    list: ["created_at", "name", "job_title", "experience", "status"], order: ["created_at", false], search: ["name", "email", "job_title"], titleOf: ["name"],
    filter: { k: "status", label: "Status", opts: [["new", "New"], ["shortlisted", "Shortlisted"], ["interview", "Interview"], ["offered", "Offered"], ["hired", "Hired"], ["rejected", "Rejected"]] },
    fields: [
      { k: "status", label: "Status", type: "select", required: true, opts: [["new", "New"], ["shortlisted", "Shortlisted"], ["interview", "Interview"], ["offered", "Offered"], ["hired", "Hired"], ["rejected", "Rejected"]] },
      { k: "job_title", label: "Applied for", readonly: true }, { k: "name", label: "Name", readonly: true }, { k: "email", label: "Email", readonly: true },
      { k: "phone", label: "Phone", readonly: true }, { k: "location", label: "Location", readonly: true }, { k: "experience", label: "Experience", readonly: true },
      { k: "current_company", label: "Current company", readonly: true }, { k: "linkedin_url", label: "LinkedIn", readonly: true },
      { k: "resume_path", label: "Résumé", type: "document", bucket: "careers", readonly: true },
      { k: "cover_note", label: "Message", type: "textarea", wide: true, readonly: true },
      { k: "notes", label: "Internal notes (not seen by the applicant)", type: "textarea", wide: true },
    ] },
  // ---------------- About ----------------
  { key: "leadership", table: "leaders", group: "about", label: "Leadership team", singular: "person", roles: ALL, visible: "is_active",
    intro: "People on the About and Leadership pages.", list: ["photo_url", "name", "designation", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10 },
    fields: [
      { k: "name", label: "Name", required: true }, { k: "designation", label: "Designation", required: true }, { k: "linkedin_url", label: "LinkedIn", type: "url" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "photo_url", label: "Photo", type: "image" }, { k: "bio", label: "Bio", type: "textarea", wide: true },
    ] },
  { key: "gallery", table: "gallery_items", group: "about", label: "Gallery", singular: "photo or video", roles: ALL, visible: "is_active",
    intro: "Photos and videos on the Gallery page — and the video library: every promo video saved on an app, business, product or programme is added here automatically (\u201cUsed on\u201d shows where), and any video here can be picked for those cards with \u201cChoose from gallery…\u201d. Untick Show to keep a video out of the public Gallery page; it stays pickable.", list: ["media_url", "title", "media_type", "used_for", "is_active"], order: ["sort_order", true], defaults: { ...on, sort_order: 10, media_type: "photo" },
    fields: [
      { k: "title", label: "Caption" }, { k: "media_type", label: "Type", type: "select", opts: [["photo", "Photo"], ["video", "Video"]], required: true },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "media_url", label: "Photo / video", type: "image", required: true }, { k: "thumbnail_url", label: "Video cover image", type: "image" },
      { k: "used_for", label: "Used on", readonly: true, help: "Filled in automatically when the video is used on a card" },
    ] },
  // ---------------- Policies & records ----------------
  { key: "policies", table: "legal_pages", group: "policies", label: "Company policies", singular: "policy", roles: ALL, visible: "is_active", preview: (r) => `/policies/${r.slug}`,
    intro: "Terms, privacy, refund, shipping, grievance and any other policy (quality, HR, code of conduct …). Terms, Privacy, Refund, Shipping and Grievance are required for selling online in India — hide rather than delete them.",
    list: ["title", "slug", "show_in_footer", "updated_at", "is_active"], order: ["sort_order", true], defaults: { ...on, show_in_footer: false, sort_order: 50 },
    fields: [
      { k: "title", label: "Title", required: true }, { k: "slug", label: "Web address", required: true, help: "Letters, numbers and dashes — the page is /policies/<this>" },
      { k: "summary", label: "One-line summary", wide: true },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" }, { k: "show_in_footer", label: "Link in the footer", type: "bool" },
      { k: "content", label: "Content", type: "longtext", wide: true, help: "Blank line = new paragraph. Start a line with “# ” for a heading and “- ” for a bullet." },
    ] },
  { key: "records", table: "compliance_records", group: "policies", label: "Registrations & licences", singular: "record", roles: ALL,
    intro: "Private: GST, Udyam, trademark and licence documents with renewal dates. Not shown on the website.",
    list: ["category", "title", "reference_number", "expiry_date"], order: ["expiry_date", true], search: ["title", "reference_number"], defaults: { reminder_days_before: 30, category: "other" },
    fields: [
      { k: "category", label: "Category", type: "select", required: true, opts: [["gst", "GST"], ["udyam", "Udyam"], ["trademark", "Trademark"], ["employee_welfare", "Employee welfare"], ["pollution_control", "Pollution control"], ["local_body_license", "Local body licence"], ["invoicing", "Invoicing"], ["other", "Other"]] },
      { k: "title", label: "Title", required: true, wide: true }, { k: "reference_number", label: "Reference no." }, { k: "issuing_authority", label: "Issued by" },
      { k: "issue_date", label: "Issued on", type: "date" }, { k: "expiry_date", label: "Valid until", type: "date" },
      { k: "reminder_days_before", label: "Remind days before", type: "number" }, { k: "document_url", label: "Document (PDF / image)", type: "document", bucket: "records" },
      { k: "notes", label: "Notes", type: "textarea", wide: true },
    ] },
];

/** Extra pages of the CMS that are not simple lists. */
export const EXTRA: { href: string; label: string; group: GroupKey; roles: Role[] }[] = [
  { href: "/cms/orders", label: "Orders & payments", group: "shop", roles: SALES },
  { href: "/cms/payments", label: "Payment settings", group: "shop", roles: ALL },
];

export const sectionByKey = (k: string) => SECTIONS.find((s) => s.key === k);
export const BUSINESS_LABEL: Record<string, string> = {
  shop: "Online shop", software: "Software", training: "Training", import_export: "Import & Export", trading: "Trading & Retail", distribution: "Distribution",
};
export const canEdit = (s: Section, role: Role) => s.roles.includes(role);
