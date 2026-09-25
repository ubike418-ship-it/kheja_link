-- =============================================================================
-- Kheja_Link — 0016_security_location_lock_3h_unlocks.sql
--
-- Production hardening, found in a security review before launch, plus two
-- product rules:
--
--   SECURITY
--   * Sign-up could create an admin. handle_new_user() copied `role` from the
--     sign-up metadata, which the caller controls, so anyone calling the auth
--     API with {"role":"admin"} got the back office. Sign-up now only ever
--     creates a tenant or a landlord, and a guard stops any non-admin writing
--     a privileged profile.
--   * Landlord phone numbers were readable by anyone. The
--     profiles_select_listing_owners policy exposed every column of a
--     landlord's profile row, phone included, to anonymous callers — around the
--     paid unlock. The table is now readable only by its owner and admins;
--     everyone else uses public_profiles, which only has name, avatar and badge.
--   * Anonymous messages are rate-limited, and payment attempts record who and
--     which number asked, so the payment server can refuse prompt-bombing.
--
--   PRODUCT
--   * The location is locked. A tenant sees the area (e.g. Makutano) and the
--     landlord's description of the location; the street/estate, building name
--     and map pin come back only through the paid unlock. Search no longer
--     indexes the street, so it cannot be probed through search either.
--   * An unlock lasts contact_unlock_hours (3) from payment. After that the
--     listing locks again and the tenant pays again to reopen it.
--   * Admin back-office functions: the overview figures and the user list.
--
-- Safe to re-run. Run AFTER 0015.
-- =============================================================================

set search_path = public, extensions;

-- =============================================================================
-- 1. Nobody signs up as an admin
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := 'seeker';
begin
  -- Only the two public roles can be chosen at sign-up. Anything else —
  -- 'admin' included — silently becomes a tenant account.
  if new.raw_user_meta_data ->> 'role' = 'landlord' then
    v_role := 'landlord';
  end if;

  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    left(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 120),
    left(nullif(trim(new.raw_user_meta_data ->> 'phone'), ''), 20),
    v_role
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The update guard from 0002 did not cover INSERT. A user may create their own
-- profile row (profiles_insert_own), so the same rules apply there.
create or replace function public.profiles_guard_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Trusted server-side work (migrations, the sign-up trigger, the service
  -- role) runs without a user.
  if auth.uid() is null then
    return new;
  end if;

  if public.current_role_is(array['admin']::public.user_role[]) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.role = 'admin' then
      new.role := 'seeker';
    end if;
    new.is_verified := false;
    return new;
  end if;

  if new.role = 'admin' and old.role <> 'admin' then
    new.role := old.role;
  end if;
  new.is_verified := old.is_verified;
  return new;
end;
$$;

drop trigger if exists profiles_guard_privileged on public.profiles;
create trigger profiles_guard_privileged
  before insert or update on public.profiles
  for each row execute function public.profiles_guard_privileged_columns();

-- Admins manage accounts (role, verified badge) from the back office.
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
  for update to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]))
  with check (public.current_role_is(array['admin']::public.user_role[]));

-- =============================================================================
-- 2. Profiles stop leaking phone numbers
-- =============================================================================
drop policy if exists profiles_select_listing_owners on public.profiles;

-- The public face of a landlord: name, avatar and badge only, for landlords
-- with a published listing. It runs with the view owner's rights so it no
-- longer needs a table policy that exposed every column.
drop view if exists public.public_profiles;
create view public.public_profiles
with (security_invoker = false) as
  select pr.id, pr.full_name, pr.avatar_url, pr.is_verified, pr.role, pr.created_at
    from public.profiles pr
   where exists (
     select 1 from public.properties p
      where p.owner_id = pr.id and p.status = 'published'
   );

revoke all on public.public_profiles from anon, authenticated;
grant select on public.public_profiles to anon, authenticated;

-- =============================================================================
-- 3. The location is part of what the unlock buys
-- =============================================================================
revoke select (address_line, building_name) on public.properties from anon, authenticated;

-- Search covers the title, the area description and the description — never
-- the street, which would let anyone probe for it one word at a time.
create or replace function public.properties_search_vector_update()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.search_vector :=
      setweight(to_tsvector('english', unaccent(coalesce(new.title, ''))), 'A')
   || setweight(to_tsvector('english', unaccent(coalesce(new.nearby, ''))), 'B')
   || setweight(to_tsvector('english', unaccent(coalesce(new.description, ''))), 'C');
  return new;
end;
$$;

drop trigger if exists properties_search_vector on public.properties;
create trigger properties_search_vector
  before insert or update of title, description, nearby on public.properties
  for each row execute function public.properties_search_vector_update();

-- Rebuild every row without the street. The trigger above fires on this.
update public.properties set title = title;

-- The owner reads back every private field when editing.
drop function if exists public.get_my_property_private(uuid);
create function public.get_my_property_private(p_property_id uuid)
returns table (
  contact_phone    text,
  contact_whatsapp text,
  latitude         numeric,
  longitude        numeric,
  landlord_name    text,
  caretaker_name   text,
  caretaker_phone  text,
  address_line     text,
  building_name    text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.contact_phone, p.contact_whatsapp, p.latitude, p.longitude,
         p.landlord_name, p.caretaker_name, p.caretaker_phone,
         p.address_line, p.building_name
    from public.properties p
   where p.id = p_property_id
     and p.owner_id = auth.uid();
$$;

revoke all on function public.get_my_property_private(uuid) from public;
grant execute on function public.get_my_property_private(uuid) to authenticated;

-- =============================================================================
-- 4. An unlock lasts 3 hours
-- =============================================================================
insert into public.app_settings (key, value, is_public, description) values
  ('contact_unlock_hours', '3', true,
   'How long a paid unlock keeps the contacts and location open, in hours. After that the tenant pays again.')
on conflict (key) do update
  set is_public = excluded.is_public, description = excluded.description;

alter table public.contact_unlocks add column if not exists expires_at timestamptz;

-- Unlocks paid before this rule get the same window from their payment time.
update public.contact_unlocks
   set expires_at = coalesce(paid_at, created_at)
                    + make_interval(hours => public.setting_num('contact_unlock_hours', 3)::int)
 where status = 'paid' and expires_at is null;

-- A tenant may now pay for the same home again once a window has ended, so
-- "one paid row per home" becomes "one open window per home", enforced below.
drop index if exists public.contact_unlocks_one_paid_idx;
create index if not exists contact_unlocks_active_idx
  on public.contact_unlocks (user_id, property_id, expires_at) where status = 'paid';

create or replace function public.unlock_hours()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(1, least(720, public.setting_num('contact_unlock_hours', 3)::int));
$$;

revoke all on function public.unlock_hours() from public, anon, authenticated;

-- A tenant's open window on a home, if any.
create or replace function public.active_unlock_until(p_user uuid, p_property_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select max(u.expires_at)
    from public.contact_unlocks u
   where u.user_id = p_user and u.property_id = p_property_id
     and u.status = 'paid' and u.expires_at > now();
$$;

revoke all on function public.active_unlock_until(uuid, uuid) from public, anon, authenticated;

create or replace function public.has_contact_unlock(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select public.active_unlock_until(auth.uid(), p_property_id) is not null
        or (
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

create or replace function public.contact_unlocks_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.amount   := public.unlock_fee();
  new.currency := public.unlock_currency();
  new.amount_received   := null;
  new.duplicate_payment := false;
  new.expires_at        := null;

  if new.status = 'pending' then
    if public.active_unlock_until(new.user_id, new.property_id) is not null then
      raise exception 'You have already unlocked this home.' using errcode = '23505';
    end if;

    update public.contact_unlocks
       set status = 'failed'
     where user_id = new.user_id and property_id = new.property_id and status = 'pending';
  end if;

  return new;
end;
$$;

-- The contact, and now the location, with when the window closes.
drop function if exists public.get_property_contact(uuid);
create function public.get_property_contact(p_property_id uuid)
returns table (
  unlocked          boolean,
  unlocked_until    timestamptz,
  landlord_name     text,
  contact_phone     text,
  contact_whatsapp  text,
  caretaker_name    text,
  caretaker_phone   text,
  management_name   text,
  management_phone  text,
  address_line      text,
  building_name     text,
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
  v_until     timestamptz;
  v_entitled  boolean;
begin
  select p.owner_id, (p.status = 'published')
    into v_owner, v_is_public
    from public.properties p
   where p.id = p_property_id;

  -- coalesce everywhere: auth.uid() is NULL for a signed-out caller (see 0009).
  v_until := public.active_unlock_until(auth.uid(), p_property_id);
  v_entitled :=
    v_owner is not null and (
      coalesce(v_owner = auth.uid(), false)
      or public.current_role_is(array['admin']::public.user_role[])
      or (coalesce(v_is_public, false) and coalesce(public.has_contact_unlock(p_property_id), false))
    );

  if v_entitled is not true then
    return query select false, null::timestamptz, null::text, null::text, null::text, null::text,
                        null::text, null::text, null::text, null::text, null::text,
                        null::numeric, null::numeric;
    return;
  end if;

  return query
    select true,
           -- Null for the owner, an admin or a House Hunting pass: no window.
           case when coalesce(v_owner = auth.uid(), false) then null else v_until end,
           coalesce(nullif(trim(p.landlord_name), ''), pr.full_name),
           p.contact_phone,
           p.contact_whatsapp,
           p.caretaker_name,
           p.caretaker_phone,
           public.setting_text('management_name'),
           public.setting_text('management_phone'),
           p.address_line,
           p.building_name,
           p.latitude,
           p.longitude
      from public.properties p
      left join public.profiles pr on pr.id = p.owner_id
     where p.id = p_property_id;
end;
$$;

revoke all on function public.get_property_contact(uuid) from public;
grant execute on function public.get_property_contact(uuid) to anon, authenticated;

create or replace function public.start_contact_unlock(p_property_id uuid)
returns table (reference text, amount numeric, currency text, already_unlocked boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fee numeric := public.unlock_fee();
  v_cur text := public.unlock_currency();
  v_ref text;
begin
  if v_uid is null then
    raise exception 'Sign in to continue.' using errcode = '28000';
  end if;

  -- An open window (or ownership, or a House Hunting pass): nothing to buy.
  if public.owns_property(p_property_id) or public.has_contact_unlock(p_property_id) then
    return query select null::text, v_fee, v_cur, true;
    return;
  end if;

  if not public.property_is_public(p_property_id) then
    raise exception 'This home is no longer listed.' using errcode = 'P0002';
  end if;

  update public.contact_unlocks cu
     set status = 'failed'
   where cu.user_id = v_uid and cu.property_id = p_property_id and cu.status = 'pending'
     and (cu.created_at < now() - interval '1 hour' or cu.amount <> v_fee);

  select cu.provider_ref into v_ref
    from public.contact_unlocks cu
   where cu.user_id = v_uid and cu.property_id = p_property_id and cu.status = 'pending'
   limit 1;

  if v_ref is null then
    v_ref := 'kl_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.contact_unlocks (user_id, property_id, status, provider, provider_ref)
    values (v_uid, p_property_id, 'pending', 'paystack', v_ref);
  end if;

  return query
    select cu.provider_ref, cu.amount, cu.currency::text, false
      from public.contact_unlocks cu
     where cu.provider_ref = v_ref;
end;
$$;

revoke all on function public.start_contact_unlock(uuid) from public, anon;
grant execute on function public.start_contact_unlock(uuid) to authenticated;

create or replace function public.confirm_contact_unlock(
  p_reference       text,
  p_provider        text    default 'paystack',
  p_amount_received numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.contact_unlocks%rowtype;
  v_title  text;
  v_hours  int := public.unlock_hours();
  v_until  timestamptz;
  v_refund numeric := public.setting_num('house_refund_amount', 200);
  v_extra  text := '';
begin
  select * into v_row
    from public.contact_unlocks
   where provider_ref = p_reference
   for update;

  if not found or v_row.status = 'paid' or v_row.duplicate_payment then
    return false;
  end if;

  if p_amount_received is not null and p_amount_received + 0.001 < v_row.amount then
    return false;
  end if;

  select p.title into v_title from public.properties p where p.id = v_row.property_id;
  v_title := coalesce(v_title, 'this home');

  -- Paid while a window on the same home was already open: owed back.
  if public.active_unlock_until(v_row.user_id, v_row.property_id) is not null then
    update public.contact_unlocks
       set duplicate_payment = true, status = 'failed', provider = p_provider,
           amount_received = coalesce(p_amount_received, amount), paid_at = now()
     where id = v_row.id;

    perform public.notify_user(v_row.user_id, 'payment', 'Duplicate payment — we will refund it',
      'You had already unlocked ' || v_title || ', so the second payment of ' ||
        public.money_label(coalesce(p_amount_received, v_row.amount), v_row.currency) ||
        ' will be refunded to you. You keep your access.',
      v_row.property_id, 'account');
    perform public.notify_admins('payment', 'Duplicate unlock payment to refund',
      'Reference ' || p_reference || ' paid again for ' || v_title || '. Refund ' ||
        public.money_label(coalesce(p_amount_received, v_row.amount), v_row.currency) || '.',
      v_row.property_id);
    return true;
  end if;

  v_until := now() + make_interval(hours => v_hours);

  update public.contact_unlocks
     set status = 'paid', paid_at = now(), expires_at = v_until, provider = p_provider,
         amount_received = p_amount_received
   where id = v_row.id;

  if v_refund > 0 and v_row.amount > v_refund then
    v_extra := ' Know of a vacant house — the one you are leaving, or one whose landlord '
            || 'wants to list? Give it to us, and once we approve it we refund you '
            || public.money_label(v_refund, v_row.currency) || '.';
  end if;

  perform public.notify_user(v_row.user_id, 'payment', 'Contact unlocked',
    'We received your ' || public.money_label(v_row.amount, v_row.currency) ||
      ' unlock payment for ' || v_title || '. The landlord''s and caretaker''s numbers '
      'and the exact location are open for ' || v_hours || ' hours, until ' ||
      to_char(v_until at time zone 'Africa/Nairobi', 'FMHH12:MI AM') || '.' || v_extra,
    v_row.property_id, 'account');

  return true;
end;
$$;

revoke all on function public.confirm_contact_unlock(text, text, numeric) from public, anon, authenticated;
grant execute on function public.confirm_contact_unlock(text, text, numeric) to service_role;

-- =============================================================================
-- 5. Rate limits
-- =============================================================================
-- Messages: at most 5 an hour from one account or one phone/email, and never
-- the same text twice in a day.
create or replace function public.inquiries_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.inquiries i
       where i.created_at > now() - interval '1 hour'
         and (
           (new.sender_id is not null and i.sender_id = new.sender_id)
           or (new.phone is not null and i.phone = new.phone)
           or (new.email is not null and lower(i.email) = lower(new.email))
         )) >= 5 then
    raise exception 'Too many messages. Please wait a while before sending another.'
      using errcode = '54000';
  end if;

  if exists (select 1 from public.inquiries i
              where i.created_at > now() - interval '1 day'
                and i.property_id = new.property_id
                and i.message = new.message
                and (i.sender_id = new.sender_id or i.phone = new.phone or lower(i.email) = lower(new.email))) then
    raise exception 'You have already sent this message.' using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists inquiries_rate_limit on public.inquiries;
create trigger inquiries_rate_limit
  before insert on public.inquiries
  for each row execute function public.inquiries_rate_limit();

-- Payments: who asked, and a one-way hash of the number that was prompted, so
-- the payment server can refuse to prompt-bomb anyone's phone.
alter table public.payment_attempts add column if not exists user_id     uuid;
alter table public.payment_attempts add column if not exists msisdn_hash text;
create index if not exists payment_attempts_user_idx   on public.payment_attempts (user_id, created_at desc);
create index if not exists payment_attempts_msisdn_idx on public.payment_attempts (msisdn_hash, created_at desc);

-- =============================================================================
-- 6. The back office
-- =============================================================================
-- Every account, with the email that only auth.users holds. Admins only.
create or replace function public.admin_list_users()
returns table (
  id              uuid,
  email           text,
  full_name       text,
  phone           text,
  role            public.user_role,
  is_verified     boolean,
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  listings        int,
  unlocks         int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_role_is(array['admin']::public.user_role[]) then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  return query
    select pr.id, u.email::text, pr.full_name, pr.phone, pr.role, pr.is_verified,
           pr.created_at, u.last_sign_in_at,
           (select count(*)::int from public.properties p where p.owner_id = pr.id),
           (select count(*)::int from public.contact_unlocks cu
             where cu.user_id = pr.id and cu.status = 'paid')
      from public.profiles pr
      left join auth.users u on u.id = pr.id
     order by pr.created_at desc
     limit 2000;
end;
$$;

revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

-- The figures on the admin overview, in one round trip. Admins only.
create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Africa/Nairobi') at time zone 'Africa/Nairobi';
begin
  if not public.current_role_is(array['admin']::public.user_role[]) then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'users',            (select count(*) from public.profiles),
    'tenants',          (select count(*) from public.profiles where role = 'seeker'),
    'landlords',        (select count(*) from public.profiles where role = 'landlord'),
    'new_users_7d',     (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'listings',         (select count(*) from public.properties),
    'published',        (select count(*) from public.properties where status = 'published'),
    'drafts',           (select count(*) from public.properties where status = 'draft'),
    'available_now',    (select count(*) from public.properties where status = 'published' and availability = 'available'),
    'unlocks_today',    (select count(*) from public.contact_unlocks where status = 'paid' and paid_at >= v_today),
    'unlocks_7d',       (select count(*) from public.contact_unlocks where status = 'paid' and paid_at > now() - interval '7 days'),
    'unlocks_open_now', (select count(*) from public.contact_unlocks where status = 'paid' and expires_at > now()),
    'revenue_today',    (select coalesce(sum(coalesce(amount_received, amount)), 0) from public.contact_unlocks where status = 'paid' and paid_at >= v_today),
    'revenue_7d',       (select coalesce(sum(coalesce(amount_received, amount)), 0) from public.contact_unlocks where status = 'paid' and paid_at > now() - interval '7 days'),
    'revenue_total',    (select coalesce(sum(coalesce(amount_received, amount)), 0) from public.contact_unlocks where status = 'paid'),
    'refunds_to_send',  (select count(*) from public.unlock_refunds where status = 'approved'),
    'refunds_paid_total', (select coalesce(sum(amount), 0) from public.unlock_refunds where status = 'paid'),
    'duplicates_to_refund', (select count(*) from public.contact_unlocks where duplicate_payment),
    'houses_to_review', (select count(*) from public.house_submissions where status = 'pending'),
    'messages_new',     (select count(*) from public.inquiries where recipient = 'admin' and status = 'new'),
    'payments_failed_24h', (select count(*) from public.payment_attempts where status = 'failed' and created_at > now() - interval '1 day'),
    'currency',         public.unlock_currency()
  );
end;
$$;

revoke all on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;
