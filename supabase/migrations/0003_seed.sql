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
