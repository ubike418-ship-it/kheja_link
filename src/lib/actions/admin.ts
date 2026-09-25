"use server";

import { revalidatePath } from "next/cache";
import { createClient, getCurrentProfile } from "@/lib/supabase/server";
import {
  adminReplySchema,
  feeAllocationSchema,
  houseReviewSchema,
  providerSchema,
  refundPaidSchema,
  settingSchema,
} from "@/lib/validation";
import type { ActionResult } from "@/lib/types";
import type {
  ApprovalStatus,
  InquiryStatus,
  PropertyStatus,
  UserRole,
  WaitlistStatus,
} from "@/lib/supabase/database.types";

/**
 * Admin writes. Every table touched here is admin-only under Row Level
 * Security (0012), so these checks exist to give a clear message — a
 * non-admin who calls an action directly is still refused by Postgres.
 */

async function requireAdmin(): Promise<ActionResult | null> {
  const profile = await getCurrentProfile();
  if (!profile) return { ok: false, error: "Sign in to continue." };
  if (profile.role !== "admin") return { ok: false, error: "Only Kheja_Link admins can do that." };
  return null;
}

const LOGO_TYPES = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"];
const LOGO_MAX_BYTES = 512 * 1024;

// -----------------------------------------------------------------------------
// Service providers
// -----------------------------------------------------------------------------

function readProvider(formData: FormData) {
  return providerSchema.safeParse({
    category: formData.get("category"),
    name: formData.get("name"),
    slug: formData.get("slug"),
    tagline: formData.get("tagline") ?? "",
    description: formData.get("description") ?? "",
    phone: formData.get("phone") ?? "",
    email: formData.get("email") ?? "",
    url: formData.get("url") ?? "",
    location: formData.get("location") ?? "",
    services: formData.get("services") ?? "",
    pricingInfo: formData.get("pricingInfo") ?? "",
    brandColor: formData.get("brandColor") ?? "#2563EB",
    logoUrl: formData.get("logoUrl") ?? "",
    approvalStatus: formData.get("approvalStatus") ?? "pending",
    isActive: formData.get("isActive") === "on",
    isOurs: formData.get("isOurs") === "on",
    sortOrder: formData.get("sortOrder") || 0,
    onboardingFee: formData.get("onboardingFee") || undefined,
    onboardingPaid: formData.get("onboardingPaid") === "on",
  });
}

const blank = (value: string | undefined) => (value && value.trim() ? value.trim() : null);

export async function saveProviderAction(
  _prev: ActionResult<{ id: string }> | null,
  formData: FormData,
): Promise<ActionResult<{ id: string }>> {
  const denied = await requireAdmin();
  if (denied) return denied as ActionResult<{ id: string }>;

  const parsed = readProvider(formData);
  if (!parsed.success) {
    return {
      ok: false,
      error: "Please fix the highlighted fields.",
      fieldErrors: parsed.error.flatten().fieldErrors as Record<string, string[]>,
    };
  }

  const v = parsed.data;
  const id = String(formData.get("id") ?? "") || null;

  const row = {
    category: v.category,
    name: v.name,
    slug: v.slug,
    tagline: blank(v.tagline),
    description: blank(v.description),
    phone: blank(v.phone),
    email: blank(v.email),
    url: blank(v.url),
    location: blank(v.location),
    services: (v.services ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 20),
    pricing_info: blank(v.pricingInfo),
    brand_color: v.brandColor.toUpperCase(),
    logo_url: blank(v.logoUrl),
    approval_status: v.approvalStatus,
    // A provider cannot be live without approval.
    is_active: v.isActive && v.approvalStatus === "approved",
    is_ours: v.isOurs,
    sort_order: v.sortOrder,
    onboarding_fee: v.onboardingFee ?? null,
    onboarding_paid: v.onboardingPaid,
  };

  const supabase = await createClient();
  const { data, error } = id
    ? await supabase.from("partners").update(row).eq("id", id).select("id").single()
    : await supabase.from("partners").insert(row).select("id").single();

  if (error || !data) {
    if (error?.code === "23505") {
      return { ok: false, error: "Another provider already uses that slug.", fieldErrors: { slug: ["Already taken"] } };
    }
    return { ok: false, error: "Could not save the provider. Please try again." };
  }

  revalidatePath("/admin/providers");
  return { ok: true, data: { id: data.id }, message: id ? "Provider updated." : "Provider added." };
}

export async function setProviderStatusAction(
  id: string,
  change: { approvalStatus?: ApprovalStatus; isActive?: boolean },
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const patch: { approval_status?: ApprovalStatus; is_active?: boolean } = {};
  if (change.approvalStatus) {
    patch.approval_status = change.approvalStatus;
    // Rejecting or un-approving always takes a provider off the app.
    if (change.approvalStatus !== "approved") patch.is_active = false;
  }
  if (typeof change.isActive === "boolean") patch.is_active = change.isActive;

  const supabase = await createClient();
  const { data: current } = await supabase
    .from("partners")
    .select("approval_status")
    .eq("id", id)
    .maybeSingle();

  if (!current) return { ok: false, error: "That provider no longer exists." };
  if (patch.is_active && (patch.approval_status ?? current.approval_status) !== "approved") {
    return { ok: false, error: "Approve the provider before making it live." };
  }

  const { error } = await supabase.from("partners").update(patch).eq("id", id);
  if (error) return { ok: false, error: "Could not update the provider." };

  revalidatePath("/admin/providers");
  return { ok: true, data: undefined, message: "Provider updated." };
}

export async function deleteProviderAction(id: string): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase.from("partners").delete().eq("id", id);
  if (error) return { ok: false, error: "Could not delete the provider." };

  revalidatePath("/admin/providers");
  return { ok: true, data: undefined, message: "Provider deleted." };
}

export async function uploadProviderLogoAction(
  formData: FormData,
): Promise<ActionResult<{ url: string }>> {
  const denied = await requireAdmin();
  if (denied) return denied as ActionResult<{ url: string }>;

  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) return { ok: false, error: "Choose an image to upload." };
  if (!LOGO_TYPES.includes(file.type)) return { ok: false, error: "Logos must be PNG, JPEG, WebP or SVG." };
  if (file.size > LOGO_MAX_BYTES) return { ok: false, error: "Logos must be 512 KB or smaller." };

  const ext = file.type === "image/svg+xml" ? "svg" : file.type.split("/")[1].replace("jpeg", "jpg");
  const path = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}.${ext}`;

  const supabase = await createClient();
  const { error } = await supabase.storage
    .from("partner-logos")
    .upload(path, file, { contentType: file.type, cacheControl: "31536000" });

  if (error) return { ok: false, error: "The logo could not be uploaded. Please try again." };

  const { data } = supabase.storage.from("partner-logos").getPublicUrl(path);
  return { ok: true, data: { url: data.publicUrl }, message: "Logo uploaded." };
}

// -----------------------------------------------------------------------------
// Stays waitlist
// -----------------------------------------------------------------------------

export async function setWaitlistStatusAction(id: string, status: WaitlistStatus): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase.from("stays_waitlist").update({ status }).eq("id", id);
  if (error) return { ok: false, error: "Could not update that entry." };

  revalidatePath("/admin/stays");
  return { ok: true, data: undefined, message: "Updated." };
}

// -----------------------------------------------------------------------------
// Business settings and the fee split
// -----------------------------------------------------------------------------

const BOOLEAN_KEYS = new Set([
  "stays_enabled",
  "service_provider_registration_enabled",
  "tenant_notifications_enabled",
]);
const AMOUNT_KEYS = new Set(["contact_unlock_fee", "house_refund_amount", "landlord_listing_fee"]);
const OPTIONAL_AMOUNT_KEYS = new Set(["service_provider_onboarding_fee"]);
/**
 * Not editable here: written by the system, or the retired House Hunting pass,
 * which must keep unlocking listings for the people who already bought it.
 */
const LOCKED_KEYS = new Set([
  "last_maintenance_at",
  "migration_0012_partners_reset",
  "migration_0015_unlock_price",
  "hunting_fee",
  "hunting_fee_currency",
  "hunting_fee_unlocks_contacts",
]);

export async function saveSettingAction(key: string, value: string): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const parsed = settingSchema.safeParse({ key, value });
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid value." };
  if (LOCKED_KEYS.has(key)) return { ok: false, error: "That setting is managed by the system." };

  const v = parsed.data.value;
  if (BOOLEAN_KEYS.has(key) && v !== "true" && v !== "false") {
    return { ok: false, error: "Use true or false." };
  }
  if (AMOUNT_KEYS.has(key) && !(v !== "" && Number.isFinite(Number(v)) && Number(v) >= 0)) {
    return { ok: false, error: "Enter an amount of 0 or more." };
  }
  if (key === "contact_unlock_fee" && Number(v) <= 0) {
    return { ok: false, error: "The unlock price must be more than 0." };
  }
  if (OPTIONAL_AMOUNT_KEYS.has(key) && v !== "" && !(Number.isFinite(Number(v)) && Number(v) >= 0)) {
    return { ok: false, error: "Enter an amount, or leave it blank." };
  }
  if (key === "landlord_listing_fee_offer_ends_on" && v !== "" && !/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    return { ok: false, error: "Use a date like 2026-12-31, or leave it blank." };
  }
  if (key === "contact_unlock_currency" && !/^[A-Z]{3}$/.test(v)) {
    return { ok: false, error: "Use a three-letter currency code, e.g. KES." };
  }

  const supabase = await createClient();

  // The refund comes out of the unlock payment, so it must stay below it.
  if (key === "contact_unlock_fee" || key === "house_refund_amount") {
    const other = key === "contact_unlock_fee" ? "house_refund_amount" : "contact_unlock_fee";
    const { data: row } = await supabase.from("app_settings").select("value").eq("key", other).maybeSingle();
    const fee = key === "contact_unlock_fee" ? Number(v) : Number(row?.value);
    const refund = key === "house_refund_amount" ? Number(v) : Number(row?.value);
    if (Number.isFinite(fee) && Number.isFinite(refund) && refund >= fee) {
      return { ok: false, error: "The house refund must be less than the unlock price." };
    }
  }
  const { data, error } = await supabase
    .from("app_settings")
    .update({ value: v, updated_at: new Date().toISOString() })
    .eq("key", key)
    .select("key");

  if (error || !data?.length) return { ok: false, error: "Could not save that setting." };

  revalidatePath("/admin/settings");
  return { ok: true, data: undefined, message: "Saved. Both apps pick this up on their next load." };
}

export async function saveFeeAllocationAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const parsed = feeAllocationSchema.safeParse({
    product: formData.get("product"),
    party: formData.get("party"),
    sharePercent: formData.get("sharePercent"),
    isActive: formData.get("isActive") === "on",
  });
  if (!parsed.success) {
    return {
      ok: false,
      error: "Please fix the highlighted fields.",
      fieldErrors: parsed.error.flatten().fieldErrors as Record<string, string[]>,
    };
  }

  const v = parsed.data;
  const supabase = await createClient();

  // The active shares of a product may not add up to more than 100%.
  const { data: others } = await supabase
    .from("fee_allocations")
    .select("party, share_percent, is_active")
    .eq("product", v.product);
  const total =
    (others ?? [])
      .filter((o) => o.is_active && o.party !== v.party)
      .reduce((sum, o) => sum + Number(o.share_percent), 0) + (v.isActive ? v.sharePercent : 0);
  if (total > 100) {
    return { ok: false, error: `Active shares would add up to ${total}%. Lower another share first.` };
  }

  const { error } = await supabase.from("fee_allocations").upsert(
    { product: v.product, party: v.party, share_percent: v.sharePercent, is_active: v.isActive },
    { onConflict: "product,party" },
  );
  if (error) return { ok: false, error: "Could not save the share." };

  revalidatePath("/admin/settings");
  return {
    ok: true,
    data: undefined,
    message: total < 100 ? `Saved. The remaining ${100 - total}% goes to the platform.` : "Saved.",
  };
}

// -----------------------------------------------------------------------------
// Messages to Kheja_Link
// -----------------------------------------------------------------------------

export async function replyToMessageAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const parsed = adminReplySchema.safeParse({
    inquiryId: formData.get("inquiryId"),
    reply: formData.get("reply"),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Write a reply." };
  }

  // The database stamps replied_at, marks it responded and drops the reply in
  // the sender's Inbox.
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inquiries")
    .update({ admin_reply: parsed.data.reply })
    .eq("id", parsed.data.inquiryId)
    .eq("recipient", "admin")
    .select("id, sender_id");

  if (error || !data?.length) return { ok: false, error: "Could not send that reply." };

  revalidatePath("/admin/messages");
  return {
    ok: true,
    data: undefined,
    message: data[0].sender_id
      ? "Reply sent to their Kheja_Link Inbox."
      : "Saved. They wrote without an account — call them on the number they left.",
  };
}

export async function setMessageStatusAction(
  inquiryId: string,
  status: InquiryStatus,
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase
    .from("inquiries")
    .update({ status })
    .eq("id", inquiryId)
    .eq("recipient", "admin");
  if (error) return { ok: false, error: "Could not update that message." };

  revalidatePath("/admin/messages");
  return { ok: true, data: undefined };
}

// -----------------------------------------------------------------------------
// Houses tenants gave us, and their refunds
// -----------------------------------------------------------------------------

export async function reviewHouseAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const parsed = houseReviewSchema.safeParse({
    submissionId: formData.get("submissionId"),
    decision: formData.get("decision"),
    note: formData.get("note") ?? "",
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid review." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_review_house_submission", {
    p_submission_id: parsed.data.submissionId,
    p_approve: parsed.data.decision === "approve",
    p_note: parsed.data.note || null,
  });

  if (error) {
    return {
      ok: false,
      error: /already been reviewed/.test(error.message)
        ? "That house has already been reviewed."
        : "Could not save that review.",
    };
  }

  revalidatePath("/admin/refunds");
  const message =
    data === "approved_with_refund"
      ? "Approved. The refund is approved — send it, then mark it paid."
      : data === "approved"
        ? "Approved. This tenant has no paid unlock to refund against."
        : "Rejected. The tenant has been told in the app.";
  return { ok: true, data: undefined, message };
}

export async function markRefundPaidAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const parsed = refundPaidSchema.safeParse({
    refundId: formData.get("refundId"),
    reference: formData.get("reference") ?? "",
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid reference." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_mark_refund_paid", {
    p_refund_id: parsed.data.refundId,
    p_reference: parsed.data.reference || null,
  });
  if (error) return { ok: false, error: "Only an approved refund can be marked paid." };

  revalidatePath("/admin/refunds");
  return { ok: true, data: undefined, message: "Marked paid. The tenant has been told in the app." };
}

// -----------------------------------------------------------------------------
// Accounts
// -----------------------------------------------------------------------------

const ROLES = new Set<UserRole>(["seeker", "landlord", "admin"]);

export async function setUserRoleAction(userId: string, role: string): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;
  if (!ROLES.has(role as UserRole)) return { ok: false, error: "Unknown role." };

  // Nobody locks themselves out of the back office by accident.
  const me = await getCurrentProfile();
  if (me?.id === userId && role !== "admin") {
    return { ok: false, error: "You cannot remove your own admin access. Ask another admin." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .update({ role: role as UserRole })
    .eq("id", userId)
    .select("id");
  if (error || !data?.length) return { ok: false, error: "Could not change that account." };

  revalidatePath("/admin/users");
  return { ok: true, data: undefined, message: "Role updated." };
}

export async function setUserVerifiedAction(userId: string, verified: boolean): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .update({ is_verified: verified })
    .eq("id", userId)
    .select("id");
  if (error || !data?.length) return { ok: false, error: "Could not change that account." };

  revalidatePath("/admin/users");
  return { ok: true, data: undefined, message: verified ? "Verified badge added." : "Verified badge removed." };
}

// -----------------------------------------------------------------------------
// Listings
// -----------------------------------------------------------------------------

const LISTING_STATUSES = new Set<PropertyStatus>(["draft", "pending", "published", "rented", "archived"]);

export async function setListingStatusAction(propertyId: string, status: string): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;
  if (!LISTING_STATUSES.has(status as PropertyStatus)) return { ok: false, error: "Unknown status." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties")
    .update({ status: status as PropertyStatus })
    .eq("id", propertyId)
    .select("slug");
  if (error || !data?.length) return { ok: false, error: "Could not change that listing." };

  revalidatePath("/admin/listings");
  revalidatePath("/properties");
  revalidatePath(`/properties/${data[0].slug}`);
  return { ok: true, data: undefined, message: "Listing updated." };
}

export async function setListingPremiumAction(propertyId: string, premium: boolean): Promise<ActionResult> {
  const denied = await requireAdmin();
  if (denied) return denied;

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties")
    .update({ is_premium: premium })
    .eq("id", propertyId)
    .select("id");
  if (error || !data?.length) return { ok: false, error: "Could not change that listing." };

  revalidatePath("/admin/listings");
  return { ok: true, data: undefined, message: premium ? "Marked premium." : "Premium removed." };
}
