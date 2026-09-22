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
