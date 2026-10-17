-- Elixir Tec: the Realtime RS9w fingerprint + card machine (read from its screens). Run once in the Supabase SQL editor after 0072 and 0073.
do $m$ declare cid uuid; begin
  select id into cid from console.customers where slug = 'elixir-tec-corporation-c0020';
  if cid is null then raise exception 'Customer elixir-tec-corporation-c0020 not found.'; end if;
  insert into console.hrms_devices (customer_id, name, vendor, model, modes, serial, protocol, location, ip, enabled, notes)
  values (cid, 'Realtime RS9w', 'Realtime', 'RS9w', '{finger,card}', 'RSS20240889536', 'json', 'Elixir Tec',
          '192.168.1.224:5005', true, 'LAN 192.168.1.224 (WiFi 192.168.1.225), TCP port 5005, device ID 1, no communication password, server-client mode FkWeb, firmware 2024-09-02, engine EbknFinger V3.0')
  on conflict (lower(serial)) where serial is not null do nothing;
end $m$;
