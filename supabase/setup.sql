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
