-- =============================================================================
-- Kheja_Link — 0005_seed_partners_hostels.sql
--
--   * the partner directory shown under a listing
--   * hostel and student-accommodation listings, with photos
--
-- Safe to re-run. Run AFTER 0004_marketplace.sql.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Partners
--
-- logo_url is deliberately null for every company but our own. The app draws a
-- styled name tile in its place, so no third-party trademark is reproduced and
-- nobody is implied to be a partner who has not agreed to be one. Fill in
-- logo_url once an agreement exists and the tile becomes a real logo with no
-- code change.
-- -----------------------------------------------------------------------------
insert into public.partners
  (category, slug, name, tagline, brand_color, icon, phone, url, is_ours, sort_order)
values
  -- Movers ------------------------------------------------------------------
  ('movers', 'movement', 'Movement', 'Our own moving service', '#2563EB',
   'truck', '+254710655709', null, true, 10),
  ('movers', 'nellions', 'Nellions', 'Household & office moving', '#0F766E',
   'truck', null, null, false, 20),
  ('movers', 'moving-solutions', 'Moving Solutions', 'Local moves in Meru', '#B45309',
   'truck', null, null, false, 30),
  ('movers', 'superior-movers', 'Superior Movers', 'Packing and transport', '#7C3AED',
   'truck', null, null, false, 40),
  ('movers', 'meru-pickups', 'Meru Pickups', 'Affordable pickup hire', '#DC2626',
   'truck', null, null, false, 50),

  -- Internet ----------------------------------------------------------------
  ('isp', 'safaricom-home', 'Safaricom Home', 'Fibre & 5G router', '#16A34A',
   'wifi', null, null, false, 10),
  ('isp', 'zuku', 'Zuku Fibre', 'Home fibre & TV', '#2563EB',
   'wifi', null, null, false, 20),
  ('isp', 'faiba', 'Faiba', 'JTL home fibre', '#EA580C',
   'wifi', null, null, false, 30),
  ('isp', 'poa-internet', 'Poa Internet', 'Low-cost home WiFi', '#0891B2',
   'wifi', null, null, false, 40),
  ('isp', 'liquid-home', 'Liquid Home', 'Fibre to the home', '#DB2777',
   'wifi', null, null, false, 50),

  -- Cleaning ----------------------------------------------------------------
  ('cleaning', 'sparkle-clean', 'Sparkle Clean', 'Move-in deep cleaning', '#0891B2',
   'sparkles', null, null, false, 10),
  ('cleaning', 'freshco-cleaners', 'FreshCo Cleaners', 'Homes & offices', '#16A34A',
   'sparkles', null, null, false, 20),
  ('cleaning', 'klin-house', 'Klin House', 'Sofa & carpet washing', '#7C3AED',
   'sparkles', null, null, false, 30),
  ('cleaning', 'meru-shine', 'Meru Shine', 'Post-construction clean', '#D97706',
   'sparkles', null, null, false, 40),
  ('cleaning', 'homecare-ke', 'HomeCare KE', 'Fumigation & sanitising', '#DC2626',
   'sparkles', null, null, false, 50)
on conflict (slug) do update
  set name        = excluded.name,
      tagline     = excluded.tagline,
      brand_color = excluded.brand_color,
      icon        = excluded.icon,
      category    = excluded.category,
      sort_order  = excluded.sort_order,
      is_ours     = excluded.is_ours;

-- -----------------------------------------------------------------------------
-- Hostels and student accommodation
--
-- Photographs are Unsplash, whose licence permits commercial use without
-- attribution. Replace them with real photographs of the actual rooms before
-- launch — a listing with someone else's photo is the thing tenants distrust
-- most.
-- -----------------------------------------------------------------------------
do $$
declare
  v_owner uuid;
  v_type  jsonb;
  v_loc   jsonb;
  r       record;
  v_prop  uuid;
  v_idx   int;
  v_url   text;
begin
  select id into v_owner from auth.users
   where email = 'demo.landlord@khejalink.co.ke';

  if v_owner is null then
    raise notice 'Demo landlord missing — run 0003_seed.sql first. Skipping hostels.';
    return;
  end if;

  select jsonb_object_agg(slug, id) into v_type from public.property_types;
  select jsonb_object_agg(slug, id) into v_loc  from public.locations;

  for r in
    select * from (values
      ('must-gate-hostel-block-a', 'MUST Gate Hostel — Block A',
       'hostel', 'must-area', 6500, 1, 1, 180, false,
       'Purpose-built student hostel two minutes from the MUST main gate. Single and shared rooms, study desk in every room, communal kitchen, laundry area and a warden on site. Water tank and backup power, so revision nights are never interrupted.',
       'Nchiru, opposite MUST main gate',
       array[
         'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('nchiru-scholars-hostel', 'Nchiru Scholars Hostel',
       'hostel', 'must-area', 5500, 1, 1, 160, false,
       'Affordable shared hostel rooms for MUST students. Bunk or single beds, shared bathrooms kept clean daily, free WiFi in the common room and a secure gate locked from 10pm. Popular with first years.',
       'Nchiru, Meru',
       array[
         'https://images.unsplash.com/photo-1541123437800-1bb1317badc2?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('kaaga-girls-hostel', 'Kaaga Ladies Hostel',
       'hostel', 'kaaga', 7500, 1, 1, 200, false,
       'Ladies-only hostel in quiet Kaaga with 24-hour security, CCTV on every corridor and a resident matron. Rooms are self-contained with a study nook, and there is a shared kitchen and reading room.',
       'Kaaga, Meru',
       array[
         'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('meru-town-executive-hostel', 'Meru Town Executive Hostel',
       'hostel', 'meru-town', 9000, 1, 1, 240, true,
       'A step up from the usual student room: private ensuite, fitted study desk, fast fibre WiFi included in the rent, and a rooftop common area. Walking distance to Meru Town college campuses.',
       'Meru Town, Central',
       array[
         'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&q=80&w=1200'
       ]),

      -- A couple of the empty types, so search is not full of dead ends.
      ('kinoru-modern-studio', 'Kinoru Modern Studio',
       'studio', 'kinoru', 18000, 1, 1, 480, false,
       'Bright open-plan studio with a fitted kitchenette, private balcony and plenty of natural light. Ideal for a young professional who wants their own space without an apartment''s cost.',
       'Kinoru, Meru',
       array[
         'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1493809842364-78817add7ffb?auto=format&fit=crop&q=80&w=1200'
       ]),

      ('gitoro-family-maisonette', 'Gitoro Family Maisonette',
       'maisonette', 'gitoro', 55000, 4, 3, 2400, true,
       'Spacious four-bedroom maisonette in a gated Gitoro court. Master ensuite, downstairs guest room, private garden, double garage and a borehole shared between only six houses.',
       'Gitoro, Meru',
       array[
         'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&q=80&w=1200',
         'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&q=80&w=1200'
       ])
    ) as t(slug, title, type_slug, loc_slug, price, beds, baths, sqft, premium,
           description, address, images)
  loop
    insert into public.properties (
      owner_id, title, slug, description, property_type_id, location_id, address_line,
      price_amount, price_currency, price_period, deposit_months,
      bedrooms, bathrooms, size_sqft, is_premium, status, available_from,
      contact_phone, contact_whatsapp, latitude, longitude, house_rules
    ) values (
      v_owner, r.title, r.slug, r.description,
      (v_type ->> r.type_slug)::uuid,
      (v_loc  ->> r.loc_slug)::uuid,
      r.address,
      r.price, 'KES', 'month', 1,
      r.beds, r.baths, r.sqft, r.premium, 'published', current_date,
      '+254710655709', '+254710655709',
      0.05 + (random() - 0.5) * 0.06,
      37.65 + (random() - 0.5) * 0.06,
      case when r.type_slug = 'hostel' then
        'No overnight guests without signing them in at the gate. Quiet hours 10pm to 6am during term. No cooking in the rooms — use the shared kitchen. Gate locks at 11pm.'
      else
        'No loud music after 10pm. Keep shared areas clean. Notify the caretaker before moving furniture in or out.'
      end
    )
    on conflict (slug) do update
      set title       = excluded.title,
          description = excluded.description,
          house_rules = excluded.house_rules,
          status      = 'published'
    returning id into v_prop;

    -- Replace the gallery so re-running keeps the photo set correct.
    delete from public.property_images where property_id = v_prop;

    v_idx := 0;
    foreach v_url in array r.images loop
      insert into public.property_images
        (property_id, public_url, alt_text, is_cover, sort_order)
      values (v_prop, v_url, r.title, v_idx = 0, v_idx);
      v_idx := v_idx + 1;
    end loop;

    insert into public.property_amenities (property_id, amenity_id)
    select v_prop, a.id
      from public.amenities a
     where a.slug in ('water', 'electricity', 'security', 'wifi')
    on conflict do nothing;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Give the original twelve listings a second and third photo, so the gallery on
-- the detail page has something to page through.
-- -----------------------------------------------------------------------------
do $$
declare
  r      record;
  extras text[] := array[
    'https://images.unsplash.com/photo-1484154218962-a197022b5858?auto=format&fit=crop&q=80&w=1200',
    'https://images.unsplash.com/photo-1502005229762-cf1b2da7c5d6?auto=format&fit=crop&q=80&w=1200'
  ];
  v_url  text;
  v_next int;
begin
  for r in
    select p.id
      from public.properties p
     where p.status = 'published'
       and (select count(*) from public.property_images i where i.property_id = p.id) = 1
  loop
    select coalesce(max(sort_order), 0) + 1 into v_next
      from public.property_images where property_id = r.id;

    foreach v_url in array extras loop
      insert into public.property_images
        (property_id, public_url, alt_text, is_cover, sort_order)
      values (r.id, v_url, null, false, v_next);
      v_next := v_next + 1;
    end loop;
  end loop;
end $$;

-- Exact coordinates for the original listings, so the unlocked map has a pin.
update public.properties p
   set latitude  = coalesce(p.latitude,  l.latitude  + (random() - 0.5) * 0.01),
       longitude = coalesce(p.longitude, l.longitude + (random() - 0.5) * 0.01)
  from public.locations l
 where l.id = p.location_id
   and (p.latitude is null or p.longitude is null);
