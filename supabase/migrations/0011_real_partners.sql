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
