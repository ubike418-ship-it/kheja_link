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
