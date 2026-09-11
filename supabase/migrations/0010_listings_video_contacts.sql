-- =============================================================================
-- Kheja_Link — 0010_listings_video_contacts.sql
--
--   * far more detail on a listing, so tenants can decide before they travel
--   * video tours, alongside photos
--   * the landlord's and caretaker's names and numbers, plus the Kheja_Link
--     management line, all released together by the KSh 150 unlock
--   * storage for videos and partner logos
--
-- Safe to re-run. Run AFTER 0009_fix_unlock_null_bug.sql.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Listing detail
-- -----------------------------------------------------------------------------
do $$ begin
  create type public.electricity_billing as enum ('prepaid_token', 'postpaid', 'included', 'shared_meter');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.water_billing as enum ('included', 'metered', 'flat_rate', 'borehole', 'none');
exception when duplicate_object then null; end $$;

alter table public.properties
  add column if not exists building_name      text,
  add column if not exists floor_number       int,
  add column if not exists total_floors       int,
  add column if not exists service_charge     numeric(10,2),
  add column if not exists water_billing      public.water_billing,
  add column if not exists water_notes        text,
  add column if not exists electricity_billing public.electricity_billing,
  add column if not exists parking_spaces     int not null default 0,
  add column if not exists pets_allowed       boolean not null default false,
  add column if not exists min_lease_months   int,
  add column if not exists notice_months      int,
  add column if not exists nearby             text,     -- schools, stage, market
  add column if not exists security_details   text,
  add column if not exists internet_ready     boolean not null default false,
  add column if not exists is_gated           boolean not null default false,
  add column if not exists has_balcony        boolean not null default false,
  add column if not exists year_built         int,
  -- The people a tenant actually rings. Private until the unlock.
  add column if not exists landlord_name      text,
  add column if not exists caretaker_name     text,
  add column if not exists caretaker_phone    text;

do $$ begin
  alter table public.properties add constraint properties_floor_ok
    check (floor_number is null or floor_number between -5 and 200);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.properties add constraint properties_service_charge_ok
    check (service_charge is null or service_charge >= 0);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.properties add constraint properties_parking_ok
    check (parking_spaces between 0 and 100);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.properties add constraint properties_lease_ok
    check (min_lease_months is null or min_lease_months between 0 and 120);
exception when duplicate_object then null; end $$;

-- Public columns: grant SELECT so they show on the listing.
grant select (
  building_name, floor_number, total_floors, service_charge,
  water_billing, water_notes, electricity_billing, parking_spaces,
  pets_allowed, min_lease_months, notice_months, nearby, security_details,
  internet_ready, is_gated, has_balcony, year_built
) on public.properties to anon, authenticated;

-- Landlords may write every new column, including the private ones.
grant insert (
  building_name, floor_number, total_floors, service_charge,
  water_billing, water_notes, electricity_billing, parking_spaces,
  pets_allowed, min_lease_months, notice_months, nearby, security_details,
  internet_ready, is_gated, has_balcony, year_built,
  landlord_name, caretaker_name, caretaker_phone
) on public.properties to authenticated;

grant update (
  building_name, floor_number, total_floors, service_charge,
  water_billing, water_notes, electricity_billing, parking_spaces,
  pets_allowed, min_lease_months, notice_months, nearby, security_details,
  internet_ready, is_gated, has_balcony, year_built,
  landlord_name, caretaker_name, caretaker_phone
) on public.properties to authenticated;

-- landlord_name, caretaker_name and caretaker_phone are deliberately NOT in the
-- SELECT grant: like the phone number, they come back only via the unlock.

-- -----------------------------------------------------------------------------
-- app_settings — the management line, kept out of client code
-- -----------------------------------------------------------------------------
create table if not exists public.app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
-- No policies: nobody reads this table directly. It is read only inside the
-- security-definer unlock function below.

insert into public.app_settings (key, value) values
  ('management_phone', '+254710655709'),
  ('management_name',  'Kheja_Link Management')
on conflict (key) do update set value = excluded.value, updated_at = now();

-- -----------------------------------------------------------------------------
-- property_videos
-- -----------------------------------------------------------------------------
create table if not exists public.property_videos (
  id               uuid primary key default gen_random_uuid(),
  property_id      uuid not null references public.properties(id) on delete cascade,
  storage_path     text,
  public_url       text not null,
  thumbnail_url    text,
  caption          text,
  duration_seconds int,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now()
);

create index if not exists property_videos_property_idx
  on public.property_videos (property_id, sort_order);

alter table public.property_videos enable row level security;

drop policy if exists property_videos_select on public.property_videos;
create policy property_videos_select on public.property_videos
  for select to anon, authenticated
  using (public.property_is_public(property_id) or public.owns_property(property_id));

drop policy if exists property_videos_write on public.property_videos;
create policy property_videos_write on public.property_videos
  for all to authenticated
  using (public.owns_property(property_id))
  with check (public.owns_property(property_id));

grant select on public.property_videos to anon, authenticated;
grant insert, update, delete on public.property_videos to authenticated;

-- -----------------------------------------------------------------------------
-- Storage: videos and partner logos
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  -- 60 MB: long enough for a proper walk-through, short enough to upload on
  -- a mobile connection without it failing halfway.
  ('property-videos', 'property-videos', true, 62914560,
   array['video/mp4', 'video/quicktime', 'video/3gpp', 'video/webm']),
  ('partner-logos', 'partner-logos', true, 524288,
   array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml', 'image/x-icon',
         'image/vnd.microsoft.icon'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Extend the per-user folder rules from 0002 to cover videos.
drop policy if exists "kheja property images are public" on storage.objects;
create policy "kheja property images are public" on storage.objects
  for select to anon, authenticated
  using (bucket_id in ('property-images', 'avatars', 'property-videos', 'partner-logos'));

drop policy if exists "kheja users upload to own folder" on storage.objects;
create policy "kheja users upload to own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('property-images', 'avatars', 'property-videos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "kheja users update own files" on storage.objects;
create policy "kheja users update own files" on storage.objects
  for update to authenticated
  using (
    bucket_id in ('property-images', 'avatars', 'property-videos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "kheja users delete own files" on storage.objects;
create policy "kheja users delete own files" on storage.objects
  for delete to authenticated
  using (
    bucket_id in ('property-images', 'avatars', 'property-videos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =============================================================================
-- The unlock now returns everyone a tenant might need to reach
-- =============================================================================
drop function if exists public.get_property_contact(uuid);

create function public.get_property_contact(p_property_id uuid)
returns table (
  unlocked          boolean,
  landlord_name     text,
  contact_phone     text,
  contact_whatsapp  text,
  caretaker_name    text,
  caretaker_phone   text,
  management_name   text,
  management_phone  text,
  latitude          numeric,
  longitude         numeric
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
  v_mgmt_name  text;
  v_mgmt_phone text;
begin
  select p.owner_id, (p.status = 'published')
    into v_owner, v_is_public
    from public.properties p
   where p.id = p_property_id;

  if v_owner is null then
    return query select false, null::text, null::text, null::text, null::text,
                        null::text, null::text, null::text, null::numeric, null::numeric;
    return;
  end if;

  -- Every comparison coalesced: auth.uid() is NULL for a signed-out caller, and
  -- a NULL here once let this guard be skipped entirely (see 0009).
  v_entitled :=
    coalesce(v_owner = auth.uid(), false)
    or (
      coalesce(v_is_public, false)
      and coalesce(public.has_contact_unlock(p_property_id), false)
    );

  if v_entitled is not true then
    return query select false, null::text, null::text, null::text, null::text,
                        null::text, null::text, null::text, null::numeric, null::numeric;
    return;
  end if;

  select value into v_mgmt_name  from public.app_settings where key = 'management_name';
  select value into v_mgmt_phone from public.app_settings where key = 'management_phone';

  return query
    select true,
           -- Fall back to the account name when the landlord left it blank.
           coalesce(nullif(trim(p.landlord_name), ''), pr.full_name),
           p.contact_phone,
           p.contact_whatsapp,
           p.caretaker_name,
           p.caretaker_phone,
           v_mgmt_name,
           v_mgmt_phone,
           p.latitude,
           p.longitude
      from public.properties p
      left join public.profiles pr on pr.id = p.owner_id
     where p.id = p_property_id;
end;
$$;

revoke all on function public.get_property_contact(uuid) from public;
grant execute on function public.get_property_contact(uuid) to anon, authenticated;

-- A landlord editing their own listing reads back every private field.
drop function if exists public.get_my_property_private(uuid);

create function public.get_my_property_private(p_property_id uuid)
returns table (
  contact_phone    text,
  contact_whatsapp text,
  latitude         numeric,
  longitude        numeric,
  landlord_name    text,
  caretaker_name   text,
  caretaker_phone  text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.contact_phone, p.contact_whatsapp, p.latitude, p.longitude,
         p.landlord_name, p.caretaker_name, p.caretaker_phone
    from public.properties p
   where p.id = p_property_id
     and p.owner_id = auth.uid();
$$;

revoke all on function public.get_my_property_private(uuid) from public;
grant execute on function public.get_my_property_private(uuid) to authenticated;

-- Give the seeded listings sensible values so the new sections are not empty.
update public.properties
   set landlord_name       = coalesce(landlord_name, 'Kheja_Link Demo Landlord'),
       caretaker_name      = coalesce(caretaker_name, 'Caretaker on site'),
       caretaker_phone     = coalesce(caretaker_phone, '+254710655709'),
       water_billing       = coalesce(water_billing, 'metered'),
       electricity_billing = coalesce(electricity_billing, 'prepaid_token'),
       min_lease_months    = coalesce(min_lease_months, 6),
       notice_months       = coalesce(notice_months, 1),
       parking_spaces      = case when bedrooms >= 2 then greatest(parking_spaces, 1)
                                  else parking_spaces end,
       is_gated            = is_gated or bedrooms >= 2,
       internet_ready      = true,
       nearby              = coalesce(nearby,
                               'Matatu stage within 5 minutes walk. Supermarket and '
                               'shops nearby. Primary and secondary schools in the area.');
