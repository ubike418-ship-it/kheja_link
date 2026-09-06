"use server";

import { getProperties } from "@/lib/queries/properties";
import { getLocations, getPropertyTypes } from "@/lib/queries/lookups";
import { formatLocation, formatRent } from "@/lib/format";
import type { PropertyFilters, PropertyListItem } from "@/lib/types";

/**
 * The floating assistant, backed by real listings.
 *
 * It reads a plain-English request, pulls out the parts that map onto real
 * columns (budget, area, house type, bedrooms) and runs the same query the
 * search page uses. It only ever reports listings that exist — there is no
 * generative step, so it cannot invent a house.
 */

export type AssistantReply = {
  message: string;
  filters: PropertyFilters;
  properties: AssistantProperty[];
  searchHref: string;
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
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6,
  single: 1, double: 2, bedsitter: 0,
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

async function interpret(query: string): Promise<PropertyFilters & { wantsPremium: boolean }> {
  const text = query.toLowerCase();
  const filters: PropertyFilters & { wantsPremium: boolean } = { wantsPremium: false };

  // --- budget -------------------------------------------------------------
  const between = text.match(/between\s+([\d.,k m]+?)\s+and\s+([\d.,km]+)/);
  if (between) {
    filters.minPrice = parseAmount(between[1]) ?? undefined;
    filters.maxPrice = parseAmount(between[2]) ?? undefined;
  } else {
    const under = text.match(/(?:under|below|less than|up to|max(?:imum)?|budget of|around|about)\s*(?:ksh|kes|sh)?\s*([\d.,]+\s*[km]?)/);
    if (under) filters.maxPrice = parseAmount(under[1]) ?? undefined;

    const over = text.match(/(?:over|above|more than|from|min(?:imum)?)\s*(?:ksh|kes|sh)?\s*([\d.,]+\s*[km]?)/);
    if (over) filters.minPrice = parseAmount(over[1]) ?? undefined;

    // A bare "ksh 25000" with no comparator reads as a ceiling.
    if (!filters.maxPrice && !filters.minPrice) {
      const bare = text.match(/(?:ksh|kes|sh)\s*([\d.,]+\s*[km]?)/);
      if (bare) filters.maxPrice = parseAmount(bare[1]) ?? undefined;
    }
  }

  // --- bedrooms -----------------------------------------------------------
  const bedNumeric = text.match(/(\d+)\s*(?:br|bed|bedroom|bedrooms|b\/r)/);
  if (bedNumeric) {
    filters.bedrooms = Number.parseInt(bedNumeric[1], 10);
  } else {
    const bedWord = text.match(/\b(one|two|three|four|five|six)\b\s*(?:bed|bedroom)/);
    if (bedWord) filters.bedrooms = NUMBER_WORDS[bedWord[1]];
  }

  // --- property type ------------------------------------------------------
  const types = await getPropertyTypes();
  const typeAliases: Record<string, string> = {
    apartment: "apartment", apartments: "apartment", flat: "apartment", flats: "apartment",
    bedsitter: "bedsitter", bedsitters: "bedsitter", "bed sitter": "bedsitter",
    "single room": "single_room", "single rooms": "single_room", room: "single_room",
    rooms: "single_room", hostel: "hostel", hostels: "hostel",
    bungalow: "bungalow", bungalows: "bungalow", house: "bungalow",
    maisonette: "maisonette", maisonettes: "maisonette",
    studio: "studio", studios: "studio",
    shop: "shop", shops: "shop", stall: "shop", retail: "shop", business: "shop",
  };
  for (const [alias, slug] of Object.entries(typeAliases)) {
    if (new RegExp(`\\b${alias}\\b`).test(text) && types.some((t) => t.slug === slug)) {
      filters.type = slug;
      break;
    }
  }

  // --- location -----------------------------------------------------------
  const locations = await getLocations();
  const matched = locations
    .filter((l) => text.includes(l.name.toLowerCase()))
    .sort((a, b) => b.name.length - a.name.length)[0];
  if (matched) filters.location = matched.slug;
  else if (/\bmust\b|meru university/.test(text)) {
    const must = locations.find((l) => l.slug === "must-area");
    if (must) filters.location = must.slug;
  }

  // --- premium ------------------------------------------------------------
  if (/\b(premium|luxury|executive|high[- ]end|posh)\b/.test(text)) {
    filters.wantsPremium = true;
    filters.premium = true;
  }

  // --- free text ----------------------------------------------------------
  // Anything left that is not a filter keyword still helps full-text search,
  // but only when nothing structured matched — otherwise it over-narrows.
  const hasStructure =
    filters.type || filters.location || filters.maxPrice || filters.minPrice || filters.bedrooms;
  if (!hasStructure && query.trim().length > 2) {
    filters.q = query.trim().slice(0, 120);
  }

  filters.sort = filters.maxPrice ? "price_asc" : "newest";
  filters.perPage = 3;
  return filters;
}

function describe(filters: PropertyFilters, total: number, typeName?: string, locationName?: string): string {
  if (total === 0) {
    const parts: string[] = [];
    if (typeName) parts.push(typeName.toLowerCase() + "s");
    if (locationName) parts.push(`in ${locationName}`);
    if (filters.maxPrice) parts.push(`under ${formatRent(filters.maxPrice).replace(" / month", "")}`);
    const what = parts.length ? parts.join(" ") : "listings matching that";
    return `I could not find any ${what} right now. Try widening the budget or a nearby area — new homes are added to Kheja_Link every week.`;
  }

  const bits: string[] = [`I found ${total} ${total === 1 ? "home" : "homes"}`];
  if (typeName) bits.push(total === 1 ? `— a ${typeName.toLowerCase()}` : `— ${typeName.toLowerCase()}s`);
  if (locationName) bits.push(`in ${locationName}`);
  if (filters.bedrooms) bits.push(`with ${filters.bedrooms}+ bedrooms`);
  if (filters.maxPrice) bits.push(`under ${formatRent(filters.maxPrice).replace(" / month", "")} a month`);
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
    };
  }

  // A couple of intents that are not searches at all.
  if (/^(hi|hey|hello|niaje|sasa|habari)\b/.test(trimmed.toLowerCase())) {
    return {
      message:
        "Hi! I can search every home on Kheja_Link for you. Try something like \"2 bedroom in Makutano under 30k\" or \"bedsitter near MUST\".",
      filters: {},
      properties: [],
      searchHref: "/properties",
    };
  }

  if (/\b(list|post|advertise|rent out)\b.*\b(my|a)\b.*\b(house|property|shop|room)\b/.test(trimmed.toLowerCase())) {
    return {
      message:
        "You can list your property yourself — head to your dashboard, add the photos, rent and location, and it goes live once you publish.",
      filters: {},
      properties: [],
      searchHref: "/dashboard/properties/new",
    };
  }

  const { wantsPremium, ...filters } = await interpret(trimmed);
  void wantsPremium;

  try {
    const result = await getProperties(filters);

    const [types, locations] = await Promise.all([getPropertyTypes(), getLocations()]);
    const typeName = filters.type ? types.find((t) => t.slug === filters.type)?.name : undefined;
    const locationName = filters.location
      ? locations.find((l) => l.slug === filters.location)?.name
      : undefined;

    return {
      message: describe(filters, result.total, typeName, locationName),
      filters,
      properties: result.items.map(toAssistantProperty),
      searchHref: buildSearchHref(filters),
    };
  } catch {
    return {
      message: "Something went wrong searching just then. Please try again in a moment.",
      filters: {},
      properties: [],
      searchHref: "/properties",
    };
  }
}
