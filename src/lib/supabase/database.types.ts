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
export type Availability = "available" | "occupied" | "notice_given" | "unavailable";
export type PartnerCategory = "movers" | "isp" | "cleaning";
export type ApprovalStatus = "pending" | "approved" | "rejected";
export type WaitlistStatus = "new" | "contacted" | "onboarded" | "declined";
export type FeeProduct = "hunting_fee" | "landlord_listing_fee" | "provider_onboarding_fee";
export type InquiryRecipient = "landlord" | "admin";
export type UnlockStatus = "pending" | "paid" | "failed" | "refunded";
export type HouseSubmissionStatus = "pending" | "approved" | "rejected";
export type RefundStatus = "pending" | "approved" | "paid" | "rejected";

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
  tenant_onboarded_at: string | null;
  landlord_onboarded_at: string | null;
  stays_onboarded_at: string | null;
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
  /** Locked behind the paid unlock (0016); only get_property_contact returns it. */
  address_line: string | null;
  /** The landlord's public description of the location. */
  nearby: string | null;
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
  availability: Availability;
  notice_date: string | null;
  availability_updated_at: string | null;
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
  /** Who the message is for. New messages always go to Kheja_Link (0015). */
  recipient: InquiryRecipient;
  admin_reply: string | null;
  replied_at: string | null;
};

export type PartnerRow = {
  id: string;
  category: PartnerCategory;
  slug: string;
  name: string;
  tagline: string | null;
  description: string | null;
  logo_url: string | null;
  brand_color: string;
  icon: string | null;
  phone: string | null;
  email: string | null;
  url: string | null;
  location: string | null;
  services: string[];
  pricing_info: string | null;
  is_ours: boolean;
  is_active: boolean;
  approval_status: ApprovalStatus;
  onboarding_fee: number | null;
  onboarding_paid: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

export type AppSettingRow = {
  key: string;
  value: string;
  is_public: boolean;
  description: string | null;
  updated_at: string;
};

export type StaysWaitlistRow = {
  id: string;
  user_id: string | null;
  full_name: string;
  phone: string | null;
  email: string | null;
  location: string | null;
  property_count: number | null;
  property_type: string | null;
  message: string | null;
  status: WaitlistStatus;
  created_at: string;
};

export type FeeAllocationRow = Timestamps & {
  id: string;
  product: FeeProduct;
  party: string;
  share_percent: number;
  is_active: boolean;
  notes: string | null;
};

export type ContactUnlockRow = {
  id: string;
  user_id: string;
  property_id: string;
  amount: number;
  currency: string;
  status: UnlockStatus;
  provider: string;
  provider_ref: string | null;
  amount_received: number | null;
  duplicate_payment: boolean;
  created_at: string;
  paid_at: string | null;
  /** End of the paid window (contact_unlock_hours after payment, 0016). */
  expires_at: string | null;
};

export type PaymentAttemptRow = {
  id: string;
  reference: string;
  product: "hunting_fee" | "contact_unlock";
  channel: "mobile_money" | "card" | "checkout";
  status: string;
  display_text: string | null;
  provider_ref: string | null;
  message: string | null;
  user_id: string | null;
  msisdn_hash: string | null;
  created_at: string;
  updated_at: string;
};

export type HouseSubmissionRow = Timestamps & {
  id: string;
  user_id: string;
  location_id: string | null;
  area: string | null;
  property_type_id: string | null;
  bedrooms: number | null;
  rent_amount: number | null;
  available_from: string | null;
  landlord_name: string | null;
  landlord_phone: string;
  relationship: "moving_out" | "landlord_agrees";
  notes: string | null;
  status: HouseSubmissionStatus;
  admin_note: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
};

export type UnlockRefundRow = Timestamps & {
  id: string;
  user_id: string;
  submission_id: string;
  unlock_id: string | null;
  amount: number;
  currency: string;
  status: RefundStatus;
  payout_reference: string | null;
  approved_at: string | null;
  paid_at: string | null;
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
      partners: {
        Row: PartnerRow;
        Insert: Insertable<PartnerRow, "category" | "slug" | "name">;
        Update: Partial<PartnerRow>;
        Relationships: [];
      };
      app_settings: {
        Row: AppSettingRow;
        Insert: Insertable<AppSettingRow, "key" | "value">;
        Update: Partial<AppSettingRow>;
        Relationships: [];
      };
      stays_waitlist: {
        Row: StaysWaitlistRow;
        Insert: Insertable<StaysWaitlistRow, "full_name">;
        Update: Partial<StaysWaitlistRow>;
        Relationships: [];
      };
      fee_allocations: {
        Row: FeeAllocationRow;
        Insert: Insertable<FeeAllocationRow, "product" | "party" | "share_percent">;
        Update: Partial<FeeAllocationRow>;
        Relationships: [];
      };
      contact_unlocks: {
        Row: ContactUnlockRow;
        Insert: Insertable<ContactUnlockRow, "user_id" | "property_id">;
        Update: Partial<ContactUnlockRow>;
        Relationships: [];
      };
      house_submissions: {
        Row: HouseSubmissionRow;
        Insert: Insertable<HouseSubmissionRow, "user_id" | "landlord_phone">;
        Update: Partial<HouseSubmissionRow>;
        Relationships: [];
      };
      payment_attempts: {
        Row: PaymentAttemptRow;
        Insert: Insertable<PaymentAttemptRow, "reference" | "product" | "channel">;
        Update: Partial<PaymentAttemptRow>;
        Relationships: [];
      };
      unlock_refunds: {
        Row: UnlockRefundRow;
        Insert: Insertable<UnlockRefundRow, "user_id" | "submission_id" | "amount">;
        Update: Partial<UnlockRefundRow>;
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
      get_my_property_private: {
        Args: { p_property_id: string };
        Returns: {
          contact_phone: string | null;
          contact_whatsapp: string | null;
          latitude: number | null;
          longitude: number | null;
          landlord_name: string | null;
          caretaker_name: string | null;
          caretaker_phone: string | null;
          address_line: string | null;
          building_name: string | null;
        }[];
      };
      run_daily_maintenance: {
        Args: Record<string, never>;
        Returns: Record<string, unknown>;
      };
      hunting_checkout_details: {
        Args: { p_reference: string };
        Returns: { amount: number; currency: string; status: string }[];
      };
      unlock_checkout_details: {
        Args: { p_reference: string };
        Returns: { amount: number; currency: string; status: string; property_id: string }[];
      };
      start_contact_unlock: {
        Args: { p_property_id: string };
        Returns: {
          reference: string | null;
          amount: number;
          currency: string;
          already_unlocked: boolean;
        }[];
      };
      admin_review_house_submission: {
        Args: { p_submission_id: string; p_approve: boolean; p_note?: string | null };
        Returns: string;
      };
      admin_overview: {
        Args: Record<string, never>;
        Returns: Record<string, number | string>;
      };
      admin_list_users: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          email: string | null;
          full_name: string | null;
          phone: string | null;
          role: UserRole;
          is_verified: boolean;
          created_at: string;
          last_sign_in_at: string | null;
          listings: number;
          unlocks: number;
        }[];
      };
      delete_my_account: {
        Args: Record<string, never>;
        Returns: boolean;
      };
      admin_delete_user: {
        Args: { p_user_id: string };
        Returns: boolean;
      };
      admin_mark_refund_paid: {
        Args: { p_refund_id: string; p_reference?: string | null };
        Returns: boolean;
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
