-- =============================================================================
-- Kheja_Link — 0017_admin_delete.sql
--
-- Admins can delete from every part of the back office. Most tables already
-- allowed it (listings, messages, providers, the Stays waitlist, the fee
-- split); this adds the rest:
--
--   * accounts — admin_delete_user(), which removes the sign-in itself and so
--     everything the account owns. An admin cannot delete their own account.
--   * unlock payments and the payment-attempt log
--   * houses tenants gave us, and their refunds
--
-- Still admin-only through Row Level Security; tenants and landlords gain
-- nothing. Safe to re-run. Run AFTER 0016.
-- =============================================================================

set search_path = public, extensions;

-- Deletes an account and, through the foreign keys, everything it owns:
-- profile, listings, favourites, unlocks, messages, houses and notifications.
create or replace function public.admin_delete_user(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_accounts int;
  v_profiles int;
begin
  if not public.current_role_is(array['admin']::public.user_role[]) then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot delete your own account from the back office.' using errcode = '42501';
  end if;

  delete from auth.users where id = p_user_id;
  get diagnostics v_accounts = row_count;
  -- A profile without a sign-in (older data) goes too.
  delete from public.profiles where id = p_user_id;
  get diagnostics v_profiles = row_count;
  return v_accounts + v_profiles > 0;
end;
$$;

revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Unlock payments.
drop policy if exists contact_unlocks_delete_admin on public.contact_unlocks;
create policy contact_unlocks_delete_admin on public.contact_unlocks
  for delete to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));
grant delete on public.contact_unlocks to authenticated;

-- The payment-attempt log.
drop policy if exists payment_attempts_delete_admin on public.payment_attempts;
create policy payment_attempts_delete_admin on public.payment_attempts
  for delete to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));
grant delete on public.payment_attempts to authenticated;

-- Houses tenants gave us (their refund goes with them).
drop policy if exists house_submissions_delete_admin on public.house_submissions;
create policy house_submissions_delete_admin on public.house_submissions
  for delete to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));
grant delete on public.house_submissions to authenticated;

drop policy if exists unlock_refunds_delete_admin on public.unlock_refunds;
create policy unlock_refunds_delete_admin on public.unlock_refunds
  for delete to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));
grant delete on public.unlock_refunds to authenticated;
