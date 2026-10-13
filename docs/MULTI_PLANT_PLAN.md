# Multi-plant support — decisions and plan

Status: **planned, not built yet.** Written 2026-10-13 after the owner's request:

> If a customer has Plant-1, Plant-2 and so on, every app must be compatible. Opening e.g. Sales Flow offers a plant
> selector; choosing a plant shows that plant's data. The summary dashboard must show all plants together and each
> plant on its own. Plants are created and controlled by the Console.

## Decisions (owner, 2026-10-13)

1. **Data:** *everything separate per plant* — each plant behaves like a separate company inside the customer, with its
   own parts, customers, suppliers, machines, plans and records.
2. **Access:** set **per user in the Console** — a user is given all plants or only chosen plants. The plant selector
   lists only the user's plants. Customer administrators and KMR staff see all plants.
3. **Rollout:** **phased**, one app family at a time, tested each time.

## What exists today (findings)

- A customer (`console.customers`) has one link `/it/app/<slug>`, licences per product (`console.licences`) and users
  (`console.customer_members`, roles per product).
- Every product keeps its data in **one workspace per customer** (`licences.product_ref`: Balloon / Process Documents /
  Capacity organisations, an HRM tenant; Sales Flow, Calibration, APQP, PPAP, RMP, MMD, Maintenance keep rows keyed by
  `customer_id`; the Operations Master is `console.ops_records`).
- Access is checked in many SQL functions (`kmr_portal`, `kmr_portal_join`, `kmr_access`, `kmr_portal_workspace`,
  `kmr_sf_*`, `kmr_cal_*`, `qp_*` …); licences are looked up by `customer_id` in about 35 migrations.
- The HRM already has plants (`hrm.plants`) but only **inside one HRM company**, created in the HRM itself — it breaks
  the platform rule that company set-up lives in the Console.
- There is no staging database. The Console's SQL tests (`supabase/tests`) run against a real Postgres.

## Proposed design

A **plant is a child workspace of a customer.**

- Console › Customer › **Plants**: add, rename, deactivate plants (code + name + address). Plants belong to the customer;
  invoices, licences and billing stay on the customer.
- Each plant gets its own workspace in every licensed product, so each app's data is separate with no change to how the
  app stores data. Plants use the customer's licences (kept in step automatically).
- **Users:** Administration › Users & access gets a *Plants* column (all / chosen). Membership is per plant.
- **Portal:** a plant selector next to the company name on KMR Apps. The choice is remembered and every app opens in that
  plant (the apps already work from the workspace they are opened with).
- **Dashboards:** the Dashboards screen gets *All plants* (roll-up across every plant the user may see) and one view per
  plant.
- Customers with one plant behave exactly as today (no selector shown).

## Phases

0. Backup, plus a way to test the database change before it reaches live data.
1. Console plants + user access + portal selector + **Sales Flow** on plants + the All-plants / per-plant dashboard.
2. Operations Master, Capacity Planner, Calibration Hub.
3. Balloon Inspector, Process Documents, APQP, PPAP, Raw Material Planning.
4. MMD, Maintenance.
5. HRM: tie HRM plants to Console plants (open question below).

## Open questions

- **HRM:** keep one HRM company per customer with its plants as a filter (employees can move between plants, one payroll
  run, one set of masters — usual for HR) **or** one HRM per plant (fully separate, matching decision 1). Needs an
  owner decision before phase 5.
- **Testing:** a separate Supabase test project, or run migration `0061` on the live project after a backup.
