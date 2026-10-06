-- 0052 — edit a line on a DRAFT invoice (description, quantity, rate). Issued invoices stay frozen. Safe to re-run.
create or replace function console.update_invoice_line(p_invoice uuid, p_line bigint, p_description text, p_qty numeric, p_unit_amount numeric) returns void
language plpgsql security definer set search_path = console, public as $$
begin
  perform console.require_manager();
  if (select status from console.invoices where id = p_invoice) is distinct from 'draft' then raise exception 'Only a draft invoice can be changed.'; end if;
  if length(trim(coalesce(p_description, ''))) = 0 then raise exception 'Describe the line.'; end if;
  if coalesce(p_qty, 0) <= 0 or coalesce(p_unit_amount, -1) < 0 then raise exception 'Quantity must be above 0 and the rate 0 or more.'; end if;
  update console.invoice_lines set description = left(trim(p_description), 300), qty = p_qty, unit_amount = p_unit_amount, amount = round(p_qty * p_unit_amount, 2)
   where id = p_line and invoice_id = p_invoice;
  perform console.invoice_recalc(p_invoice);
end $$;
revoke all on function console.update_invoice_line(uuid, bigint, text, numeric, numeric) from public, anon;
grant execute on function console.update_invoice_line(uuid, bigint, text, numeric, numeric) to authenticated;
