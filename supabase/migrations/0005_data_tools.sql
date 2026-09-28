-- =====================================================================
-- KMR Console — data tools: sample data (Load / Flush), JSON export, nightly backups (kept 7 days).
-- Server-only (service key); the Console checks the person is an owner / administrator first. Safe to re-run.
-- =====================================================================
create or replace function console.demo_load() returns integer
language plpgsql security definer set search_path = console, public as $fn$
begin
  if exists (select 1 from console.customers where source = 'KMR demo data') then raise exception 'Sample data is already loaded. Flush it first to load it again.'; end if;
insert into console.customers (name, legal_name, country, currency, tax_id, city, state, contact_name, contact_email, contact_phone, status, source, notes) values
  ('Sri Balaji Auto Components', 'Sri Balaji Auto Components Pvt Ltd', 'IN', 'INR', '29AABCS1234F1Z5', 'Bengaluru', 'Karnataka', 'Ramesh Babu', 'ramesh@sribalaji.demo.kmr.test', '+91 98450 11111', 'active', 'KMR demo data', 'Tier-2 machining supplier'),
  ('Hosur Precision Forgings', 'Hosur Precision Forgings LLP', 'IN', 'INR', '33AAHFH5678K1Z2', 'Hosur', 'Tamil Nadu', 'Kavitha S', 'kavitha@hosurforge.demo.kmr.test', '+91 94430 22222', 'pilot', 'KMR demo data', 'Pilot of Balloon Inspector for PPAP'),
  ('Pune Gear Works', 'Pune Gear Works Pvt Ltd', 'IN', 'INR', '27AACCP4321L1Z9', 'Pune', 'Maharashtra', 'Amit Deshpande', 'amit@punegear.demo.kmr.test', '+91 98220 33333', 'lead', 'KMR demo data', 'Met at IMTEX'),
  ('Müller Präzisionsteile GmbH', 'Müller Präzisionsteile GmbH', 'DE', 'EUR', 'DE812345678', 'Stuttgart', 'Baden-Württemberg', 'Jonas Müller', 'jonas@mueller.demo.kmr.test', '+49 711 555 0100', 'pilot', 'KMR demo data', 'Export customer — Quality Suite'),
  ('Great Lakes Stamping Inc', 'Great Lakes Stamping Inc', 'US', 'USD', '38-1234567', 'Detroit', 'Michigan', 'Sarah Collins', 'sarah@glstamping.demo.kmr.test', '+1 313 555 0142', 'lead', 'KMR demo data', 'Asked for a demo of HRM + attendance'),
  ('Gulf Fabrication LLC', 'Gulf Fabrication LLC', 'AE', 'AED', '100234567800003', 'Sharjah', 'Sharjah', 'Imran Qureshi', 'imran@gulffab.demo.kmr.test', '+971 6 555 0199', 'inactive', 'KMR demo data', 'Trial ended — follow up next quarter');

insert into console.licences (customer_id, product_code, status, starts_on, valid_until, seats, notes)
select c.id, x.product, x.status, current_date - x.started, current_date + x.ends, x.seats, 'Demo licence (not connected to a workspace)'
  from (values ('Sri Balaji Auto Components', 'hrm', 'active', 120, 245, 150),
               ('Sri Balaji Auto Components', 'balloon', 'active', 120, 245, 10),
               ('Hosur Precision Forgings', 'balloon', 'pilot', 20, 10, 5),
               ('Müller Präzisionsteile GmbH', 'pd', 'trial', 10, 20, 5),
               ('Gulf Fabrication LLC', 'hrm', 'expired', 60, -5, 40)) x(cust, product, status, started, ends, seats)
  join console.customers c on c.name = x.cust and c.source = 'KMR demo data';

insert into console.leads (name, company, email, phone, country, products, message, source) values
  ('Mahesh Gowda', 'Tumkur Castings', 'mahesh@tumkurcast.demo.kmr.test', '+91 99000 44444', 'India', '{hrm}', '180 workmen across 2 shifts, using eSSL devices', 'website'),
  ('Elena Rossi', 'Rossi Meccanica Srl', 'elena@rossimec.demo.kmr.test', '+39 011 555 0177', 'Italy', '{balloon,pd}', 'PPAP documents for an Indian OEM customer', 'website');
  return (select count(*) from console.customers where source = 'KMR demo data');
end $fn$;

create or replace function console.demo_flush() returns integer
language plpgsql security definer set search_path = console, public as $fn$
declare n integer;
begin
  delete from console.tickets where raised_by_email like '%demo.kmr.test';
  delete from console.leads where email like '%demo.kmr.test';
  delete from console.customers where source = 'KMR demo data';
  get diagnostics n = row_count;
  return n;
end $fn$;

create or replace function console.console_export() returns jsonb
language plpgsql stable security definer set search_path = console, public as $fn$
declare out jsonb := '{}'::jsonb; t text; rows jsonb;
begin
  foreach t in array array['products','customers','licences','licence_events','releases','tickets','ticket_messages','leads','staff'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from console.%I x', t) into rows;
    out := out || jsonb_build_object(t, rows);
  end loop;
  return jsonb_build_object('format', 'kmr-console-backup', 'version', 1, 'exported_at', now(), 'tables', out);
end $fn$;

revoke all on function console.demo_load(), console.demo_flush(), console.console_export() from public, anon, authenticated;
grant execute on function console.demo_load(), console.demo_flush(), console.console_export() to service_role;

insert into storage.buckets (id, name, public, file_size_limit) values ('kmr-backups', 'kmr-backups', false, 52428800) on conflict (id) do nothing;
