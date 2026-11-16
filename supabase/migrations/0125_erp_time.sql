-- 0125: show the time an ERP record was made. The bridge now sends the full date and time of ERP date columns (and any creation-time column);
-- invoices from the ERP are stored with that moment (ERP clock = India time) in "issued_at", so the Invoicing list can show it.
-- Invoices loaded earlier get their time the next time the bridge sends them. Safe to run again.
do $$ declare d text; begin
  d := pg_get_functiondef('public.kmr_inv_import(text,jsonb)'::regprocedure);
  d := replace(d, $a$else 'issued' end, (v ->> 'date')::date, 'ERP import'$a$,
                  $a$else 'issued' end, coalesce(nullif(v ->> 'erp_time', '')::timestamp at time zone 'Asia/Kolkata', (v ->> 'date')::date), 'ERP import'$a$);
  if position('erp time backfill' in d) = 0 then
    d := replace(d, $a$  return jsonb_build_object('invoices', n);$a$, $a$  -- erp time backfill: invoices loaded earlier get the time the ERP made them
  update console.inv_invoice i set issued_at = (x.v ->> 'erp_time')::timestamp at time zone 'Asia/Kolkata'
    from jsonb_array_elements(coalesce(p -> 'invoices', '[]'::jsonb)) x(v)
   where i.customer_id = cid and i.inv_no = x.v ->> 'no' and i.issued_by = 'ERP import' and coalesce(x.v ->> 'erp_time', '') <> ''
     and i.issued_at is distinct from (x.v ->> 'erp_time')::timestamp at time zone 'Asia/Kolkata';
  return jsonb_build_object('invoices', n);$a$);
  end if;
  execute d;
end $$;
