-- =============================================================================
-- Kheja_Link — 0007_payment_webhook.sql
--
-- Lets the payment webhook confirm an unlock.
--
-- confirm_contact_unlock is deliberately unreachable by anon and authenticated:
-- if a user could call it they could unlock any listing for free. Only the
-- service role may, and the service role key lives on the server, in the
-- webhook handler, never in either app.
--
-- Safe to re-run.
-- =============================================================================

set search_path = public, extensions;

grant execute on function public.confirm_contact_unlock(text, text) to service_role;

-- The webhook looks the row up by reference before confirming it.
grant select, update on public.contact_unlocks to service_role;

-- A pending unlock older than an hour was abandoned at the payment page.
create or replace function public.expire_stale_unlocks()
returns integer
language sql
security definer
set search_path = public
as $$
  with expired as (
    update public.contact_unlocks
       set status = 'failed'
     where status = 'pending'
       and created_at < now() - interval '1 hour'
    returning 1
  )
  select count(*)::int from expired;
$$;

revoke all on function public.expire_stale_unlocks() from public, anon, authenticated;
grant execute on function public.expire_stale_unlocks() to service_role;
