-- 0119 — Sales Invoicing: bring the old ERP invoices in (idempotent: an invoice number that is already here is skipped)
create or replace function public.kmr_inv_import(p_slug text, p jsonb) returns jsonb language plpgsql security definer set search_path = console, public as $$
declare cid uuid := console.qp_edit(p_slug, 'inv'); n int := 0; r record; iid uuid; k int;
begin
  if console.qp_role(cid, 'inv') <> 'admin' then raise exception 'Only an administrator can import ERP invoices.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p -> 'invoices', '[]'::jsonb)) v loop
    insert into console.inv_invoice (customer_id, inv_no, inv_date, doc_type, supply_type, buyer_code, buyer_name, buyer_gstin, buyer_addr, buyer_loc, buyer_pin, buyer_state, po_no, po_date, dc_no, dc_date, vehicle_no, mode, delivery_terms, pay_days, remarks,
        taxable, cgst, sgst, igst, tcs, round_off, total, status, issued_at, issued_by, cancel_reason, created_by)
    select cid, v ->> 'no', (v ->> 'date')::date, 'INV', coalesce(nullif(v ->> 'supply', ''), 'B2B'), v ->> 'buyer_code', coalesce(nullif(v ->> 'buyer_name', ''), v ->> 'buyer_code', '-'), nullif(v ->> 'gstin', ''), v ->> 'addr', v ->> 'loc', v ->> 'pin', v ->> 'state',
      nullif(v ->> 'po_no', ''), nullif(v ->> 'po_date', '')::date, nullif(v ->> 'dc_no', ''), nullif(v ->> 'dc_date', '')::date, nullif(v ->> 'vehicle', ''), nullif(v ->> 'mode', ''), nullif(v ->> 'terms', ''), nullif(v ->> 'pay_days', '')::int, nullif(v ->> 'remarks', ''),
      coalesce((v ->> 'taxable')::numeric, 0), coalesce((v ->> 'cgst')::numeric, 0), coalesce((v ->> 'sgst')::numeric, 0), coalesce((v ->> 'igst')::numeric, 0), coalesce((v ->> 'tcs')::numeric, 0), coalesce((v ->> 'round_off')::numeric, 0), coalesce((v ->> 'total')::numeric, 0),
      case when (v ->> 'cancelled') = 'true' then 'cancelled' else 'issued' end, (v ->> 'date')::date, 'ERP import', case when (v ->> 'cancelled') = 'true' then 'Cancelled in the old ERP' end, 'ERP import'
    from (select r.value as v) s
    on conflict (customer_id, inv_no) do nothing returning id into iid;
    if iid is not null then
      k := 0;
      insert into console.inv_lines (customer_id, inv_id, sl, item_code, description, hsn, uom, qty, rate, discount, gst_rate, taxable, cgst, sgst, igst, packing)
      select cid, iid, row_number() over (order by ord), l ->> 'code', coalesce(nullif(l ->> 'desc', ''), l ->> 'code', '-'), l ->> 'hsn', coalesce(nullif(l ->> 'uom', ''), 'Nos'), greatest(coalesce((l ->> 'qty')::numeric, 0), 0.0001), coalesce((l ->> 'rate')::numeric, 0), coalesce((l ->> 'discount')::numeric, 0),
        coalesce((l ->> 'gst')::numeric, 0), coalesce((l ->> 'taxable')::numeric, 0), coalesce((l ->> 'cgst')::numeric, 0), coalesce((l ->> 'sgst')::numeric, 0), coalesce((l ->> 'igst')::numeric, 0), l ->> 'packing'
      from jsonb_array_elements(coalesce(r.value -> 'lines', '[]'::jsonb)) with ordinality as t(l, ord);
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('invoices', n);
end $$;
create index if not exists inv_invoice_buyer on console.inv_invoice (customer_id, buyer_name);
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'kmr_inv_import' loop
    execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig);
  end loop; end $$;
