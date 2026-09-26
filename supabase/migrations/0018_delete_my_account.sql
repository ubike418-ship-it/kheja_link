-- =============================================================================
-- Kheja_Link — 0018_delete_my_account.sql
--
-- Anyone who can create an account can delete it themselves, in the app and
-- on the website (a Google Play requirement, and simply right).
--
-- delete_my_account() removes the caller's sign-in, which cascades to their
-- profile and everything it owns: listings (with photos and videos records),
-- saved homes, alerts, requests, unlock records, houses given, messages sent
-- with the account, and notifications.
--
-- The last admin cannot delete themselves, so the back office is never left
-- without anyone. Safe to re-run. Run AFTER 0017.
-- =============================================================================

set search_path = public, extensions;

create or replace function public.delete_my_account()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in to continue.' using errcode = '28000';
  end if;

  if public.current_role_is(array['admin']::public.user_role[])
     and (select count(*) from public.profiles where role = 'admin') <= 1 then
    raise exception 'You are the only admin. Make someone else an admin before deleting your account.'
      using errcode = '42501';
  end if;

  delete from auth.users where id = v_uid;
  delete from public.profiles where id = v_uid;
  return true;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
