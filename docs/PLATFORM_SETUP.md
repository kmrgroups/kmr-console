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

## 10. Company identity on invoices (seal, signature, Udyam)

*Already ran the platform setup?* Run **`supabase/migrations/0020_seller_identity.sql`** once.

- **Console → Prices & invoices → Seller details**: trade name (invoices lead with it) and legal name, constitution,
  GSTIN, PAN, Udyam number and MSME category, website, authorised signatory (name, designation), and switches for the
  seal / signature and the MSME note (MSMED Act, 2006 — payment within 45 days).
- **Seal & signature**: upload PNGs (transparent background looks best). They are stored in the private `kmr-billing`
  bucket and shown only on invoices through links that expire. Issued invoices keep the seal / signature they were
  issued with; a new upload applies to invoices issued afterwards.

## 11. Website CMS (www.kmr-groups.com has no admin panel)

*Already ran the platform setup?* Run **`supabase/migrations/0021_website.sql`** once, then the website's
**`supabase/add-multi-business.sql`**, **`supabase/add-premium-site.sql`**, **`supabase/add-cms-update.sql`** and **`supabase/add-home-content.sql`** (in that order). The website's
**`supabase/drop-operations.sql`** permanently removes the old website Operations tables that nothing else uses (it keeps `employees`, which the HR module uses) — export them first if needed.

**Website CMS** (sidebar) manages every part of the website — add, edit, hide / show, delete:
- **Brand & company** — company profile (logo, GSTIN, Udyam, story, vision, mission, values), contact & social links
  (address, phones, email, WhatsApp, hours, map, LinkedIn / Facebook / Instagram / YouTube / X), founder photo & message.
- **Home page** — hero slides (the banner at the very top), highlight numbers, who we serve, why choose KMR, product
  benefits (productivity · quality · cost · delivery), how it works, header button and announcement bar.
- **Business verticals**, **Shop products**, **Software solutions**, **Training programmes**, **Trade items**.
- **Careers** — job openings and applications (résumés in the private `kmr-careers` bucket, opened with expiring links).
- **About us** — leadership team, gallery. **Policies & records** — any number of policies (footer link on / off) and
  private registrations & licences.
- **Orders & payments** and **Payment settings** (Online shop group). Customers' Operations Master data is confidential and is never copied to the website.
- **Sample content** (Overview): load example slides, products, jobs, people and photos, and remove them in one click.
- Photos upload straight from the browser to storage with a progress bar (up to 25 MB) and are shown whole on the website — never cropped.
- Owner / admin edit everything; sales edit products, programmes, solutions, trade items and orders; support can view.

**Payments** (Website CMS › Payment settings):
- *Bank transfer / UPI* — the account and UPI ID in **Prices & invoices › Seller details** (Federal Bank). The page shows
  a ₹1 test QR so you can check the payee name before going live.
- *Online (Razorpay)* — set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` in the **website's**
  Vercel project, add the webhook `https://www.kmr-groups.com/api/pay/razorpay/webhook` (events *payment.captured*,
  *order.paid*), and make sure Razorpay's settlement bank account is the same Federal Bank account. Then tick
  *Online payment*. Every online payment is checked with Razorpay (signature, order, amount) before the order is paid.

## 12. Milestone 5 — safety, emails, health (run `supabase/migrations/0022_hardening.sql` once)

**Add these in Vercel to the kmr-console and website projects (not the HRM — each HRM customer sends from its own
mailbox, set up in HRM › Settings › Company email), then Redeploy:**

```
RESEND_API_KEY=re_…                 # same key the HRM uses (resend.com › API keys)
EMAIL_FROM=KMR Group of Companies <no-reply@kmr-groups.com>   # domain verified in Resend
ALERT_EMAIL=info@kmr-groups.com      # where KMR's own notices go (orders, payments, enquiries, errors)
```
and in kmr-console only: `CRON_SECRET=` any long random text (without it the nightly backup now refuses to run).

What happens automatically:
- **Emails** — invoice issued (with pay link), payment received / rejected, support ticket replies, shop order
  placed / paid / rejected, payment reported (to KMR), enquiries and pilot requests (KMR + thank-you to the customer),
  job applications (KMR + applicant). Without the keys nothing is sent and the Console shows "skipped".
- **Protection** — too many sign-ins, orders, payment reports or form posts from one place are refused for a while.
- **Error alerts** — server errors are recorded; one email per error per hour.
- **Backups** — every night, two files (Console + website data; customers' app data), kept 30 days.
- **Console › System health** — traffic lights for errors, emails, backups; **Console › Activity log** — who changed what.
- **Website** — security headers, `sitemap.xml`, `robots.txt`, company details for Google, Vercel Analytics
  (switch on under Vercel › the website project › Analytics).

## 13. Test data (Console › Test data — owner only)

Run `supabase/migrations/0023_test_data.sql` once (after 0022), and the website's `supabase/fix-order-link.sql`.

1. **Download settings (.json)** — KMR products, prices, seller details, platform settings and all website content.
   **Upload** the same file to put them back (staff logins are never changed).
2. **Load demo data everywhere** — Console sample customers, website sample content, and the demo customer
   *KMR Demo Manufacturing* with a live HRM company (24 employees, a month of attendance), Balloon Inspector,
   Process Documents and Capacity Planner workspaces and Operations Master sample data — one login for all of them
   (password shown once). **Remove demo data** takes out exactly that.
3. **Clean out** (type FLUSH) — removes customers, invoices, payments, tickets, enquiries, orders, applications,
   app workspaces, HRM companies (KMR's own HRM company keeps its settings and administrators; set `KMR_HRM_SLUG` if its
   short name is not `kmr`), logs and unused logins. A full backup of every app is saved first and listed on the page.

## 14. Operations Master everywhere (run `supabase/migrations/0024_ops_links.sql` once)

- **Process Documents** reads machines, gauges and customers from the customer's Operations Master (read-only in the
  workspace, with an "Open Operations Master" button), and fills part name, drawing no., revision, material and
  customer from **Parts** when a new project starts. A workspace that typed its own lists first gets a one-time
  **Move to Operations Master** button. Consumables stay per workspace.
- **Operations Master › Download all (Excel)** — one sheet per list; **Upload Excel workbook** — existing codes are
  updated, new ones added, nothing is deleted.
- New fields: Machines — capacity, processes it can do, max job size, capability, PM frequency; Customers — our
  supplier code, address, their CC / SC symbols, engineering approval.

## 15. Operations Master is the only source (run `supabase/migrations/0025_ops_sample_per_list.sql`)

- Every list has its own **Load sample … / Flush sample …** button (administrators). Flush removes only sample
  records; anything you added or changed stays. Uploading a downloaded workbook unchanged keeps sample records as sample.
- Process Documents and Capacity Planner linked to a customer use **only** the Operations Master: an empty list there
  is an empty list in the app (no built-in machines or consumables). Earlier lists typed into an app are kept aside
  and offered once through **Move to Operations Master**.
- Consumables have **Used in processes** (e.g. TURN1, VMC, WASH) so Process Documents lists them per operation.

## 16. Data Master (run `supabase/migrations/0026_data_master.sql`, after HRM 0005 and Console 0025)

KMR Apps › Masters › **Data Master** (company administrators): one card per app — HRM, Balloon Inspector, Process
Documents, Capacity Planner and the Operations Master — with the number of records, **Download JSON**, **Upload JSON**
(replaces that app's data with the file; a file of another app or another company is refused) and **Flush all data**
(type FLUSH; a JSON backup is downloaded first, then the data is removed). Logins, users and access are never removed.
HRM flush can also reset the company setup (plants, departments, shifts, leave types, holidays, payroll rules) to the
defaults. Balloon Inspector drawing files are kept so a restore brings reports back complete.

## 17. Operations Master card buttons and sample drawing (run `supabase/migrations/0027_ops_card_actions.sql`, after 0026)

Every Operations Master card now shows how many records are **sample** and how many are **yours**, with four buttons:

- **Load sample** / **Flush sample** — only that list's sample records (company administrators).
- **Load data** — upload a JSON file for that list (a file from Flush data, a Data Master backup, or a plain list).
  Existing codes are updated, new ones added.
- **Flush data** — removes your own (non-sample) records of that list. A JSON backup downloads automatically first;
  use Load data with that file to bring them back.

The **Balloon Inspector drawings** card (companies with Balloon Inspector; run `0028_balloon_card_data.sql` too) has
the same four buttons:

- **Load sample** adds a ready-made drawing, Mounting Plate EX-2040, to the company's Balloon Inspector reports; opening
  it there balloons it automatically. **Flush sample** removes it. The drawing file lives on the website
  (`/it/balloon/samples/`), so no storage upload is needed.
- **Flush data** removes the company's own reports (everything except the sample). A JSON backup downloads first;
  drawing files stay in storage. **Load data** with that file (or a Data Master Balloon backup) brings them back.

## 18. Grand Master (run `supabase/migrations/0029_grand_master.sql`, after 0028)

KMR Apps › Masters › **Grand Master** (company administrators), three cards for the whole company:

1. **Real Data Master** — everything the team created in every app (HRM, Balloon Inspector, Process Documents,
   Capacity Planner, Operations Master), not the sample data. **Download JSON** saves one file for all apps.
   **Upload JSON** puts every app back as it was in that file. **Flush real data** (type FLUSH) downloads that file
   first, then removes the real data. Sample data, company setup, logins and access stay.
2. **Sample Data Master** — **Load sample data** fills every app at once (HRM sample employees with a month of
   attendance, the sample drawing, all Operations Master sample lists). **Flush sample data** removes only sample data.
   HRM works out the sample attendance through `/it/hrm/api/sample-attendance` (needs the HRM app deployed).
3. **Administration Data** — company details & logo, users & access, invoices & payments. **Download JSON**,
   **Upload JSON** and **Flush admin data** (choose the parts; the backup downloads first). The company name, you and
   the main contact always stay; logins are never deleted. Invoices and payments are KMR's tax records: company
   administrators can download them, only KMR staff can flush or restore them.

## 19. HRM recruitment (run HRM `0006_recruitment.sql`, then `supabase/migrations/0030_hrm_recruitment.sql`)

HRM Phase 4 adds Recruitment (requisitions, job descriptions, resume scoring, careers page, interviews, offers). On the
platform:

- KMR Apps › Users & access can give the HRM role **Interviewer**: they sit on interview panels and fill in scorecards,
  and see nothing else in HRM.
- Data Master and Grand Master flushes of HRM also clear recruitment data. Resume files stay in storage (bucket
  `hrm-resumes`), so a restore brings them back.
- The HRM's daily recruitment job (`/it/hrm/api/cron/recruitment`, about 8:30 AM IST) sends interview reminders and
  regret messages and lapses old offers. It needs `CRON_SECRET` set in the HRM's Vercel project (same as the existing
  nightly job).

## 20. Sample data through the whole flow (run HRM `0007_sample_flow.sql`, then `supabase/migrations/0031_sample_flow.sql`)

Grand Master › Sample Data Master › **Load sample data** (and Console › Test data) now fill every HRM module that is
built, joined up with each other:

- 24 sample employees in two plants, a month of attendance, leave and pending requests, salaries and two loans (as before).
- The hiring flow: 3 openings with approved job descriptions (one waiting for approval), 10 candidates with resumes
  scored by the HRM's own engine, and one at every stage — new, shortlisted against the recommendation, on hold,
  declined with the regret sent, interview coming up, interview done with the panel's scorecard, offer sent, offer
  declined, offer accepted. The accepted one is a new joiner on the employee list with the salary from the offer.
- Pressing **Load sample data** again on a company that already has the sample employees adds the missing parts.
- Everything sample shows a **Sample** tag in HRM, never appears on the public careers page, and is never messaged:
  sample e-mails end in `@demo.kmr.test`, and the HRM skips every e-mail and WhatsApp to them (a made-up mobile
  number might belong to a real person).
- **Flush sample data** removes all of it. **Flush real data** keeps it. The Data Master's full HRM flush removes both.
- Each new HRM module adds its own sample data to `hrm.demo_flow`, so this button keeps covering everything.

## 21. HRM QMS & training — Phase 5A (run HRM `0008_qms.sql`, then `supabase/migrations/0032_hrm_qms.sql`)

- HRM › **QMS & training**: skill matrix, competency mapping, training needs (TNI), training plan with ID-card
  attendance, training effectiveness, on-the-job training, internal auditors, roles & responsibilities, KPIs and the
  Audit Pack PDF (IATF 16949 7.2 / 7.3, ISO 9001 5.3, 6.2, 7.2, 9.1). Employees sign their R&R and awareness sessions
  in *My skills & training*.
- Every company gets a ready competency library (18) and training programmes (14); new companies get them, and the
  payroll and recruitment defaults, the moment they are created.
- Grand Master › Load sample data also loads sample QMS records joined to the sample people (two lines with a skill
  matrix and alerts, competency gaps, training done / scheduled / planned, effectiveness due and evaluated, OJT,
  auditors, R&R, three months of KPIs). Flush real data keeps them; Flush sample data removes them.
- The flushes call `hrm.module_flush(tenant, 'all' | 'real' | 'sample')`; later HRM modules add their tables there.
  The competency library and training programmes are company setup: Flush real data keeps them.
- The nightly HRM job also sends training reminders the day before and tells supervisors which effectiveness checks
  are due. WhatsApp templates to submit: `hrm_training_invite`, `hrm_training_reminder`.

## 22. HRM positions (run HRM `0009_positions.sql`; no console file)

The QMS runs on **Position + Role + Department** instead of designations: requisition → job description of the
position → R&R sheet (roles, responsibilities, authority, competency, KPI; landscape PDF with the company logo and
clauses) → competency mapping per person → KPI sheet per person → training needs → calendar → attendance → effectiveness.
Every employee has a Position (new joiners get it from the requisition). What was written per designation becomes a
position of that name. Sample data includes five positions with holders. The platform setup file includes it.

## 23. HRM free AI for the QMS (run HRM `0010_ai.sql`; no console file)

The AI drafts the position's job description and R&R sheet, proposes training programmes for needs that have none,
writes pre / post test questions and puts the QMS findings in order. A named person approves or accepts everything it
writes; every run is logged (HRM › QMS › AI & review). Only free services are used.

To switch it on (plain steps):
1. Make one or more free keys: **openrouter.ai** → Keys; **console.groq.com** → API Keys; **aistudio.google.com** → Get API key. No card needed.
2. Vercel → the **kmr-hrm** project → Settings → Environment Variables → add `OPENROUTER_API_KEY`, `GROQ_API_KEY`
   and/or `GEMINI_API_KEY` (Production) → Redeploy.
3. HRM → QMS → AI & review → **Check the connection**.

Never paste a key into chat or e-mail. Without keys the HRM uses its own rule-based writer. The full flush also clears
the AI log; the platform setup file includes it.

## 24. HRM engagement — Phase 5B (run HRM `0011_engage.sql`; no console file)

Announcements (with acknowledgement), recognition wall and Employee of the month, suggestions / Kaizen with review and
savings, and surveys (anonymous by default; results only from 5 answers) — HRM › Engagement, and *Notices & ideas* in each
person's portal. Grand Master › Load sample data now also loads sample engagement records ("HRM engagement" in the
counts); the sample and real flushes clear them with the rest. The platform setup file includes it.

## 25. HRM policies & compliance — Phase 5C (run HRM `0012_compliance.sql`; no console file)

Controlled documents (policies, procedures, formats — revision, prepared / approved by, review date, master list PDF),
policies acknowledged by each person in the portal, and the statutory compliance register (PF, ESI, PT, TDS, returns,
licence renewals — a Karnataka starting list the company checks with its consultant) with proof and daily reminders.
Every new company gets the starting list; Grand Master sample data includes sample documents and filings
("HRM policies & compliance" in the counts). The platform setup file includes it.

## 26. HRM safety — Phase 5D (run HRM `0013_safety.sql`; no console file)

Incidents and near misses (employees report from the phone with a photo), investigation with why-why and root cause,
corrective / preventive actions with owners, days without a lost-time injury, LTIFR and severity rate from the man-hours in
attendance, PPE with replacement dates, and medical examination dates (no medical findings). Every new company gets a
starting PPE list; Grand Master sample data includes sample incidents, PPE issues and examinations ("HRM safety" in the counts).
The platform setup file includes it.

## 22. Sales Flow — monthly sales plan vs actual despatch (run `supabase/migrations/0033_sales_flow.sql`)

*Needs 0011, 0015 and 0029.* Adds the product **Sales Flow** (licence code `sales`, one per customer company).

1. Supabase → SQL Editor → run `supabase/migrations/0033_sales_flow.sql` (already included for new projects in `KMR_PLATFORM_SETUP.sql`).
2. Website repo: copy `website-files/it/sales.html` to `/it/sales.html` and set `CFG.SUPABASE_ANON_KEY` (same publishable key as the other apps).
3. Console → customer → **Switch on Sales Flow** (administrator name + email, licence status/valid until) → the card appears on the customer's KMR Apps page.
4. Colleagues: Administration › Users & access → role **Sales Flow** = admin / editor / viewer.
5. In the app: **Sales plan › Add parts** (customer, part no., part name, price from Operations Master and the customer's rate contract) → enter demand qty and delivery (specific date / daily / weekly) → **Daily despatch** each day → **Dashboard**.
6. Try the screens without a database: open `/it/sales.html?demo=1`.

*Sales Flow updates:* `0034_sales_flow_company.sql` (opens from the portal card without `?co=`) and `0035_sales_flow_prices.sql` (finds more prices in the Operations Master). Unplanned sales: **Daily despatch › Add part not in plan** adds the part to the month's plan with plan qty 0; it shows as *Unplanned sales* on the Dashboard.

*Sales Flow — analysis:* the Dashboard has a **Sales plan analysis** (Class A / B / C parts by plan value, auto briefing, "where to concentrate" list with indicators). Thresholds and currency rates are in `CFG` at the top of `website-files/it/sales.html` (`ABC`, `CONC`, `FX`). The page has a **← Company · KMR Apps** button (bottom left) like the other apps.

*Sales Flow — loss & action plans (run `0036_sales_flow_loss.sql`, after 0033):* **Sales loss** screen (per part: demand / dispatched / pending qty and value, % of loss, reason from a searchable list incl. *Others* with custom text) and **Action plan** screen (issue, brief, immediate action, permanent action, responsibility, target date, status Opened / Under progress / Closed). The Dashboard has two extra views: *Sales loss analysis* and *Action plan status* (overdue, responsible-person wise, issue wise). The reason list, the customer-driven reasons and the status list are in `CFG` at the top of `sales.html`.

## 23. Calibration Hub — first version (run `supabase/migrations/0037_calibration.sql`, after 0033)
Product `calib`. Copy `website-files/it/calibration.html` to `/it/calibration.html`, switch it on per customer in the Console, give colleagues the **Calibration Hub** role (admin / editor / viewer). Try without a database: `/it/calibration.html?demo=1`. QR links open a gauge card with `?co=<company>&g=<tag>`.

*Calibration Hub — import & QR labels:* run `0038_calibration_import.sql` (after 0037). **Instruments › Import Excel / CSV** loads a whole gauge register (columns matched by heading; existing tags are updated); **QR labels** prints labels that open the gauge card when scanned.

*Calibration Hub — public key & MSA:* the console now serves its public (anon) key at `/it/console/api/public-config` (route `app/api/public-config/route.ts`, allowed in `middleware.ts`); `/it/calibration.html` reads it automatically, so no key is pasted into the page. Run `0039_calibration_msa.sql` (after 0037) for **MSA › New Gage R&R study** (average & range method).

*Calibration Hub — Operations Master gauges:* run `0040_calibration_ops_gauges.sql` (after 0037). **Add instrument** can pick a gauge from Operations Master › Gauges (fields filled in), **Sync from Operations Master** adds all missing gauges, and *Next due* is calculated from *Last calibration date + Frequency*. The Standards tab has a one-click **audit pack** (4 CSV files); each gauge card shows an interval review and issue/return status.

*Calibration Hub — gauges from Operations Master:* **＋ Add from Operations Master** lists the gauges of Operations Master › Gauges (run `0041_calibration_ops_location.sql` after 0040). Location shows as *machine code · machine name* or *Gauge room · room no.* (Operations Master fields `location` and `gauge_room_no`).

*Operations Master › Gauges (website repo `public/it/apps/ops.js`, copy in `website-files/it/apps/ops.js`):* the gauge form now holds the full instrument record — type, make, model, serial no., range, least count, tolerance, department, criticality, calibrated (internal/external), lab, custodian, frequency, last calibrated, next due (auto) and **Location** = machine code from the Machines list or *Gauge room* (then **Gauge room location number**). Calibration Hub reads these fields (run `0041_calibration_ops_location.sql`); **Sync from Operations Master** also refreshes existing gauges.

*Calibration Hub — control plan, typed entry, edit / delete (run `0042_calibration_crud.sql`, after 0039):* MSA studies pick a characteristic and tolerance from the Process Documents **Control Plan** (`pd_projects.doc.docs.cp.rows`; tolerance is read from the spec text such as `25.00 ±0.02` or `60.0 - 60.3`) or accept typed values. Instruments can be added from the Operations Master or manually; location = machine from the Operations Master Machines list or typed (*Gauge room* asks for the room number). Instruments, calibration records, history entries, OOT cases and MSA studies can all be edited and deleted by admins / editors. Operations Master › Gauges (`ops.js`): location accepts a machine or typed text, frequency is pick-or-type, next due is calculated from last calibrated (or today).

*Process Documents & shared UI (website repo, see `website-changes.zip`):* drag a process by its ⠿ handle (or ↑/↓) in **Process plan** — numbers keep their order, characteristics follow their process and all documents are rebuilt; **Add operation** inserts anywhere and accepts a typed process name; SOP has a drawing / photo box (upload or drag & drop) above Tools / Gauges and prints one process per A3 portrait page; every PDF opens in a viewer first (Download inside it); right-click / long-press on menus and buttons offers Open in new tab / window (`/it/apps/kmr-ui.js`).
