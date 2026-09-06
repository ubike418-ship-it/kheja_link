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
