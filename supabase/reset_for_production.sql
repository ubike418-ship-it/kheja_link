-- =============================================================================
-- Kheja_Link — reset_for_production.sql
--
-- RUN ONCE, BY HAND, just before launch. This is NOT a migration and is not in
-- setup.sql. It permanently deletes data and cannot be undone — take a backup
-- first (Supabase → Database → Backups) if you might want anything back.
--
-- It deletes every account except the demo landlord, and everything those
-- accounts made: their listings, favourites, unlocks, payments, refunds,
-- houses, requests, alerts, messages and notifications. It then clears the
-- remaining activity on the demo landlord's sample listings (views, likes,
-- messages, payment logs, the Stays waitlist) so production starts clean.
--
-- It keeps: the demo landlord and their sample listings, areas, property
-- types, amenities, MoveMate and the other providers, and every business
-- setting (prices, refund amount, unlock hours).
--
-- Run 0016 first. Then paste this whole file into the SQL Editor and press Run.
-- Files people uploaded stay in Storage; delete them in Supabase → Storage if
-- you want the space back (the database no longer points at them).
-- =============================================================================

begin;

-- The account whose sample listings stay.
create temporary table keep_users on commit drop as
  select id from auth.users where email = 'demo.landlord@khejalink.co.ke';

do $$ begin
  if not exists (select 1 from keep_users) then
    raise exception 'The demo landlord account was not found — nothing was deleted.';
  end if;
end $$;

-- Activity on the listings that stay. Most of this would go with the deleted
-- accounts anyway; guests' rows (no account) would not, so clear it all.
delete from public.inquiries;
delete from public.notifications;
delete from public.favorites;
delete from public.property_interests;
delete from public.tenancies;
delete from public.unlock_refunds;
delete from public.house_submissions;
delete from public.contact_unlocks;
delete from public.payment_allocations;
delete from public.hunting_payments;
delete from public.hunting_services;
delete from public.payment_attempts;
delete from public.notification_outbox;
delete from public.stays_waitlist;

-- Every other account. Deleting from auth.users cascades to profiles and on to
-- everything each profile owns, including any listings they had.
delete from auth.users where id not in (select id from keep_users);

-- The sample listings start from zero.
update public.properties
   set view_count = 0, like_count = 0
 where owner_id in (select id from keep_users);

-- Let daily maintenance run straight away.
update public.app_settings set value = '' where key = 'last_maintenance_at';

commit;

-- What is left — expect 1 account, the sample listings, and zeros below.
select
  (select count(*) from auth.users)               as accounts,
  (select count(*) from public.properties)        as listings,
  (select count(*) from public.contact_unlocks)   as unlocks,
  (select count(*) from public.inquiries)         as messages,
  (select count(*) from public.notifications)     as notifications;

-- -----------------------------------------------------------------------------
-- AFTER RUNNING: make yourself the admin.
-- 1. Sign up in the app or on the website with your own email.
-- 2. Then run this line, with that email:
--
--   update public.profiles set role = 'admin'
--    where id = (select id from auth.users where email = 'YOUR-EMAIL-HERE');
-- -----------------------------------------------------------------------------
