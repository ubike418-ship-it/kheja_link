import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { AmenityRow, LocationRow, PropertyTypeRow } from "@/lib/supabase/database.types";

/**
 * Reference data. Small, rarely changes and read on almost every page, so each
 * lookup is deduped per request with React's `cache`.
 */

export const getPropertyTypes = cache(async (): Promise<PropertyTypeRow[]> => {
  const supabase = await createClient();
  const { data } = await supabase.from("property_types").select("*").order("sort_order");
  return data ?? [];
});

export const getLocations = cache(async (): Promise<LocationRow[]> => {
  const supabase = await createClient();
  const { data } = await supabase.from("locations").select("*").order("name");
  return data ?? [];
});

export const getAmenities = cache(async (): Promise<AmenityRow[]> => {
  const supabase = await createClient();
  const { data } = await supabase.from("amenities").select("*").order("sort_order");
  return data ?? [];
});

/** The cheapest and dearest published rents, used to seed the price slider. */
export const getPriceBounds = cache(async (): Promise<{ min: number; max: number }> => {
  const supabase = await createClient();

  const [{ data: lowest }, { data: highest }] = await Promise.all([
    supabase
      .from("properties")
      .select("price_amount")
      .eq("status", "published")
      .order("price_amount", { ascending: true })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("properties")
      .select("price_amount")
      .eq("status", "published")
      .order("price_amount", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const min = Math.floor((lowest?.price_amount ?? 0) / 1000) * 1000;
  const max = Math.ceil((highest?.price_amount ?? 100_000) / 1000) * 1000;
  return { min, max: Math.max(max, min + 1000) };
});
