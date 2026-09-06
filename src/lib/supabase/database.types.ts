/**
 * Types for the Kheja_Link Supabase schema.
 *
 * Kept in sync by hand with supabase/migrations/*.sql. If you change the schema,
 * change this file in the same commit — or regenerate it with:
 *
 *   npx supabase gen types typescript --project-id <ref> > src/lib/supabase/database.types.ts
 */

export type UserRole = "seeker" | "landlord" | "admin";
export type PropertyStatus = "draft" | "pending" | "published" | "rented" | "archived";
export type PricePeriod = "month" | "year";
export type InquiryStatus = "new" | "read" | "responded" | "closed";

type Timestamps = {
  created_at: string;
  updated_at: string;
};

export type ProfileRow = Timestamps & {
  id: string;
  full_name: string | null;
  phone: string | null;
  avatar_url: string | null;
  role: UserRole;
  is_verified: boolean;
  bio: string | null;
};

export type PublicProfileRow = {
  id: string;
  full_name: string | null;
  avatar_url: string | null;
  is_verified: boolean;
  role: UserRole;
  created_at: string;
};

export type PropertyTypeRow = {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  icon: string | null;
  sort_order: number;
  created_at: string;
};

export type LocationRow = {
  id: string;
  slug: string;
  name: string;
  area: string | null;
  county: string;
  latitude: number | null;
  longitude: number | null;
  created_at: string;
};

export type AmenityRow = {
  id: string;
  slug: string;
  name: string;
  icon: string | null;
  sort_order: number;
};

export type PropertyRow = Timestamps & {
  id: string;
  owner_id: string;
  title: string;
  slug: string;
  description: string | null;
  property_type_id: string;
  location_id: string;
  address_line: string | null;
  price_amount: number;
  price_currency: string;
  price_period: PricePeriod;
  deposit_months: number;
  bedrooms: number;
  bathrooms: number;
  size_sqft: number | null;
  is_premium: boolean;
  is_furnished: boolean;
  status: PropertyStatus;
  available_from: string | null;
  contact_phone: string | null;
  contact_whatsapp: string | null;
  view_count: number;
  published_at: string | null;
};

export type PropertyImageRow = {
  id: string;
  property_id: string;
  storage_path: string | null;
  public_url: string;
  alt_text: string | null;
  is_cover: boolean;
  sort_order: number;
  created_at: string;
};

export type PropertyAmenityRow = {
  property_id: string;
  amenity_id: string;
};

export type FavoriteRow = {
  user_id: string;
  property_id: string;
  created_at: string;
};

export type InquiryRow = Timestamps & {
  id: string;
  property_id: string;
  sender_id: string | null;
  name: string;
  email: string | null;
  phone: string | null;
  message: string;
  status: InquiryStatus;
};

/**
 * Insert shape: every column is optional except the ones with no database
 * default, which the caller genuinely has to supply.
 */
type Insertable<T, Required extends keyof T = never> = Partial<T> & Pick<T, Required>;

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: ProfileRow;
        Insert: Insertable<ProfileRow, "id">;
        Update: Partial<ProfileRow>;
        Relationships: [];
      };
      property_types: {
        Row: PropertyTypeRow;
        Insert: Insertable<PropertyTypeRow, "slug" | "name">;
        Update: Partial<PropertyTypeRow>;
        Relationships: [];
      };
      locations: {
        Row: LocationRow;
        Insert: Insertable<LocationRow, "slug" | "name">;
        Update: Partial<LocationRow>;
        Relationships: [];
      };
      amenities: {
        Row: AmenityRow;
        Insert: Insertable<AmenityRow, "slug" | "name">;
        Update: Partial<AmenityRow>;
        Relationships: [];
      };
      properties: {
        Row: PropertyRow;
        Insert: Insertable<
          PropertyRow,
          "owner_id" | "title" | "slug" | "property_type_id" | "location_id" | "price_amount"
        >;
        Update: Partial<PropertyRow>;
        Relationships: [];
      };
      property_images: {
        Row: PropertyImageRow;
        Insert: Insertable<PropertyImageRow, "property_id" | "public_url">;
        Update: Partial<PropertyImageRow>;
        Relationships: [];
      };
      property_amenities: {
        Row: PropertyAmenityRow;
        Insert: PropertyAmenityRow;
        Update: Partial<PropertyAmenityRow>;
        Relationships: [];
      };
      favorites: {
        Row: FavoriteRow;
        Insert: Insertable<FavoriteRow, "user_id" | "property_id">;
        Update: Partial<FavoriteRow>;
        Relationships: [];
      };
      inquiries: {
        Row: InquiryRow;
        Insert: Insertable<InquiryRow, "property_id" | "name" | "message">;
        Update: Partial<InquiryRow>;
        Relationships: [];
      };
    };
    Views: {
      public_profiles: {
        Row: PublicProfileRow;
        Relationships: [];
      };
    };
    Functions: {
      increment_property_views: {
        Args: { p_property_id: string };
        Returns: undefined;
      };
    };
    Enums: {
      user_role: UserRole;
      property_status: PropertyStatus;
      price_period: PricePeriod;
      inquiry_status: InquiryStatus;
    };
    CompositeTypes: Record<never, never>;
  };
};
