import { z } from "zod";

/**
 * One source of truth for input rules. These mirror the CHECK constraints in
 * the database, so a bad value is rejected before it ever reaches Postgres —
 * and Postgres still refuses it if something slips past.
 */

const phone = z
  .string()
  .trim()
  .regex(/^\+?[\d\s-]{7,20}$/, "Enter a valid phone number, e.g. +254 712 345 678");

export const signUpSchema = z
  .object({
    fullName: z.string().trim().min(2, "Tell us your name").max(120),
    email: z.string().trim().toLowerCase().email("Enter a valid email address"),
    phone: phone.optional().or(z.literal("")),
    password: z
      .string()
      .min(8, "Use at least 8 characters")
      .max(72, "Passwords are limited to 72 characters"),
    confirmPassword: z.string(),
    role: z.enum(["seeker", "landlord"]).default("seeker"),
  })
  .refine((v) => v.password === v.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const signInSchema = z.object({
  email: z.string().trim().toLowerCase().email("Enter a valid email address"),
  password: z.string().min(1, "Enter your password"),
});

export const profileSchema = z.object({
  fullName: z.string().trim().min(2, "Tell us your name").max(120),
  phone: phone.optional().or(z.literal("")),
  bio: z.string().trim().max(600, "Keep your bio under 600 characters").optional().or(z.literal("")),
  role: z.enum(["seeker", "landlord"]),
});

export const inquirySchema = z.object({
  propertyId: z.string().uuid("Unknown property"),
  name: z.string().trim().min(2, "Tell the landlord your name").max(120),
  email: z.string().trim().toLowerCase().email("Enter a valid email address").optional().or(z.literal("")),
  phone: phone.optional().or(z.literal("")),
  message: z
    .string()
    .trim()
    .min(10, "Add a short message so the landlord can help you")
    .max(2000, "Keep your message under 2000 characters"),
});

export const propertySchema = z.object({
  title: z.string().trim().min(6, "Give the listing a clear title").max(160),
  description: z
    .string()
    .trim()
    .min(30, "Describe the place in at least 30 characters")
    .max(4000)
    .optional()
    .or(z.literal("")),
  propertyTypeId: z.string().uuid("Choose a property type"),
  locationId: z.string().uuid("Choose a location"),
  addressLine: z.string().trim().max(200).optional().or(z.literal("")),
  priceAmount: z.coerce
    .number()
    .positive("Rent must be greater than zero")
    .max(100_000_000, "That rent looks too high"),
  pricePeriod: z.enum(["month", "year"]).default("month"),
  depositMonths: z.coerce.number().int().min(0).max(24).default(1),
  bedrooms: z.coerce.number().int().min(0, "Cannot be negative").max(50),
  bathrooms: z.coerce.number().int().min(0, "Cannot be negative").max(50),
  sizeSqft: z.coerce.number().int().min(1).max(1_000_000).optional(),
  // Booleans are read from checkbox presence in the action, not coerced here —
  // z.coerce.boolean() would turn the string "false" into true.
  isFurnished: z.boolean().default(false),
  isPremium: z.boolean().default(false),
  status: z.enum(["draft", "published", "rented", "archived"]).default("draft"),
  availableFrom: z.string().trim().optional().or(z.literal("")),
  contactPhone: phone.optional().or(z.literal("")),
  contactWhatsapp: phone.optional().or(z.literal("")),
  amenityIds: z.array(z.string().uuid()).default([]),
  imageUrls: z.array(z.string().url()).max(12, "Up to 12 photos per listing").default([]),
});

export type SignUpInput = z.infer<typeof signUpSchema>;
export type SignInInput = z.infer<typeof signInSchema>;
export type ProfileInput = z.infer<typeof profileSchema>;
export type InquiryInput = z.infer<typeof inquirySchema>;
export type PropertyInput = z.infer<typeof propertySchema>;

/** Flattens a ZodError into the fieldErrors shape our ActionResult uses. */
export function fieldErrorsOf(error: z.ZodError): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const issue of error.issues) {
    const key = issue.path.join(".") || "form";
    (out[key] ??= []).push(issue.message);
  }
  return out;
}

// -----------------------------------------------------------------------------
// 0012: availability, service providers and business settings
// -----------------------------------------------------------------------------

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Pick a date");

/** Mirrors properties_availability_ok and properties_notice_needs_date. */
export const availabilitySchema = z
  .object({
    propertyId: z.string().uuid("Unknown property"),
    availability: z.enum(["available", "occupied", "notice_given", "unavailable"]),
    availableFrom: isoDate.optional().or(z.literal("")),
    noticeDate: isoDate.optional().or(z.literal("")),
  })
  .refine((v) => v.availability !== "notice_given" || !!v.availableFrom, {
    message: "Choose the date it becomes available",
    path: ["availableFrom"],
  })
  .refine(
    (v) =>
      v.availability !== "notice_given" ||
      !v.availableFrom ||
      v.availableFrom > new Date().toISOString().slice(0, 10),
    { message: "The available-from date must be in the future", path: ["availableFrom"] },
  );

const optionalText = (max: number) => z.string().trim().max(max).optional().or(z.literal(""));

/** Mirrors the partners columns and partners_approval_ok. */
export const providerSchema = z.object({
  category: z.enum(["movers", "isp", "cleaning"]),
  name: z.string().trim().min(2, "Enter the company name").max(120),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, "Lowercase letters, numbers and dashes only")
    .max(80),
  tagline: optionalText(120),
  description: optionalText(1000),
  phone: phone.optional().or(z.literal("")),
  email: z.string().trim().toLowerCase().email("Enter a valid email address").optional().or(z.literal("")),
  url: z.string().trim().url("Enter a full link, e.g. https://example.co.ke").optional().or(z.literal("")),
  location: optionalText(120),
  services: optionalText(600),
  pricingInfo: optionalText(600),
  brandColor: z.string().regex(/^#[0-9a-fA-F]{6}$/, "Use a colour like #2563EB"),
  logoUrl: z.string().trim().url().optional().or(z.literal("")),
  approvalStatus: z.enum(["pending", "approved", "rejected"]),
  isActive: z.boolean(),
  isOurs: z.boolean(),
  sortOrder: z.coerce.number().int().min(0).max(10000),
  onboardingFee: z.coerce.number().min(0).max(10_000_000).optional(),
  onboardingPaid: z.boolean(),
});

export const settingSchema = z.object({
  key: z.string().regex(/^[a-z0-9_]{2,80}$/),
  value: z.string().trim().max(500, "Keep values under 500 characters"),
});

export const feeAllocationSchema = z.object({
  product: z.enum(["hunting_fee", "landlord_listing_fee", "provider_onboarding_fee"]),
  party: z.string().trim().toLowerCase().regex(/^[a-z_]{2,40}$/, "Lowercase letters and underscores, e.g. partner"),
  sharePercent: z.coerce.number().min(0).max(100),
  isActive: z.boolean(),
});
