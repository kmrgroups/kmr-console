-- kmr_mlp_save now also stores 'woff' (weekly off day, -1 none, 0 Sunday .. 6 Saturday)
create or replace function public.kmr_mlp_save(p_slug text, p_month text, p_cfg jsonb)
 returns jsonb language plpgsql security definer set search_path to 'console','public' as $f$
declare cid uuid := console.qp_edit(p_slug,'mlp'); kv record;
begin
  for kv in select key k, value v from jsonb_each_text(coalesce(p_cfg,'{}'::jsonb)) where value ~ '^-?[0-9.]+$' and key in ('hpd','eff','days','wait','supd','woff') loop
    insert into console.ppl_cfg (customer_id,k,v) values (cid,kv.k,kv.v::numeric) on conflict (customer_id,k) do update set v=excluded.v;
  end loop;
  return public.kmr_mlp_data(p_slug,p_month);
end $f$;
