-- =============================================================================
-- Kheja_Link — 0014_payment_charges.sql
--
-- Kheja_Link takes payments through its own screens: the tenant chooses
-- M-Pesa and types their number in the app, and the server drives Paystack's
-- API behind it. Two things that needs from the database:
--
--   * unlock_checkout_details(), so the server can price a contact unlock from
--     its own row rather than from anything the app sends — the hunting fee
--     already has hunting_checkout_details() from 0012
--   * payment_attempts, a small log of what was tried, so a tenant who says
--     "I paid and nothing happened" can be answered
--
-- Money is still only ever confirmed by the server: either the signed Paystack
-- webhook, or the server asking Paystack to verify the reference. Nothing the
-- app sends can mark a payment paid.
--
-- Safe to re-run. Run AFTER 0013.
-- =============================================================================

set search_path = public, extensions;

-- What the payment server needs to charge a contact unlock. The reference is
-- unguessable and this returns no personal data.
create or replace function public.unlock_checkout_details(p_reference text)
returns table (amount numeric, currency text, status text, property_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select cu.amount, cu.currency::text, cu.status::text, cu.property_id
    from public.contact_unlocks cu
   where cu.provider_ref = p_reference;
$$;

revoke all on function public.unlock_checkout_details(text) from public;
grant execute on function public.unlock_checkout_details(text) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- payment_attempts — one row per charge we ask Paystack for
-- -----------------------------------------------------------------------------
create table if not exists public.payment_attempts (
  id           uuid primary key default gen_random_uuid(),
  reference    text not null,
  product      text not null,
  channel      text not null,
  status       text not null default 'pending',
  -- What Paystack told the customer to do, shown in our own screen.
  display_text text,
  provider_ref text,
  message      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint payment_attempts_product_ok check (product in ('hunting_fee', 'contact_unlock')),
  constraint payment_attempts_channel_ok check (channel in ('mobile_money', 'card', 'checkout')),
  constraint payment_attempts_status_ok
    check (status in ('pending', 'send_otp', 'open_url', 'success', 'failed', 'abandoned'))
);

create index if not exists payment_attempts_reference_idx
  on public.payment_attempts (reference, created_at desc);

drop trigger if exists payment_attempts_set_updated_at on public.payment_attempts;
create trigger payment_attempts_set_updated_at
  before update on public.payment_attempts
  for each row execute function public.set_updated_at();

alter table public.payment_attempts enable row level security;

-- Only admins read the log through the API; the payment server writes it with
-- the service role.
drop policy if exists payment_attempts_admin on public.payment_attempts;
create policy payment_attempts_admin on public.payment_attempts
  for select to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));

revoke insert, update, delete on public.payment_attempts from anon, authenticated;
grant select on public.payment_attempts to authenticated;
grant select, insert, update on public.payment_attempts to service_role;
