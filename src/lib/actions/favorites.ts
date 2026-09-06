"use server";

import { revalidatePath } from "next/cache";
import { createClient, getCurrentUser } from "@/lib/supabase/server";
import type { ActionResult } from "@/lib/types";

/**
 * Saving a home. RLS pins every row to `user_id = auth.uid()`, so a malicious
 * caller cannot save or unsave on someone else's behalf even by forging ids.
 */
export async function toggleFavoriteAction(
  propertyId: string,
): Promise<ActionResult<{ favorited: boolean }>> {
  const user = await getCurrentUser();
  if (!user) {
    return { ok: false, error: "Sign in to save homes to your list." };
  }

  const supabase = await createClient();

  const { data: existing } = await supabase
    .from("favorites")
    .select("property_id")
    .eq("user_id", user.id)
    .eq("property_id", propertyId)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from("favorites")
      .delete()
      .eq("user_id", user.id)
      .eq("property_id", propertyId);

    if (error) return { ok: false, error: "Could not remove that home. Please try again." };

    revalidatePath("/favorites");
    return { ok: true, data: { favorited: false }, message: "Removed from your saved homes." };
  }

  const { error } = await supabase
    .from("favorites")
    .insert({ user_id: user.id, property_id: propertyId });

  if (error) return { ok: false, error: "Could not save that home. Please try again." };

  revalidatePath("/favorites");
  return { ok: true, data: { favorited: true }, message: "Saved to your list." };
}
