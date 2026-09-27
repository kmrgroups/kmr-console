-- =====================================================================
-- KMR DEMO FLUSH — removes everything DEMO_DATA.sql added, nothing else:
-- employees with @demo.kmr.test emails (with their punches, attendance, leave and requests),
-- the two demo plants (DP1, DP2), and Console customers with source 'KMR demo data' (with their licences,
-- tickets and pilot requests). Holidays are kept. Real companies, employees and customers are untouched.
-- =====================================================================
delete from hrm.employees where email like '%@demo.kmr.test';
delete from hrm.plants p where p.code in ('DP1','DP2') and not exists (select 1 from hrm.employees e where e.plant_id = p.id);
delete from console.customers where source = 'KMR demo data';
do $$ begin
  if to_regclass('console.leads') is not null then execute 'delete from console.leads where email like ''%demo.kmr.test'''; end if;
  if to_regclass('console.tickets') is not null then execute 'delete from console.tickets where raised_by_email like ''%@demo.kmr.test'''; end if;
end $$;
select 'DEMO DATA REMOVED' as result,
       (select count(*) from hrm.employees where email like '%@demo.kmr.test') as demo_employees_left,
       (select count(*) from console.customers where source = 'KMR demo data') as demo_customers_left;
