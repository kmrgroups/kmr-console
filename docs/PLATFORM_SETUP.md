# KMR platform — Milestone 1 setup (pilot, free plans)

What you get: **KMR Console** at `www.kmr-groups.com/it/console` (customers, licences, products, staff) and
**HRM Suite** at `www.kmr-groups.com/it/hrm` for every customer company, controlled by Console licences.
Balloon Inspector and Process Documents keep working exactly as today (`/it/balloon.html`, `/it/pd.html`).

## 1. Supabase (project dehlcusptkzfhqvpfyjh) — 5 minutes

1. **Backup first:** Database → Backups (free plan keeps daily backups) — or ask for an export script.
2. Open `supabase/KMR_PLATFORM_SETUP.sql`. At the top, set **owner_email** to your existing login
   (the one you use for the website admin) and **owner_name**.
3. SQL Editor → New query → paste the whole file → **Run**. It ends with **KMR PLATFORM READY**.
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
APP_SECRET=77uptu5MaANIvPGbrSJS0pz8IUcn1MwRXRBbsuFvavfPlomDTUeBtzEa
CRON_SECRET=59c1180c3c3dc2d092dc17eba04a15ab534c778ecc1abd92
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
