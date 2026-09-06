"use server";

import { revalidatePath } from "next/cache";
import { createClient, getCurrentUser } from "@/lib/supabase/server";
import { fieldErrorsOf, inquirySchema } from "@/lib/validation";
import type { InquiryStatus } from "@/lib/supabase/database.types";
import type { ActionResult } from "@/lib/types";

/**
 * Contacting a landlord. Guests may send an inquiry without an account — RLS
 * allows INSERT from anon but never SELECT, so nobody can read the resulting
 * personal data except the listing owner and the sender themselves.
 */
export async function sendInquiryAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const parsed = inquirySchema.safeParse({
    propertyId: formData.get("propertyId"),
    name: formData.get("name"),
    email: formData.get("email") ?? "",
    phone: formData.get("phone") ?? "",
    message: formData.get("message"),
  });

  if (!parsed.success) {
    return {
      ok: false,
      error: "Please fix the highlighted fields.",
      fieldErrors: fieldErrorsOf(parsed.error),
    };
  }

  const { propertyId, name, email, phone, message } = parsed.data;

  if (!email && !phone) {
    return {
      ok: false,
      error: "Leave an email or a phone number so the landlord can reply.",
      fieldErrors: { email: ["Add an email or a phone number"] },
    };
  }

  const user = await getCurrentUser();
  const supabase = await createClient();

  const { error } = await supabase.from("inquiries").insert({
    property_id: propertyId,
    sender_id: user?.id ?? null,
    name,
    email: email || null,
    phone: phone || null,
    message,
  });

  if (error) {
    // The RLS check fails when the listing is not published — treat that as a
    // gone listing rather than leaking policy detail.
    return {
      ok: false,
      error: "This listing is no longer accepting inquiries. Please try another home.",
    };
  }

  revalidatePath("/dashboard/inquiries");
  return {
    ok: true,
    data: undefined,
    message: "Message sent. The landlord will get back to you shortly.",
  };
}

/** Landlords marking a lead as read / responded / closed. */
export async function updateInquiryStatusAction(
  inquiryId: string,
  status: InquiryStatus,
): Promise<ActionResult> {
  const user = await getCurrentUser();
  if (!user) return { ok: false, error: "Please sign in first." };

  const supabase = await createClient();
  const { error } = await supabase.from("inquiries").update({ status }).eq("id", inquiryId);

  if (error) return { ok: false, error: "Could not update that inquiry." };

  revalidatePath("/dashboard/inquiries");
  return { ok: true, data: undefined };
}
