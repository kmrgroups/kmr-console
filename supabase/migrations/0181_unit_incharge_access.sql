-- 0181: customer_members.incharge (unit in-charge gets the Daily management mail only); kmr_digest_scan adds in-charges to the recipients.
-- Access change applied directly in the DB: Hebbar (Unit-2 in-charge), Praveen, Yogesh, Ravi, Philomena, Rishab and the developer admin are members of all three Esbee plants
-- (existing role kept, otherwise editor on every licensed app); Jayaram is editor on every Unit-2 app only and was removed from the other plants and the main company.
alter table console.customer_members add column if not exists incharge boolean not null default false;
-- kmr_digest_scan: see the function in the database (recipients = typed list + admins if switched on + members with incharge).
