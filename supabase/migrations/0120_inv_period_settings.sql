-- 0120 — Sales Invoicing: period search over all years, ERP import fix (payment terms like "IMMEDIATE"), seller details taken from the old ERP's e-invoice data
create or replace function public.kmr_inv_find(p_slug text, p_from date, p_to date, p_q text default null) returns jsonb language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid := console.qp_cid(p_slug, 'inv'); q text := nullif(trim(coalesce(p_q, '')), '');
begin
  return jsonb_build_object('invoices', coalesce((select jsonb_agg(x order by x ->> 'inv_date' desc, x ->> 'inv_no' desc) from (
      select jsonb_strip_nulls(to_jsonb(i) - 'customer_id' || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l) - 'customer_id' order by l.sl) from console.inv_lines l where l.inv_id = i.id), '[]'::jsonb))) x
      from console.inv_invoice i where i.customer_id = cid and (p_from is null or i.inv_date >= p_from) and (p_to is null or i.inv_date <= p_to)
        and (q is null or concat_ws(' ', i.inv_no, i.buyer_name, i.po_no, i.dc_no) ilike '%' || q || '%') order by i.inv_date desc, i.inv_no desc limit 3000) z), '[]'::jsonb),
    'total', (select count(*) from console.inv_invoice i where i.customer_id = cid and (p_from is null or i.inv_date >= p_from) and (p_to is null or i.inv_date <= p_to) and (q is null or concat_ws(' ', i.inv_no, i.buyer_name, i.po_no, i.dc_no) ilike '%' || q || '%')));
end $$;

-- the import: payment terms that are not a number of days (IMMEDIATE, LC ...) are kept in the remarks
do $$ declare d text; begin
  d := pg_get_functiondef('public.kmr_inv_import(text,jsonb)'::regprocedure);
  d := replace(d, $a$nullif(v ->> 'pay_days', '')::int$a$, $a$nullif(regexp_replace(coalesce(v ->> 'pay_days', ''), '\D', '', 'g'), '')::int$a$);
  d := replace(d, $a$nullif(v ->> 'remarks', '')$a$, $a$nullif(concat_ws('. ', nullif(v ->> 'remarks', ''), case when coalesce(v ->> 'pay_days', '') !~ '^\d*$' then 'Payment: ' || (v ->> 'pay_days') end), '')$a$);
  execute d;
end $$;

-- seller details as the old ERP sends them to the e-invoice portal (bank details, terms and Tally ledger names are not in the ERP: fill them in Settings)
insert into console.inv_settings (customer_id, legal_name, trade_name, gstin, addr1, addr2, loc, pin, state_code, phone, email, prefix, start_no, terms)
select c.id, 'Esbee Precision Industries (Unit - II)', 'Esbee Precision Industries', '29AAAFE6725G1ZG', 'Plot No.51, 4th Phase', 'Bommasandra Industrial Area', 'Bangalore', '560099', '29', '08027839280', 'admin.epi@nerigroup.in', 'EPI', 1,
  'Goods once sold will not be taken back. Interest at 18% p.a. on delayed payment. Subject to Bangalore jurisdiction.'
from console.customers c where c.slug like 'esbee-precision-industries-esbee-precisi-%'
on conflict (customer_id) do update set legal_name = coalesce(nullif(console.inv_settings.legal_name, ''), excluded.legal_name), trade_name = coalesce(nullif(console.inv_settings.trade_name, ''), excluded.trade_name),
  gstin = coalesce(nullif(console.inv_settings.gstin, ''), excluded.gstin), addr1 = coalesce(nullif(console.inv_settings.addr1, ''), excluded.addr1), addr2 = coalesce(nullif(console.inv_settings.addr2, ''), excluded.addr2),
  loc = coalesce(nullif(console.inv_settings.loc, ''), excluded.loc), pin = coalesce(nullif(console.inv_settings.pin, ''), excluded.pin), state_code = coalesce(nullif(console.inv_settings.state_code, ''), excluded.state_code),
  phone = coalesce(nullif(console.inv_settings.phone, ''), excluded.phone), email = coalesce(nullif(console.inv_settings.email, ''), excluded.email), prefix = case when console.inv_settings.prefix = 'INV' then 'EPI' else console.inv_settings.prefix end,
  terms = coalesce(nullif(console.inv_settings.terms, ''), excluded.terms);

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('kmr_inv_find') loop
    execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig);
  end loop; end $$;
