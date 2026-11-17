-- The daily management / finance mail queries were cancelled by the database time limit when the cron job ran (applied via the connector).
alter function public.kmr_digest_scan() set statement_timeout = '120s';
alter function public.kmr_fin_scan() set statement_timeout = '120s';
alter function public.kmr_digest_mark(uuid) set statement_timeout = '60s';
