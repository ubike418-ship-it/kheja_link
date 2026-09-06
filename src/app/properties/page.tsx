import { Suspense } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { Compass, Plus } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import PropertyCard from "@/components/PropertyCard";
import PropertyFilterPanel from "@/components/PropertyFilterPanel";
import PropertyPagination from "@/components/PropertyPagination";
import { getProperties } from "@/lib/queries/properties";
import { withFavoriteState } from "@/lib/queries/favorites";
import { getAmenities, getLocations, getPriceBounds, getPropertyTypes } from "@/lib/queries/lookups";
import { getCurrentProfile } from "@/lib/supabase/server";
import type { PropertyFilters, PropertySort } from "@/lib/types";
import { PROPERTY_SORTS } from "@/lib/types";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Search Rentals",
  description:
    "Search every long-term rental on Kheja_Link — filter by area, house type, rent, bedrooms and amenities across Meru.",
};

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function positiveInt(value: string | string[] | undefined): number | undefined {
  const raw = first(value);
  if (!raw) return undefined;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
}

/** Turns raw query-string values into a validated filter object. */
function parseFilters(params: Record<string, string | string[] | undefined>): PropertyFilters {
  const sortRaw = first(params.sort);
  const sort = PROPERTY_SORTS.some((s) => s.value === sortRaw)
    ? (sortRaw as PropertySort)
    : "newest";

  const amenities = first(params.amenities)?.split(",").filter(Boolean);

  return {
    q: first(params.q)?.slice(0, 120) || undefined,
    type: first(params.type),
    location: first(params.location),
    minPrice: positiveInt(params.minPrice),
    maxPrice: positiveInt(params.maxPrice),
    bedrooms: positiveInt(params.bedrooms),
    amenities: amenities?.length ? amenities : undefined,
    furnished: first(params.furnished) === "1",
    premium: first(params.premium) === "1",
    sort,
    page: positiveInt(params.page) || 1,
    perPage: 12,
  };
}

export default async function PropertiesPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const filters = parseFilters(params);

  const [types, locations, amenities, bounds, profile] = await Promise.all([
    getPropertyTypes(),
    getLocations(),
    getAmenities(),
    getPriceBounds(),
    getCurrentProfile(),
  ]);

  let result;
  let loadError: string | null = null;
  try {
    result = await getProperties(filters);
  } catch {
    result = { items: [], total: 0, page: 1, perPage: 12, pageCount: 1 };
    loadError = "We could not reach the listings just now. Please refresh in a moment.";
  }

  const properties = await withFavoriteState(result.items);

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-7xl mx-auto space-y-12">
          <header className="space-y-4">
            <div className="flex items-center gap-2 text-blue-600 font-black uppercase tracking-[0.2em] text-[10px]">
              <Compass className="w-4 h-4" />
              <span>Every home on Kheja_Link</span>
            </div>
            <h1 className="text-5xl md:text-7xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Search Rentals
            </h1>
          </header>

          <Suspense fallback={<div className="h-16 rounded-[2rem] bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 animate-pulse" />}>
            <PropertyFilterPanel
              types={types}
              locations={locations}
              amenities={amenities}
              bounds={bounds}
              resultCount={result.total}
            />
          </Suspense>

          {loadError ? (
            <EmptyState
              title="Something went wrong"
              body={loadError}
              actionHref="/properties"
              actionLabel="Try again"
            />
          ) : properties.length > 0 ? (
            <>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-12">
                {properties.map((property) => (
                  <PropertyCard key={property.id} property={property} />
                ))}
              </div>
              <Suspense fallback={null}>
                <PropertyPagination page={result.page} pageCount={result.pageCount} />
              </Suspense>
            </>
          ) : (
            <EmptyState
              title="No homes match that search"
              body="Try widening your budget, choosing a nearby area, or clearing a filter or two. New homes are added to Kheja_Link every week."
              actionHref="/properties"
              actionLabel="Clear all filters"
            />
          )}
        </div>
      </main>

      <Footer />
    </div>
  );
}

function EmptyState({
  title,
  body,
  actionHref,
  actionLabel,
}: {
  title: string;
  body: string;
  actionHref: string;
  actionLabel: string;
}) {
  return (
    <div className="py-32 text-center space-y-6">
      <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-900 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
        <Compass className="w-12 h-12 text-zinc-300" />
      </div>
      <div className="space-y-2">
        <h2 className="text-2xl font-black text-zinc-900 dark:text-white">{title}</h2>
        <p className="text-zinc-500 font-medium max-w-md mx-auto">{body}</p>
      </div>
      <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
        <Link
          href={actionHref}
          className="inline-flex items-center justify-center px-8 h-14 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl font-black hover:scale-[1.02] transition-transform"
        >
          {actionLabel}
        </Link>
        <Link
          href="/dashboard/properties/new"
          className="inline-flex items-center justify-center gap-2 px-8 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors"
        >
          <Plus className="w-5 h-5" />
          List your property
        </Link>
      </div>
    </div>
  );
}
