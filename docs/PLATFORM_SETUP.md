# KMR platform — setup (pilot, free plans) · Milestones 1 + 2

What you get: **KMR Console** at `www.kmr-groups.com/it/console` (customers, licences, products, staff) and
**HRM Suite** at `www.kmr-groups.com/it/hrm` for every customer company, controlled by Console licences.
Balloon Inspector and Process Documents (`/it/balloon.html`, `/it/pd.html`) are also controlled by Console licences.
Every workspace that exists today is adopted automatically as a **pilot** licence, so nobody is locked out.
`www.kmr-groups.com/it/` is the **KMR Apps** home listing all three apps. One KMR login (email + password) works in every app.

## 1. Supabase (project dehlcusptkzfhqvpfyjh) — 5 minutes

1. **Backup first:** Database → Backups (free plan keeps daily backups) — or ask for an export script.
2. Open `supabase/KMR_PLATFORM_SETUP.sql`. At the top, set **owner_email** to your existing login
   (the one you use for the website admin) and **owner_name**.
3. SQL Editor → New query → paste the whole file → **Run**. It ends with **KMR PLATFORM READY**.
   *Already ran the Milestone 1 version of this file?* Then run only `supabase/migrations/0002_quality_suite.sql`.
   It only *adds* the `console` and `hrm` sections; website and tool tables are not touched.
4. **Project Settings → Data API → Exposed schemas**: add `hrm` and `console` → Save.
5. **Project Settings → API Keys**: note the *publishable / anon* key and the *secret / service_role* key.

## 2. Vercel — two new projects (names matter)

Add New → Project → import each repo. If a repo is not listed: *Adjust GitHub App Permissions* → allow it.

**Project `kmr-hrm`** (repo `kmrgroups/kmr-hrm`) — Environment Variables (paste the block, fill the two keys):

```
NEXT_PUBLIC_SUPABASE_URL=https://dehlcusptkzfhqvpfyjh.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=paste-publishable-or-anon-key
SUPABASE_SERVICE_ROLE_KEY=paste-secret-or-service-role-key
NEXT_PUBLIC_BASE_PATH=/it/hrm
APP_PUBLIC_URL=https://www.kmr-groups.com/it/hrm
ALLOWED_ORIGINS=www.kmr-groups.com
APP_SECRET=paste-a-random-48-character-string   # openssl rand -base64 36
CRON_SECRET=paste-another-random-string
```
(Optional, for emails: `RESEND_API_KEY` and `EMAIL_FROM`.)

**Project `kmr-console`** (repo `kmrgroups/kmr-console`):

```
NEXT_PUBLIC_SUPABASE_URL=https://dehlcusptkzfhqvpfyjh.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=paste-publishable-or-anon-key
SUPABASE_SERVICE_ROLE_KEY=paste-secret-or-service-role-key
NEXT_PUBLIC_BASE_PATH=/it/console
ALLOWED_ORIGINS=www.kmr-groups.com
PLATFORM_URL=https://www.kmr-groups.com
```

Do **not** add a domain to either project. The website forwards `/it/hrm` and `/it/console` to
`https://kmr-hrm.vercel.app` and `https://kmr-console.vercel.app`. If Vercel gives a project a different
address, set `HRM_ORIGIN` / `CONSOLE_ORIGIN` on the **kmr-group-website** project and redeploy it.

## 3. Demo

1. Open `https://www.kmr-groups.com/it/console` → sign in with the owner login.
2. **Customers → New customer** (e.g. "Demo Engineering"), save.
3. On the customer's page: **Switch on HRM** → fill the administrator's email → *Create HRM company*.
   The message shows the sign-in link and a temporary password (shown once).
4. Open the link (`/it/hrm/login?co=…`) in a private window → sign in as that administrator → change the
   password → add employees, set up attendance and leave.
5. Back in the Console: **Change licence → suspended** → within a minute the customer sees *Access paused*.
   Set it back to *trial* and access returns, with all data intact.

## 4. Demo — Balloon Inspector / Process Documents (Milestone 2)

1. Console → **Customers** — your existing tool workspaces are listed as pilot customers.
2. Open a customer → **Switch on Balloon Inspector** (or Process Documents) → administrator email → create.
   The message shows the sign-in address and, for a new login, a temporary password.
3. Sign in at `/it/balloon.html` — the workspace is there; the administrator adds colleagues under Admin → Users
   (up to the licence's user limit).
4. Console → **Change licence → suspended** → the tool shows *Access paused* and the database refuses its data.
   Back to *pilot* → everything returns.

Workspaces created inside the tools (Admin → Companies) appear in the Console automatically with a 30-day trial.

## 5. Milestone 3 — service layer (tickets, release notes, pilot requests)

*Already ran the platform setup?* Run **`supabase/migrations/0003_service.sql`** once in the SQL Editor
(the full `KMR_PLATFORM_SETUP.sql` already includes it for new projects).

- **HRM → Help & support** (left menu, for everyone): raise a ticket, follow KMR's replies, see *What's new*.
- **Console → Support tickets**: reply, set status / priority, assign to a colleague. The customer sees replies in the HRM.
- **Console → Pilot requests**: requests from the form at the bottom of `www.kmr-groups.com/it/`.
  *Convert to customer* opens it as a Console customer, ready for *Switch on HRM / Balloon / PD*.

## 6. Demo data (for sales demos and testing)

- **Load:** `supabase/demo/DEMO_DATA.sql` — set `demo_company` at the top to the short name of an HRM company you
  created in the Console (e.g. `demo-engineering`), run it, then in the HRM: *Attendance → Recalculate attendance*
  (from 30 days ago to today). You get 24 employees in two plants, a month of biometric punches (late arrivals,
  a missed punch, night shifts), leave balances, pending leave and correction requests, 6 demo customers across
  India / Germany / USA / UAE, 2 support tickets and 2 pilot requests.
- **Remove:** `supabase/demo/DEMO_FLUSH.sql` — deletes only what the demo added (tagged `demo.kmr.test` /
  `KMR demo data`). Real companies, employees and customers are untouched. Load again any time.

## 7. Customer portal — one link per customer

*Already ran the platform setup?* Run **`supabase/migrations/0004_portal.sql`** once.

- Console → customer → **Customer portal**: the customer's personal link `www.kmr-groups.com/it/app/<name>`
  (change the name if you like) and **Upload logo** (shown on their sign-in and header).
- The customer signs in there with their KMR login (the same email and password as in their apps) and sees:
  **Your apps** (from their Console licences) with *Open*; **More KMR apps** — clicking one shows
  *Not in your plan* with **Try with sample data** and **Buy subscription**; upcoming modules marked *Soon*.
- Opening the HRM from the portal signs them in automatically (no second sign-in).
- **HRM sample data for non-customers (optional):** create a customer "KMR Demo" in the Console, *Switch on HRM*
  with an administrator such as `demo@kmr-groups.com`, load `supabase/demo/DEMO_DATA.sql` for its short name,
  then in Vercel → kmr-hrm → Environment Variables add `HRM_DEMO_EMAIL=demo@kmr-groups.com` and redeploy.
  Without it, *Try with sample data* for the HRM is simply switched off.

## 8. Data tools — sample data, JSON, nightly backups (every product)

*Already ran the platform setup?* In the SQL Editor run, once each:
**`kmr-hrm/supabase/migrations/0003_data_tools.sql`** and **`kmr-console/supabase/migrations/0005_data_tools.sql`**
(and `0004_portal.sql` if not yet done).

- **HRM → Settings → Data & backups** (company administrators): *Load sample data* / *Flush sample data*,
  *Download JSON now*, *Restore from a JSON file* (same company; a safety copy is saved first), nightly backups list.
- **Console → Data & backups** (owners / administrators): the same for the Console.
- **Nightly at 12 AM India time** each company's HRM data and the Console data are backed up automatically (kept 7 days).
  The first time an administrator opens the app after that, the latest backup downloads to their computer
  (can be switched off per computer on the Data & backups page).
- Console: add `CRON_SECRET` (any long random text) to the kmr-console project in Vercel to protect its backup job.

## 9. Portal behaviour and dashboards

Run **`supabase/migrations/0006_portal_dashboards.sql`** once.
- Tools not bought (or paused) open straight away with **sample data**, with a banner; *Use my company's data*
  shows the subscription screen with *Buy subscription*.
- Opening a bought tool from the portal needs **no second sign-in**; the HRM only admits that customer's people.
- Every tool shows **"← KMR Apps"** to return to the customer's own screen.
- Each tool's card on the portal shows its live figures (HRM: employees, in today, awaiting approval;
  Balloon Inspector: reports, users; Process Documents: projects, users). Every new tool adds its figures.

## 10. Customer Administration (M6) — one user list, one company profile

Run **`supabase/migrations/0011_customer_admin.sql`** once. It imports everyone who already has access to a tool.
- Customer portal → **Administration** (company administrators only; the main contact always is one):
  **Company details & logo** — saved once, pushed to every tool of that customer (also when KMR staff change them in the Console);
  **Users & access** — add a person once and choose their role in each tool; access inside every tool follows automatically.
- Tools no longer manage users or company branding: Balloon Inspector's Admin opens KMR Apps › Administration,
  Process Documents' Admin keeps only document settings, the Capacity Planner and the HRM show the company from
  Administration. HRM employees' own self-service logins are still created by HR onboarding.

## 11. Operations Master (M7)

Run **`supabase/migrations/0015_operations_master.sql`** once (needs 0011).
- KMR Apps › **Masters › Operations Master**: parts, customers, suppliers, machines, gauges, tools, consumables, raw material,
  rate contracts, cycle times, CFT team & key contacts, documents & records (with the file). Search, add, edit, delete,
  CSV export / import (import updates existing codes, adds new ones).
- Access in **Administration › Users & access → Operations Master**: admin / editor / viewer. Company administrators always
  have full access; people without a role do not see it.
- Next step (M7b): the tools read these masters instead of keeping their own copies.

## 12. Capacity Planner uses the Operations Master (M7b)

Run **`supabase/migrations/0016_capacity_masters.sql`** once (needs 0015).
- The planner reads **Machines**, **Parts**, **Cycle times** and the new **Plant standards** from KMR Apps › Operations Master,
  and **holidays** from the customer's HRM holiday calendar (weekly off from Plant standards). Its Masters page is read-only.
- A planner that already had its own masters shows **Move to Operations Master** (administrators, once; never overwrites).
- The planner keeps only its monthly plans.

## 9. Milestone 4 — prices, invoices and payments to KMR's bank account

*Already ran the platform setup?* Run **`supabase/migrations/0018_billing.sql`** and then
**`supabase/migrations/0019_bank_payments.sql`** once each in the SQL Editor.

1. **Console → Prices & invoices → Seller details**: legal name, GSTIN, GST-registered address, state + state code, PAN,
   invoice prefix (numbers look like `KMR/26-27/0001`, restarting every April), and the **bank account** customers pay
   into (account name, number, IFSC, bank, branch, SWIFT for customers abroad) plus a **UPI ID** if the account has one.
   Without a GSTIN no GST is charged. An invoice can't be issued until an address and a bank account or UPI ID are set.
2. **Price list**: for each product a price per user (per employee for the HRM), monthly and/or yearly, in every
   currency you sell in (customers are billed in their own currency), with a minimum billed.
3. **Customer → Billing → Create invoice**: tick the products, users / employees and period → a draft with GST worked
   out (CGST + SGST in your state, IGST for other states, zero-rated export under LUT abroad). Add a line (training,
   set-up), then **Issue**. Issued invoices can't be edited — cancel and re-issue instead; the number stays in the series.
4. **Getting paid**: every issued invoice has a **pay link** (`/it/console/pay/…`) showing the invoice, your bank account
   with copy buttons, and — with a UPI ID — a **UPI QR with the amount and invoice number filled in**. The customer
   pays from their bank or UPI app and taps **I've paid** with the UTR / reference. The customer's administrators also
   see their invoices in their KMR portal under *Invoices & payments*.
5. **Confirming**: the Console shows **Payment reported — check your bank** on the invoice (and *payment to verify* in the
   list). Find the UTR / amount in your bank statement, then **Confirm** (invoice paid, licences active until the end of
   the paid period with the paid limit) or **Reject** with a reason the customer sees. Money that arrives without a report
   (cheque, direct transfer): **Mark as paid** with the reference.
