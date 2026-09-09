-- =============================================================================
-- Kheja_Link — 0009_fix_unlock_null_bug.sql
--
-- Fixes a hole in get_property_contact().
--
-- For a signed-out caller auth.uid() is NULL, so `v_owner = auth.uid()`
-- evaluated to NULL rather than false. `NULL or false` is NULL, and
-- `IF NOT NULL THEN` is not taken — so the guard was skipped entirely and the
-- function fell through to the branch that returns the phone number, the
-- WhatsApp number and the exact coordinates.
--
-- In other words: the KSh 150 paywall was open to anyone not signed in.
--
-- Every comparison against auth.uid() is now wrapped in coalesce, and the
-- entitlement check is explicitly `is not true` so NULL can never pass.
--
-- Safe to re-run.
-- =============================================================================

set search_path = public, extensions;

create or replace function public.get_property_contact(p_property_id uuid)
returns table (
  unlocked         boolean,
  contact_phone    text,
  contact_whatsapp text,
  latitude         numeric,
  longitude        numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner     uuid;
  v_is_public boolean;
  v_entitled  boolean;
begin
  select p.owner_id, (p.status = 'published')
    into v_owner, v_is_public
    from public.properties p
   where p.id = p_property_id;

  if v_owner is null then
    return query select false, null::text, null::text, null::numeric, null::numeric;
    return;
  end if;

  -- coalesce everywhere: auth.uid() is NULL for a signed-out caller, and a
  -- NULL here previously meant "not false", which let the guard be skipped.
  v_entitled :=
    coalesce(v_owner = auth.uid(), false)
    or (
      coalesce(v_is_public, false)
      and coalesce(public.has_contact_unlock(p_property_id), false)
    );

  if v_entitled is not true then
    return query select false, null::text, null::text, null::numeric, null::numeric;
    return;
  end if;

  return query
    select true, p.contact_phone, p.contact_whatsapp, p.latitude, p.longitude
      from public.properties p
     where p.id = p_property_id;
end;
$$;

-- has_contact_unlock has the same shape of risk, so pin it to false for anon.
create or replace function public.has_contact_unlock(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select exists (
      select 1 from public.contact_unlocks u
       where u.property_id = p_property_id
         and u.user_id = auth.uid()
         and u.status = 'paid'
    )
    where auth.uid() is not null
  ), false);
$$;

revoke all on function public.get_property_contact(uuid) from public;
grant execute on function public.get_property_contact(uuid) to anon, authenticated;
grant execute on function public.has_contact_unlock(uuid)  to anon, authenticated;
