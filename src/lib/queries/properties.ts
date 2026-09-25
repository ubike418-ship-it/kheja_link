import { createClient } from "@/lib/supabase/server";
import type {
  Paginated,
  PropertyDetail,
  PropertyFilters,
  PropertyListItem,
  PropertySort,
} from "@/lib/types";

/** Columns a property card needs, joined in one round-trip. */
// Explicit, because the contact numbers and the exact location (street,
// building, map pin) are revoked from the API roles — they sit behind the paid
// contact unlock and come back only through get_property_contact(). `select=*`
// would be denied outright. `nearby` is the landlord's public description of
// the location.
const PROPERTY_COLUMNS = "id, owner_id, title, slug, description, property_type_id, location_id, nearby, price_amount, price_currency, price_period, deposit_months, bedrooms, bathrooms, size_sqft, is_premium, is_furnished, status, available_from, view_count, published_at, created_at, updated_at, like_count, house_rules, availability, notice_date";

const LIST_SELECT = `
  ${PROPERTY_COLUMNS},
  property_type:property_types ( id, slug, name, icon ),
  location:locations ( id, slug, name, area, county, latitude, longitude ),
  images:property_images ( id, public_url, alt_text, is_cover, sort_order )
` as const;

const DEFAULT_PER_PAGE = 12;
const MAX_PER_PAGE = 48;

function applySort<T extends { order: (col: string, opts?: object) => T }>(
  query: T,
  sort: PropertySort = "newest",
): T {
  switch (sort) {
    case "price_asc":
      return query.order("price_amount", { ascending: true });
    case "price_desc":
      return query.order("price_amount", { ascending: false });
    case "bedrooms_desc":
      return query.order("bedrooms", { ascending: false });
    case "popular":
      return query.order("view_count", { ascending: false });
    case "newest":
    default:
      return query.order("published_at", { ascending: false, nullsFirst: false });
  }
}

/** Sorts images so the cover is always first. */
function normaliseImages(rows: PropertyListItem[]): PropertyListItem[] {
  return rows.map((row) => ({
    ...row,
    images: [...(row.images ?? [])].sort((a, b) => {
      if (a.is_cover !== b.is_cover) return a.is_cover ? -1 : 1;
      return a.sort_order - b.sort_order;
    }),
  }));
}

/**
 * The main listing query: full-text search + structured filters + pagination.
 * Only published listings are ever returned — RLS enforces that too, this just
 * makes the intent explicit and lets Postgres use the partial indexes.
 */
export async function getProperties(filters: PropertyFilters = {}): Promise<Paginated<PropertyListItem>> {
  const supabase = await createClient();

  const page = Math.max(1, filters.page ?? 1);
  const perPage = Math.min(MAX_PER_PAGE, Math.max(1, filters.perPage ?? DEFAULT_PER_PAGE));
  const from = (page - 1) * perPage;

  let query = supabase
    .from("properties")
    .select(LIST_SELECT, { count: "exact" })
    .eq("status", "published");

  if (filters.q?.trim()) {
    // websearch_to_tsquery understands quoted phrases and OR, and never throws
    // on user input the way plain to_tsquery does.
    query = query.textSearch("search_vector", filters.q.trim(), {
      type: "websearch",
      config: "english",
    });
  }

  if (filters.type) {
    const { data: type } = await supabase
      .from("property_types")
      .select("id")
      .eq("slug", filters.type)
      .maybeSingle();
    // An unknown type slug must return nothing rather than everything.
    if (!type) return { items: [], total: 0, page, perPage, pageCount: 0 };
    query = query.eq("property_type_id", type.id);
  }

  if (filters.location) {
    const { data: location } = await supabase
      .from("locations")
      .select("id")
      .eq("slug", filters.location)
      .maybeSingle();
    if (!location) return { items: [], total: 0, page, perPage, pageCount: 0 };
    query = query.eq("location_id", location.id);
  }

  if (typeof filters.minPrice === "number") query = query.gte("price_amount", filters.minPrice);
  if (typeof filters.maxPrice === "number") query = query.lte("price_amount", filters.maxPrice);
  if (typeof filters.bedrooms === "number") query = query.gte("bedrooms", filters.bedrooms);
  if (filters.furnished) query = query.eq("is_furnished", true);
  if (filters.premium) query = query.eq("is_premium", true);

  if (filters.amenities?.length) {
    // "has every one of these amenities": resolve the slugs, then intersect the
    // join table down to properties matching the full set.
    const { data: amenityRows } = await supabase
      .from("amenities")
      .select("id")
      .in("slug", filters.amenities);

    const amenityIds = (amenityRows ?? []).map((a) => a.id);
    if (amenityIds.length !== filters.amenities.length) {
      return { items: [], total: 0, page, perPage, pageCount: 0 };
    }

    const { data: matches } = await supabase
      .from("property_amenities")
      .select("property_id, amenity_id")
      .in("amenity_id", amenityIds);

    const counts = new Map<string, number>();
    for (const row of matches ?? []) {
      counts.set(row.property_id, (counts.get(row.property_id) ?? 0) + 1);
    }
    const propertyIds = [...counts.entries()]
      .filter(([, n]) => n >= amenityIds.length)
      .map(([id]) => id);

    if (propertyIds.length === 0) return { items: [], total: 0, page, perPage, pageCount: 0 };
    query = query.in("id", propertyIds);
  }

  query = applySort(query, filters.sort).range(from, from + perPage - 1);

  const { data, error, count } = await query;
  if (error) throw new Error(`Could not load properties: ${error.message}`);

  const total = count ?? 0;
  return {
    items: normaliseImages((data ?? []) as unknown as PropertyListItem[]),
    total,
    page,
    perPage,
    pageCount: Math.max(1, Math.ceil(total / perPage)),
  };
}

/** Homepage feed: newest published listings, optionally narrowed by category. */
export async function getFeaturedProperties(
  filters: Pick<PropertyFilters, "type" | "premium"> & { limit?: number } = {},
): Promise<PropertyListItem[]> {
  const { items } = await getProperties({
    type: filters.type,
    premium: filters.premium,
    perPage: filters.limit ?? 6,
    sort: "newest",
  });
  return items;
}

export async function getPropertyBySlug(slug: string): Promise<PropertyDetail | null> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("properties")
    .select(
      `
      ${LIST_SELECT},
      property_amenities ( amenities ( id, slug, name, icon, sort_order ) )
    `,
    )
    .eq("slug", slug)
    .maybeSingle();

  if (error) throw new Error(`Could not load property: ${error.message}`);
  if (!data) return null;

  const raw = data as unknown as PropertyListItem & {
    property_amenities: { amenities: PropertyDetail["amenities"][number] | null }[] | null;
  };

  // The owner comes from the public_profiles view, which deliberately omits
  // phone and email. PostgREST cannot embed a view through a foreign key, so
  // this is a second (indexed, primary-key) lookup.
  const { data: owner } = await supabase
    .from("public_profiles")
    .select("id, full_name, avatar_url, is_verified, role, created_at")
    .eq("id", raw.owner_id)
    .maybeSingle();

  const [normalised] = normaliseImages([raw]);

  return {
    ...normalised,
    owner: (owner as PropertyDetail["owner"]) ?? null,
    amenities: (raw.property_amenities ?? [])
      .map((row) => row.amenities)
      .filter((a): a is PropertyDetail["amenities"][number] => Boolean(a))
      .sort((a, b) => a.sort_order - b.sort_order),
  };
}

/** Other listings a visitor is likely to want next. */
export async function getSimilarProperties(
  property: Pick<PropertyListItem, "id" | "property_type_id" | "location_id" | "price_amount">,
  limit = 3,
): Promise<PropertyListItem[]> {
  const supabase = await createClient();

  const { data } = await supabase
    .from("properties")
    .select(LIST_SELECT)
    .eq("status", "published")
    .neq("id", property.id)
    .or(`property_type_id.eq.${property.property_type_id},location_id.eq.${property.location_id}`)
    .order("published_at", { ascending: false, nullsFirst: false })
    .limit(limit);

  return normaliseImages((data ?? []) as unknown as PropertyListItem[]);
}

/** Every listing belonging to the signed-in landlord, in any status. */
export async function getMyProperties(ownerId: string): Promise<PropertyListItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("properties")
    .select(LIST_SELECT)
    .eq("owner_id", ownerId)
    .order("created_at", { ascending: false });

  if (error) throw new Error(`Could not load your listings: ${error.message}`);
  return normaliseImages((data ?? []) as unknown as PropertyListItem[]);
}

export async function getMyPropertyById(
  id: string,
  ownerId: string,
): Promise<(PropertyListItem & { amenity_ids: string[] }) | null> {
  const supabase = await createClient();

  const { data } = await supabase
    .from("properties")
    .select(`${LIST_SELECT}, property_amenities ( amenity_id )`)
    .eq("id", id)
    .eq("owner_id", ownerId)
    .maybeSingle();

  if (!data) return null;

  const raw = data as unknown as PropertyListItem & {
    property_amenities: { amenity_id: string }[] | null;
  };
  const [normalised] = normaliseImages([raw]);

  // The contact columns are revoked from the API roles (they sit behind the
  // paid contact unlock), so they never arrive on the row above. Without this, the
  // edit form opened with a blank phone number — and saving it silently wiped
  // the landlord's real number. The owner reads them back through a function
  // that checks ownership.
  const { data: privateRows } = await supabase.rpc("get_my_property_private", {
    p_property_id: id,
  });
  const privateFields = (Array.isArray(privateRows) ? privateRows[0] : null) as {
    contact_phone: string | null;
    contact_whatsapp: string | null;
    address_line: string | null;
  } | null;

  return {
    ...normalised,
    contact_phone: privateFields?.contact_phone ?? null,
    contact_whatsapp: privateFields?.contact_whatsapp ?? null,
    address_line: privateFields?.address_line ?? null,
    amenity_ids: (raw.property_amenities ?? []).map((a) => a.amenity_id),
  };
}

/** Counts for the landlord dashboard header. */
export async function getLandlordStats(ownerId: string) {
  const supabase = await createClient();

  const [{ data: properties }, { count: inquiryCount }] = await Promise.all([
    supabase.from("properties").select("status, view_count").eq("owner_id", ownerId),
    supabase
      .from("inquiries")
      .select("id", { count: "exact", head: true })
      .eq("recipient", "landlord")
      .eq("status", "new"),
  ]);

  const rows = properties ?? [];
  return {
    total: rows.length,
    published: rows.filter((p) => p.status === "published").length,
    drafts: rows.filter((p) => p.status === "draft").length,
    rented: rows.filter((p) => p.status === "rented").length,
    views: rows.reduce((sum, p) => sum + (p.view_count ?? 0), 0),
    newInquiries: inquiryCount ?? 0,
  };
}

/** Fire-and-forget view counter. Never let analytics break a page render. */
export async function recordPropertyView(propertyId: string): Promise<void> {
  try {
    const supabase = await createClient();
    await supabase.rpc("increment_property_views", { p_property_id: propertyId });
  } catch {
    // Intentionally ignored.
  }
}
