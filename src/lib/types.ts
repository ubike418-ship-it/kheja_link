import type {
  AmenityRow,
  InquiryRow,
  LocationRow,
  PropertyImageRow,
  PropertyRow,
  PropertyTypeRow,
  PublicProfileRow,
} from "./supabase/database.types";

/** A listing joined with everything a card needs to render. */
export type PropertyListItem = PropertyRow & {
  property_type: Pick<PropertyTypeRow, "id" | "slug" | "name" | "icon"> | null;
  location: Pick<
    LocationRow,
    "id" | "slug" | "name" | "area" | "county" | "latitude" | "longitude"
  > | null;
  images: Pick<PropertyImageRow, "id" | "public_url" | "alt_text" | "is_cover" | "sort_order">[];
  is_favorited?: boolean;
};

/** A listing joined with everything the detail page needs. */
export type PropertyDetail = PropertyListItem & {
  owner: PublicProfileRow | null;
  amenities: AmenityRow[];
};

export type InquiryWithProperty = InquiryRow & {
  property: Pick<PropertyRow, "id" | "title" | "slug"> | null;
};

/**
 * The category ids used by the CircularMenu and the navbar.
 * `hunt` means "everything", `premium` is a tier flag rather than a type, and
 * `list` opens the landlord flow — the rest map onto property_types.slug.
 */
export const CATEGORY_TO_TYPE_SLUG: Record<string, string | undefined> = {
  hunt: undefined,
  apartments: "apartment",
  bedsitters: "bedsitter",
  rooms: "single_room",
  shops: "shop",
  premium: undefined,
  list: undefined,
};

export type PropertyFilters = {
  /** Free-text query across title, address and description. */
  q?: string;
  /** property_types.slug */
  type?: string;
  /** locations.slug */
  location?: string;
  minPrice?: number;
  maxPrice?: number;
  bedrooms?: number;
  /** amenities.slug[] — a listing must have all of them. */
  amenities?: string[];
  furnished?: boolean;
  premium?: boolean;
  sort?: PropertySort;
  page?: number;
  perPage?: number;
};

export const PROPERTY_SORTS = [
  { value: "newest", label: "Newest first" },
  { value: "price_asc", label: "Price: low to high" },
  { value: "price_desc", label: "Price: high to low" },
  { value: "bedrooms_desc", label: "Most bedrooms" },
  { value: "popular", label: "Most viewed" },
] as const;

export type PropertySort = (typeof PROPERTY_SORTS)[number]["value"];

export type Paginated<T> = {
  items: T[];
  total: number;
  page: number;
  perPage: number;
  pageCount: number;
};

/** Uniform result shape returned by every server action. */
export type ActionResult<T = undefined> =
  | { ok: true; data: T; message?: string }
  | { ok: false; error: string; fieldErrors?: Record<string, string[]> };
