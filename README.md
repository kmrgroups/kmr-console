# KMR Console

Back office for KMR Group of Companies' software products: customers, licences (which company may use
which product, until when, for how many), product versions, and KMR staff. Products check their licences here.

- Served at `www.kmr-groups.com/it/console` (the website forwards the path).
- Database: schema `console` in the KMR Supabase project, next to `hrm` and the tools' tables.
- Setup: **docs/PLATFORM_SETUP.md**. One-time database setup: `supabase/KMR_PLATFORM_SETUP.sql`.

Milestones: 1 Console + HRM licences ✓ · 2 Balloon Inspector & Process Documents under Console licences,
one login across apps ✓ · 3 support tickets, releases, pilot requests from the website · 4 prices, test payments and
invoices · 5 hardening.
