"use server";

import { revalidatePath } from "next/cache";
import { createClient, getCurrentProfile } from "@/lib/supabase/server";
import type { ProfileRow } from "@/lib/supabase/database.types";
import { slugify } from "@/lib/format";
import { availabilitySchema, fieldErrorsOf, propertySchema } from "@/lib/validation";
import type { ActionResult } from "@/lib/types";

const IMAGE_BUCKET = "property-images";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/avif"];

/** Reads the shared listing fields out of a FormData payload. */
function parseListingForm(formData: FormData) {
  const sizeRaw = String(formData.get("sizeSqft") ?? "").trim();

  return propertySchema.safeParse({
    title: formData.get("title"),
    description: formData.get("description") ?? "",
    propertyTypeId: formData.get("propertyTypeId"),
    locationId: formData.get("locationId"),
    addressLine: formData.get("addressLine") ?? "",
    locationDescription: formData.get("locationDescription") ?? "",
    priceAmount: formData.get("priceAmount"),
    pricePeriod: formData.get("pricePeriod") ?? "month",
    depositMonths: formData.get("depositMonths") ?? 1,
    bedrooms: formData.get("bedrooms") ?? 0,
    bathrooms: formData.get("bathrooms") ?? 0,
    sizeSqft: sizeRaw === "" ? undefined : sizeRaw,
    // Checkbox semantics: present means true.
    isFurnished: formData.get("isFurnished") !== null,
    isPremium: formData.get("isPremium") !== null,
    status: formData.get("status") ?? "draft",
    availableFrom: formData.get("availableFrom") ?? "",
    contactPhone: formData.get("contactPhone") ?? "",
    contactWhatsapp: formData.get("contactWhatsapp") ?? "",
    amenityIds: formData.getAll("amenityIds").map(String).filter(Boolean),
    imageUrls: formData.getAll("imageUrls").map(String).filter(Boolean),
  });
}

/**
 * Only landlords and admins may list. The RLS policy enforces this too; this
 * check just produces a friendly message instead of a database error.
 */
type LandlordGate = { error: string } | { profile: ProfileRow };

async function requireLandlord(): Promise<LandlordGate> {
  const profile = await getCurrentProfile();
  if (!profile) return { error: "Please sign in to manage listings." };
  if (profile.role !== "landlord" && profile.role !== "admin") {
    return {
      error:
        "Your account is set up for house hunting. Switch to a landlord account in your profile to start listing.",
    };
  }
  return { profile };
}

export async function createPropertyAction(
  _prev: ActionResult<{ slug: string }> | null,
  formData: FormData,
): Promise<ActionResult<{ slug: string }>> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const parsed = parseListingForm(formData);
  if (!parsed.success) {
    return { ok: false, error: "Please fix the highlighted fields.", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const input = parsed.data;
  const supabase = await createClient();

  const { data: property, error } = await supabase
    .from("properties")
    .insert({
      owner_id: gate.profile.id,
      title: input.title,
      slug: slugify(input.title),
      description: input.description || null,
      property_type_id: input.propertyTypeId,
      location_id: input.locationId,
      address_line: input.addressLine || null,
      nearby: input.locationDescription || null,
      price_amount: input.priceAmount,
      price_currency: "KES",
      price_period: input.pricePeriod,
      deposit_months: input.depositMonths,
      bedrooms: input.bedrooms,
      bathrooms: input.bathrooms,
      size_sqft: input.sizeSqft ?? null,
      is_furnished: input.isFurnished,
      is_premium: input.isPremium,
      status: input.status,
      available_from: input.availableFrom || null,
      contact_phone: input.contactPhone || gate.profile.phone || null,
      contact_whatsapp: input.contactWhatsapp || null,
    })
    .select("id, slug")
    .single();

  if (error || !property) {
    return { ok: false, error: `Could not create the listing: ${error?.message ?? "unknown error"}` };
  }

  await syncAmenities(property.id, input.amenityIds);
  await syncImages(property.id, input.imageUrls);

  revalidatePath("/dashboard/properties");
  revalidatePath("/properties");
  revalidatePath("/");

  return {
    ok: true,
    data: { slug: property.slug },
    message: input.status === "published" ? "Your listing is live." : "Draft saved.",
  };
}

export async function updatePropertyAction(
  propertyId: string,
  _prev: ActionResult<{ slug: string }> | null,
  formData: FormData,
): Promise<ActionResult<{ slug: string }>> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const parsed = parseListingForm(formData);
  if (!parsed.success) {
    return { ok: false, error: "Please fix the highlighted fields.", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const input = parsed.data;
  const supabase = await createClient();

  // The RLS UPDATE policy already restricts this to rows we own; matching on
  // owner_id as well means a wrong id returns "not found" rather than nothing.
  const { data: property, error } = await supabase
    .from("properties")
    .update({
      title: input.title,
      description: input.description || null,
      property_type_id: input.propertyTypeId,
      location_id: input.locationId,
      address_line: input.addressLine || null,
      nearby: input.locationDescription || null,
      price_amount: input.priceAmount,
      price_period: input.pricePeriod,
      deposit_months: input.depositMonths,
      bedrooms: input.bedrooms,
      bathrooms: input.bathrooms,
      size_sqft: input.sizeSqft ?? null,
      is_furnished: input.isFurnished,
      is_premium: input.isPremium,
      status: input.status,
      available_from: input.availableFrom || null,
      contact_phone: input.contactPhone || null,
      contact_whatsapp: input.contactWhatsapp || null,
    })
    .eq("id", propertyId)
    .eq("owner_id", gate.profile.id)
    .select("id, slug")
    .single();

  if (error || !property) {
    return { ok: false, error: `Could not save the listing: ${error?.message ?? "not found"}` };
  }

  await syncAmenities(property.id, input.amenityIds);
  await syncImages(property.id, input.imageUrls);

  revalidatePath("/dashboard/properties");
  revalidatePath(`/properties/${property.slug}`);
  revalidatePath("/properties");
  revalidatePath("/");

  return { ok: true, data: { slug: property.slug }, message: "Listing updated." };
}

export async function deletePropertyAction(propertyId: string): Promise<ActionResult> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const supabase = await createClient();

  // Remove the stored files first — deleting the row cascades the image records
  // away and we would lose the paths.
  const { data: images } = await supabase
    .from("property_images")
    .select("storage_path")
    .eq("property_id", propertyId);

  const paths = (images ?? []).map((i) => i.storage_path).filter((p): p is string => Boolean(p));
  if (paths.length) await supabase.storage.from(IMAGE_BUCKET).remove(paths);

  const { error } = await supabase
    .from("properties")
    .delete()
    .eq("id", propertyId)
    .eq("owner_id", gate.profile.id);

  if (error) return { ok: false, error: "Could not delete that listing." };

  revalidatePath("/dashboard/properties");
  revalidatePath("/properties");
  revalidatePath("/");
  return { ok: true, data: undefined, message: "Listing deleted." };
}

/** Quick status flip from the dashboard list, without opening the full form. */
export async function setPropertyStatusAction(
  propertyId: string,
  status: "draft" | "published" | "rented" | "archived",
): Promise<ActionResult> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const supabase = await createClient();
  const { error } = await supabase
    .from("properties")
    .update({ status })
    .eq("id", propertyId)
    .eq("owner_id", gate.profile.id);

  if (error) return { ok: false, error: "Could not update that listing." };

  revalidatePath("/dashboard/properties");
  revalidatePath("/properties");
  revalidatePath("/");
  return { ok: true, data: undefined, message: `Listing marked as ${status}.` };
}

/**
 * Sets whether a home can be moved into: free now, free from a date, occupied,
 * or temporarily off the market. Tenants waiting on the home are notified by
 * the database when it becomes available — nothing to do here.
 */
export async function setPropertyAvailabilityAction(input: {
  propertyId: string;
  availability: "available" | "occupied" | "notice_given" | "unavailable";
  availableFrom?: string;
  noticeDate?: string;
}): Promise<ActionResult> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const parsed = availabilitySchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the dates and try again." };
  }
  const v = parsed.data;

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties")
    .update({
      availability: v.availability,
      available_from: v.availability === "notice_given" ? v.availableFrom || null : null,
      notice_date: v.availability === "notice_given" ? v.noticeDate || null : null,
    })
    .eq("id", v.propertyId)
    .eq("owner_id", gate.profile.id)
    .select("slug")
    .maybeSingle();

  if (error || !data) return { ok: false, error: "Could not update availability. Please try again." };

  revalidatePath("/dashboard/properties");
  revalidatePath(`/properties/${data.slug}`);
  revalidatePath("/properties");
  return {
    ok: true,
    data: undefined,
    message:
      v.availability === "available"
        ? "Marked available. Anyone waiting for this home has been told."
        : "Availability updated.",
  };
}

/**
 * Uploads one photo to Supabase Storage and returns its public URL.
 * The path starts with the uploader's id, which is what the storage policy
 * checks — a user physically cannot write into someone else's folder.
 */
export async function uploadPropertyImageAction(formData: FormData): Promise<ActionResult<{ url: string; path: string }>> {
  const gate = await requireLandlord();
  if ("error" in gate) return { ok: false, error: gate.error };

  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, error: "Choose a photo to upload." };
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return { ok: false, error: "Photos must be 5 MB or smaller." };
  }
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
    return { ok: false, error: "Photos must be JPEG, PNG, WebP or AVIF." };
  }

  const supabase = await createClient();
  const extension = file.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
  const path = `${gate.profile.id}/${crypto.randomUUID()}.${extension}`;

  const { error } = await supabase.storage
    .from(IMAGE_BUCKET)
    .upload(path, file, { cacheControl: "31536000", upsert: false, contentType: file.type });

  if (error) return { ok: false, error: `Upload failed: ${error.message}` };

  const {
    data: { publicUrl },
  } = supabase.storage.from(IMAGE_BUCKET).getPublicUrl(path);

  return { ok: true, data: { url: publicUrl, path } };
}

/** Replaces the amenity set for a listing. */
async function syncAmenities(propertyId: string, amenityIds: string[]) {
  const supabase = await createClient();
  await supabase.from("property_amenities").delete().eq("property_id", propertyId);
  if (amenityIds.length === 0) return;
  await supabase
    .from("property_amenities")
    .insert(amenityIds.map((amenity_id) => ({ property_id: propertyId, amenity_id })));
}

/**
 * Replaces the image set, preserving order and marking the first as cover.
 * Storage objects for removed images are deleted so we do not accumulate orphans.
 */
async function syncImages(propertyId: string, urls: string[]) {
  const supabase = await createClient();

  const { data: existing } = await supabase
    .from("property_images")
    .select("id, public_url, storage_path")
    .eq("property_id", propertyId);

  const keep = new Set(urls);
  const dropped = (existing ?? []).filter((row) => !keep.has(row.public_url));

  if (dropped.length) {
    await supabase
      .from("property_images")
      .delete()
      .in(
        "id",
        dropped.map((d) => d.id),
      );
    const paths = dropped.map((d) => d.storage_path).filter((p): p is string => Boolean(p));
    if (paths.length) await supabase.storage.from(IMAGE_BUCKET).remove(paths);
  }

  if (urls.length === 0) return;

  // Rewrite the whole set so sort_order and the single cover flag stay correct.
  await supabase.from("property_images").delete().eq("property_id", propertyId);
  await supabase.from("property_images").insert(
    urls.map((public_url, index) => ({
      property_id: propertyId,
      public_url,
      storage_path: storagePathFromUrl(public_url),
      is_cover: index === 0,
      sort_order: index,
    })),
  );
}

/** Recovers the bucket-relative path from a Supabase public URL, if it is one. */
function storagePathFromUrl(url: string): string | null {
  const marker = `/storage/v1/object/public/${IMAGE_BUCKET}/`;
  const index = url.indexOf(marker);
  return index === -1 ? null : decodeURIComponent(url.slice(index + marker.length));
}
