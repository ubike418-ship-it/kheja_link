import { createClient, getCurrentUser } from "@/lib/supabase/server";
import type { PropertyListItem } from "@/lib/types";

/**
 * Favourites are private: RLS restricts every row to `user_id = auth.uid()`,
 * so these queries are safe even though they never mention the user id.
 */

/** The set of property ids the signed-in user has saved. Empty when signed out. */
export async function getFavoriteIds(): Promise<Set<string>> {
  const user = await getCurrentUser();
  if (!user) return new Set();

  const supabase = await createClient();
  const { data } = await supabase.from("favorites").select("property_id").eq("user_id", user.id);
  return new Set((data ?? []).map((row) => row.property_id));
}

/** Decorates a list of properties with the viewer's saved state. */
export async function withFavoriteState(items: PropertyListItem[]): Promise<PropertyListItem[]> {
  if (items.length === 0) return items;
  const favorites = await getFavoriteIds();
  if (favorites.size === 0) return items.map((item) => ({ ...item, is_favorited: false }));
  return items.map((item) => ({ ...item, is_favorited: favorites.has(item.id) }));
}

/** The viewer's saved listings, newest save first. */
export async function getFavoriteProperties(): Promise<PropertyListItem[]> {
  const user = await getCurrentUser();
  if (!user) return [];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("favorites")
    .select(
      `
      created_at,
      property:properties (
        id, owner_id, title, slug, description, property_type_id, location_id, address_line, price_amount, price_currency, price_period, deposit_months, bedrooms, bathrooms, size_sqft, is_premium, is_furnished, status, available_from, view_count, published_at, created_at, updated_at, like_count, house_rules,
        property_type:property_types ( id, slug, name, icon ),
        location:locations ( id, slug, name, area, county, latitude, longitude ),
        images:property_images ( id, public_url, alt_text, is_cover, sort_order )
      )
    `,
    )
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  if (error) throw new Error(`Could not load your saved homes: ${error.message}`);

  return (data ?? [])
    .map((row) => (row as unknown as { property: PropertyListItem | null }).property)
    .filter((p): p is PropertyListItem => Boolean(p))
    .map((p) => ({
      ...p,
      is_favorited: true,
      images: [...(p.images ?? [])].sort((a, b) => {
        if (a.is_cover !== b.is_cover) return a.is_cover ? -1 : 1;
        return a.sort_order - b.sort_order;
      }),
    }));
}
