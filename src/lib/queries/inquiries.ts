import { createClient } from "@/lib/supabase/server";
import type { InquiryWithProperty } from "@/lib/types";

/**
 * Inquiries hold personal data. RLS limits SELECT to the listing owner and the
 * original sender, so these queries cannot leak another landlord's leads.
 */

export async function getInquiriesForOwner(): Promise<InquiryWithProperty[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("inquiries")
    .select("*, property:properties ( id, title, slug )")
    .order("created_at", { ascending: false });

  if (error) throw new Error(`Could not load inquiries: ${error.message}`);
  return (data ?? []) as unknown as InquiryWithProperty[];
}

export async function getInquiriesSentByMe(userId: string): Promise<InquiryWithProperty[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("inquiries")
    .select("*, property:properties ( id, title, slug )")
    .eq("sender_id", userId)
    .order("created_at", { ascending: false });

  if (error) throw new Error(`Could not load your messages: ${error.message}`);
  return (data ?? []) as unknown as InquiryWithProperty[];
}
