-- pg_cron jobs (UTC) that start the website's jobs on the exact minute; applied via the connector.
select cron.schedule('kmr-digest-0830', '0 3 * * *', $$select console.kmr_fire('digest')$$);      -- 08:30 India
select cron.schedule('kmr-finance-0900', '30 3 * * *', $$select console.kmr_fire('finance')$$);   -- 09:00 India
select cron.schedule('kmr-tsk-0800', '30 2 * * *', $$select console.kmr_fire('tsk')$$);           -- 08:00 India (no longer on Vercel's schedule)
select cron.schedule('kmr-backup-p1', '40 18 * * *', $$select console.kmr_fire('backup?pass=1')$$); -- 00:10 India, then passes 2-5
select cron.schedule('kmr-backup-p2', '55 18 * * *', $$select console.kmr_fire('backup?pass=2')$$);
select cron.schedule('kmr-backup-p3', '25 19 * * *', $$select console.kmr_fire('backup?pass=3')$$);
select cron.schedule('kmr-backup-p4', '55 19 * * *', $$select console.kmr_fire('backup?pass=4')$$);
select cron.schedule('kmr-backup-p5', '25 20 * * *', $$select console.kmr_fire('backup?pass=5')$$);
