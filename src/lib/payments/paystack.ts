import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Paystack, used as an API only.
 *
 * Kheja_Link shows its own payment screens — choose M-Pesa, type your number,
 * watch the status — and this module talks to Paystack behind them. Nothing
 * here trusts the app: the amount always comes from the pending row in our own
 * database, and a payment is only ever marked paid after Paystack itself says
 * so, either through the signed webhook or through a server-side verify.
 *
 * Reference prefixes tell the two products apart:
 *   kl_…  a contact unlock for one listing (contact_unlock_fee, KES 500)
 *   kh_…  the retired house hunting pass — only checkouts already open
 */

const PAYSTACK = "https://api.paystack.co";

export type Product = "hunting_fee" | "contact_unlock";

export type Checkout = {
  product: Product;
  amount: number;
  currency: string;
  status: string;
  propertyId?: string | null;
};

export function productFor(reference: string): Product | null {
  if (reference.startsWith("kh_")) return "hunting_fee";
  if (reference.startsWith("kl_")) return "contact_unlock";
  return null;
}

export function isValidReference(reference: string | undefined): reference is string {
  return !!reference && /^k[lh]_[a-z0-9_]{6,80}$/i.test(reference);
}

/** Normalises a Kenyan number to +2547…/+2541…. Null if it is not one. */
export function kenyanMsisdn(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const digits = raw.replace(/[^\d+]/g, "");
  if (/^\+254[17]\d{8}$/.test(digits)) return digits;
  if (/^254[17]\d{8}$/.test(digits)) return `+${digits}`;
  if (/^0[17]\d{8}$/.test(digits)) return `+254${digits.slice(1)}`;
  if (/^[17]\d{8}$/.test(digits)) return `+254${digits}`;
  return null;
}

/** The same number as 07…/01…, which some Paystack endpoints prefer. */
export function localMsisdn(international: string): string {
  return international.replace(/^\+254/, "0");
}

export function serviceClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}

/**
 * A Supabase client acting as the signed-in tenant, from the app's bearer
 * token. Row Level Security then does the access control for us: a payment
 * that is not theirs simply is not there.
 */
export function userClient(request: Request): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const authorization = request.headers.get("authorization") ?? "";
  if (!url || !anon || !authorization.toLowerCase().startsWith("bearer ")) return null;
  return createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
}

/** The pending payment, read as the tenant — so it must be their own. */
export async function loadCheckout(
  db: SupabaseClient,
  reference: string,
): Promise<Checkout | null> {
  const product = productFor(reference);
  if (!product) return null;

  if (product === "hunting_fee") {
    const { data } = await db
      .from("hunting_payments")
      .select("amount, currency, status")
      .eq("provider_ref", reference)
      .maybeSingle();
    if (!data) return null;
    return {
      product,
      amount: Number(data.amount),
      currency: (data.currency ?? "KES").trim(),
      status: data.status,
    };
  }

  const { data } = await db
    .from("contact_unlocks")
    .select("amount, currency, status, property_id")
    .eq("provider_ref", reference)
    .maybeSingle();
  if (!data) return null;
  return {
    product,
    amount: Number(data.amount),
    currency: (data.currency ?? "KES").trim(),
    status: data.status,
    propertyId: data.property_id,
  };
}

type PaystackResponse<T> = { ok: boolean; status: number; message: string; data: T | null };

export async function paystack<T>(
  path: string,
  init?: { method?: string; body?: unknown },
): Promise<PaystackResponse<T>> {
  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) {
    return { ok: false, status: 503, message: "Payments are not configured.", data: null };
  }

  try {
    const response = await fetch(`${PAYSTACK}${path}`, {
      method: init?.method ?? "GET",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      body: init?.body ? JSON.stringify(init.body) : undefined,
      cache: "no-store",
    });

    const body = (await response.json().catch(() => null)) as
      | { status?: boolean; message?: string; data?: T }
      | null;

    return {
      ok: response.ok && body?.status !== false,
      status: response.status,
      message: body?.message ?? "",
      data: (body?.data as T) ?? null,
    };
  } catch {
    return {
      ok: false,
      status: 502,
      message: "Could not reach the payment provider. Please try again.",
      data: null,
    };
  }
}

export type VerifiedTransaction = {
  status: string;
  amount: number;
  currency: string;
  gateway_response?: string;
  display_text?: string;
};

/**
 * Asks Paystack what really happened, then — and only then — marks our row
 * paid. Safe to call repeatedly: confirming twice does nothing the second time.
 */
export async function verifyAndConfirm(reference: string): Promise<{
  status: "success" | "pending" | "failed" | "unknown";
  message: string;
  displayText?: string | null;
}> {
  const product = productFor(reference);
  if (!product) return { status: "unknown", message: "Unknown payment." };

  const verified = await paystack<VerifiedTransaction>(
    `/transaction/verify/${encodeURIComponent(reference)}`,
  );

  if (!verified.ok || !verified.data) {
    // A transaction Paystack has never seen means the charge never started.
    const notFound = verified.status === 404;
    return {
      status: notFound ? "unknown" : "pending",
      message: notFound ? "No payment has been started yet." : verified.message || "Still checking…",
    };
  }

  const tx = verified.data;
  const paid = Number(tx.amount ?? 0) / 100;

  if (tx.status === "success") {
    const admin = serviceClient();
    if (!admin) {
      return {
        status: "pending",
        message:
          "Your payment went through, but Kheja_Link could not record it. " +
          "Please contact support — you will not be charged again.",
      };
    }

    if (product === "hunting_fee") {
      const { error } = await admin.rpc("confirm_hunting_payment", {
        p_reference: reference,
        p_provider: "paystack",
        p_amount_received: paid,
      });
      if (error) return { status: "pending", message: "Confirming your payment…" };
    } else {
      const { data: details } = await admin.rpc("unlock_checkout_details", {
        p_reference: reference,
      });
      const expected = Array.isArray(details) ? Number(details[0]?.amount ?? 0) : 0;
      if (expected > 0 && paid + 0.001 < expected) {
        return { status: "failed", message: "The amount paid was less than the price." };
      }
      const { error } = await admin.rpc("confirm_contact_unlock", {
        p_reference: reference,
        p_provider: "paystack",
        p_amount_received: paid,
      });
      if (error) return { status: "pending", message: "Confirming your payment…" };
    }

    return { status: "success", message: "Payment received." };
  }

  if (tx.status === "failed" || tx.status === "reversed") {
    return {
      status: "failed",
      message: tx.gateway_response || "The payment did not go through.",
    };
  }

  // ongoing / pending / processing / abandoned / queued
  return {
    status: tx.status === "abandoned" ? "failed" : "pending",
    message:
      tx.status === "abandoned"
        ? "The payment was not completed."
        : tx.gateway_response || "Waiting for your confirmation…",
    displayText: tx.display_text ?? null,
  };
}
