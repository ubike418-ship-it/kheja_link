"use server";

import { getProperties } from "@/lib/queries/properties";
import { getLocations, getPropertyTypes, getAmenities } from "@/lib/queries/lookups";
import { createClient } from "@/lib/supabase/server";
import { formatLocation, formatRent } from "@/lib/format";
import { matchKnowledge, type SiteStats } from "@/lib/assistant/knowledge";
import type { PropertyFilters, PropertyListItem } from "@/lib/types";

/**
 * The Kheja_Link assistant.
 *
 * It does two things, in this order:
 *
 *   1. Answers questions about Kheja_Link itself, from a knowledge base whose
 *      figures are filled in from the live database.
 *   2. Otherwise treats the message as a property search — pulling budget,
 *      area, house type and bedroom count out of plain English and running the
 *      same query the search page uses.
 *
 * There is no generative step anywhere, so it cannot invent a house, a price
 * or a policy. Everything it says is either a stated fact about the product or
 * a row that exists in the database.
 */

export type AssistantReply = {
  message: string;
  filters: PropertyFilters;
  properties: AssistantProperty[];
  searchHref: string;
  /** Label for the link, when the answer offers one. */
  hrefLabel?: string;
  /** Follow-up chips shown under the reply. */
  suggestions?: string[];
};

export type AssistantProperty = {
  id: string;
  slug: string;
  title: string;
  price: string;
  location: string;
  type: string;
  bedrooms: number;
  image: string | null;
};

const NUMBER_WORDS: Record<string, number> = {
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, single: 1, double: 2,
};

/** "45k", "45,000", "ksh 45000" -> 45000 */
function parseAmount(raw: string): number | null {
  const cleaned = raw.toLowerCase().replace(/[,\s]/g, "");
  const match = cleaned.match(/(\d+(?:\.\d+)?)(k|m)?/);
  if (!match) return null;
  const value = Number.parseFloat(match[1]);
  if (Number.isNaN(value)) return null;
  if (match[2] === "k") return value * 1_000;
  if (match[2] === "m") return value * 1_000_000;
  // A bare small number in a money context almost always means thousands.
  return value < 1000 ? value * 1000 : value;
}

/** Live figures, so every factual answer reflects the real database. */
async function loadStats(): Promise<SiteStats> {
  const [types, locations, amenities] = await Promise.all([
    getPropertyTypes(),
    getLocations(),
    getAmenities(),
  ]);

  const supabase = await createClient();

  const [{ count }, { data: priceRows }, { data: typeRows }] = await Promise.all([
    supabase
      .from("properties")
      .select("id", { count: "exact", head: true })
      .eq("status", "published"),
    supabase
      .from("properties")
      .select("price_amount, title, slug, price_currency, price_period")
      .eq("status", "published")
      .order("price_amount", { ascending: true }),
    supabase.from("properties").select("property_type_id").eq("status", "published"),
  ]);

  const perType = new Map<string, number>();
  for (const row of typeRows ?? []) {
    const id = row.property_type_id;
    perType.set(id, (perType.get(id) ?? 0) + 1);
  }

  const prices = (priceRows ?? []).map((r) => Number(r.price_amount));
  const cheapestRow = priceRows?.[0];

  return {
    total: count ?? 0,
    minPrice: prices.length ? Math.min(...prices) : 0,
    maxPrice: prices.length ? Math.max(...prices) : 0,
    locations: locations.map((l) => l.name),
    amenities: amenities.map((a) => a.name),
    types: types.map((t) => ({
      name: t.name,
      slug: t.slug,
      count: perType.get(t.id) ?? 0,
    })),
    cheapest: cheapestRow
      ? {
          title: cheapestRow.title,
          slug: cheapestRow.slug,
          price: formatRent(
            Number(cheapestRow.price_amount),
            cheapestRow.price_period,
            cheapestRow.price_currency,
          ),
        }
      : null,
  };
}

/** Pulls structured filters out of plain English. */
async function interpret(query: string): Promise<PropertyFilters> {
  const text = query.toLowerCase();
  const filters: PropertyFilters = {};

  // --- budget ---------------------------------------------------------------
  const between = text.match(/between\s+([\d.,k\s]+?)\s+and\s+([\d.,km]+)/);
  if (between) {
    filters.minPrice = parseAmount(between[1]) ?? undefined;
    filters.maxPrice = parseAmount(between[2]) ?? undefined;
  } else {
    const under = text.match(
      /(?:under|below|less than|up to|max(?:imum)?|budget of|around|about|within)\s*(?:ksh|kes|sh)?\s*([\d.,]+\s*[km]?)/,
    );
    if (under) filters.maxPrice = parseAmount(under[1]) ?? undefined;

    const over = text.match(
      /(?:over|above|more than|from|min(?:imum)?|starting at)\s*(?:ksh|kes|sh)?\s*([\d.,]+\s*[km]?)/,
    );
    if (over) filters.minPrice = parseAmount(over[1]) ?? undefined;

    if (!filters.maxPrice && !filters.minPrice) {
      const bare = text.match(/(?:ksh|kes|sh)\s*([\d.,]+\s*[km]?)/);
      if (bare) filters.maxPrice = parseAmount(bare[1]) ?? undefined;
    }
  }

  // --- bedrooms -------------------------------------------------------------
  const bedNumeric = text.match(/(\d+)\s*(?:br|bed|bedroom|bedrooms|b\/r)\b/);
  if (bedNumeric) {
    filters.bedrooms = Number.parseInt(bedNumeric[1], 10);
  } else {
    const bedWord = text.match(/\b(one|two|three|four|five|six)\b\s*(?:bed|bedroom)/);
    if (bedWord) filters.bedrooms = NUMBER_WORDS[bedWord[1]];
  }

  // --- property type --------------------------------------------------------
  const types = await getPropertyTypes();
  const aliases: Record<string, string> = {
    apartment: "apartment", apartments: "apartment", flat: "apartment", flats: "apartment",
    bedsitter: "bedsitter", bedsitters: "bedsitter", "bed sitter": "bedsitter",
    "single room": "single_room", "single rooms": "single_room", room: "single_room",
    rooms: "single_room", hostel: "hostel", hostels: "hostel",
    bungalow: "bungalow", bungalows: "bungalow",
    maisonette: "maisonette", maisonettes: "maisonette",
    studio: "studio", studios: "studio",
    shop: "shop", shops: "shop", stall: "shop", retail: "shop",
  };
  for (const [alias, slug] of Object.entries(aliases)) {
    if (new RegExp(`\\b${alias}\\b`).test(text) && types.some((t) => t.slug === slug)) {
      filters.type = slug;
      break;
    }
  }

  // --- location -------------------------------------------------------------
  const locations = await getLocations();
  const matched = locations
    .filter((l) => text.includes(l.name.toLowerCase()))
    .sort((a, b) => b.name.length - a.name.length)[0];
  if (matched) {
    filters.location = matched.slug;
  } else if (/\bmust\b|meru university|nchiru|campus/.test(text)) {
    const must = locations.find((l) => l.slug === "must-area");
    if (must) filters.location = must.slug;
  }

  // --- flags ----------------------------------------------------------------
  if (/\b(premium|luxury|executive|high[- ]end|posh)\b/.test(text)) filters.premium = true;
  if (/\bfurnished\b/.test(text)) filters.furnished = true;

  // Free text only helps when nothing structured matched; otherwise it
  // over-narrows an already-good query.
  const hasStructure =
    filters.type || filters.location || filters.maxPrice || filters.minPrice || filters.bedrooms;
  if (!hasStructure && query.trim().length > 2) {
    filters.q = query.trim().slice(0, 120);
  }

  filters.sort = filters.maxPrice ? "price_asc" : "newest";
  filters.perPage = 3;
  return filters;
}

function describe(
  filters: PropertyFilters,
  total: number,
  typeName?: string,
  locationName?: string,
): string {
  if (total === 0) {
    const parts: string[] = [];
    if (typeName) parts.push(`${typeName.toLowerCase()}s`);
    if (locationName) parts.push(`in ${locationName}`);
    if (filters.maxPrice) {
      parts.push(`under ${formatRent(filters.maxPrice).replace(" / month", "")}`);
    }
    const what = parts.length ? parts.join(" ") : "listings matching that";
    return (
      `I could not find any ${what} right now.\n\n` +
      `Try widening the budget or a nearby area — new homes are added to Kheja_Link every week. ` +
      `You can also ask me what areas we cover.`
    );
  }

  const bits: string[] = [`I found ${total} ${total === 1 ? "home" : "homes"}`];
  if (typeName) bits.push(total === 1 ? `— a ${typeName.toLowerCase()}` : `— ${typeName.toLowerCase()}s`);
  if (locationName) bits.push(`in ${locationName}`);
  if (filters.bedrooms) bits.push(`with ${filters.bedrooms}+ bedrooms`);
  if (filters.maxPrice) {
    bits.push(`under ${formatRent(filters.maxPrice).replace(" / month", "")} a month`);
  }
  return `${bits.join(" ")}. Here are the closest matches:`;
}

function toAssistantProperty(p: PropertyListItem): AssistantProperty {
  return {
    id: p.id,
    slug: p.slug,
    title: p.title,
    price: formatRent(p.price_amount, p.price_period, p.price_currency),
    location: formatLocation(p.location),
    type: p.property_type?.name ?? "Rental",
    bedrooms: p.bedrooms,
    image: p.images?.[0]?.public_url ?? null,
  };
}

function buildSearchHref(filters: PropertyFilters): string {
  const params = new URLSearchParams();
  if (filters.q) params.set("q", filters.q);
  if (filters.type) params.set("type", filters.type);
  if (filters.location) params.set("location", filters.location);
  if (filters.minPrice) params.set("minPrice", String(filters.minPrice));
  if (filters.maxPrice) params.set("maxPrice", String(filters.maxPrice));
  if (filters.bedrooms) params.set("bedrooms", String(filters.bedrooms));
  if (filters.premium) params.set("premium", "1");
  if (filters.furnished) params.set("furnished", "1");
  const query = params.toString();
  return query ? `/properties?${query}` : "/properties";
}

export async function askAssistantAction(query: string): Promise<AssistantReply> {
  const trimmed = query.trim();

  if (trimmed.length < 2) {
    return {
      message: "Tell me what you are looking for — a budget, an area, or the kind of house.",
      filters: {},
      properties: [],
      searchHref: "/properties",
      suggestions: ["What areas do you cover?", "Is it free?", "2 bedroom under 30k"],
    };
  }

  try {
    const filters = await interpret(trimmed);

    // "bedsitter near MUST" is a search, even though it mentions a topic the
    // knowledge base has an article about. A budget or bedroom count is always
    // decisive; a house type only counts when paired with a place.
    const hasStrongSearchSignal = Boolean(
      filters.maxPrice ||
        filters.minPrice ||
        filters.bedrooms ||
        (filters.type && filters.location),
    );

    // 1. A question about Kheja_Link itself.
    if (!hasStrongSearchSignal) {
      const entry = matchKnowledge(trimmed);
      if (entry) {
        const stats = await loadStats();
        const answer = entry.answer(stats);
        return {
          message: answer.message,
          filters: {},
          properties: [],
          searchHref: answer.href ?? "/properties",
          hrefLabel: answer.hrefLabel,
          suggestions: answer.suggestions,
        };
      }
    }

    // 2. Otherwise, a property search.
    const result = await getProperties(filters);

    const [types, locations] = await Promise.all([getPropertyTypes(), getLocations()]);
    const typeName = filters.type ? types.find((t) => t.slug === filters.type)?.name : undefined;
    const locationName = filters.location
      ? locations.find((l) => l.slug === filters.location)?.name
      : undefined;

    const found = result.total > 0;

    return {
      message: describe(filters, result.total, typeName, locationName),
      filters,
      properties: result.items.map(toAssistantProperty),
      searchHref: buildSearchHref(filters),
      hrefLabel: found ? "See all matches" : "Browse everything",
      suggestions: found
        ? ["What should I check at a viewing?", "How do I contact a landlord?"]
        : ["What areas do you cover?", "What's the price range?", "Show me everything"],
    };
  } catch {
    return {
      message:
        "Something went wrong just then. Please try again in a moment — or browse the listings directly.",
      filters: {},
      properties: [],
      searchHref: "/properties",
      hrefLabel: "Browse homes",
    };
  }
}
