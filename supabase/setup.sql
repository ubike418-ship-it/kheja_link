-- =============================================================================
-- Kheja_Link — complete database setup
-- Paste this whole file into the Supabase SQL Editor and press Run.
-- It is idempotent: running it twice is safe.
-- =============================================================================

-- =============================================================================
-- Kheja_Link — 0001_schema.sql
-- Core relational schema for the rental discovery platform.
-- Run this FIRST in the Supabase SQL Editor.
-- =============================================================================

-- Supabase installs extensions into either public or extensions depending on the
-- project's age, so keep both on the path for this script.
set search_path = public, extensions;

create extension if not exists "pgcrypto";
create extension if not exists "unaccent";

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('seeker', 'landlord', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.property_status as enum ('draft', 'pending', 'published', 'rented', 'archived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.price_period as enum ('month', 'year');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.inquiry_status as enum ('new', 'read', 'responded', 'closed');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- Shared trigger: keep updated_at honest
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- profiles — one row per auth user, created automatically on signup
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text,
  phone        text,
  avatar_url   text,
  role         public.user_role not null default 'seeker',
  is_verified  boolean not null default false,
  bio          text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint profiles_full_name_len check (full_name is null or char_length(full_name) <= 120),
  constraint profiles_phone_len     check (phone is null or char_length(phone) between 7 and 20)
);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-provision a profile whenever a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'role', '')::public.user_role, 'seeker')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Lookup tables
-- -----------------------------------------------------------------------------
create table if not exists public.property_types (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  description text,
  icon        text,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.locations (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,                    -- e.g. "Makutano"
  area       text,                             -- e.g. "Meru Town"
  county     text not null default 'Meru',     -- Kenya-wide ready
  latitude   numeric(9,6),
  longitude  numeric(9,6),
  created_at timestamptz not null default now()
);

create index if not exists locations_county_idx on public.locations (county);

create table if not exists public.amenities (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  icon       text,
  sort_order int not null default 0
);

-- -----------------------------------------------------------------------------
-- properties — the heart of the product
-- -----------------------------------------------------------------------------
create table if not exists public.properties (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  title            text not null,
  slug             text not null unique,
  description      text,
  property_type_id uuid not null references public.property_types(id) on delete restrict,
  location_id      uuid not null references public.locations(id) on delete restrict,
  address_line     text,

  price_amount     numeric(12,2) not null,
  price_currency   char(3) not null default 'KES',
  price_period     public.price_period not null default 'month',
  deposit_months   int not null default 1,

  bedrooms         int not null default 0,
  bathrooms        int not null default 0,
  size_sqft        int,

  is_premium       boolean not null default false,
  is_furnished     boolean not null default false,
  status           public.property_status not null default 'draft',
  available_from   date,

  contact_phone    text,
  contact_whatsapp text,

  view_count       int not null default 0,
  published_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint properties_title_len    check (char_length(title) between 6 and 160),
  constraint properties_price_pos    check (price_amount > 0),
  constraint properties_bedrooms_ok  check (bedrooms  between 0 and 50),
  constraint properties_bathrooms_ok check (bathrooms between 0 and 50),
  constraint properties_size_ok      check (size_sqft is null or size_sqft between 1 and 1000000),
  constraint properties_deposit_ok   check (deposit_months between 0 and 24)
);

-- Full-text search over title + address + description, maintained by trigger.
alter table public.properties add column if not exists search_vector tsvector;

create or replace function public.properties_search_vector_update()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.search_vector :=
      setweight(to_tsvector('english', unaccent(coalesce(new.title, ''))), 'A')
   || setweight(to_tsvector('english', unaccent(coalesce(new.address_line, ''))), 'B')
   || setweight(to_tsvector('english', unaccent(coalesce(new.description, ''))), 'C');
  return new;
end;
$$;

drop trigger if exists properties_search_vector on public.properties;
create trigger properties_search_vector
  before insert or update of title, description, address_line on public.properties
  for each row execute function public.properties_search_vector_update();

-- Stamp published_at the first time a listing goes live.
create or replace function public.properties_stamp_published()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'published' and new.published_at is null then
    new.published_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists properties_set_published on public.properties;
create trigger properties_set_published
  before insert or update of status on public.properties
  for each row execute function public.properties_stamp_published();

-- Deliberately NOT fired by view_count: a page view is not an edit, and letting
-- it bump updated_at would make the column (and the sitemap) meaningless.
drop trigger if exists properties_set_updated_at on public.properties;
create trigger properties_set_updated_at
  before update of
    title, description, property_type_id, location_id, address_line,
    price_amount, price_currency, price_period, deposit_months,
    bedrooms, bathrooms, size_sqft, is_premium, is_furnished,
    status, available_from, contact_phone, contact_whatsapp
  on public.properties
  for each row execute function public.set_updated_at();

create index if not exists properties_feed_idx     on public.properties (status, published_at desc);
create index if not exists properties_owner_idx    on public.properties (owner_id, created_at desc);
create index if not exists properties_type_idx     on public.properties (property_type_id) where status = 'published';
create index if not exists properties_location_idx on public.properties (location_id)      where status = 'published';
create index if not exists properties_price_idx    on public.properties (price_amount)     where status = 'published';
create index if not exists properties_bedrooms_idx on public.properties (bedrooms)         where status = 'published';
create index if not exists properties_premium_idx  on public.properties (is_premium)       where status = 'published';
create index if not exists properties_search_idx   on public.properties using gin (search_vector);

-- -----------------------------------------------------------------------------
-- property_images
-- -----------------------------------------------------------------------------
create table if not exists public.property_images (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  storage_path text,                     -- path inside the property-images bucket
  public_url   text not null,            -- resolved URL actually rendered
  alt_text     text,
  is_cover     boolean not null default false,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists property_images_property_idx
  on public.property_images (property_id, sort_order);

-- At most one cover image per property.
create unique index if not exists property_images_one_cover_idx
  on public.property_images (property_id) where is_cover;

-- -----------------------------------------------------------------------------
-- property_amenities (join)
-- -----------------------------------------------------------------------------
create table if not exists public.property_amenities (
  property_id uuid not null references public.properties(id) on delete cascade,
  amenity_id  uuid not null references public.amenities(id)  on delete cascade,
  primary key (property_id, amenity_id)
);

create index if not exists property_amenities_amenity_idx
  on public.property_amenities (amenity_id);

-- -----------------------------------------------------------------------------
-- favorites
-- -----------------------------------------------------------------------------
create table if not exists public.favorites (
  user_id     uuid not null references public.profiles(id)   on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, property_id)
);

create index if not exists favorites_user_idx on public.favorites (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- inquiries — a seeker (or guest) contacting a landlord. Holds PII.
-- -----------------------------------------------------------------------------
create table if not exists public.inquiries (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  sender_id   uuid references public.profiles(id) on delete set null,  -- null = guest
  name        text not null,
  email       text,
  phone       text,
  message     text not null,
  status      public.inquiry_status not null default 'new',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint inquiries_name_len    check (char_length(name) between 2 and 120),
  constraint inquiries_message_len check (char_length(message) between 10 and 2000),
  constraint inquiries_contactable check (email is not null or phone is not null)
);

create index if not exists inquiries_property_idx on public.inquiries (property_id, created_at desc);
create index if not exists inquiries_sender_idx   on public.inquiries (sender_id, created_at desc);

drop trigger if exists inquiries_set_updated_at on public.inquiries;
create trigger inquiries_set_updated_at
  before update on public.inquiries
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Public-safe author view: name/avatar only, never phone or email.
-- -----------------------------------------------------------------------------
drop view if exists public.public_profiles;
create view public.public_profiles
with (security_invoker = true) as
  select id, full_name, avatar_url, is_verified, role, created_at
  from public.profiles;

-- -----------------------------------------------------------------------------
-- increment_property_views — safe view counter.
-- security definer on purpose: it bypasses the owner-only UPDATE policy, but it
-- can only ever touch view_count, and only on an already-published listing.
-- -----------------------------------------------------------------------------
create or replace function public.increment_property_views(p_property_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.properties
     set view_count = view_count + 1
   where id = p_property_id
     and status = 'published';
end;
$$;

revoke all on function public.increment_property_views(uuid) from public;
grant execute on function public.increment_property_views(uuid) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Grants. Row Level Security still decides which rows are visible; these just
-- make the tables addressable by the API roles.
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select on
  public.property_types, public.locations, public.amenities,
  public.properties, public.property_images, public.property_amenities,
  public.public_profiles
to anon, authenticated;

grant select, insert, update, delete on
  public.profiles, public.properties, public.property_images,
  public.property_amenities, public.favorites, public.inquiries
to authenticated;

-- Guests may send an inquiry (and only that).
grant insert on public.inquiries to anon;

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

-- =============================================================================
-- Kheja_Link — 0003_seed.sql
-- Reference data (property types, Meru locations, amenities) plus the twelve
-- demo listings carried over from the original design mock, so the site looks
-- exactly as designed the moment it is connected.
--
-- Safe to re-run: every insert is idempotent on its natural key.
-- Run AFTER 0002_rls.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Property types
-- -----------------------------------------------------------------------------
insert into public.property_types (slug, name, description, icon, sort_order) values
  ('apartment',   'Apartment',   'Self-contained units in a multi-storey block',      'Building2',   10),
  ('bedsitter',   'Bedsitter',   'Single open-plan room with its own kitchen and bath','LayoutGrid',  20),
  ('single_room', 'Single Room', 'Affordable single rooms, popular with students',     'User',        30),
  ('bungalow',    'Bungalow',    'Standalone single-storey family homes',              'Home',        40),
  ('maisonette',  'Maisonette',  'Two-storey family homes, often in a gated court',    'Home',        50),
  ('studio',      'Studio',      'Compact open-plan self-contained units',             'LayoutGrid',  60),
  ('shop',        'Shop',        'Retail and commercial premises',                     'ShoppingBag', 70),
  ('hostel',      'Hostel',      'Shared student accommodation',                       'Users',       80)
on conflict (slug) do update
  set name        = excluded.name,
      description = excluded.description,
      icon        = excluded.icon,
      sort_order  = excluded.sort_order;

-- -----------------------------------------------------------------------------
-- Locations (Meru first — the county column keeps this Kenya-wide ready)
-- -----------------------------------------------------------------------------
insert into public.locations (slug, name, area, county, latitude, longitude) values
  ('makutano',   'Makutano',   'Meru Town',   'Meru',  0.056000, 37.655000),
  ('meru-town',  'Meru Town',  'Central',     'Meru',  0.047400, 37.649900),
  ('nkubu',      'Nkubu',      'Imenti South','Meru', -0.061000, 37.665000),
  ('kinoru',     'Kinoru',     'Meru Town',   'Meru',  0.061000, 37.636000),
  ('milimani',   'Milimani',   'Meru Town',   'Meru',  0.052000, 37.643000),
  ('must-area',  'MUST Area',  'Nchiru',      'Meru',  0.083000, 37.593000),
  ('gitoro',     'Gitoro',     'Meru Town',   'Meru',  0.075000, 37.680000),
  ('kaaga',      'Kaaga',      'Meru Town',   'Meru',  0.070000, 37.660000)
on conflict (slug) do update
  set name      = excluded.name,
      area      = excluded.area,
      county    = excluded.county,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

-- -----------------------------------------------------------------------------
-- Amenities
-- -----------------------------------------------------------------------------
insert into public.amenities (slug, name, icon, sort_order) values
  ('water',        'Constant Water',   'Droplets',    10),
  ('electricity',  'Prepaid Tokens',   'Zap',         20),
  ('parking',      'Parking',          'Car',         30),
  ('security',     '24/7 Security',    'ShieldCheck', 40),
  ('wifi',         'WiFi Ready',       'Wifi',        50),
  ('borehole',     'Borehole',         'Waves',       60),
  ('cctv',         'CCTV',             'Cctv',        70),
  ('balcony',      'Balcony',          'Sun',         80),
  ('lift',         'Lift',             'MoveVertical',90),
  ('gated',        'Gated Community',  'Fence',      100),
  ('furnished',    'Furnished',        'Sofa',       110),
  ('backup_power', 'Backup Generator', 'BatteryCharging', 120)
on conflict (slug) do update
  set name       = excluded.name,
      icon       = excluded.icon,
      sort_order = excluded.sort_order;

-- -----------------------------------------------------------------------------
-- Demo landlord + the twelve original design listings.
--
-- The listings need an owner, and owner_id must point at a real auth user.
-- We create one demo landlord account if it does not already exist:
--
--     email:    demo.landlord@khejalink.co.ke
--     password: KhejaDemo2026!
--
-- >>> Delete this account (or change its password) before going live. <<<
-- -----------------------------------------------------------------------------
set search_path = public, extensions;

do $$
declare
  v_owner uuid;
  v_type  jsonb;
  v_loc   jsonb;
  r       record;
  v_prop  uuid;
begin
  select id into v_owner from auth.users where email = 'demo.landlord@khejalink.co.ke';

  if v_owner is null then
    v_owner := gen_random_uuid();
    -- The empty-string token columns are not decorative: GoTrue scans them into
    -- Go strings and errors on NULL, which would make this account unable to
    -- sign in.
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token,
      email_change, email_change_token_new, email_change_token_current
    ) values (
      v_owner,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'demo.landlord@khejalink.co.ke',
      crypt('KhejaDemo2026!', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Kheja_Link Demo Landlord","role":"landlord"}'::jsonb,
      now(), now(),
      '', '', '', '', ''
    );

    -- GoTrue also expects an identity row for the email provider.
    insert into auth.identities (
      id, user_id, provider_id, provider, identity_data,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_owner, v_owner::text, 'email',
      jsonb_build_object(
        'sub', v_owner::text,
        'email', 'demo.landlord@khejalink.co.ke',
        'email_verified', true,
        'phone_verified', false
      ),
      now(), now(), now()
    )
    on conflict do nothing;
  end if;

  -- The on_auth_user_created trigger creates the profile; make sure it exists
  -- and is a verified landlord either way.
  insert into public.profiles (id, full_name, phone, role, is_verified, bio)
  values (
    v_owner,
    'Kheja_Link Demo Landlord',
    '+254710655709',
    'landlord',
    true,
    'Verified demo listings showcasing Kheja_Link across Meru County.'
  )
  on conflict (id) do update
    set full_name    = excluded.full_name,
        phone        = excluded.phone,
        role         = 'landlord',
        is_verified  = true,
        bio          = excluded.bio;

  -- Lookup maps, so the listing rows below stay readable.
  select jsonb_object_agg(slug, id) into v_type from public.property_types;
  select jsonb_object_agg(slug, id) into v_loc  from public.locations;

  for r in
    select * from (values
      ('executive-3br-rental-apartment-makutano', 'Executive 3BR Rental Apartment',
       'apartment', 'makutano', 45000, 3, 2, 1800, false,
       'A bright, executive three-bedroom apartment in the heart of Makutano. Master ensuite, fitted kitchen, ample parking and round-the-clock security. Walking distance to Greenwood Mall and the Meru–Nanyuki highway.',
       'Off Meru–Maua Road, Makutano',
       'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?auto=format&fit=crop&q=80&w=1200'),

      ('spacious-family-rental-home-nkubu', 'Spacious Family Rental Home',
       'bungalow', 'nkubu', 35000, 3, 2, 2000, false,
       'A generous three-bedroom bungalow on its own compound in Nkubu. Mature garden, borehole water, detached servant quarters and a quiet residential street ideal for families.',
       'Nkubu, Imenti South',
       'https://images.unsplash.com/photo-1568605114967-8130f3a36994?auto=format&fit=crop&q=80&w=1200'),

      ('modern-2br-apartment-unit-meru-town', 'Modern 2BR Apartment Unit',
       'apartment', 'meru-town', 25000, 2, 1, 1200, false,
       'Newly finished two-bedroom unit right in Meru Town. Tiled throughout, large windows, reliable county water and prepaid electricity tokens. Minutes from the CBD.',
       'Meru Town, Central',
       'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&q=80&w=1200'),

      ('summit-heights-residences-makutano', 'Summit Heights Residences',
       'apartment', 'makutano', 30000, 2, 2, 1100, false,
       'Contemporary two-bedroom apartments in a well-managed Makutano block. Lift access, backup generator, CCTV and secure basement parking.',
       'Summit Heights, Makutano',
       'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?auto=format&fit=crop&q=80&w=1200'),

      ('greenfield-rental-units-kinoru', 'Greenfield Rental Units',
       'apartment', 'kinoru', 28000, 2, 1, 950, false,
       'Well-kept two-bedroom units in leafy Kinoru. Gated community with a shared courtyard, constant water and a resident caretaker on site.',
       'Greenfield Court, Kinoru',
       'https://images.unsplash.com/photo-1536376074432-bf12406b4b74?auto=format&fit=crop&q=80&w=1200'),

      ('spacious-student-room-must', 'Spacious Student Room',
       'single_room', 'must-area', 8500, 1, 1, 250, false,
       'Clean, spacious single rooms a short walk from Meru University of Science and Technology. Shared water points, secure gate and a study-friendly compound.',
       'Nchiru, near MUST main gate',
       'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&q=80&w=1200'),

      ('comfortable-single-room-milimani', 'Comfortable Single Room',
       'single_room', 'milimani', 7000, 1, 1, 200, false,
       'Affordable single room in quiet Milimani. Own metered electricity, shared water and a caretaker on the compound. Well suited to students and young professionals.',
       'Milimani, Meru Town',
       'https://images.unsplash.com/photo-1554995207-c18c203602cb?auto=format&fit=crop&q=80&w=1200'),

      ('modern-bedsitter-unit-makutano', 'Modern Bedsitter Unit',
       'bedsitter', 'makutano', 15000, 1, 1, 400, false,
       'Modern self-contained bedsitter with a fitted kitchenette, hot shower and private balcony. Secure block in Makutano with 24-hour lighting.',
       'Makutano, Meru',
       'https://images.unsplash.com/photo-1522156373667-4c7234bbd804?auto=format&fit=crop&q=80&w=1200'),

      ('executive-bedsitter-meru-town', 'Executive Bedsitter',
       'bedsitter', 'meru-town', 12000, 1, 1, 350, false,
       'Neat executive bedsitter in Meru Town. Tiled floors, built-in wardrobe and a private bathroom, with the CBD on your doorstep.',
       'Meru Town, Central',
       'https://images.unsplash.com/photo-1536376074432-bf12406b4b74?auto=format&fit=crop&q=80&w=1200'),

      ('premium-luxury-suite-makutano', 'Premium Luxury Suite',
       'apartment', 'makutano', 60000, 2, 2, 1400, true,
       'A premium two-bedroom suite finished to a high standard: quartz worktops, underfloor-heated bathrooms, private balcony with a view over Makutano, lift, generator and dedicated parking.',
       'Makutano Heights, Makutano',
       'https://images.unsplash.com/photo-1613490493576-7fde63acd811?auto=format&fit=crop&q=80&w=1200'),

      ('prime-retail-shop-space-meru-town', 'Prime Retail Shop Space',
       'shop', 'meru-town', 35000, 0, 0, 500, false,
       'High-footfall retail space on Meru Town main street. Roller shutter frontage, three-phase power and a rear store room. Ideal for a boutique, pharmacy or electronics shop.',
       'Main Street, Meru Town',
       'https://images.unsplash.com/photo-1534452203293-494d7ddbf7e0?auto=format&fit=crop&q=80&w=1200'),

      ('modern-commercial-stall-makutano', 'Modern Commercial Stall',
       'shop', 'makutano', 12000, 0, 0, 150, false,
       'Compact commercial stall in a busy Makutano arcade. Steady daily footfall, shared washrooms and secure overnight lock-up.',
       'Makutano Arcade, Makutano',
       'https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&q=80&w=1200')
    ) as t(slug, title, type_slug, loc_slug, price, beds, baths, sqft, premium, description, address, image)
  loop
    insert into public.properties (
      owner_id, title, slug, description, property_type_id, location_id, address_line,
      price_amount, price_currency, price_period, deposit_months,
      bedrooms, bathrooms, size_sqft, is_premium, status, available_from,
      contact_phone, contact_whatsapp
    ) values (
      v_owner, r.title, r.slug, r.description,
      (v_type ->> r.type_slug)::uuid,
      (v_loc  ->> r.loc_slug)::uuid,
      r.address,
      r.price, 'KES', 'month', 1,
      r.beds, r.baths, r.sqft, r.premium, 'published', current_date,
      '+254710655709', '+254710655709'
    )
    on conflict (slug) do update
      set title       = excluded.title,
          description = excluded.description,
          status      = 'published'
    returning id into v_prop;

    insert into public.property_images (property_id, public_url, alt_text, is_cover, sort_order)
    select v_prop, r.image, r.title, true, 0
    where not exists (
      select 1 from public.property_images pi
       where pi.property_id = v_prop and pi.is_cover
    );

    -- A sensible default amenity set so the detail page is not bare.
    insert into public.property_amenities (property_id, amenity_id)
    select v_prop, a.id
      from public.amenities a
     where a.slug in ('water', 'electricity', 'security', 'parking')
    on conflict do nothing;
  end loop;
end $$;

-- =============================================================================
-- Kheja_Link — 0004_marketplace.sql
--
-- Adds, on top of the base schema:
--   * like counts on listings
--   * in-app notifications, including "a home you liked is vacant again"
--   * the KSh 150 contact unlock, enforced in the database rather than the UI
--   * tenancies: booked -> checked in -> moved out, with landlord notifications
--   * house rules on a listing
--   * the partner directory behind the movers / internet / cleaning rails
--
-- Safe to re-run. Run AFTER 0003_seed.sql.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
do $$ begin
  create type public.notification_type as enum (
    'vacancy', 'inquiry', 'booking', 'check_in', 'move_out', 'listing_status', 'system'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.unlock_status as enum ('pending', 'paid', 'failed', 'refunded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tenancy_status as enum ('booked', 'checked_in', 'moved_out', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.partner_category as enum ('movers', 'isp', 'cleaning');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- New columns on properties
-- -----------------------------------------------------------------------------
alter table public.properties add column if not exists like_count  int not null default 0;
alter table public.properties add column if not exists house_rules text;

-- The exact position of the house, as opposed to locations.latitude/longitude
-- which is only the area. This is part of what the KSh 150 unlocks, so it is
-- revoked from the API roles below.
alter table public.properties add column if not exists latitude  numeric(9,6);
alter table public.properties add column if not exists longitude numeric(9,6);

-- -----------------------------------------------------------------------------
-- notifications — in-app only, no push infrastructure
-- -----------------------------------------------------------------------------
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  type        public.notification_type not null default 'system',
  title       text not null,
  body        text,
  property_id uuid references public.properties(id) on delete cascade,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, is_read, created_at desc);

-- -----------------------------------------------------------------------------
-- contact_unlocks — the KSh 150 purchase
-- -----------------------------------------------------------------------------
create table if not exists public.contact_unlocks (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  property_id  uuid not null references public.properties(id) on delete cascade,
  amount       numeric(10,2) not null default 150,
  currency     char(3) not null default 'KES',
  status       public.unlock_status not null default 'pending',
  provider     text not null default 'paystack',
  provider_ref text,
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  constraint contact_unlocks_amount_positive check (amount > 0)
);

-- A person pays once per house; re-opening it later stays unlocked.
create unique index if not exists contact_unlocks_one_paid_idx
  on public.contact_unlocks (user_id, property_id) where status = 'paid';

create index if not exists contact_unlocks_user_idx on public.contact_unlocks (user_id);
create unique index if not exists contact_unlocks_ref_idx
  on public.contact_unlocks (provider_ref) where provider_ref is not null;

-- -----------------------------------------------------------------------------
-- tenancies — booked, checked in, moved out
-- -----------------------------------------------------------------------------
create table if not exists public.tenancies (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  tenant_id     uuid not null references public.profiles(id) on delete cascade,
  status        public.tenancy_status not null default 'booked',
  booked_at     timestamptz not null default now(),
  checked_in_at timestamptz,
  moved_out_at  timestamptz,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists tenancies_property_idx on public.tenancies (property_id, status);
create index if not exists tenancies_tenant_idx   on public.tenancies (tenant_id, created_at desc);

-- One live tenancy per person per house.
create unique index if not exists tenancies_one_active_idx
  on public.tenancies (property_id, tenant_id)
  where status in ('booked', 'checked_in');

drop trigger if exists tenancies_set_updated_at on public.tenancies;
create trigger tenancies_set_updated_at
  before update on public.tenancies
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- partners — the movers / internet / cleaning rails under a listing
-- -----------------------------------------------------------------------------
create table if not exists public.partners (
  id          uuid primary key default gen_random_uuid(),
  category    public.partner_category not null,
  slug        text not null unique,
  name        text not null,
  tagline     text,
  -- Null until a real agreement exists. Until then the app draws a styled
  -- name tile, so no third-party trademark is reproduced.
  logo_url    text,
  brand_color text not null default '#2563EB',
  icon        text,
  phone       text,
  url         text,
  is_ours     boolean not null default false,
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists partners_category_idx
  on public.partners (category, sort_order) where is_active;

-- =============================================================================
-- Like counts
-- =============================================================================
create or replace function public.sync_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.properties
       set like_count = like_count + 1
     where id = new.property_id;
    return new;
  else
    update public.properties
       set like_count = greatest(0, like_count - 1)
     where id = old.property_id;
    return old;
  end if;
end;
$$;

drop trigger if exists favorites_sync_like_count on public.favorites;
create trigger favorites_sync_like_count
  after insert or delete on public.favorites
  for each row execute function public.sync_like_count();

-- Backfill for anything saved before this migration.
update public.properties p
   set like_count = coalesce((
     select count(*) from public.favorites f where f.property_id = p.id
   ), 0);

-- =============================================================================
-- Vacancy notifications
--
-- The point of the feature: someone likes a house that is taken, and hears
-- about it the moment it frees up.
-- =============================================================================
create or replace function public.notify_watchers_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_location text;
begin
  if new.status = old.status then
    return new;
  end if;

  select l.name into v_location from public.locations l where l.id = new.location_id;

  -- Became available again.
  if new.status = 'published' and old.status in ('rented', 'archived', 'draft') then
    insert into public.notifications (user_id, type, title, body, property_id)
    select f.user_id,
           'vacancy',
           'A home you liked is available',
           new.title || ' in ' || coalesce(v_location, 'Meru') ||
             ' is vacant again. Be quick — saved homes go fast.',
           new.id
      from public.favorites f
     where f.property_id = new.id
       and f.user_id <> new.owner_id;
  end if;

  -- Just taken.
  if new.status = 'rented' and old.status = 'published' then
    insert into public.notifications (user_id, type, title, body, property_id)
    select f.user_id,
           'listing_status',
           'A home you liked has been taken',
           new.title || ' is no longer available. We will tell you if it frees up.',
           new.id
      from public.favorites f
     where f.property_id = new.id
       and f.user_id <> new.owner_id;
  end if;

  return new;
end;
$$;

drop trigger if exists properties_notify_watchers on public.properties;
create trigger properties_notify_watchers
  after update of status on public.properties
  for each row execute function public.notify_watchers_on_status_change();

-- =============================================================================
-- Tenancy notifications, so a landlord knows who is coming and going
-- =============================================================================
create or replace function public.notify_landlord_on_tenancy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
  v_name  text;
begin
  select p.owner_id, p.title into v_owner, v_title
    from public.properties p where p.id = new.property_id;

  select coalesce(pr.full_name, 'Someone') into v_name
    from public.profiles pr where pr.id = new.tenant_id;

  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, type, title, body, property_id)
    values (v_owner, 'booking', 'New booking request',
            v_name || ' has booked to move into ' || v_title || '.', new.property_id);
    return new;
  end if;

  if new.status <> old.status then
    if new.status = 'checked_in' then
      insert into public.notifications (user_id, type, title, body, property_id)
      values (v_owner, 'check_in', 'Tenant has checked in',
              v_name || ' has moved into ' || v_title || '.', new.property_id);
    elsif new.status = 'moved_out' then
      insert into public.notifications (user_id, type, title, body, property_id)
      values (v_owner, 'move_out', 'Tenant has moved out',
              v_name || ' has moved out of ' || v_title ||
                '. Publish it again to let people know it is vacant.',
              new.property_id);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists tenancies_notify_landlord on public.tenancies;
create trigger tenancies_notify_landlord
  after insert or update of status on public.tenancies
  for each row execute function public.notify_landlord_on_tenancy();

-- Tell the landlord when someone new asks about a listing.
create or replace function public.notify_landlord_on_inquiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
begin
  select p.owner_id, p.title into v_owner, v_title
    from public.properties p where p.id = new.property_id;

  insert into public.notifications (user_id, type, title, body, property_id)
  values (v_owner, 'inquiry', 'New inquiry',
          new.name || ' asked about ' || v_title || '.', new.property_id);
  return new;
end;
$$;

drop trigger if exists inquiries_notify_landlord on public.inquiries;
create trigger inquiries_notify_landlord
  after insert on public.inquiries
  for each row execute function public.notify_landlord_on_inquiry();

-- =============================================================================
-- The paywall
--
-- Contact details and the exact map position are removed from the API roles
-- entirely, so no crafted request can read them. They come back only through
-- get_property_contact(), which checks for ownership or a paid unlock.
-- =============================================================================
revoke select (contact_phone, contact_whatsapp, latitude, longitude)
  on public.properties from anon, authenticated;

create or replace function public.has_contact_unlock(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.contact_unlocks u
     where u.property_id = p_property_id
       and u.user_id = auth.uid()
       and u.status = 'paid'
  );
$$;

-- A later migration changes this function's return shape, which
-- `create or replace` cannot undo on a re-run.
drop function if exists public.get_property_contact(uuid);

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
  v_owner uuid;
  v_is_public boolean;
  v_entitled boolean;
begin
  select p.owner_id, (p.status = 'published')
    into v_owner, v_is_public
    from public.properties p
   where p.id = p_property_id;

  if v_owner is null then
    return;
  end if;

  -- The owner always sees their own; everyone else needs to have paid, and
  -- only on a listing that is actually public.
  v_entitled := (v_owner = auth.uid())
                or (v_is_public and public.has_contact_unlock(p_property_id));

  if not v_entitled then
    return query select false, null::text, null::text, null::numeric, null::numeric;
    return;
  end if;

  return query
    select true, p.contact_phone, p.contact_whatsapp, p.latitude, p.longitude
      from public.properties p
     where p.id = p_property_id;
end;
$$;

revoke all on function public.get_property_contact(uuid) from public;
grant execute on function public.get_property_contact(uuid) to anon, authenticated;
grant execute on function public.has_contact_unlock(uuid)  to anon, authenticated;

-- Called by the payment webhook once the provider confirms. security definer so
-- it can flip the row without granting users UPDATE on contact_unlocks.
create or replace function public.confirm_contact_unlock(
  p_reference text,
  p_provider  text default 'paystack'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  update public.contact_unlocks
     set status = 'paid', paid_at = now(), provider = p_provider
   where provider_ref = p_reference
     and status <> 'paid'
  returning id into v_id;

  return v_id is not null;
end;
$$;

revoke all on function public.confirm_contact_unlock(text, text) from public, anon, authenticated;

-- =============================================================================
-- Row Level Security
-- =============================================================================
alter table public.notifications   enable row level security;
alter table public.contact_unlocks enable row level security;
alter table public.tenancies       enable row level security;
alter table public.partners        enable row level security;

-- Notifications belong to exactly one person.
drop policy if exists notifications_own on public.notifications;
create policy notifications_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated using (user_id = auth.uid());

-- Unlocks: a user may start one for themselves and read their own. Only the
-- security-definer confirm function may mark one paid.
drop policy if exists contact_unlocks_select_own on public.contact_unlocks;
create policy contact_unlocks_select_own on public.contact_unlocks
  for select to authenticated using (user_id = auth.uid());

drop policy if exists contact_unlocks_insert_own on public.contact_unlocks;
create policy contact_unlocks_insert_own on public.contact_unlocks
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

-- Tenancies: the tenant and the property's owner can see them.
drop policy if exists tenancies_select on public.tenancies;
create policy tenancies_select on public.tenancies
  for select to authenticated
  using (tenant_id = auth.uid() or public.owns_property(property_id));

drop policy if exists tenancies_insert_own on public.tenancies;
create policy tenancies_insert_own on public.tenancies
  for insert to authenticated
  with check (tenant_id = auth.uid() and public.property_is_public(property_id));

drop policy if exists tenancies_update on public.tenancies;
create policy tenancies_update on public.tenancies
  for update to authenticated
  using (tenant_id = auth.uid() or public.owns_property(property_id))
  with check (tenant_id = auth.uid() or public.owns_property(property_id));

-- Partners are a public directory.
drop policy if exists partners_read on public.partners;
create policy partners_read on public.partners
  for select to anon, authenticated using (is_active);

drop policy if exists partners_admin_write on public.partners;
create policy partners_admin_write on public.partners
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
grant select                on public.partners       to anon, authenticated;
grant select, update, delete on public.notifications to authenticated;
grant select, insert        on public.contact_unlocks to authenticated;
grant select, insert, update on public.tenancies      to authenticated;

-- =============================================================================
-- Kheja_Link — 0005_seed_partners_hostels.sql
--
--   * the partner directory shown under a listing
--   * hostel and student-accommodation listings, with photos
--
-- Safe to re-run. Run AFTER 0004_marketplace.sql.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Partners
--
-- logo_url is deliberately null for every company but our own. The app draws a
-- styled name tile in its place, so no third-party trademark is reproduced and
-- nobody is implied to be a partner who has not agreed to be one. Fill in
-- logo_url once an agreement exists and the tile becomes a real logo with no
-- code change.
-- -----------------------------------------------------------------------------
insert into public.partners
  (category, slug, name, tagline, brand_color, icon, phone, url, is_ours, sort_order)
values
  -- Movers ------------------------------------------------------------------
  ('movers', 'movement', 'Movement', 'Our own moving service', '#2563EB',
   'truck', '+254710655709', null, true, 10),
  ('movers', 'nellions', 'Nellions', 'Household & office moving', '#0F766E',
   'truck', null, null, false, 20),
  ('movers', 'moving-solutions', 'Moving Solutions', 'Local moves in Meru', '#B45309',
   'truck', null, null, false, 30),
  ('movers', 'superior-movers', 'Superior Movers', 'Packing and transport', '#7C3AED',
   'truck', null, null, false, 40),
  ('movers', 'meru-pickups', 'Meru Pickups', 'Affordable pickup hire', '#DC2626',
   'truck', null, null, false, 50),

  -- Internet ----------------------------------------------------------------
  ('isp', 'safaricom-home', 'Safaricom Home', 'Fibre & 5G router', '#16A34A',
   'wifi', null, null, false, 10),
  ('isp', 'zuku', 'Zuku Fibre', 'Home fibre & TV', '#2563EB',
   'wifi', null, null, false, 20),
  ('isp', 'faiba', 'Faiba', 'JTL home fibre', '#EA580C',
   'wifi', null, null, false, 30),
  ('isp', 'poa-internet', 'Poa Internet', 'Low-cost home WiFi', '#0891B2',
   'wifi', null, null, false, 40),
  ('isp', 'liquid-home', 'Liquid Home', 'Fibre to the home', '#DB2777',
   'wifi', null, null, false, 50),

  -- Cleaning ----------------------------------------------------------------
  ('cleaning', 'sparkle-clean', 'Sparkle Clean', 'Move-in deep cleaning', '#0891B2',
   'sparkles', null, null, false, 10),
  ('cleaning', 'freshco-cleaners', 'FreshCo Cleaners', 'Homes & offices', '#16A34A',
   'sparkles', null, null, false, 20),
  ('cleaning', 'klin-house', 'Klin House', 'Sofa & carpet washing', '#7C3AED',
   'sparkles', null, null, false, 30),
  ('cleaning', 'meru-shine', 'Meru Shine', 'Post-construction clean', '#D97706',
   'sparkles', null, null, false, 40),
  ('cleaning', 'homecare-ke', 'HomeCare KE', 'Fumigation & sanitising', '#DC2626',
   'sparkles', null, null, false, 50)
on conflict (slug) do update
  set name        = excluded.name,
      tagline     = excluded.tagline,
      brand_color = excluded.brand_color,
      icon        = excluded.icon,
      category    = excluded.category,
      sort_order  = excluded.sort_order,
      is_ours     = excluded.is_ours;

-- -----------------------------------------------------------------------------
-- Hostels and student accommodation
--
-- Photographs are Unsplash, whose licence permits commercial use without
-- attribution. Replace them with real photographs of the actual rooms before
-- launch — a listing with someone else's photo is the thing tenants distrust
-- most.
-- -----------------------------------------------------------------------------
do $$
declare
  v_owner uuid;
  v_type  jsonb;
  v_loc   jsonb;
  r       record;
  v_prop  uuid;
  v_idx   int;
  v_url   text;
begin
  select id into v_owner from auth.users
   where email = 'demo.landlord@khejalink.co.ke';

  if v_owner is null then
    raise notice 'Demo landlord missing — run 0003_seed.sql first. Skipping hostels.';
    return;
  end if;

  select jsonb_object_agg(slug, id) into v_type from public.property_types;
  select jsonb_object_agg(slug, id) into v_loc  from public.locations;

  for r in
    select * from (values
      ('must-gate-hostel-block-a', 'MUST Gate Hostel — Block A',
       'hostel', 'must-area', 6500, 1, 1, 180, false,
       'Purpose-built student hostel two minutes from the MUST main gate. Single and shared rooms, study desk in every room, communal kitchen, laundry area and a warden on site. Water tank and backup power, so revision nights are never interrupted.',
       'Nchiru, opposite MUST main gate',
       array[
         'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('nchiru-scholars-hostel', 'Nchiru Scholars Hostel',
       'hostel', 'must-area', 5500, 1, 1, 160, false,
       'Affordable shared hostel rooms for MUST students. Bunk or single beds, shared bathrooms kept clean daily, free WiFi in the common room and a secure gate locked from 10pm. Popular with first years.',
       'Nchiru, Meru',
       array[
         'https://images.unsplash.com/photo-1541123437800-1bb1317badc2?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('kaaga-girls-hostel', 'Kaaga Ladies Hostel',
       'hostel', 'kaaga', 7500, 1, 1, 200, false,
       'Ladies-only hostel in quiet Kaaga with 24-hour security, CCTV on every corridor and a resident matron. Rooms are self-contained with a study nook, and there is a shared kitchen and reading room.',
       'Kaaga, Meru',
       array[
         'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('meru-town-executive-hostel', 'Meru Town Executive Hostel',
       'hostel', 'meru-town', 9000, 1, 1, 240, true,
       'A step up from the usual student room: private ensuite, fitted study desk, fast fibre WiFi included in the rent, and a rooftop common area. Walking distance to Meru Town college campuses.',
       'Meru Town, Central',
       array[
         'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&q=80&w=1200'
       ]),

      -- A couple of the empty types, so search is not full of dead ends.
      ('kinoru-modern-studio', 'Kinoru Modern Studio',
       'studio', 'kinoru', 18000, 1, 1, 480, false,
       'Bright open-plan studio with a fitted kitchenette, private balcony and plenty of natural light. Ideal for a young professional who wants their own space without an apartment''s cost.',
       'Kinoru, Meru',
       array[
         'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1493809842364-78817add7ffb?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('gitoro-family-maisonette', 'Gitoro Family Maisonette',
       'maisonette', 'gitoro', 55000, 4, 3, 2400, true,
       'Spacious four-bedroom maisonette in a gated Gitoro court. Master ensuite, downstairs guest room, private garden, double garage and a borehole shared between only six houses.',
       'Gitoro, Meru',
       array[
         'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&q=80&w=1200'
       ])
    ) as t(slug, title, type_slug, loc_slug, price, beds, baths, sqft, premium,
           description, address, images)
  loop
    insert into public.properties (
      owner_id, title, slug, description, property_type_id, location_id, address_line,
      price_amount, price_currency, price_period, deposit_months,
      bedrooms, bathrooms, size_sqft, is_premium, status, available_from,
      contact_phone, contact_whatsapp, latitude, longitude, house_rules
    ) values (
      v_owner, r.title, r.slug, r.description,
      (v_type ->> r.type_slug)::uuid,
      (v_loc  ->> r.loc_slug)::uuid,
      r.address,
      r.price, 'KES', 'month', 1,
      r.beds, r.baths, r.sqft, r.premium, 'published', current_date,
      '+254710655709', '+254710655709',
      0.05 + (random() - 0.5) * 0.06,
      37.65 + (random() - 0.5) * 0.06,
      case when r.type_slug = 'hostel' then
        'No overnight guests without signing them in at the gate. Quiet hours 10pm to 6am during term. No cooking in the rooms — use the shared kitchen. Gate locks at 11pm.'
      else
        'No loud music after 10pm. Keep shared areas clean. Notify the caretaker before moving furniture in or out.'
      end
    )
    on conflict (slug) do update
      set title       = excluded.title,
          description = excluded.description,
          house_rules = excluded.house_rules,
          status      = 'published'
    returning id into v_prop;

    -- Replace the gallery so re-running keeps the photo set correct.
    delete from public.property_images where property_id = v_prop;

    v_idx := 0;
    foreach v_url in array r.images loop
      insert into public.property_images
        (property_id, public_url, alt_text, is_cover, sort_order)
      values (v_prop, v_url, r.title, v_idx = 0, v_idx);
      v_idx := v_idx + 1;
    end loop;

    insert into public.property_amenities (property_id, amenity_id)
    select v_prop, a.id
      from public.amenities a
     where a.slug in ('water', 'electricity', 'security', 'wifi')
    on conflict do nothing;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Give the original twelve listings a second and third photo, so the gallery on
-- the detail page has something to page through.
-- -----------------------------------------------------------------------------
do $$
declare
  r      record;
  extras text[] := array[
    'https://images.unsplash.com/photo-1484154218962-a197022b5858?auto=format&fit=crop&q=80&w=1200',
    'https://images.unsplash.com/photo-1502005229762-cf1b2da7c5d6?auto=format&fit=crop&q=80&w=1200'
  ];
  v_url  text;
  v_next int;
begin
  for r in
    select p.id
      from public.properties p
     where p.status = 'published'
       and (select count(*) from public.property_images i where i.property_id = p.id) = 1
  loop
    select coalesce(max(sort_order), 0) + 1 into v_next
      from public.property_images where property_id = r.id;

    foreach v_url in array extras loop
      insert into public.property_images
        (property_id, public_url, alt_text, is_cover, sort_order)
      values (r.id, v_url, null, false, v_next);
      v_next := v_next + 1;
    end loop;
  end loop;
end $$;

-- Exact coordinates for the original listings, so the unlocked map has a pin.
update public.properties p
   set latitude  = coalesce(p.latitude,  l.latitude  + (random() - 0.5) * 0.01),
       longitude = coalesce(p.longitude, l.longitude + (random() - 0.5) * 0.01)
  from public.locations l
 where l.id = p.location_id
   and (p.latitude is null or p.longitude is null);

-- =============================================================================
-- Kheja_Link — 0006_lock_contact_columns.sql
--
-- 0004 tried to hide the contact columns with a column-level REVOKE, which does
-- nothing on its own: a table-level GRANT SELECT already covers every column,
-- and revoking a column privilege does not carve a hole in it. Postgres needs
-- the table grant removed first, then SELECT granted column by column.
--
-- After this, contact_phone, contact_whatsapp, latitude and longitude are
-- unreadable through the API by any role. They come back only through
-- get_property_contact(), which requires ownership or a paid unlock.
--
-- Note this makes `select=*` fail on properties, which is intended — both apps
-- select explicit column lists.
--
-- Safe to re-run. Run AFTER 0004_marketplace.sql.
-- =============================================================================

set search_path = public, extensions;

-- Drop the blanket grants, including the ineffective column revokes from 0004.
revoke all privileges on public.properties from anon;
revoke all privileges on public.properties from authenticated;

-- Everything except contact_phone, contact_whatsapp, latitude, longitude.
-- search_vector is omitted too: it is an internal index, not content.
grant select (
  id, owner_id, title, slug, description,
  property_type_id, location_id, address_line,
  price_amount, price_currency, price_period, deposit_months,
  bedrooms, bathrooms, size_sqft,
  is_premium, is_furnished, status, available_from,
  view_count, published_at, created_at, updated_at,
  like_count, house_rules
) on public.properties to anon, authenticated;

-- Landlords still need to write the protected columns on their own listings;
-- Row Level Security decides which rows, this decides which columns.
grant insert (
  owner_id, title, slug, description,
  property_type_id, location_id, address_line,
  price_amount, price_currency, price_period, deposit_months,
  bedrooms, bathrooms, size_sqft,
  is_premium, is_furnished, status, available_from,
  contact_phone, contact_whatsapp, latitude, longitude, house_rules
) on public.properties to authenticated;

grant update (
  title, slug, description,
  property_type_id, location_id, address_line,
  price_amount, price_currency, price_period, deposit_months,
  bedrooms, bathrooms, size_sqft,
  is_premium, is_furnished, status, available_from,
  contact_phone, contact_whatsapp, latitude, longitude, house_rules
) on public.properties to authenticated;

grant delete on public.properties to authenticated;

-- -----------------------------------------------------------------------------
-- A landlord managing a listing needs to read back what they wrote. RLS already
-- limits this to rows they own.
-- -----------------------------------------------------------------------------
-- A later migration changes this function's return shape, which
-- `create or replace` cannot undo on a re-run.
drop function if exists public.get_my_property_private(uuid);

create or replace function public.get_my_property_private(p_property_id uuid)
returns table (
  contact_phone    text,
  contact_whatsapp text,
  latitude         numeric,
  longitude        numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select p.contact_phone, p.contact_whatsapp, p.latitude, p.longitude
    from public.properties p
   where p.id = p_property_id
     and p.owner_id = auth.uid();
$$;

revoke all on function public.get_my_property_private(uuid) from public;
grant execute on function public.get_my_property_private(uuid) to authenticated;

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

-- =============================================================================
-- Kheja_Link — 0008_grant_search_vector.sql
--
-- 0006 granted SELECT column by column and left search_vector out. Postgres
-- requires SELECT on a column to *filter* by it as well as to read it, so
-- full-text search started failing with "permission denied for table
-- properties".
--
-- The column is an internal tsvector, not content, and no query ever asks for
-- it in a projection — but the grant is needed for the WHERE clause.
--
-- Safe to re-run.
-- =============================================================================

set search_path = public, extensions;

grant select (search_vector) on public.properties to anon, authenticated;

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

-- A later migration changes this function's return shape, which
-- `create or replace` cannot undo on a re-run.
drop function if exists public.get_property_contact(uuid);

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

-- =============================================================================
-- Kheja_Link — 0011_real_partners.sql
--
-- Replaces the partner directory with real companies and their real logos.
--
-- 0005 seeded several placeholder names that are not real businesses (Meru
-- Pickups, Sparkle Clean, FreshCo Cleaners, Klin House, Meru Shine, HomeCare KE,
-- Moving Solutions, Superior Movers). Showing an invented company to a tenant as
-- somewhere to call is misleading, so they are removed here.
--
-- Every company below was confirmed to exist before being listed — its domain
-- resolves and serves a site — and every logo is that company's own icon,
-- fetched from its own site and hosted in the partner-logos bucket.
--
-- Where a real company's logo could not be retrieved at a usable size,
-- logo_url stays NULL and the app draws a styled name tile instead.
--
-- These companies are listed for tenants' convenience. None of them is a
-- partner of Kheja_Link, and the app says so under the rails.
--
-- Safe to re-run. Run AFTER 0010.
-- =============================================================================

set search_path = public, extensions;

-- Remove the placeholders. Kept in one explicit list so nothing real is touched.
delete from public.partners
 where slug in (
   'meru-pickups', 'moving-solutions', 'superior-movers',
   'sparkle-clean', 'freshco-cleaners', 'klin-house', 'meru-shine', 'homecare-ke',
   'liquid-home'
 );

-- Upsert the real directory. The logo host is built from the project URL so
-- this file carries no environment-specific address.
do $$
declare
  v_base text := 'https://vyoefhmmmgsnwnfztuah.supabase.co/storage/v1/object/public/partner-logos/';
begin
  insert into public.partners
    (category, slug, name, tagline, logo_url, brand_color, url, is_ours, sort_order)
  values
    -- Movers --------------------------------------------------------------
    -- Our own company. It has no logo of its own yet, so it carries the
    -- Kheja_Link mark.
    ('movers', 'movement', 'Movement', 'Our own moving service',
     v_base || 'movement.jpg', '#2563EB', null, true, 10),
    ('movers', 'nellions', 'Nellions', 'Household and office moving',
     v_base || 'nellions.png', '#6B2C91', 'https://nellions.co.ke', false, 20),
    ('movers', 'cube-movers', 'Cube Movers', 'Packing, moving and storage',
     v_base || 'cube-movers.png', '#1D4ED8', 'https://cubemovers.co.ke', false, 30),

    -- Internet ------------------------------------------------------------
    ('isp', 'safaricom-home', 'Safaricom Home', 'Home fibre and 5G',
     v_base || 'safaricom-home.png', '#16A34A', 'https://www.safaricom.co.ke', false, 10),
    ('isp', 'zuku', 'Zuku', 'Home fibre and TV',
     v_base || 'zuku.png', '#0EA5E9', 'https://zuku.co.ke', false, 20),
    ('isp', 'airtel', 'Airtel', '4G and home internet',
     v_base || 'airtel.png', '#E40000', 'https://www.airtelkenya.com', false, 30),
    ('isp', 'faiba', 'Faiba by JTL', 'Home fibre',
     v_base || 'faiba.png', '#16A34A', 'https://faiba.co.ke', false, 40),
    ('isp', 'telkom', 'Telkom', 'Home internet',
     v_base || 'telkom.png', '#0891B2', 'https://telkom.co.ke', false, 50),
    ('isp', 'starlink', 'Starlink', 'Satellite internet anywhere',
     v_base || 'starlink.png', '#111827', 'https://www.starlink.com', false, 60),
    ('isp', 'poa-internet', 'Poa Internet', 'Affordable home WiFi',
     null, '#0891B2', 'https://poa.co.ke', false, 70),

    -- Cleaning and hygiene ------------------------------------------------
    ('cleaning', 'rentokil-initial', 'Rentokil Initial', 'Fumigation and hygiene',
     null, '#D6001C', 'https://www.rentokil.co.ke', false, 10)
  on conflict (slug) do update
    set category    = excluded.category,
        name        = excluded.name,
        tagline     = excluded.tagline,
        logo_url    = excluded.logo_url,
        brand_color = excluded.brand_color,
        url         = excluded.url,
        is_ours     = excluded.is_ours,
        sort_order  = excluded.sort_order,
        is_active   = true;
end $$;

-- =============================================================================
-- Kheja_Link — 0012_hunting_availability_requests.sql
--
-- The product update:
--   * business rules in the database (hunting fee, listing fee, feature flags)
--     instead of scattered through two clients
--   * the KES 500 house hunting fee: payments, a per-tenant service status and
--     a configurable split of each payment
--   * property availability: available / occupied / notice given / unavailable,
--     with an expected vacancy date, so an occupied home stays discoverable
--   * property interests: "notify me when this home is free" and "notify me
--     about any 1-bedroom in Makutano under KSh 15,000"
--   * house requests, built on the existing tenancies table, with landlord
--     accept / decline and a guard so nobody can move a request on their own
--   * notification preferences and an email / SMS outbox that a server job
--     drains, so channels are chosen by the user rather than hard-coded
--   * a Stays (short-term) waitlist, while the feature itself stays switched off
--   * the partners table becomes a manually onboarded service-provider
--     directory with an approval step; only MoveMate Kenya is live
--   * run_daily_maintenance(), called by the keep-alive jobs, which also keeps
--     a free Supabase project from pausing
--
-- Safe to re-run. Run AFTER 0011_real_partners.sql.
--
-- Note on types: new status columns are text + CHECK rather than enums. Postgres
-- refuses to use an enum value in the same transaction that added it, and the
-- SQL editor runs this whole file as one transaction, so an enum here would
-- make the file fail on first run.
-- =============================================================================

set search_path = public, extensions;

-- =============================================================================
-- 1. Business settings
--
-- app_settings already holds the management line (private). Rows marked
-- is_public are readable by both apps, so a price or a feature flag can change
-- without shipping a new build.
-- =============================================================================
alter table public.app_settings add column if not exists is_public   boolean not null default false;
alter table public.app_settings add column if not exists description text;

-- Values are only written the first time. Re-running this file refreshes the
-- descriptions but never overwrites a value an admin has since changed.
insert into public.app_settings (key, value, is_public, description) values
  ('hunting_fee',                          '500',  true,  'House hunting fee a tenant pays, in hunting_fee_currency. Separate from rent and deposit.'),
  ('hunting_fee_currency',                 'KES',  true,  'Currency of the house hunting fee.'),
  ('hunting_fee_unlocks_contacts',         'true', true,  'While a tenant''s hunting service is active, landlord contacts on every listing are unlocked.'),
  ('contact_unlock_fee',                   '150',  true,  'Per-listing contact unlock, for tenants without an active hunting service.'),
  ('landlord_listing_fee',                 '0',    true,  'Fee to list a property. 0 = free.'),
  ('landlord_listing_fee_offer_label',     'Free Property Listing — Limited-Time Offer', true, 'Shown to landlords while the listing fee is 0.'),
  ('landlord_listing_fee_offer_ends_on',   '',     true,  'Optional ISO date the free-listing offer ends. Blank = no date is shown.'),
  ('stays_enabled',                        'false', true, 'Short-term Stays. Keep false until the feature is finished.'),
  ('service_provider_registration_enabled','false', true, 'Public self-registration for movers, internet and cleaning companies. Off: they are onboarded manually.'),
  ('service_provider_onboarding_fee',      '',     false, 'Commercial fee for onboarding a provider, set by the Kheja_Link team. Blank = not set.'),
  ('tenant_notifications_enabled',         'true', true,  'Master switch for vacancy and match alerts to tenants.'),
  ('last_maintenance_at',                  '',     false, 'Stamped by run_daily_maintenance().')
on conflict (key) do update
  set is_public   = excluded.is_public,
      description = excluded.description;

alter table public.app_settings enable row level security;

drop policy if exists app_settings_public_read on public.app_settings;
create policy app_settings_public_read on public.app_settings
  for select to anon, authenticated
  using (is_public or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

grant select on public.app_settings to anon, authenticated;
grant insert, update on public.app_settings to authenticated;

-- Readers for use inside other functions. security definer so they can see the
-- private rows too; they only ever return a single named value.
create or replace function public.setting_text(p_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(value), '') from public.app_settings where key = p_key;
$$;

create or replace function public.setting_num(p_key text, p_default numeric default 0)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v text := public.setting_text(p_key);
begin
  return coalesce(v::numeric, p_default);
exception when others then
  return p_default;
end;
$$;

create or replace function public.setting_bool(p_key text, p_default boolean default false)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(lower(public.setting_text(p_key)) in ('true', '1', 'yes', 'on'), p_default);
$$;

revoke all on function public.setting_text(text)                  from public, anon, authenticated;
revoke all on function public.setting_num(text, numeric)          from public, anon, authenticated;
revoke all on function public.setting_bool(text, boolean)         from public, anon, authenticated;

-- =============================================================================
-- 2. Fee allocation — how each payment is split
--
-- Deliberately a table, not constants: the split of the KES 500 is a business
-- decision that has not been finalised. Until it is, everything goes to the
-- platform. Each confirmed payment snapshots the split in effect at that time
-- into payment_allocations, so changing the rule later never rewrites history.
-- =============================================================================
create table if not exists public.fee_allocations (
  id            uuid primary key default gen_random_uuid(),
  product       text not null,
  party         text not null,
  share_percent numeric(5,2) not null,
  is_active     boolean not null default true,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint fee_allocations_product_ok
    check (product in ('hunting_fee', 'landlord_listing_fee', 'provider_onboarding_fee')),
  constraint fee_allocations_party_ok check (party ~ '^[a-z_]{2,40}$'),
  constraint fee_allocations_share_ok check (share_percent between 0 and 100),
  constraint fee_allocations_unique unique (product, party)
);

insert into public.fee_allocations (product, party, share_percent, notes) values
  ('hunting_fee', 'platform', 100, 'Default until the split is agreed. Add partner / landlord rows and lower this.')
on conflict (product, party) do nothing;

drop trigger if exists fee_allocations_set_updated_at on public.fee_allocations;
create trigger fee_allocations_set_updated_at
  before update on public.fee_allocations
  for each row execute function public.set_updated_at();

alter table public.fee_allocations enable row level security;

drop policy if exists fee_allocations_admin on public.fee_allocations;
create policy fee_allocations_admin on public.fee_allocations
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

grant select, insert, update, delete on public.fee_allocations to authenticated;

-- =============================================================================
-- 3. Onboarding — one flag per role, stored on the account
--
-- The app also keeps a per-device flag, so the tutorial never shows twice on a
-- phone even before sign-in. The account flag carries it across devices.
-- =============================================================================
alter table public.profiles add column if not exists tenant_onboarded_at   timestamptz;
alter table public.profiles add column if not exists landlord_onboarded_at timestamptz;
alter table public.profiles add column if not exists stays_onboarded_at    timestamptz;

-- =============================================================================
-- 4. Property availability
--
-- status still says whether a listing is public (draft / published / archived
-- / rented). availability says whether the home can be moved into:
--
--   available     free now
--   occupied      someone lives there, no date yet
--   notice_given  occupied, but free from available_from
--   unavailable   temporarily off the market (repairs, etc.)
--
-- A published listing stays discoverable in every state, so a tenant who sees
-- an occupied home can ask to be told when it frees up.
-- =============================================================================
alter table public.properties add column if not exists availability            text not null default 'available';
alter table public.properties add column if not exists notice_date             date;
alter table public.properties add column if not exists availability_updated_at timestamptz;

do $$ begin
  alter table public.properties add constraint properties_availability_ok
    check (availability in ('available', 'occupied', 'notice_given', 'unavailable'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.properties add constraint properties_notice_needs_date
    check (availability <> 'notice_given' or available_from is not null);
exception when duplicate_object then null; end $$;

-- Backfill before any new trigger exists, so this cannot send notifications.
update public.properties
   set availability = 'occupied'
 where status = 'rented' and availability = 'available';

update public.properties
   set availability = 'notice_given'
 where status = 'published'
   and availability = 'available'
   and available_from is not null
   and available_from > current_date;

grant select (availability, notice_date, availability_updated_at)
  on public.properties to anon, authenticated;
grant insert (availability, notice_date) on public.properties to authenticated;
grant update (availability, notice_date) on public.properties to authenticated;

create index if not exists properties_availability_idx
  on public.properties (availability, available_from) where status = 'published';

-- Keep availability and status coherent whichever one the landlord changes.
create or replace function public.properties_sync_availability()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    -- Marked rented: it is occupied.
    if new.status = 'rented' and old.status <> 'rented'
       and new.availability is not distinct from old.availability
       and new.availability = 'available' then
      new.availability := 'occupied';
    end if;

    -- Re-published after being rented, with no availability chosen: free now.
    if old.status = 'rented' and new.status = 'published'
       and new.availability is not distinct from old.availability
       and new.availability = 'occupied' then
      new.availability := 'available';
    end if;
  end if;

  -- "Available" with a future date means "coming available" — unless the
  -- landlord has just switched to "available now", in which case the old date
  -- is stale and goes.
  if new.availability = 'available'
     and new.available_from is not null and new.available_from > current_date then
    if tg_op = 'UPDATE' and old.availability is distinct from 'available' then
      new.available_from := null;
    else
      new.availability := 'notice_given';
    end if;
  end if;

  if new.availability = 'available' then
    new.notice_date := null;
  end if;

  if tg_op = 'INSERT'
     or new.availability  is distinct from old.availability
     or new.available_from is distinct from old.available_from then
    new.availability_updated_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists properties_sync_availability on public.properties;
create trigger properties_sync_availability
  before insert or update of status, availability, available_from on public.properties
  for each row execute function public.properties_sync_availability();

-- Can a tenant request this home right now?
create or replace function public.property_is_requestable(p_property_id uuid)
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
       and p.availability = 'available'
  );
$$;

grant execute on function public.property_is_requestable(uuid) to anon, authenticated;

-- =============================================================================
-- 5. Notifications: preferences, channels and the outbox
-- =============================================================================

-- notifications.type becomes text (see the note at the top about enums).
do $$ begin
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'notifications'
         and column_name = 'type') <> 'text' then
    alter table public.notifications alter column "type" drop default;
    alter table public.notifications alter column "type" type text using "type"::text;
    alter table public.notifications alter column "type" set default 'system';
  end if;
end $$;

do $$ begin
  alter table public.notifications add constraint notifications_type_ok
    check (type in ('vacancy', 'inquiry', 'booking', 'check_in', 'move_out',
                    'listing_status', 'system', 'payment', 'request', 'match'));
exception when duplicate_object then null; end $$;

create table if not exists public.notification_preferences (
  user_id             uuid primary key references public.profiles(id) on delete cascade,
  in_app              boolean not null default true,
  email               boolean not null default true,
  -- Off by default: an SMS costs money and nobody asked for one yet.
  sms                 boolean not null default false,
  availability_alerts boolean not null default true,
  request_updates     boolean not null default true,
  updated_at          timestamptz not null default now()
);

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_own on public.notification_preferences;
create policy notification_preferences_own on public.notification_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.notification_preferences to authenticated;

-- Email and SMS waiting to be sent. Nobody reads this through the API: a
-- server job holding the service role drains it (src/app/api/cron).
create table if not exists public.notification_outbox (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  notification_id uuid references public.notifications(id) on delete set null,
  channel         text not null,
  subject         text not null,
  body            text,
  property_id     uuid references public.properties(id) on delete set null,
  status          text not null default 'pending',
  attempts        int  not null default 0,
  last_error      text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  constraint notification_outbox_channel_ok check (channel in ('email', 'sms')),
  constraint notification_outbox_status_ok check (status in ('pending', 'sent', 'failed', 'skipped'))
);

create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (created_at) where status = 'pending';

-- One email and one SMS per notification, however often a job retries.
create unique index if not exists notification_outbox_once_idx
  on public.notification_outbox (notification_id, channel) where notification_id is not null;

alter table public.notification_outbox enable row level security;
-- No policies: invisible to anon and authenticated.
grant select, update on public.notification_outbox to service_role;

-- The one place a notification is created. Honours the user's preferences, so
-- no trigger can spam someone who switched a category off.
--
--   p_category: 'account'      always delivered in-app (payments, security)
--               'availability' vacancy and match alerts
--               'request'      house request updates
--               'listing'      landlord listing and lead events
create or replace function public.notify_user(
  p_user     uuid,
  p_type     text,
  p_title    text,
  p_body     text,
  p_property uuid default null,
  p_category text default 'account'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_in_app       boolean;
  v_email        boolean;
  v_sms          boolean;
  v_availability boolean;
  v_requests     boolean;
  v_id           uuid;
begin
  if p_user is null then
    return null;
  end if;

  select np.in_app, np.email, np.sms, np.availability_alerts, np.request_updates
    into v_in_app, v_email, v_sms, v_availability, v_requests
    from public.notification_preferences np
   where np.user_id = p_user;

  v_in_app       := coalesce(v_in_app, true);
  v_email        := coalesce(v_email, true);
  v_sms          := coalesce(v_sms, false);
  v_availability := coalesce(v_availability, true);
  v_requests     := coalesce(v_requests, true);

  if p_category = 'availability'
     and (not v_availability or not public.setting_bool('tenant_notifications_enabled', true)) then
    return null;
  end if;

  if p_category = 'request' and not v_requests then
    return null;
  end if;

  -- Account notices always land in-app: they are about money or access.
  if v_in_app or p_category = 'account' then
    insert into public.notifications (user_id, type, title, body, property_id)
    values (p_user, p_type, p_title, p_body, p_property)
    returning id into v_id;
  end if;

  if v_email then
    insert into public.notification_outbox (user_id, notification_id, channel, subject, body, property_id)
    values (p_user, v_id, 'email', p_title, p_body, p_property);
  end if;

  if v_sms then
    insert into public.notification_outbox (user_id, notification_id, channel, subject, body, property_id)
    values (p_user, v_id, 'sms', p_title, p_body, p_property);
  end if;

  return v_id;
end;
$$;

revoke all on function public.notify_user(uuid, text, text, text, uuid, text) from public, anon, authenticated;

-- =============================================================================
-- 6. Property interests — "notify me"
--
-- Two shapes in one table:
--   * property_id set: this exact home. Becomes 'notified' once it frees up.
--   * property_id null: a standing search (type, area, budget, bedrooms). Stays
--     'active' and fires for every new match.
-- =============================================================================
create table if not exists public.property_interests (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles(id) on delete cascade,
  property_id           uuid references public.properties(id) on delete cascade,
  property_type_id      uuid references public.property_types(id) on delete set null,
  location_id           uuid references public.locations(id) on delete set null,
  min_price             numeric(12,2),
  max_price             numeric(12,2),
  bedrooms              int,
  available_within_days int,
  notification_enabled  boolean not null default true,
  status                text not null default 'active',
  last_notified_at      timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint property_interests_status_ok check (status in ('active', 'notified', 'cancelled')),
  constraint property_interests_has_target check (
    property_id is not null or property_type_id is not null or location_id is not null
    or max_price is not null or min_price is not null or bedrooms is not null
  ),
  constraint property_interests_budget_ok check (
    (min_price is null or min_price >= 0) and (max_price is null or max_price > 0)
    and (min_price is null or max_price is null or min_price <= max_price)
  ),
  constraint property_interests_bedrooms_ok check (bedrooms is null or bedrooms between 0 and 50),
  constraint property_interests_window_ok
    check (available_within_days is null or available_within_days between 1 and 365)
);

create index if not exists property_interests_user_idx
  on public.property_interests (user_id, created_at desc);
create index if not exists property_interests_property_idx
  on public.property_interests (property_id) where status = 'active';
create index if not exists property_interests_search_idx
  on public.property_interests (property_type_id, location_id)
  where status = 'active' and property_id is null;

-- One live subscription per person per home.
create unique index if not exists property_interests_one_active_idx
  on public.property_interests (user_id, property_id)
  where property_id is not null and status = 'active';

drop trigger if exists property_interests_set_updated_at on public.property_interests;
create trigger property_interests_set_updated_at
  before update on public.property_interests
  for each row execute function public.set_updated_at();

alter table public.property_interests enable row level security;

drop policy if exists property_interests_select_own on public.property_interests;
create policy property_interests_select_own on public.property_interests
  for select to authenticated using (user_id = auth.uid());

drop policy if exists property_interests_insert_own on public.property_interests;
create policy property_interests_insert_own on public.property_interests
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'active'
    and (property_id is null or public.property_is_public(property_id))
  );

drop policy if exists property_interests_update_own on public.property_interests;
create policy property_interests_update_own on public.property_interests
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists property_interests_delete_own on public.property_interests;
create policy property_interests_delete_own on public.property_interests
  for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.property_interests to authenticated;

-- A landlord sees how many people are waiting on each of their homes, and their
-- first names — never a phone number or email.
create or replace function public.get_my_property_interest_counts()
returns table (property_id uuid, saved_count int, waiting_count int)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         (select count(*)::int from public.favorites f where f.property_id = p.id),
         (select count(*)::int from public.property_interests i
           where i.property_id = p.id and i.status = 'active')
    from public.properties p
   where p.owner_id = auth.uid();
$$;

create or replace function public.get_interested_tenants(p_property_id uuid)
returns table (first_name text, kind text, since timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select split_part(coalesce(nullif(trim(pr.full_name), ''), 'A tenant'), ' ', 1),
         x.kind,
         x.since
    from (
      select i.user_id, 'waiting'::text as kind, i.created_at as since
        from public.property_interests i
       where i.property_id = p_property_id and i.status = 'active'
      union all
      select f.user_id, 'saved'::text, f.created_at
        from public.favorites f
       where f.property_id = p_property_id
    ) x
    join public.profiles pr on pr.id = x.user_id
   where exists (
     select 1 from public.properties p
      where p.id = p_property_id and p.owner_id = auth.uid()
   )
   order by x.since desc
   limit 100;
$$;

revoke all on function public.get_my_property_interest_counts() from public, anon;
revoke all on function public.get_interested_tenants(uuid)      from public, anon;
grant execute on function public.get_my_property_interest_counts() to authenticated;
grant execute on function public.get_interested_tenants(uuid)      to authenticated;

-- =============================================================================
-- 7. Matching — who hears about a home when it frees up
-- =============================================================================
create or replace function public.notify_property_availability(
  p_property_id uuid,
  p_event       text   -- 'available' | 'coming'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  p          record;
  v_type     text;
  v_location text;
  v_when     text;
  v_sent     int := 0;
  r          record;
begin
  select pr.* into p from public.properties pr where pr.id = p_property_id;
  if not found or p.status <> 'published' then
    return 0;
  end if;

  select t.name into v_type     from public.property_types t where t.id = p.property_type_id;
  select l.name into v_location from public.locations l      where l.id = p.location_id;
  v_type     := coalesce(v_type, 'home');
  v_location := coalesce(v_location, 'Meru');
  v_when     := coalesce(to_char(p.available_from, 'FMDD Mon YYYY'), 'soon');

  -- People who asked about this exact home: saved it, or tapped "Notify me".
  for r in
    select distinct u.user_id from (
      select f.user_id from public.favorites f where f.property_id = p.id
      union
      select i.user_id from public.property_interests i
       where i.property_id = p.id and i.status = 'active' and i.notification_enabled
    ) u
    where u.user_id <> p.owner_id
  loop
    if p_event = 'available' then
      perform public.notify_user(r.user_id, 'vacancy', 'House Available',
        'The ' || lower(v_type) || ' you saved, ' || p.title || ' in ' || v_location ||
        ', is now available. Open it to request the house.',
        p.id, 'availability');
    else
      perform public.notify_user(r.user_id, 'vacancy', 'Coming available',
        p.title || ' in ' || v_location || ' is expected to be free from ' || v_when ||
        '. We will tell you again when it is available.',
        p.id, 'availability');
    end if;
    v_sent := v_sent + 1;
  end loop;

  if p_event = 'available' then
    update public.property_interests
       set status = 'notified', last_notified_at = now()
     where property_id = p.id and status = 'active';
  end if;

  -- Standing searches. Skip anyone just told about this home above, and anyone
  -- already matched to it in the last week.
  for r in
    select distinct i.user_id
      from public.property_interests i
     where i.property_id is null
       and i.status = 'active'
       and i.notification_enabled
       and i.user_id <> p.owner_id
       and (i.property_type_id is null or i.property_type_id = p.property_type_id)
       and (i.location_id      is null or i.location_id      = p.location_id)
       and (i.min_price        is null or p.price_amount    >= i.min_price)
       and (i.max_price        is null or p.price_amount    <= i.max_price)
       and (i.bedrooms         is null or p.bedrooms         = i.bedrooms)
       and (
         p_event = 'available'
         or i.available_within_days is null
         or p.available_from <= current_date + i.available_within_days
       )
       and not exists (select 1 from public.favorites f
                        where f.property_id = p.id and f.user_id = i.user_id)
       and not exists (select 1 from public.property_interests i2
                        where i2.property_id = p.id and i2.user_id = i.user_id)
       and not exists (select 1 from public.notifications n
                        where n.user_id = i.user_id and n.property_id = p.id
                          and n.type = 'match'
                          and n.created_at > now() - interval '7 days')
  loop
    perform public.notify_user(r.user_id, 'match',
      case when p_event = 'available' then 'New Match Found' else 'Match coming available' end,
      case when p_event = 'available'
        then 'A ' || lower(v_type) || ' in ' || v_location || ' matching your preferences is now available: ' || p.title || '.'
        else 'A ' || lower(v_type) || ' in ' || v_location || ' matching your preferences will be available from ' || v_when || ': ' || p.title || '.'
      end,
      p.id, 'availability');
    v_sent := v_sent + 1;
  end loop;

  update public.property_interests i
     set last_notified_at = now()
   where i.property_id is null and i.status = 'active'
     and exists (select 1 from public.notifications n
                  where n.user_id = i.user_id and n.property_id = p.id
                    and n.type = 'match' and n.created_at > now() - interval '1 minute');

  return v_sent;
end;
$$;

revoke all on function public.notify_property_availability(uuid, text) from public, anon, authenticated;

-- Replaces the 0004 status-only watcher. Covers status and availability.
create or replace function public.notify_watchers_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_was_open boolean;
  v_is_open  boolean;
  v_was_coming boolean;
  v_is_coming  boolean;
begin
  if tg_op = 'INSERT' then
    if new.status = 'published' and new.availability = 'available' then
      perform public.notify_property_availability(new.id, 'available');
    elsif new.status = 'published' and new.availability = 'notice_given' then
      perform public.notify_property_availability(new.id, 'coming');
    end if;
    return new;
  end if;

  v_was_open   := old.status = 'published' and old.availability = 'available';
  v_is_open    := new.status = 'published' and new.availability = 'available';
  v_was_coming := old.status = 'published' and old.availability = 'notice_given';
  v_is_coming  := new.status = 'published' and new.availability = 'notice_given';

  if v_is_open and not v_was_open then
    perform public.notify_property_availability(new.id, 'available');
  elsif v_is_coming and (not v_was_coming or new.available_from is distinct from old.available_from) then
    perform public.notify_property_availability(new.id, 'coming');
  end if;

  -- Just taken: tell the people who saved it, so they are not left guessing.
  if v_was_open and not v_is_open and new.status in ('published', 'rented')
     and new.availability in ('occupied', 'notice_given') then
    insert into public.notifications (user_id, type, title, body, property_id)
    select f.user_id, 'listing_status', 'A home you saved has been taken',
           new.title || ' is no longer available. We will tell you if it frees up.',
           new.id
      from public.favorites f
     where f.property_id = new.id
       and f.user_id <> new.owner_id
       and coalesce((select np.availability_alerts and np.in_app
                       from public.notification_preferences np
                      where np.user_id = f.user_id), true);
  end if;

  return new;
end;
$$;

drop trigger if exists properties_notify_watchers on public.properties;
create trigger properties_notify_watchers
  after insert or update of status, availability, available_from on public.properties
  for each row execute function public.notify_watchers_on_status_change();

-- =============================================================================
-- 8. House requests — the tenancies table, extended
--
--   booked      pending, sent by the tenant
--   viewed      the landlord has opened it
--   accepted    the landlord agreed; the tenant can now move in
--   declined    the landlord said no
--   checked_in  the tenant moved in
--   moved_out   the tenancy ended
--   cancelled   withdrawn by the tenant
-- =============================================================================
drop index if exists public.tenancies_one_active_idx;
-- Triggers declared "update of status" pin the column's type; both are
-- recreated below.
drop trigger if exists tenancies_notify_landlord on public.tenancies;
drop trigger if exists tenancies_hunting_track on public.tenancies;

do $$ begin
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'tenancies'
         and column_name = 'status') <> 'text' then
    alter table public.tenancies alter column status drop default;
    alter table public.tenancies alter column status type text using status::text;
    alter table public.tenancies alter column status set default 'booked';
  end if;
end $$;

do $$ begin
  alter table public.tenancies add constraint tenancies_status_ok
    check (status in ('booked', 'viewed', 'accepted', 'declined',
                      'checked_in', 'moved_out', 'cancelled'));
exception when duplicate_object then null; end $$;

alter table public.tenancies add column if not exists preferred_move_in date;
alter table public.tenancies add column if not exists landlord_response text;
alter table public.tenancies add column if not exists responded_at      timestamptz;

do $$ begin
  alter table public.tenancies add constraint tenancies_response_len
    check (landlord_response is null or char_length(landlord_response) <= 1000);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.tenancies add constraint tenancies_note_len
    check (note is null or char_length(note) <= 1000);
exception when duplicate_object then null; end $$;

-- One open request per person per home — the database, not the app, stops
-- duplicates.
create unique index if not exists tenancies_one_active_idx
  on public.tenancies (property_id, tenant_id)
  where status in ('booked', 'viewed', 'accepted', 'checked_in');

-- A request can only be made for a home that is free now.
drop policy if exists tenancies_insert_own on public.tenancies;
create policy tenancies_insert_own on public.tenancies
  for insert to authenticated
  with check (
    tenant_id = auth.uid()
    and status = 'booked'
    and public.property_is_requestable(property_id)
    and not public.owns_property(property_id)
  );

-- Who may move a request where. RLS already limits updates to the tenant and
-- the owner; this limits *which* changes each of them may make.
create or replace function public.tenancies_guard_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_is_owner boolean;
  v_is_admin boolean;
begin
  -- Trusted server-side work (service role, maintenance) is not a user request.
  if v_uid is null then
    return new;
  end if;

  if new.property_id <> old.property_id or new.tenant_id <> old.tenant_id then
    raise exception 'A request cannot be moved to another home or person.'
      using errcode = '42501';
  end if;

  v_is_owner := public.owns_property(new.property_id);
  v_is_admin := public.current_role_is(array['admin']::public.user_role[]);

  if v_is_admin then
    return new;
  end if;

  if new.status is distinct from old.status then
    if v_is_owner and (
         (old.status = 'booked'     and new.status in ('viewed', 'accepted', 'declined'))
      or (old.status = 'viewed'     and new.status in ('accepted', 'declined'))
      or (old.status = 'accepted'   and new.status in ('declined', 'checked_in'))
      or (old.status = 'checked_in' and new.status = 'moved_out')
    ) then
      new.responded_at := case when new.status in ('accepted', 'declined') then now()
                               else new.responded_at end;
    elsif old.tenant_id = v_uid and (
         (old.status in ('booked', 'viewed', 'accepted') and new.status = 'cancelled')
      or (old.status = 'accepted'   and new.status = 'checked_in')
      or (old.status = 'checked_in' and new.status = 'moved_out')
    ) then
      null;
    else
      raise exception 'That change to the request is not allowed.'
        using errcode = '42501';
    end if;
  end if;

  -- Only the landlord writes the response; only the tenant edits their note.
  if not v_is_owner and new.landlord_response is distinct from old.landlord_response then
    new.landlord_response := old.landlord_response;
  end if;
  if old.tenant_id <> v_uid then
    new.note := old.note;
    new.preferred_move_in := old.preferred_move_in;
  end if;

  return new;
end;
$$;

drop trigger if exists tenancies_guard_transition on public.tenancies;
create trigger tenancies_guard_transition
  before update on public.tenancies
  for each row execute function public.tenancies_guard_transition();

-- Replaces the 0004 landlord-only notifier: both sides now hear about changes.
create or replace function public.notify_landlord_on_tenancy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
  v_name  text;
  v_extra text;
begin
  select p.owner_id, p.title into v_owner, v_title
    from public.properties p where p.id = new.property_id;

  select split_part(coalesce(nullif(trim(pr.full_name), ''), 'A tenant'), ' ', 1)
    into v_name
    from public.profiles pr where pr.id = new.tenant_id;
  v_name := coalesce(v_name, 'A tenant');

  if tg_op = 'INSERT' then
    v_extra := case when new.preferred_move_in is not null
                    then ' Preferred move-in: ' || to_char(new.preferred_move_in, 'FMDD Mon YYYY') || '.'
                    else '' end;
    perform public.notify_user(v_owner, 'request', 'New Tenant Request',
      v_name || ' wants to rent ' || v_title || '.' || v_extra,
      new.property_id, 'request');
    perform public.notify_user(new.tenant_id, 'request', 'Request sent',
      'Your request for ' || v_title || ' was sent. We will tell you when the landlord responds.',
      new.property_id, 'request');
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  v_extra := case when nullif(trim(new.landlord_response), '') is not null
                  then ' The landlord says: "' || left(trim(new.landlord_response), 280) || '"'
                  else '' end;

  case new.status
    when 'viewed' then
      perform public.notify_user(new.tenant_id, 'request', 'Request viewed',
        'The landlord has seen your request for ' || v_title || '.',
        new.property_id, 'request');
    when 'accepted' then
      perform public.notify_user(new.tenant_id, 'request', 'Request accepted',
        'Good news — your request for ' || v_title || ' was accepted.' || v_extra,
        new.property_id, 'request');
    when 'declined' then
      perform public.notify_user(new.tenant_id, 'request', 'Request declined',
        'Your request for ' || v_title || ' was not accepted this time.' || v_extra,
        new.property_id, 'request');
    when 'cancelled' then
      perform public.notify_user(v_owner, 'request', 'Request withdrawn',
        v_name || ' withdrew their request for ' || v_title || '.',
        new.property_id, 'request');
    when 'checked_in' then
      perform public.notify_user(v_owner, 'check_in', 'Tenant has checked in',
        v_name || ' has moved into ' || v_title || '.', new.property_id, 'listing');
    when 'moved_out' then
      perform public.notify_user(v_owner, 'move_out', 'Tenant has moved out',
        v_name || ' has moved out of ' || v_title ||
          '. Set its availability to let waiting tenants know.',
        new.property_id, 'listing');
    else
      null;
  end case;

  return new;
end;
$$;

drop trigger if exists tenancies_notify_landlord on public.tenancies;
create trigger tenancies_notify_landlord
  after insert or update of status on public.tenancies
  for each row execute function public.notify_landlord_on_tenancy();

-- New inquiries go through the preference-aware path too.
create or replace function public.notify_landlord_on_inquiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
begin
  select p.owner_id, p.title into v_owner, v_title
    from public.properties p where p.id = new.property_id;

  perform public.notify_user(v_owner, 'inquiry', 'New inquiry',
    new.name || ' asked about ' || v_title || '.', new.property_id, 'listing');
  return new;
end;
$$;

-- A landlord's view of requests: the tenant's first name always, and their
-- phone number only once the landlord has accepted.
create or replace function public.get_requests_for_owner()
returns table (
  id                uuid,
  property_id       uuid,
  property_title    text,
  property_slug     text,
  property_type     text,
  tenant_name       text,
  tenant_phone      text,
  status            text,
  note              text,
  preferred_move_in date,
  landlord_response text,
  booked_at         timestamptz,
  responded_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.property_id, p.title, p.slug, pt.name,
         coalesce(nullif(trim(pr.full_name), ''), 'A tenant'),
         case when t.status in ('accepted', 'checked_in') then pr.phone end,
         t.status, t.note, t.preferred_move_in, t.landlord_response,
         t.booked_at, t.responded_at
    from public.tenancies t
    join public.properties p on p.id = t.property_id
    left join public.property_types pt on pt.id = p.property_type_id
    left join public.profiles pr on pr.id = t.tenant_id
   where p.owner_id = auth.uid()
   order by t.created_at desc;
$$;

revoke all on function public.get_requests_for_owner() from public, anon;
grant execute on function public.get_requests_for_owner() to authenticated;

-- =============================================================================
-- 9. The KES 500 house hunting fee
-- =============================================================================
create table if not exists public.hunting_payments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  amount          numeric(10,2) not null,
  currency        char(3) not null default 'KES',
  status          text not null default 'pending',
  provider        text not null default 'paystack',
  provider_ref    text not null unique,
  amount_received numeric(10,2),
  created_at      timestamptz not null default now(),
  paid_at         timestamptz,
  constraint hunting_payments_amount_ok check (amount > 0),
  constraint hunting_payments_status_ok check (status in ('pending', 'paid', 'failed', 'refunded'))
);

create index if not exists hunting_payments_user_idx on public.hunting_payments (user_id, created_at desc);

-- At most one checkout in flight per person.
create unique index if not exists hunting_payments_one_pending_idx
  on public.hunting_payments (user_id) where status = 'pending';

create table if not exists public.hunting_services (
  user_id             uuid primary key references public.profiles(id) on delete cascade,
  status              text not null default 'unpaid',
  payment_id          uuid references public.hunting_payments(id) on delete set null,
  activated_at        timestamptz,
  matched_at          timestamptz,
  matched_property_id uuid references public.properties(id) on delete set null,
  completed_at        timestamptz,
  updated_at          timestamptz not null default now(),
  constraint hunting_services_status_ok check (
    status in ('unpaid', 'payment_pending', 'paid', 'service_active', 'matched', 'completed')
  )
);

drop trigger if exists hunting_services_set_updated_at on public.hunting_services;
create trigger hunting_services_set_updated_at
  before update on public.hunting_services
  for each row execute function public.set_updated_at();

create table if not exists public.payment_allocations (
  id            uuid primary key default gen_random_uuid(),
  payment_id    uuid not null references public.hunting_payments(id) on delete cascade,
  product       text not null,
  party         text not null,
  share_percent numeric(5,2) not null,
  amount        numeric(10,2) not null,
  created_at    timestamptz not null default now(),
  constraint payment_allocations_unique unique (payment_id, party)
);

alter table public.hunting_payments    enable row level security;
alter table public.hunting_services    enable row level security;
alter table public.payment_allocations enable row level security;

-- Tenants read their own; nobody writes these through the API. Payments are
-- created by start_hunting_payment() and confirmed only by the webhook.
drop policy if exists hunting_payments_select_own on public.hunting_payments;
create policy hunting_payments_select_own on public.hunting_payments
  for select to authenticated
  using (user_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists hunting_services_select_own on public.hunting_services;
create policy hunting_services_select_own on public.hunting_services
  for select to authenticated
  using (user_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists payment_allocations_admin on public.payment_allocations;
create policy payment_allocations_admin on public.payment_allocations
  for select to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));

revoke insert, update, delete on public.hunting_payments    from anon, authenticated;
revoke insert, update, delete on public.hunting_services    from anon, authenticated;
revoke insert, update, delete on public.payment_allocations from anon, authenticated;
grant select on public.hunting_payments, public.hunting_services, public.payment_allocations
  to authenticated;

-- Starts (or resumes) a checkout. The amount comes from app_settings, never
-- from the client. Returns the reference to hand to the payment page.
create or replace function public.start_hunting_payment()
returns table (reference text, amount numeric, currency text, service_status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_ref     text;
  v_amount  numeric := public.setting_num('hunting_fee', 500);
  v_cur     text    := coalesce(public.setting_text('hunting_fee_currency'), 'KES');
begin
  if v_uid is null then
    raise exception 'Sign in to continue.' using errcode = '28000';
  end if;

  select hs.status into v_status from public.hunting_services hs where hs.user_id = v_uid;

  -- Already paid: nothing to buy. Never charge twice.
  if v_status in ('paid', 'service_active', 'matched') then
    return query select null::text, v_amount, v_cur, v_status;
    return;
  end if;

  -- An abandoned checkout older than an hour is dead; start a fresh one.
  update public.hunting_payments hp
     set status = 'failed'
   where hp.user_id = v_uid and hp.status = 'pending'
     and hp.created_at < now() - interval '1 hour';

  select hp.provider_ref into v_ref
    from public.hunting_payments hp
   where hp.user_id = v_uid and hp.status = 'pending'
   limit 1;

  if v_ref is null then
    v_ref := 'kh_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.hunting_payments (user_id, amount, currency, provider_ref)
    values (v_uid, v_amount, v_cur, v_ref);
  end if;

  insert into public.hunting_services (user_id, status)
  values (v_uid, 'payment_pending')
  on conflict (user_id) do update
    set status = 'payment_pending'
  where public.hunting_services.status in ('unpaid', 'payment_pending', 'completed');

  return query
    select v_ref, hp.amount, hp.currency::text, 'payment_pending'::text
      from public.hunting_payments hp where hp.provider_ref = v_ref;
end;
$$;

revoke all on function public.start_hunting_payment() from public, anon;
grant execute on function public.start_hunting_payment() to authenticated;

-- What the payment server needs to open a checkout for a reference. The
-- reference is an unguessable random id, and this returns no personal data.
create or replace function public.hunting_checkout_details(p_reference text)
returns table (amount numeric, currency text, status text)
language sql
stable
security definer
set search_path = public
as $$
  select hp.amount, hp.currency::text, hp.status
    from public.hunting_payments hp
   where hp.provider_ref = p_reference;
$$;

revoke all on function public.hunting_checkout_details(text) from public;
grant execute on function public.hunting_checkout_details(text) to anon, authenticated, service_role;

-- Called only by the payment webhook, after the provider's signature has been
-- verified. Idempotent: a retried webhook changes nothing and returns false.
create or replace function public.confirm_hunting_payment(
  p_reference       text,
  p_provider        text default 'paystack',
  p_amount_received numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_user   uuid;
  v_amount numeric;
  v_cur    text;
  v_total  numeric;
begin
  update public.hunting_payments
     set status = 'paid', paid_at = now(), provider = p_provider,
         amount_received = p_amount_received
   where provider_ref = p_reference
     and status in ('pending', 'failed')
     -- An underpayment is not a payment.
     and (p_amount_received is null or p_amount_received >= amount)
  returning id, user_id, amount, currency into v_id, v_user, v_amount, v_cur;

  if v_id is null then
    return false;
  end if;

  -- Snapshot the split in force right now.
  insert into public.payment_allocations (payment_id, product, party, share_percent, amount)
  select v_id, 'hunting_fee', fa.party, fa.share_percent, round(v_amount * fa.share_percent / 100, 2)
    from public.fee_allocations fa
   where fa.product = 'hunting_fee' and fa.is_active
  on conflict (payment_id, party) do nothing;

  -- Anything the configured shares do not cover stays with the platform.
  select coalesce(sum(pa.amount), 0) into v_total
    from public.payment_allocations pa where pa.payment_id = v_id;
  if v_total < v_amount then
    insert into public.payment_allocations (payment_id, product, party, share_percent, amount)
    values (v_id, 'hunting_fee', 'platform', 0, v_amount - v_total)
    on conflict (payment_id, party) do update
      set amount = public.payment_allocations.amount + excluded.amount;
  end if;

  insert into public.hunting_services (user_id, status, payment_id, activated_at)
  values (v_user, 'service_active', v_id, now())
  on conflict (user_id) do update
    set status = 'service_active', payment_id = v_id, activated_at = now(),
        matched_at = null, matched_property_id = null, completed_at = null
  where public.hunting_services.status in ('unpaid', 'payment_pending', 'completed');

  perform public.notify_user(v_user, 'payment', 'Hunting fee payment successful',
    'We received your ' || v_cur || ' ' || to_char(v_amount, 'FM999,999') ||
    ' house hunting fee. Your House Hunting service is now active. This fee is '
    'separate from rent and deposit, which you pay the landlord directly.',
    null, 'account');

  return true;
end;
$$;

revoke all on function public.confirm_hunting_payment(text, text, numeric) from public, anon, authenticated;
grant execute on function public.confirm_hunting_payment(text, text, numeric) to service_role;

-- Accepted request -> matched; moved in -> completed.
create or replace function public.hunting_track_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'accepted' then
    update public.hunting_services
       set status = 'matched', matched_at = now(), matched_property_id = new.property_id
     where user_id = new.tenant_id and status = 'service_active';
  elsif new.status = 'checked_in' then
    update public.hunting_services
       set status = 'completed', completed_at = now()
     where user_id = new.tenant_id and status in ('service_active', 'matched');
  elsif new.status in ('declined', 'cancelled') then
    -- The match fell through: back to hunting, fee still counts.
    update public.hunting_services
       set status = 'service_active', matched_at = null, matched_property_id = null
     where user_id = new.tenant_id and status = 'matched'
       and matched_property_id = new.property_id;
  end if;

  return new;
end;
$$;

drop trigger if exists tenancies_hunting_track on public.tenancies;
create trigger tenancies_hunting_track
  after update of status on public.tenancies
  for each row execute function public.hunting_track_request();

-- An active hunting service unlocks contacts on every listing, if configured.
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
    ) or (
      public.setting_bool('hunting_fee_unlocks_contacts', true)
      and exists (
        select 1 from public.hunting_services hs
         where hs.user_id = auth.uid()
           and hs.status in ('service_active', 'matched')
      )
    )
    where auth.uid() is not null
  ), false);
$$;

grant execute on function public.has_contact_unlock(uuid) to anon, authenticated;

-- =============================================================================
-- 10. Stays — interest list only. The feature itself is not live.
-- =============================================================================
create table if not exists public.stays_waitlist (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references public.profiles(id) on delete set null,
  full_name      text not null,
  phone          text,
  email          text,
  location       text,
  property_count int,
  property_type  text,
  message        text,
  status         text not null default 'new',
  created_at     timestamptz not null default now(),
  constraint stays_waitlist_name_len    check (char_length(full_name) between 2 and 120),
  constraint stays_waitlist_phone_len   check (phone is null or char_length(phone) between 7 and 20),
  constraint stays_waitlist_email_ok    check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  constraint stays_waitlist_contactable check (phone is not null or email is not null),
  constraint stays_waitlist_count_ok    check (property_count is null or property_count between 1 and 500),
  constraint stays_waitlist_text_len    check (
    (location is null or char_length(location) <= 120)
    and (property_type is null or char_length(property_type) <= 60)
    and (message is null or char_length(message) <= 1000)
  ),
  constraint stays_waitlist_status_ok   check (status in ('new', 'contacted', 'onboarded', 'declined'))
);

create unique index if not exists stays_waitlist_phone_idx on public.stays_waitlist (phone) where phone is not null;
create unique index if not exists stays_waitlist_email_idx on public.stays_waitlist (lower(email)) where email is not null;

alter table public.stays_waitlist enable row level security;

drop policy if exists stays_waitlist_insert on public.stays_waitlist;
create policy stays_waitlist_insert on public.stays_waitlist
  for insert to anon, authenticated
  with check (status = 'new' and (user_id is null or user_id = auth.uid()));

drop policy if exists stays_waitlist_admin on public.stays_waitlist;
create policy stays_waitlist_admin on public.stays_waitlist
  for all to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

grant insert on public.stays_waitlist to anon, authenticated;
grant select, update, delete on public.stays_waitlist to authenticated;

-- =============================================================================
-- 11. Service providers — the partners table, with manual approval
-- =============================================================================
alter table public.partners add column if not exists email           text;
alter table public.partners add column if not exists location        text;
alter table public.partners add column if not exists description     text;
alter table public.partners add column if not exists services        text[] not null default '{}';
alter table public.partners add column if not exists pricing_info    text;
alter table public.partners add column if not exists approval_status text not null default 'pending';
alter table public.partners add column if not exists onboarding_fee  numeric(10,2);
alter table public.partners add column if not exists onboarding_paid boolean not null default false;
alter table public.partners add column if not exists updated_at      timestamptz not null default now();

do $$ begin
  alter table public.partners add constraint partners_approval_ok
    check (approval_status in ('pending', 'approved', 'rejected'));
exception when duplicate_object then null; end $$;

drop trigger if exists partners_set_updated_at on public.partners;
create trigger partners_set_updated_at
  before update on public.partners
  for each row execute function public.set_updated_at();

-- Only approved, active providers are public.
drop policy if exists partners_read on public.partners;
create policy partners_read on public.partners
  for select to anon, authenticated
  using (is_active and approval_status = 'approved');

grant insert, update, delete on public.partners to authenticated;  -- RLS: admins only

-- MoveMate Kenya is Kheja_Link's moving partner, and the only company we have
-- an agreement with. It takes over the old "Movement" row.
update public.partners set slug = 'movemate-kenya'
 where slug = 'movement'
   and not exists (select 1 from public.partners where slug = 'movemate-kenya');

insert into public.partners
  (category, slug, name, tagline, description, logo_url, brand_color, phone,
   is_ours, is_active, approval_status, sort_order, location, services)
values
  ('movers', 'movemate-kenya', 'MoveMate Kenya', 'Our moving partner',
   'House moving across Meru and beyond — packing, loading and transport.',
   'https://www.khejalink.name.ng/partners/movemate-kenya.jpeg', '#2F8F2F',
   '+254710655709', true, true, 'approved', 10, 'Meru',
   array['House moving', 'Packing', 'Transport'])
on conflict (slug) do update
  set name            = excluded.name,
      tagline         = excluded.tagline,
      description     = coalesce(public.partners.description, excluded.description),
      logo_url        = excluded.logo_url,
      brand_color     = excluded.brand_color,
      phone           = coalesce(public.partners.phone, excluded.phone),
      is_ours         = true,
      is_active       = true,
      approval_status = 'approved',
      category        = 'movers';

-- Every other company was listed without an agreement. Take them off the app,
-- once: the marker stops a re-run from undoing an admin's later approval.
do $$ begin
  if not exists (select 1 from public.app_settings where key = 'migration_0012_partners_reset') then
    update public.partners
       set is_active = false, approval_status = 'pending'
     where slug <> 'movemate-kenya';
    insert into public.app_settings (key, value, is_public, description)
    values ('migration_0012_partners_reset', now()::text, false,
            'Marker: non-partner companies were deactivated once by 0012.');
  end if;
end $$;

-- Admins upload provider logos from the web admin.
drop policy if exists "kheja admins manage partner logos" on storage.objects;
create policy "kheja admins manage partner logos" on storage.objects
  for all to authenticated
  using (bucket_id = 'partner-logos' and public.current_role_is(array['admin']::public.user_role[]))
  with check (bucket_id = 'partner-logos' and public.current_role_is(array['admin']::public.user_role[]));

-- =============================================================================
-- 12. Daily maintenance (and keep-alive)
--
-- Safe for anyone to call: it only does what the data already says should
-- happen, and it runs at most once an hour however often it is called. The
-- keep-alive jobs call it through the public API, which is exactly the kind of
-- activity that stops a free Supabase project from being paused.
-- =============================================================================
create or replace function public.run_daily_maintenance()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last      timestamptz;
  v_promoted  int := 0;
  v_payments  int := 0;
  v_unlocks   int := 0;
  r           record;
begin
  begin
    v_last := nullif(public.setting_text('last_maintenance_at'), '')::timestamptz;
  exception when others then
    v_last := null;
  end;

  if v_last is not null and v_last > now() - interval '1 hour' then
    return jsonb_build_object('ok', true, 'skipped', true, 'last_run', v_last);
  end if;

  update public.app_settings set value = now()::text, updated_at = now()
   where key = 'last_maintenance_at';

  -- Homes whose notice period has run out are now free. The status trigger
  -- tells everyone waiting; the landlord hears it happened.
  for r in
    update public.properties
       set availability = 'available'
     where status = 'published'
       and availability = 'notice_given'
       and available_from <= current_date
    returning id, owner_id, title
  loop
    perform public.notify_user(r.owner_id, 'listing_status', 'Listing now shown as available',
      r.title || ' reached its available-from date and is now shown as available. '
        || 'If the tenant has not left yet, set its availability again.',
      r.id, 'listing');
    v_promoted := v_promoted + 1;
  end loop;

  -- Abandoned checkouts.
  with expired as (
    update public.hunting_payments set status = 'failed'
     where status = 'pending' and created_at < now() - interval '1 hour'
    returning user_id
  )
  select count(*) into v_payments from expired;

  update public.hunting_services hs
     set status = 'unpaid'
   where hs.status = 'payment_pending'
     and not exists (select 1 from public.hunting_payments hp
                      where hp.user_id = hs.user_id and hp.status = 'pending');

  with expired as (
    update public.contact_unlocks set status = 'failed'
     where status = 'pending' and created_at < now() - interval '1 hour'
    returning 1
  )
  select count(*) into v_unlocks from expired;

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'vacancies_opened', v_promoted,
    'payments_expired', v_payments,
    'unlocks_expired', v_unlocks
  );
end;
$$;

revoke all on function public.run_daily_maintenance() from public;
grant execute on function public.run_daily_maintenance() to anon, authenticated, service_role;

-- Also run it inside the database once a day where pg_cron is available. This
-- keeps vacancy dates honest; it does not by itself stop the project pausing,
-- which needs traffic from outside (see .github/workflows/supabase-keepalive.yml).
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('kheja-daily-maintenance', '15 3 * * *',
                        'select public.run_daily_maintenance()');
exception when others then
  raise notice 'pg_cron not available (%). The external keep-alive jobs cover it.', sqlerrm;
end $$;

-- =============================================================================
-- Kheja_Link — 0013_in_app_notifications_only.sql
--
-- Kheja_Link does not send email or SMS. Every notification lives in the app,
-- in the Inbox. So:
--
--   * notify_user() only ever writes the in-app notification — nothing is
--     queued in notification_outbox any more
--   * in-app notifications cannot be switched off (they are the only channel);
--     people still choose which *kinds* they get (availability alerts, request
--     updates)
--   * the email / sms preference columns are turned off and left unused
--
-- The outbox table is kept, empty, so a channel can be added later without a
-- schema change. Safe to re-run. Run AFTER 0012.
-- =============================================================================

set search_path = public, extensions;

alter table public.notification_preferences alter column in_app set default true;
alter table public.notification_preferences alter column email  set default false;
alter table public.notification_preferences alter column sms    set default false;

update public.notification_preferences
   set in_app = true, email = false, sms = false
 where in_app is distinct from true or email or sms;

-- Nothing will ever send what is waiting.
update public.notification_outbox
   set status = 'skipped', last_error = 'In-app notifications only (0013).'
 where status = 'pending';

create or replace function public.notify_user(
  p_user     uuid,
  p_type     text,
  p_title    text,
  p_body     text,
  p_property uuid default null,
  p_category text default 'account'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_availability boolean;
  v_requests     boolean;
  v_id           uuid;
begin
  if p_user is null then
    return null;
  end if;

  select np.availability_alerts, np.request_updates
    into v_availability, v_requests
    from public.notification_preferences np
   where np.user_id = p_user;

  if p_category = 'availability'
     and (not coalesce(v_availability, true)
          or not public.setting_bool('tenant_notifications_enabled', true)) then
    return null;
  end if;

  if p_category = 'request' and not coalesce(v_requests, true) then
    return null;
  end if;

  insert into public.notifications (user_id, type, title, body, property_id)
  values (p_user, p_type, p_title, p_body, p_property)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.notify_user(uuid, text, text, text, uuid, text) from public, anon, authenticated;

-- The "a home you saved has been taken" notice checked the in-app switch too.
create or replace function public.notify_watchers_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_was_open   boolean;
  v_is_open    boolean;
  v_was_coming boolean;
  v_is_coming  boolean;
begin
  if tg_op = 'INSERT' then
    if new.status = 'published' and new.availability = 'available' then
      perform public.notify_property_availability(new.id, 'available');
    elsif new.status = 'published' and new.availability = 'notice_given' then
      perform public.notify_property_availability(new.id, 'coming');
    end if;
    return new;
  end if;

  v_was_open   := old.status = 'published' and old.availability = 'available';
  v_is_open    := new.status = 'published' and new.availability = 'available';
  v_was_coming := old.status = 'published' and old.availability = 'notice_given';
  v_is_coming  := new.status = 'published' and new.availability = 'notice_given';

  if v_is_open and not v_was_open then
    perform public.notify_property_availability(new.id, 'available');
  elsif v_is_coming and (not v_was_coming or new.available_from is distinct from old.available_from) then
    perform public.notify_property_availability(new.id, 'coming');
  end if;

  if v_was_open and not v_is_open and new.status in ('published', 'rented')
     and new.availability in ('occupied', 'notice_given') then
    insert into public.notifications (user_id, type, title, body, property_id)
    select f.user_id, 'listing_status', 'A home you saved has been taken',
           new.title || ' is no longer available. We will tell you if it frees up.',
           new.id
      from public.favorites f
     where f.property_id = new.id
       and f.user_id <> new.owner_id
       and coalesce((select np.availability_alerts
                       from public.notification_preferences np
                      where np.user_id = f.user_id), true);
  end if;

  return new;
end;
$$;

