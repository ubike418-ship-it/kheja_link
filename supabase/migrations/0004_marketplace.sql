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
