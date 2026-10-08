-- Re-sends every customer's name, details and logo to its tools (HRM company logo, favicon and PDFs).
-- Safe to run more than once. Fixes tools created before the logo was uploaded.
update console.customers set logo_url = logo_url where logo_url is not null;
