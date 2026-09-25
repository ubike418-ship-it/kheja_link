import { createClient } from "@/lib/supabase/server";

/**
 * What unlocking a listing costs, and what comes back for giving us a house.
 *
 * The numbers live in app_settings (contact_unlock_fee, house_refund_amount),
 * editable in Admin → Business settings. The database prices every payment
 * from the same rows, so what this shows is what M-Pesa charges. The values
 * below are only the fallback while the settings cannot be read.
 */
export type UnlockPricing = {
  unlockFee: number;
  refundAmount: number;
  currency: string;
};

export const DEFAULT_PRICING: UnlockPricing = { unlockFee: 500, refundAmount: 200, currency: "KES" };

export async function getUnlockPricing(): Promise<UnlockPricing> {
  try {
    const supabase = await createClient();
    const { data } = await supabase
      .from("app_settings")
      .select("key, value")
      .in("key", ["contact_unlock_fee", "house_refund_amount", "contact_unlock_currency"]);

    const byKey = new Map((data ?? []).map((row) => [row.key, row.value.trim()]));
    const num = (key: string, fallback: number) => {
      const n = Number(byKey.get(key));
      return byKey.get(key) && Number.isFinite(n) ? n : fallback;
    };

    return {
      unlockFee: num("contact_unlock_fee", DEFAULT_PRICING.unlockFee),
      refundAmount: num("house_refund_amount", DEFAULT_PRICING.refundAmount),
      currency: byKey.get("contact_unlock_currency") || DEFAULT_PRICING.currency,
    };
  } catch {
    return DEFAULT_PRICING;
  }
}
