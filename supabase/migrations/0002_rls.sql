-- =============================================================================
-- Kheja_Link — 0002_rls.sql
-- Row Level Security. Run AFTER 0001_schema.sql.
--
-- Guiding rules:
--   * Browsing rentals is public and requires no account.
--   * Only PUBLISHED listings (and their images/amenities) are publicly visible.
--   * A landlord can only ever touch rows they own.
--   * Favourites are private to their owner.
--   * Inquiries hold PII: the public may INSERT but never SELECT.
--   * Contact phone/email on profiles is never publicly selectable.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

-- Does the current user own this property? security definer so the policy can
-- read properties without recursing back through properties' own policies.
create or replace function public.owns_property(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.properties p
     where p.id = p_property_id
       and p.owner_id = auth.uid()
  );
$$;

-- Is this property publicly visible?
create or replace function public.property_is_public(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.properties p
     where p.id = p_property_id
       and p.status = 'published'
  );
$$;

create or replace function public.current_role_is(p_roles public.user_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles pr
     where pr.id = auth.uid()
       and pr.role = any(p_roles)
  );
$$;

grant execute on function public.owns_property(uuid)                 to anon, authenticated;
grant execute on function public.property_is_public(uuid)            to anon, authenticated;
grant execute on function public.current_role_is(public.user_role[]) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Enable RLS everywhere
-- -----------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.property_types     enable row level security;
alter table public.locations          enable row level security;
alter table public.amenities          enable row level security;
alter table public.properties         enable row level security;
alter table public.property_images    enable row level security;
alter table public.property_amenities enable row level security;
alter table public.favorites          enable row level security;
alter table public.inquiries          enable row level security;

-- -----------------------------------------------------------------------------
-- profiles
--   Read: a user reads their own full row. Everyone else must go through the
--   public_profiles view, which simply omits phone/email columns — so we also
--   allow reading rows that own a published listing, restricted by that view.
-- -----------------------------------------------------------------------------
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid());

drop policy if exists profiles_select_listing_owners on public.profiles;
create policy profiles_select_listing_owners on public.profiles
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.properties p
       where p.owner_id = profiles.id
         and p.status = 'published'
    )
  );

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Note: `role` and `is_verified` are deliberately NOT protected by a column
-- grant here — see the trigger below, which pins them for non-admins.
create or replace function public.profiles_guard_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null for trusted server-side work (migrations, seeds, the
  -- service role). This guard exists to stop an end user escalating their own
  -- privileges, so it should not fire outside a user request.
  if auth.uid() is null then
    return new;
  end if;

  if public.current_role_is(array['admin']::public.user_role[]) then
    return new;
  end if;

  -- A user may opt in to being a landlord, but may not grant themselves admin
  -- and may not self-verify.
  if new.role = 'admin' and old.role <> 'admin' then
    new.role := old.role;
  end if;
  new.is_verified := old.is_verified;
  return new;
end;
$$;

drop trigger if exists profiles_guard_privileged on public.profiles;
create trigger profiles_guard_privileged
  before update on public.profiles
  for each row execute function public.profiles_guard_privileged_columns();

-- -----------------------------------------------------------------------------
-- Lookup tables — world readable, admin writable
-- -----------------------------------------------------------------------------
drop policy if exists property_types_read on public.property_types;
create policy property_types_read on public.property_types
  for select to anon, authenticated using (true);

drop policy if exists property_types_admin_write on public.property_types;
create policy property_types_admin_write on public.property_types
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists locations_read on public.locations;
create policy locations_read on public.locations
  for select to anon, authenticated using (true);

drop policy if exists locations_admin_write on public.locations;
create policy locations_admin_write on public.locations
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists amenities_read on public.amenities;
create policy amenities_read on public.amenities
  for select to anon, authenticated using (true);

drop policy if exists amenities_admin_write on public.amenities;
create policy amenities_admin_write on public.amenities
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

-- -----------------------------------------------------------------------------
-- properties
-- -----------------------------------------------------------------------------
drop policy if exists properties_select_published on public.properties;
create policy properties_select_published on public.properties
  for select to anon, authenticated
  using (status = 'published');

drop policy if exists properties_select_own on public.properties;
create policy properties_select_own on public.properties
  for select to authenticated
  using (owner_id = auth.uid());

drop policy if exists properties_select_admin on public.properties;
create policy properties_select_admin on public.properties
  for select to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists properties_insert_own on public.properties;
create policy properties_insert_own on public.properties
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and public.current_role_is(array['landlord','admin']::public.user_role[])
  );

drop policy if exists properties_update_own on public.properties;
create policy properties_update_own on public.properties
  for update to authenticated
  using (owner_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]))
  with check (owner_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists properties_delete_own on public.properties;
create policy properties_delete_own on public.properties
  for delete to authenticated
  using (owner_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

-- -----------------------------------------------------------------------------
-- property_images — visibility follows the parent listing
-- -----------------------------------------------------------------------------
drop policy if exists property_images_select on public.property_images;
create policy property_images_select on public.property_images
  for select to anon, authenticated
  using (public.property_is_public(property_id) or public.owns_property(property_id));

drop policy if exists property_images_write on public.property_images;
create policy property_images_write on public.property_images
  for all to authenticated
  using (public.owns_property(property_id))
  with check (public.owns_property(property_id));

-- -----------------------------------------------------------------------------
-- property_amenities — same rule
-- -----------------------------------------------------------------------------
drop policy if exists property_amenities_select on public.property_amenities;
create policy property_amenities_select on public.property_amenities
  for select to anon, authenticated
  using (public.property_is_public(property_id) or public.owns_property(property_id));

drop policy if exists property_amenities_write on public.property_amenities;
create policy property_amenities_write on public.property_amenities
  for all to authenticated
  using (public.owns_property(property_id))
  with check (public.owns_property(property_id));

-- -----------------------------------------------------------------------------
-- favorites — strictly private to their owner
-- -----------------------------------------------------------------------------
drop policy if exists favorites_own on public.favorites;
create policy favorites_own on public.favorites
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- inquiries — public may INSERT (contact a landlord) but never SELECT.
-- Only the listing owner and the original sender can read one back.
-- -----------------------------------------------------------------------------
drop policy if exists inquiries_insert_public on public.inquiries;
create policy inquiries_insert_public on public.inquiries
  for insert to anon, authenticated
  with check (
    public.property_is_public(property_id)
    -- a signed-in sender must claim their own id; guests must leave it null
    and (sender_id is null or sender_id = auth.uid())
  );

drop policy if exists inquiries_select_owner_or_sender on public.inquiries;
create policy inquiries_select_owner_or_sender on public.inquiries
  for select to authenticated
  using (public.owns_property(property_id) or sender_id = auth.uid());

drop policy if exists inquiries_update_owner on public.inquiries;
create policy inquiries_update_owner on public.inquiries
  for update to authenticated
  using (public.owns_property(property_id))
  with check (public.owns_property(property_id));

drop policy if exists inquiries_delete_owner on public.inquiries;
create policy inquiries_delete_owner on public.inquiries
  for delete to authenticated
  using (public.owns_property(property_id));

-- -----------------------------------------------------------------------------
-- Storage: property-images + avatars buckets
-- Path convention: {auth.uid()}/{property_id}/{file}.  The first path segment
-- must match the uploader, which is what gives us per-user write isolation.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('property-images', 'property-images', true, 5242880,
   array['image/jpeg','image/png','image/webp','image/avif']),
  ('avatars', 'avatars', true, 2097152,
   array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "kheja property images are public" on storage.objects;
create policy "kheja property images are public" on storage.objects
  for select to anon, authenticated
  using (bucket_id in ('property-images', 'avatars'));

drop policy if exists "kheja users upload to own folder" on storage.objects;
create policy "kheja users upload to own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('property-images', 'avatars')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "kheja users update own files" on storage.objects;
create policy "kheja users update own files" on storage.objects
  for update to authenticated
  using (
    bucket_id in ('property-images', 'avatars')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "kheja users delete own files" on storage.objects;
create policy "kheja users delete own files" on storage.objects
  for delete to authenticated
  using (
    bucket_id in ('property-images', 'avatars')
    and (storage.foldername(name))[1] = auth.uid()::text
  );
