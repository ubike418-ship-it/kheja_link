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
