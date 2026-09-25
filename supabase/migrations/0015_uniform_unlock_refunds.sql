-- =============================================================================
-- Kheja_Link — 0015_uniform_unlock_refunds.sql
--
-- The pricing update:
--
--   * One unlock price. Unlocking a listing — the landlord's and caretaker's
--     numbers and the exact location — costs contact_unlock_fee (KES 500), the
--     same for everyone and every listing, charged once per listing when the
--     tenant taps "Unlock contact". The KES 150 price is gone.
--   * The price is set by the database, never by an app. Until now the app
--     wrote the amount onto its own pending row and the M-Pesa charge used it,
--     so a modified app could name its own price. A trigger now prices every
--     row, and confirming a payment refuses one that paid less than that.
--   * One checkout per tenant per listing. start_contact_unlock() resumes the
--     pending one instead of opening a second, and a listing already unlocked
--     is never sold again. If two payments for one listing ever land anyway,
--     the second is flagged for a refund and both the tenant and the admins
--     are told.
--   * The House Hunting pass (KES 500, every listing) is no longer sold. Passes
--     already bought keep working, as do all unlocks paid at the old price.
--   * Give us a house, get house_refund_amount (KES 200) back. A tenant who has
--     paid for an unlock submits a house (the one they are leaving, or one whose
--     landlord agrees to list). An admin approves it, which approves the
--     refund; the admin then sends the money and marks it paid. Every step is
--     an in-app notification.
--   * Messages go to Kheja_Link, not the landlord. New inquiries are addressed
--     to the admins, who can reply in-app. Inquiries landlords already received
--     stay with them.
--
-- The revenue split (fee_allocations / payment_allocations) is untouched.
--
-- Safe to re-run. Run AFTER 0014.
-- =============================================================================

set search_path = public, extensions;

-- =============================================================================
-- 1. Prices, in one place
-- =============================================================================
insert into public.app_settings (key, value, is_public, description) values
  ('contact_unlock_fee',      '500', true, 'Price to unlock one listing (landlord and caretaker contacts + exact location). One price for everyone and every listing, charged once per listing.'),
  ('contact_unlock_currency', 'KES', true, 'Currency of the contact unlock and of the house refund.'),
  ('house_refund_amount',     '200', true, 'Refunded to a tenant who paid for an unlock and then gives Kheja_Link a house that an admin approves. 0 switches refunds off.')
on conflict (key) do update
  set is_public   = excluded.is_public,
      description = excluded.description;

-- The one deliberate overwrite: the old KES 150 price goes, once. The marker
-- stops a re-run from undoing a price an admin has set since.
do $$ begin
  if not exists (select 1 from public.app_settings where key = 'migration_0015_unlock_price') then
    update public.app_settings set value = '500', updated_at = now()
     where key = 'contact_unlock_fee';
    insert into public.app_settings (key, value, is_public, description)
    values ('migration_0015_unlock_price', now()::text, false,
            'Marker: 0015 moved the contact unlock from KES 150 to KES 500 once.');
  end if;
end $$;

-- The hunting pass is retired. Its rows stay so passes already bought keep
-- working; hunting_fee_unlocks_contacts must stay true for that.
update public.app_settings
   set description = 'Retired in 0015: the House Hunting pass is no longer sold. Kept for passes already bought.'
 where key in ('hunting_fee', 'hunting_fee_currency');
update public.app_settings
   set description = 'Keeps House Hunting passes bought before 0015 unlocking every listing. Leave true.'
 where key = 'hunting_fee_unlocks_contacts';

-- =============================================================================
-- 2. Helpers
-- =============================================================================
create or replace function public.unlock_fee()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select public.setting_num('contact_unlock_fee', 500);
$$;

create or replace function public.unlock_currency()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.setting_text('contact_unlock_currency'), 'KES');
$$;

create or replace function public.money_label(p_amount numeric, p_currency text default 'KES')
returns text
language sql
immutable
as $$
  select case when coalesce(p_currency, 'KES') = 'KES' then 'KSh ' else p_currency || ' ' end
         || to_char(p_amount, 'FM999,999,990');
$$;

revoke all on function public.unlock_fee()      from public, anon, authenticated;
revoke all on function public.unlock_currency() from public, anon, authenticated;

-- Every admin hears about it in their Inbox.
create or replace function public.notify_admins(
  p_type     text,
  p_title    text,
  p_body     text,
  p_property uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sent int := 0;
  r      record;
begin
  for r in select pr.id from public.profiles pr where pr.role = 'admin' loop
    perform public.notify_user(r.id, p_type, p_title, p_body, p_property, 'account');
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

revoke all on function public.notify_admins(text, text, text, uuid) from public, anon, authenticated;

-- =============================================================================
-- 3. Contact unlocks: priced by the database, one per listing
-- =============================================================================
alter table public.contact_unlocks alter column amount set default 500;
alter table public.contact_unlocks add column if not exists amount_received   numeric(10,2);
-- Set when a second payment lands for a listing the tenant already unlocked.
-- It is owed back; the admin refunds it by hand.
alter table public.contact_unlocks add column if not exists duplicate_payment boolean not null default false;

-- Older app builds opened a fresh checkout on every tap. Keep only the newest
-- pending one per tenant per listing, so the index below can exist.
update public.contact_unlocks cu
   set status = 'failed'
 where cu.status = 'pending'
   and exists (
     select 1 from public.contact_unlocks x
      where x.user_id = cu.user_id
        and x.property_id = cu.property_id
        and x.status = 'pending'
        and (x.created_at, x.id) > (cu.created_at, cu.id)
   );

create unique index if not exists contact_unlocks_one_pending_idx
  on public.contact_unlocks (user_id, property_id) where status = 'pending';

-- Whatever an app sends, the row costs what app_settings says.
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

  if new.status = 'pending' then
    if exists (select 1 from public.contact_unlocks u
                where u.user_id = new.user_id and u.property_id = new.property_id
                  and u.status = 'paid') then
      raise exception 'You have already unlocked this home.' using errcode = '23505';
    end if;

    -- An older app build starting over: the new checkout replaces the old one.
    update public.contact_unlocks
       set status = 'failed'
     where user_id = new.user_id and property_id = new.property_id and status = 'pending';
  end if;

  return new;
end;
$$;

drop trigger if exists contact_unlocks_price on public.contact_unlocks;
create trigger contact_unlocks_price
  before insert on public.contact_unlocks
  for each row execute function public.contact_unlocks_price();

-- Starts (or resumes) the checkout for one listing. The app never sends an
-- amount. Returns already_unlocked = true, and no reference, when there is
-- nothing to buy — so nobody is ever charged twice for the same home.
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

  if public.owns_property(p_property_id) or public.has_contact_unlock(p_property_id) then
    return query select null::text, v_fee, v_cur, true;
    return;
  end if;

  if not public.property_is_public(p_property_id) then
    raise exception 'This home is no longer listed.' using errcode = 'P0002';
  end if;

  -- A checkout abandoned an hour ago, or priced before the fee changed, is dead.
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

-- Called by the payment server once Paystack confirms. Idempotent, refuses an
-- underpayment, and never lets one tenant hold two paid unlocks for one home.
-- The old two-argument version would make calls ambiguous, so it goes.
drop function if exists public.confirm_contact_unlock(text, text);

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

  -- An underpayment is not a payment. Each row is held to its own price, so a
  -- prompt already on someone's phone when the price changed still completes.
  if p_amount_received is not null and p_amount_received + 0.001 < v_row.amount then
    return false;
  end if;

  select p.title into v_title from public.properties p where p.id = v_row.property_id;
  v_title := coalesce(v_title, 'this home');

  if exists (select 1 from public.contact_unlocks u
              where u.user_id = v_row.user_id and u.property_id = v_row.property_id
                and u.status = 'paid') then
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

  update public.contact_unlocks
     set status = 'paid', paid_at = now(), provider = p_provider,
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
      'and the exact location are now on the listing, and stay yours.' || v_extra,
    v_row.property_id, 'account');

  return true;
end;
$$;

revoke all on function public.confirm_contact_unlock(text, text, numeric) from public, anon, authenticated;
grant execute on function public.confirm_contact_unlock(text, text, numeric) to service_role;

-- =============================================================================
-- 4. The House Hunting pass is no longer sold
--
-- confirm_hunting_payment() and has_contact_unlock() are left alone, so a
-- checkout already on someone's phone still completes and every pass already
-- bought keeps unlocking listings.
-- =============================================================================
create or replace function public.start_hunting_payment()
returns table (reference text, amount numeric, currency text, service_status text)
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'The House Hunting pass is no longer sold. Unlock the homes you like instead — % each.',
    public.money_label(public.unlock_fee(), public.unlock_currency())
    using errcode = 'P0001';
end;
$$;

-- =============================================================================
-- 5. Give us a house, get money back
-- =============================================================================
create table if not exists public.house_submissions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  location_id      uuid references public.locations(id) on delete set null,
  area             text,
  property_type_id uuid references public.property_types(id) on delete set null,
  bedrooms         int,
  rent_amount      numeric(12,2),
  available_from   date,
  landlord_name    text,
  landlord_phone   text not null,
  -- moving_out: the tenant is leaving it. landlord_agrees: the landlord wants it listed.
  relationship     text not null default 'moving_out',
  notes            text,
  status           text not null default 'pending',
  admin_note       text,
  reviewed_by      uuid references public.profiles(id) on delete set null,
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint house_submissions_status_ok       check (status in ('pending', 'approved', 'rejected')),
  constraint house_submissions_relationship_ok check (relationship in ('moving_out', 'landlord_agrees')),
  constraint house_submissions_where           check (location_id is not null or nullif(trim(area), '') is not null),
  constraint house_submissions_area_len        check (area is null or char_length(area) <= 160),
  constraint house_submissions_bedrooms_ok     check (bedrooms is null or bedrooms between 0 and 50),
  constraint house_submissions_rent_ok         check (rent_amount is null or rent_amount > 0),
  constraint house_submissions_landlord_len    check (landlord_name is null or char_length(landlord_name) <= 120),
  constraint house_submissions_phone_len       check (char_length(landlord_phone) between 7 and 20),
  constraint house_submissions_notes_len       check (notes is null or char_length(notes) <= 1000),
  constraint house_submissions_admin_note_len  check (admin_note is null or char_length(admin_note) <= 500)
);

create index if not exists house_submissions_user_idx   on public.house_submissions (user_id, created_at desc);
create index if not exists house_submissions_status_idx on public.house_submissions (status, created_at);

drop trigger if exists house_submissions_set_updated_at on public.house_submissions;
create trigger house_submissions_set_updated_at
  before update on public.house_submissions
  for each row execute function public.set_updated_at();

-- status: pending (house under review) -> approved (house approved, money owed)
-- -> paid (money sent). rejected when the house is not taken.
create table if not exists public.unlock_refunds (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  submission_id    uuid not null unique references public.house_submissions(id) on delete cascade,
  -- The paid unlock this refund is against. One refund per unlock. Null only
  -- if the listing was later deleted, taking its unlocks with it.
  unlock_id        uuid references public.contact_unlocks(id) on delete set null,
  amount           numeric(10,2) not null,
  currency         char(3) not null default 'KES',
  status           text not null default 'pending',
  payout_reference text,
  approved_at      timestamptz,
  paid_at          timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint unlock_refunds_amount_ok check (amount > 0),
  constraint unlock_refunds_status_ok check (status in ('pending', 'approved', 'paid', 'rejected')),
  constraint unlock_refunds_ref_len   check (payout_reference is null or char_length(payout_reference) <= 60)
);

create unique index if not exists unlock_refunds_one_per_unlock_idx
  on public.unlock_refunds (unlock_id) where status <> 'rejected';
create index if not exists unlock_refunds_user_idx   on public.unlock_refunds (user_id, created_at desc);
create index if not exists unlock_refunds_status_idx on public.unlock_refunds (status, created_at);

drop trigger if exists unlock_refunds_set_updated_at on public.unlock_refunds;
create trigger unlock_refunds_set_updated_at
  before update on public.unlock_refunds
  for each row execute function public.set_updated_at();

-- The paid unlock a refund can be taken against: paid at more than the refund
-- (so KES 150 unlocks bought before 0015 do not qualify for KES 200), and not
-- already carrying a live refund. Oldest first.
create or replace function public.refundable_unlock_for(p_user uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select cu.id
    from public.contact_unlocks cu
   where cu.user_id = p_user
     and cu.status = 'paid'
     and cu.amount > public.setting_num('house_refund_amount', 200)
     and public.setting_num('house_refund_amount', 200) > 0
     and not exists (select 1 from public.unlock_refunds r
                      where r.unlock_id = cu.id and r.status <> 'rejected')
   order by cu.paid_at nulls last, cu.created_at
   limit 1;
$$;

revoke all on function public.refundable_unlock_for(uuid) from public, anon, authenticated;

-- On a new house: open the refund if the tenant qualifies, and tell everyone.
create or replace function public.house_submissions_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unlock uuid := public.refundable_unlock_for(new.user_id);
  v_amount numeric := public.setting_num('house_refund_amount', 200);
  v_cur    text := public.unlock_currency();
  v_where  text;
begin
  select coalesce(nullif(trim(new.area), ''), l.name) into v_where
    from (select 1) x left join public.locations l on l.id = new.location_id;
  v_where := coalesce(v_where, 'Meru');

  if v_unlock is not null then
    insert into public.unlock_refunds (user_id, submission_id, unlock_id, amount, currency, status)
    values (new.user_id, new.id, v_unlock, v_amount, v_cur, 'pending');

    perform public.notify_user(new.user_id, 'payment', 'House received — refund pending',
      'Thank you for the house in ' || v_where || '. We will check it with the landlord. '
        || 'Once it is approved, ' || public.money_label(v_amount, v_cur)
        || ' of your unlock payment comes back to you.',
      null, 'account');
  else
    perform public.notify_user(new.user_id, 'system', 'House received',
      'Thank you for the house in ' || v_where || '. We will check it with the landlord. '
        || 'A refund applies only after you have paid to unlock a listing, once per unlock.',
      null, 'account');
  end if;

  perform public.notify_admins('system', 'New house submitted',
    'A tenant submitted a house in ' || v_where || '. Review it under Admin → Houses & refunds.');

  return new;
end;
$$;

drop trigger if exists house_submissions_after_insert on public.house_submissions;
create trigger house_submissions_after_insert
  after insert on public.house_submissions
  for each row execute function public.house_submissions_after_insert();

-- Stops anyone flooding the review queue.
create or replace function public.house_submissions_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.house_submissions
       where user_id = new.user_id and status = 'pending') >= 5 then
    raise exception 'You already have 5 houses waiting for review.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists house_submissions_limit on public.house_submissions;
create trigger house_submissions_limit
  before insert on public.house_submissions
  for each row execute function public.house_submissions_limit();

-- Admin: approve or reject a house. Approving approves its refund.
create or replace function public.admin_review_house_submission(
  p_submission_id uuid,
  p_approve       boolean,
  p_note          text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub    public.house_submissions%rowtype;
  v_refund public.unlock_refunds%rowtype;
  v_unlock uuid;
  v_note   text := nullif(trim(p_note), '');
  v_tail   text := '';
begin
  if not public.current_role_is(array['admin']::public.user_role[]) then
    raise exception 'Only an admin can review houses.' using errcode = '42501';
  end if;

  select * into v_sub from public.house_submissions where id = p_submission_id for update;
  if not found then
    raise exception 'That house could not be found.' using errcode = 'P0002';
  end if;
  if v_sub.status <> 'pending' then
    raise exception 'That house has already been reviewed.' using errcode = '23514';
  end if;

  update public.house_submissions
     set status = case when p_approve then 'approved' else 'rejected' end,
         admin_note = v_note, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_submission_id;

  if v_note is not null then
    v_tail := ' Note from Kheja_Link: "' || left(v_note, 280) || '"';
  end if;

  select * into v_refund from public.unlock_refunds where submission_id = p_submission_id for update;

  if p_approve then
    -- Paid for an unlock since submitting? They qualify now.
    if v_refund.id is null then
      v_unlock := public.refundable_unlock_for(v_sub.user_id);
      if v_unlock is not null then
        insert into public.unlock_refunds (user_id, submission_id, unlock_id, amount, currency, status)
        values (v_sub.user_id, v_sub.id, v_unlock,
                public.setting_num('house_refund_amount', 200), public.unlock_currency(), 'pending')
        returning * into v_refund;
      end if;
    end if;

    if v_refund.id is not null and v_refund.status = 'pending' then
      update public.unlock_refunds set status = 'approved', approved_at = now()
       where id = v_refund.id;
      perform public.notify_user(v_sub.user_id, 'payment', 'Refund approved',
        'Your house was approved. We are sending you ' ||
          public.money_label(v_refund.amount, v_refund.currency) ||
          ' and will tell you here once it is paid.' || v_tail,
        null, 'account');
      return 'approved_with_refund';
    end if;

    perform public.notify_user(v_sub.user_id, 'system', 'House approved',
      'Thank you — the house you gave us was approved.' || v_tail, null, 'account');
    return 'approved';
  end if;

  if v_refund.id is not null and v_refund.status in ('pending', 'approved') then
    update public.unlock_refunds set status = 'rejected' where id = v_refund.id;
  end if;

  perform public.notify_user(v_sub.user_id, 'system', 'House not approved',
    'We could not take on the house you submitted, so no refund applies to it. '
      || 'Your unlock still counts if you give us another house.' || v_tail,
    null, 'account');
  return 'rejected';
end;
$$;

revoke all on function public.admin_review_house_submission(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_house_submission(uuid, boolean, text) to authenticated;

-- Admin: the money has been sent.
create or replace function public.admin_mark_refund_paid(
  p_refund_id uuid,
  p_reference text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund public.unlock_refunds%rowtype;
  v_ref    text := nullif(trim(p_reference), '');
begin
  if not public.current_role_is(array['admin']::public.user_role[]) then
    raise exception 'Only an admin can mark refunds paid.' using errcode = '42501';
  end if;

  update public.unlock_refunds
     set status = 'paid', paid_at = now(), payout_reference = v_ref
   where id = p_refund_id and status = 'approved'
  returning * into v_refund;

  if v_refund.id is null then
    raise exception 'Only an approved refund can be marked paid.' using errcode = '23514';
  end if;

  perform public.notify_user(v_refund.user_id, 'payment', 'Refund paid',
    public.money_label(v_refund.amount, v_refund.currency) || ' has been sent to you.' ||
      case when v_ref is not null then ' M-Pesa reference: ' || v_ref || '.' else '' end ||
      ' Thank you for the house.',
    null, 'account');
  return true;
end;
$$;

revoke all on function public.admin_mark_refund_paid(uuid, text) from public, anon;
grant execute on function public.admin_mark_refund_paid(uuid, text) to authenticated;

-- Row Level Security --------------------------------------------------------
alter table public.house_submissions enable row level security;
alter table public.unlock_refunds    enable row level security;

drop policy if exists house_submissions_select on public.house_submissions;
create policy house_submissions_select on public.house_submissions
  for select to authenticated
  using (user_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists house_submissions_insert_own on public.house_submissions;
create policy house_submissions_insert_own on public.house_submissions
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

drop policy if exists unlock_refunds_select on public.unlock_refunds;
create policy unlock_refunds_select on public.unlock_refunds
  for select to authenticated
  using (user_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

-- Tenants choose only the house details; review fields and refunds are written
-- by the functions above.
revoke all on public.house_submissions from anon, authenticated;
revoke all on public.unlock_refunds    from anon, authenticated;
grant select on public.house_submissions, public.unlock_refunds to authenticated;
grant insert (
  user_id, location_id, area, property_type_id, bedrooms, rent_amount,
  available_from, landlord_name, landlord_phone, relationship, notes
) on public.house_submissions to authenticated;

-- =============================================================================
-- 6. Messages go to Kheja_Link
-- =============================================================================
-- Existing rows were sent to landlords and stay theirs; new ones go to admins.
alter table public.inquiries add column if not exists recipient text not null default 'landlord';
alter table public.inquiries alter column recipient set default 'admin';
alter table public.inquiries add column if not exists admin_reply text;
alter table public.inquiries add column if not exists replied_at  timestamptz;

do $$ begin
  alter table public.inquiries add constraint inquiries_recipient_ok
    check (recipient in ('landlord', 'admin'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.inquiries add constraint inquiries_reply_len
    check (admin_reply is null or char_length(admin_reply) between 1 and 2000);
exception when duplicate_object then null; end $$;

create index if not exists inquiries_admin_idx
  on public.inquiries (created_at desc) where recipient = 'admin';

drop policy if exists inquiries_insert_public on public.inquiries;
create policy inquiries_insert_public on public.inquiries
  for insert to anon, authenticated
  with check (
    public.property_is_public(property_id)
    and (sender_id is null or sender_id = auth.uid())
    -- Free messages to landlords are over: every new message goes to Kheja_Link.
    and recipient = 'admin'
    and admin_reply is null
  );

drop policy if exists inquiries_select_owner_or_sender on public.inquiries;
create policy inquiries_select_owner_or_sender on public.inquiries
  for select to authenticated
  using (
    (recipient = 'landlord' and public.owns_property(property_id))
    or sender_id = auth.uid()
    or (recipient = 'admin' and public.current_role_is(array['admin']::public.user_role[]))
  );

drop policy if exists inquiries_update_owner on public.inquiries;
create policy inquiries_update_owner on public.inquiries
  for update to authenticated
  using (
    (recipient = 'landlord' and public.owns_property(property_id))
    or (recipient = 'admin' and public.current_role_is(array['admin']::public.user_role[]))
  )
  with check (
    (recipient = 'landlord' and public.owns_property(property_id))
    or (recipient = 'admin' and public.current_role_is(array['admin']::public.user_role[]))
  );

drop policy if exists inquiries_delete_owner on public.inquiries;
create policy inquiries_delete_owner on public.inquiries
  for delete to authenticated
  using (
    (recipient = 'landlord' and public.owns_property(property_id))
    or (recipient = 'admin' and public.current_role_is(array['admin']::public.user_role[]))
  );

-- Only an admin writes a reply, and a message cannot be re-addressed.
create or replace function public.inquiries_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.recipient := old.recipient;
  new.property_id := old.property_id;
  new.sender_id := old.sender_id;

  if new.admin_reply is distinct from old.admin_reply then
    if auth.uid() is not null
       and not public.current_role_is(array['admin']::public.user_role[]) then
      new.admin_reply := old.admin_reply;
    else
      new.replied_at := now();
      if new.status in ('new', 'read') then
        new.status := 'responded';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists inquiries_guard_update on public.inquiries;
create trigger inquiries_guard_update
  before update on public.inquiries
  for each row execute function public.inquiries_guard_update();

-- New message: the admins hear about it, not the landlord.
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

  if new.recipient = 'admin' then
    perform public.notify_admins('inquiry', 'New message',
      new.name || ' asked about ' || coalesce(v_title, 'a listing') || ': "' ||
        left(new.message, 160) || '"',
      new.property_id);
  else
    perform public.notify_user(v_owner, 'inquiry', 'New inquiry',
      new.name || ' asked about ' || v_title || '.', new.property_id, 'listing');
  end if;
  return new;
end;
$$;

-- The reply lands in the sender's Inbox. A guest has no Inbox; the admin calls
-- the number they left instead.
create or replace function public.notify_sender_on_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  if new.sender_id is null or new.admin_reply is null
     or new.admin_reply is not distinct from old.admin_reply then
    return new;
  end if;

  select p.title into v_title from public.properties p where p.id = new.property_id;

  perform public.notify_user(new.sender_id, 'inquiry', 'Kheja_Link replied',
    'About ' || coalesce(v_title, 'your message') || ': "' || left(new.admin_reply, 600) || '"',
    new.property_id, 'account');
  return new;
end;
$$;

drop trigger if exists inquiries_notify_reply on public.inquiries;
create trigger inquiries_notify_reply
  after update of admin_reply on public.inquiries
  for each row execute function public.notify_sender_on_reply();

-- =============================================================================
-- 7. Admin read access for the refunds page: the unlock ledger, and who the
--    tenant is (name and phone) so the refund can be sent to them
-- =============================================================================
drop policy if exists contact_unlocks_select_own on public.contact_unlocks;
create policy contact_unlocks_select_own on public.contact_unlocks
  for select to authenticated
  using (user_id = auth.uid() or public.current_role_is(array['admin']::public.user_role[]));

drop policy if exists profiles_select_admin on public.profiles;
create policy profiles_select_admin on public.profiles
  for select to authenticated
  using (public.current_role_is(array['admin']::public.user_role[]));
