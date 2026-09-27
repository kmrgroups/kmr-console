
-- =====================================================================
-- The Console owner
-- =====================================================================
insert into console.staff (user_id, full_name, email, role)
select u.id, s.owner_name, lower(s.owner_email), 'owner'
  from kmr_setup s join auth.users u on lower(u.email) = lower(s.owner_email);
drop table kmr_setup;

select 'KMR PLATFORM READY' as result,
       (select count(*) from console.products) as products,
       (select count(*) from console.staff)    as console_staff,
       (select string_agg(id, ', ') from storage.buckets where id like 'hrm-%') as hrm_buckets;
