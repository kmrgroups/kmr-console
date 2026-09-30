/**
 * The website's and the old website admin's tables, managed from the KMR Console (Website and Operations).
 * One definition per table drives the list, the form and saving. Writes go through the Console server with the
 * service key, after the staff member's role is checked (lib/manage-server.ts).
 */
export type FieldType = "text" | "textarea" | "number" | "money" | "bool" | "date" | "select" | "image" | "document" | "url" | "ref";
export interface Field {
  k: string; label: string; type?: FieldType; required?: boolean; help?: string; wide?: boolean;
  opts?: [string, string][];               // select: [value, label]
  ref?: { table: string; label: string };  // ref: another table's id, shown by its label column
}
export interface Resource {
  key: string; table: string; section: "website" | "operations"; label: string; singular: string; intro: string;
  fields: Field[]; list: string[]; order: [string, boolean]; search?: string[]; filter?: { k: string; label: string; opts: [string, string][] };
  single?: boolean; noCreate?: boolean; noDelete?: boolean; roles: ("owner" | "admin" | "sales" | "support")[];
  defaults?: Record<string, string | number | boolean>;   // a new record starts with these
}

export const BUSINESSES: [string, string][] = [
  ["shop", "Online shop"], ["training", "Training & Education"], ["import_export", "Import & Export"], ["trading", "Trading & Retail"], ["distribution", "Distribution"],
];
const MANAGERS: Resource["roles"] = ["owner", "admin"];
const SALES: Resource["roles"] = ["owner", "admin", "sales"];

export const RESOURCES: Resource[] = [
  // ---------------- Website ----------------
  { key: "products", table: "products", section: "website", label: "Products", singular: "product", roles: SALES,
    intro: "Everything the website sells or quotes for: shop goods (bought online), courses, and enquiry-only trade items. Hidden products are not shown on the website.",
    list: ["image_url", "name", "sku", "business", "price", "stock_quantity", "is_active"], order: ["sort_order", true], search: ["name", "sku", "category"],
    filter: { k: "business", label: "Business", opts: BUSINESSES },
    defaults: { business: "shop", kind: "goods", price: 0, stock_quantity: 0, sort_order: 100, is_active: true, unit: "nos" },
    fields: [
      { k: "name", label: "Name", required: true, wide: true },
      { k: "business", label: "Business", type: "select", opts: BUSINESSES, required: true },
      { k: "kind", label: "Type", type: "select", opts: [["goods", "Goods"], ["course", "Course / training"], ["service", "Service"]], required: true },
      { k: "sku", label: "SKU / code" }, { k: "category", label: "Category" },
      { k: "price", label: "Price (₹, incl. GST)", type: "money", required: true }, { k: "mrp", label: "MRP (₹)", type: "money" },
      { k: "stock_quantity", label: "In stock", type: "number", help: "Goods only; reduced when an order is paid" },
      { k: "unit", label: "Unit", help: "nos, kg, set, seat …" }, { k: "hsn_code", label: "HSN / SAC" },
      { k: "enquiry_only", label: "Enquiry only (request a quote, no online order)", type: "bool" },
      { k: "is_active", label: "Show on the website", type: "bool" }, { k: "featured", label: "Feature on the home page", type: "bool" },
      { k: "sort_order", label: "Order in lists", type: "number" },
      { k: "image_url", label: "Photo", type: "image" },
      { k: "description", label: "Description", type: "textarea", wide: true },
    ] },
  { key: "hero", table: "hero_content", section: "website", label: "Home page banner", singular: "banner", roles: MANAGERS, single: true, noDelete: true,
    intro: "The banner image and headline at the top of the home page.", list: ["headline"], order: ["updated_at", false],
    fields: [
      { k: "headline", label: "Headline", required: true, wide: true }, { k: "subheadline", label: "Sub-headline", type: "textarea", wide: true },
      { k: "cta_label", label: "Button text" }, { k: "cta_link", label: "Button link", help: "e.g. /shop or /software" },
      { k: "banner_image_url", label: "Banner image", type: "image" },
    ] },
  { key: "businesses", table: "verticals", section: "website", label: "Businesses", singular: "business", roles: MANAGERS,
    intro: "The business cards on the home page and the Businesses page. The link decides where each card goes (/shop, /software, /training, /trade#import_export …).",
    list: ["icon_url", "title", "code", "link", "is_active"], order: ["sort_order", true], defaults: { sort_order: 10, is_active: true },
    fields: [
      { k: "title", label: "Name", required: true }, { k: "code", label: "Short label" }, { k: "link", label: "Link" }, { k: "slug", label: "Key" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "is_active", label: "Show", type: "bool" },
      { k: "icon_url", label: "Icon / image", type: "image" }, { k: "description", label: "Description", type: "textarea", wide: true },
    ] },
  { key: "leadership", table: "leaders", section: "website", label: "Leadership", singular: "person", roles: MANAGERS,
    intro: "People on the Leadership page.", list: ["photo_url", "name", "designation"], order: ["sort_order", true], defaults: { sort_order: 10 },
    fields: [
      { k: "name", label: "Name", required: true }, { k: "designation", label: "Designation", required: true }, { k: "linkedin_url", label: "LinkedIn", type: "url" },
      { k: "sort_order", label: "Order", type: "number" }, { k: "photo_url", label: "Photo", type: "image" }, { k: "bio", label: "Bio", type: "textarea", wide: true },
    ] },
  { key: "gallery", table: "gallery_items", section: "website", label: "Gallery", singular: "item", roles: MANAGERS,
    intro: "Photos and videos on the Gallery page.", list: ["media_url", "title", "media_type"], order: ["sort_order", true], defaults: { sort_order: 10, media_type: "photo" },
    fields: [
      { k: "title", label: "Title" }, { k: "media_type", label: "Type", type: "select", opts: [["photo", "Photo"], ["video", "Video"]], required: true },
      { k: "sort_order", label: "Order", type: "number" }, { k: "media_url", label: "Photo / video", type: "image", required: true }, { k: "thumbnail_url", label: "Video thumbnail", type: "image" },
    ] },
  { key: "legal", table: "legal_pages", section: "website", label: "Legal pages", singular: "page", roles: MANAGERS, noCreate: true, noDelete: true,
    intro: "Terms, privacy, refund, shipping and grievance pages (required for selling online in India).", list: ["title", "slug", "updated_at"], order: ["slug", true],
    fields: [{ k: "title", label: "Title", required: true, wide: true }, { k: "content", label: "Content", type: "textarea", wide: true }] },
  { key: "company", table: "company_info", section: "website", label: "Company info", singular: "company info", roles: MANAGERS, single: true, noDelete: true,
    intro: "Shown across the website (About, Contact, footer, map). It is public — never put Aadhaar, PAN or bank numbers here.", list: ["trade_name"], order: ["updated_at", false],
    fields: [
      { k: "trade_name", label: "Trade name" }, { k: "brand_name", label: "Brand name (menu)" }, { k: "legal_name", label: "Legal name" },
      { k: "constitution", label: "Constitution" }, { k: "proprietor_name", label: "Proprietor / director" }, { k: "proprietor_title", label: "Their title" },
      { k: "gstin", label: "GSTIN" }, { k: "udyam_number", label: "Udyam no." }, { k: "msme_category", label: "MSME category" }, { k: "cin", label: "CIN / LLPIN" },
      { k: "trademark_status", label: "Trademark", wide: true },
      { k: "registered_address", label: "Address (street)", wide: true }, { k: "city", label: "City / town" }, { k: "state", label: "State" }, { k: "postal_code", label: "PIN" },
      { k: "email", label: "Email" }, { k: "phone", label: "Phone" }, { k: "whatsapp_number", label: "WhatsApp (with country code, no +)" }, { k: "website_url", label: "Website", type: "url" },
      { k: "map_lat", label: "Map latitude", type: "number" }, { k: "map_lng", label: "Map longitude", type: "number" }, { k: "founded_year", label: "Founded", type: "number" },
      { k: "tagline", label: "Tagline" }, { k: "slogan", label: "Slogan" },
      { k: "short_about", label: "Footer text", type: "textarea", wide: true }, { k: "vision", label: "Vision", type: "textarea", wide: true }, { k: "mission", label: "Mission", type: "textarea", wide: true },
      { k: "facebook_url", label: "Facebook", type: "url" }, { k: "instagram_url", label: "Instagram", type: "url" }, { k: "linkedin_url", label: "LinkedIn", type: "url" },
      { k: "youtube_url", label: "YouTube", type: "url" }, { k: "twitter_url", label: "X / Twitter", type: "url" },
      { k: "logo_url", label: "Logo (menu and footer)", type: "image" }, { k: "logo_full_url", label: "Logo with businesses", type: "image" }, { k: "letterhead_url", label: "Letterhead", type: "image" },
    ] },
  { key: "compliance", table: "compliance_records", section: "website", label: "Compliance", singular: "record", roles: MANAGERS,
    intro: "Registrations, licences and renewals (GST, Udyam, trademark …) with reminders. Documents are stored privately.",
    list: ["category", "title", "reference_number", "expiry_date"], order: ["expiry_date", true], search: ["title", "reference_number"], defaults: { reminder_days_before: 30, category: "other" },
    filter: { k: "category", label: "Category", opts: [["gst", "GST"], ["udyam", "Udyam"], ["trademark", "Trademark"], ["employee_welfare", "Employee welfare"], ["pollution_control", "Pollution control"], ["local_body_license", "Local body licence"], ["invoicing", "Invoicing"], ["other", "Other"]] },
    fields: [
      { k: "category", label: "Category", type: "select", required: true, opts: [["gst", "GST"], ["udyam", "Udyam"], ["trademark", "Trademark"], ["employee_welfare", "Employee welfare"], ["pollution_control", "Pollution control"], ["local_body_license", "Local body licence"], ["invoicing", "Invoicing"], ["other", "Other"]] },
      { k: "title", label: "Title", required: true, wide: true }, { k: "reference_number", label: "Reference no." }, { k: "issuing_authority", label: "Issued by" },
      { k: "issue_date", label: "Issued on", type: "date" }, { k: "expiry_date", label: "Valid until", type: "date" },
      { k: "reminder_days_before", label: "Remind days before", type: "number" }, { k: "document_url", label: "Document (PDF / image)", type: "document" },
      { k: "notes", label: "Notes", type: "textarea", wide: true },
    ] },
  // ---------------- Operations ----------------
  { key: "customers", table: "customers", section: "operations", label: "Customers", singular: "customer", roles: SALES,
    intro: "Trading and shop customers (billing and shipping details).", list: ["name", "contact_person", "phone", "gstin", "is_active"], order: ["name", true], search: ["name", "contact_person", "email", "phone", "gstin"], defaults: { is_active: true },
    fields: [
      { k: "name", label: "Name", required: true, wide: true }, { k: "contact_person", label: "Contact person" }, { k: "email", label: "Email" }, { k: "phone", label: "Phone" }, { k: "gstin", label: "GSTIN" },
      { k: "is_active", label: "Active", type: "bool" }, { k: "billing_address", label: "Billing address", type: "textarea", wide: true },
      { k: "shipping_address", label: "Shipping address", type: "textarea", wide: true }, { k: "notes", label: "Notes", type: "textarea", wide: true },
    ] },
  { key: "vendors", table: "vendors", section: "operations", label: "Vendors", singular: "vendor", roles: SALES,
    intro: "Suppliers you buy from.", list: ["name", "contact_person", "phone", "gstin", "is_active"], order: ["name", true], search: ["name", "contact_person", "email", "phone", "gstin"], defaults: { is_active: true },
    fields: [
      { k: "name", label: "Name", required: true, wide: true }, { k: "contact_person", label: "Contact person" }, { k: "email", label: "Email" }, { k: "phone", label: "Phone" }, { k: "gstin", label: "GSTIN" },
      { k: "is_active", label: "Active", type: "bool" }, { k: "address", label: "Address", type: "textarea", wide: true }, { k: "notes", label: "Notes", type: "textarea", wide: true },
    ] },
  { key: "items", table: "inventory_items", section: "operations", label: "Inventory items", singular: "item", roles: SALES,
    intro: "Items you stock or trade. Stock levels come from Stock movements.", list: ["item_code", "name", "item_type", "unit_of_measure", "selling_price", "is_active"], order: ["item_code", true], search: ["item_code", "name", "category", "hsn_code"], defaults: { item_type: "trading", unit_of_measure: "nos", is_active: true, standard_cost: 0, selling_price: 0, reorder_level: 0 },
    filter: { k: "item_type", label: "Type", opts: [["raw_material", "Raw material"], ["finished_good", "Finished good"], ["trading", "Trading"], ["service", "Service"]] },
    fields: [
      { k: "item_code", label: "Item code", required: true }, { k: "name", label: "Name", required: true },
      { k: "item_type", label: "Type", type: "select", required: true, opts: [["raw_material", "Raw material"], ["finished_good", "Finished good"], ["trading", "Trading"], ["service", "Service"]] },
      { k: "category", label: "Category" }, { k: "unit_of_measure", label: "Unit", required: true }, { k: "hsn_code", label: "HSN code" },
      { k: "standard_cost", label: "Standard cost (₹)", type: "money" }, { k: "selling_price", label: "Selling price (₹)", type: "money" },
      { k: "reorder_level", label: "Reorder level", type: "number" }, { k: "is_active", label: "Active", type: "bool" },
    ] },
  { key: "warehouses", table: "warehouses", section: "operations", label: "Warehouses", singular: "warehouse", roles: SALES,
    intro: "Where stock is kept.", list: ["name", "address", "is_active"], order: ["name", true], defaults: { is_active: true },
    fields: [{ k: "name", label: "Name", required: true }, { k: "is_active", label: "Active", type: "bool" }, { k: "address", label: "Address", type: "textarea", wide: true }] },
  { key: "employees", table: "employees", section: "operations", label: "Employees (KMR)", singular: "employee", roles: MANAGERS,
    intro: "KMR's own staff register from the old website admin. Customer companies use the HRM for their employees.",
    list: ["employee_code", "full_name", "department", "designation", "is_active"], order: ["employee_code", true], search: ["employee_code", "full_name", "email", "phone"], defaults: { is_active: true },
    fields: [
      { k: "employee_code", label: "Employee code", required: true }, { k: "full_name", label: "Full name", required: true }, { k: "department", label: "Department" },
      { k: "designation", label: "Designation" }, { k: "email", label: "Email" }, { k: "phone", label: "Phone" }, { k: "date_of_joining", label: "Joined on", type: "date" },
      { k: "pf_number", label: "PF number" }, { k: "is_active", label: "Active", type: "bool" },
    ] },
];

export const resourceByKey = (k: string) => RESOURCES.find((r) => r.key === k);
export const BUSINESS_LABEL = Object.fromEntries(BUSINESSES) as Record<string, string>;
