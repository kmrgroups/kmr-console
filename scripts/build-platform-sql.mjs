#!/usr/bin/env node
// Builds supabase/KMR_PLATFORM_SETUP.sql (one file for a fresh KMR Supabase project) from the migrations.
// Order: Console 0001, HRM (copied from kmrgroups/kmr-hrm into supabase/products/hrm), Console 0002 (quality tools).
import fs from "node:fs";
const u = (p) => new URL(`../supabase/${p}`, import.meta.url);
const parts = ["migrations/0001_console.sql",
  ...fs.readdirSync(u("products/hrm/")).filter((f) => f.endsWith(".sql")).sort().map((f) => `products/hrm/${f}`),
  "migrations/0002_quality_suite.sql", "migrations/0003_service.sql", "migrations/0004_portal.sql", "migrations/0005_data_tools.sql", "migrations/0006_portal_dashboards.sql", "migrations/0007_portal_access.sql", "migrations/0008_my_portals.sql", "migrations/0009_portal_workspace.sql", "migrations/0010_capacity.sql"];
const bar = "=".repeat(69);
const body = parts.map((p) => `\n-- ${bar}\n-- ${p}\n-- ${bar}\n` + fs.readFileSync(u(p), "utf8")).join("\n");
fs.writeFileSync(u("KMR_PLATFORM_SETUP.sql"), fs.readFileSync(u("setup-head.sql"), "utf8") + body + fs.readFileSync(u("setup-tail.sql"), "utf8"));
console.log("supabase/KMR_PLATFORM_SETUP.sql written from", parts.join(", "));
