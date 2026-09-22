import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

/**
 * Starts a payment and returns a Paystack checkout URL.
 *
 * Two products share this route, told apart by the reference prefix:
 *
 *   kl_…  the KSh 150 contact unlock for one listing
 *   kh_…  the house hunting fee (KES 500 by default)
 *
 * Either way the app has already written a `pending` row and holds its
 * reference. For the hunting fee the amount is read back from that row — which
 * the database priced from app_settings — so nothing the app sends can change
 * what is charged. Only the webhook can mark a payment paid.
 *
 * Without PAYSTACK_SECRET_KEY the contact unlock falls back to demo mode, as it
 * always has. The hunting fee only does so when PAYMENTS_DEMO_MODE=true, so a
 * missing key in production can never hand out the service for free.
 */

export const dynamic = "force-dynamic";

const UNLOCK_AMOUNT_KES = 150;

type Body = {
  reference?: string;
  email?: string;
  propertyTitle?: string;
};

function serviceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}

function anonClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}

async function paystackCheckout(
  secret: string,
  payload: { email: string; amount: number; currency: string; reference: string; metadata: object },
) {
  try {
    const response = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        ...payload,
        // Paystack takes the smallest currency unit.
        amount: Math.round(payload.amount * 100),
      }),
    });

    const body = (await response.json()) as {
      status?: boolean;
      message?: string;
      data?: { authorization_url?: string };
    };

    if (!response.ok || !body.status || !body.data?.authorization_url) {
      return NextResponse.json(
        { error: body.message ?? "Could not start the payment." },
        { status: 502 },
      );
    }

    return NextResponse.json({
      mode: "paystack",
      checkoutUrl: body.data.authorization_url,
      reference: payload.reference,
    });
  } catch {
    return NextResponse.json(
      { error: "Could not reach the payment provider. Please try again." },
      { status: 502 },
    );
  }
}

async function startHuntingFee(reference: string, email: string, secret: string | undefined) {
  const db = anonClient();
  if (!db) {
    return NextResponse.json({ error: "Payments are not configured." }, { status: 503 });
  }

  const { data, error } = await db.rpc("hunting_checkout_details", { p_reference: reference });
  const row = Array.isArray(data) ? data[0] : null;

  if (error || !row) {
    return NextResponse.json({ error: "That payment could not be found. Please start again." }, { status: 404 });
  }
  if (row.status === "paid") {
    return NextResponse.json({ mode: "already_paid", paid: true });
  }
  if (row.status !== "pending") {
    return NextResponse.json(
      { error: "That payment has expired. Please start again." },
      { status: 409 },
    );
  }

  if (!secret) {
    const admin = serviceClient();
    if (process.env.PAYMENTS_DEMO_MODE !== "true" || !admin) {
      return NextResponse.json(
        { error: "Payments are not available right now. Please try again later." },
        { status: 503 },
      );
    }

    const { data: confirmed, error: confirmError } = await admin.rpc("confirm_hunting_payment", {
      p_reference: reference,
      p_provider: "demo",
      p_amount_received: row.amount,
    });
    if (confirmError) {
      return NextResponse.json({ error: "Could not complete the payment." }, { status: 500 });
    }
    return NextResponse.json({
      mode: "demo",
      paid: confirmed === true,
      message: "Demo mode — activated without taking a payment.",
    });
  }

  return paystackCheckout(secret, {
    email,
    amount: Number(row.amount),
    currency: row.currency?.trim() || "KES",
    reference,
    metadata: { product: "hunting_fee" },
  });
}

export async function POST(request: Request) {
  let body: Body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  const email = body.email?.trim();

  if (!reference || !/^k[lh]_[a-z0-9_]+$/i.test(reference)) {
    return NextResponse.json({ error: "A valid reference is required." }, { status: 400 });
  }
  if (!email || !email.includes("@")) {
    return NextResponse.json({ error: "A valid email is required." }, { status: 400 });
  }

  const secret = process.env.PAYSTACK_SECRET_KEY;

  if (reference.startsWith("kh_")) {
    return startHuntingFee(reference, email, secret);
  }

  // ---- Contact unlock: demo mode when no provider is configured -------------
  if (!secret) {
    const admin = serviceClient();
    if (!admin) {
      return NextResponse.json(
        {
          error:
            "Payments are not configured. Set PAYSTACK_SECRET_KEY, or " +
            "SUPABASE_SERVICE_ROLE_KEY for demo mode.",
        },
        { status: 503 },
      );
    }

    const { data, error } = await admin.rpc("confirm_contact_unlock", {
      p_reference: reference,
      p_provider: "demo",
    });

    if (error) {
      return NextResponse.json({ error: "Could not complete the unlock." }, { status: 500 });
    }

    return NextResponse.json({
      mode: "demo",
      unlocked: data === true,
      message: "Demo mode — unlocked without taking a payment.",
    });
  }

  return paystackCheckout(secret, {
    email,
    amount: UNLOCK_AMOUNT_KES,
    currency: "KES",
    reference,
    metadata: { product: "contact_unlock", property: body.propertyTitle ?? null },
  });
}
