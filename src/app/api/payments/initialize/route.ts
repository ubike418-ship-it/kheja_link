import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

/**
 * Starts a KSh 150 contact unlock.
 *
 * The app has already written a `pending` row and holds its reference. This
 * asks Paystack for a checkout URL for that reference and hands it back.
 *
 * If Paystack is not configured, the unlock is confirmed immediately and the
 * response says so — the whole flow stays usable for demos without anyone
 * being charged. Set PAYSTACK_SECRET_KEY to take real payments.
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

export async function POST(request: Request) {
  let body: Body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  const email = body.email?.trim();

  if (!reference || !/^kl_[a-z0-9_]+$/i.test(reference)) {
    return NextResponse.json({ error: "A valid reference is required." }, { status: 400 });
  }
  if (!email || !email.includes("@")) {
    return NextResponse.json({ error: "A valid email is required." }, { status: 400 });
  }

  const secret = process.env.PAYSTACK_SECRET_KEY;

  // ---- Demo mode: no provider configured -----------------------------------
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

  // ---- Real Paystack checkout ----------------------------------------------
  try {
    const response = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        // Paystack takes the smallest currency unit.
        amount: UNLOCK_AMOUNT_KES * 100,
        currency: "KES",
        reference,
        metadata: {
          product: "contact_unlock",
          property: body.propertyTitle ?? null,
        },
      }),
    });

    const payload = (await response.json()) as {
      status?: boolean;
      message?: string;
      data?: { authorization_url?: string };
    };

    if (!response.ok || !payload.status || !payload.data?.authorization_url) {
      return NextResponse.json(
        { error: payload.message ?? "Could not start the payment." },
        { status: 502 },
      );
    }

    return NextResponse.json({
      mode: "paystack",
      checkoutUrl: payload.data.authorization_url,
      reference,
    });
  } catch {
    return NextResponse.json(
      { error: "Could not reach the payment provider. Please try again." },
      { status: 502 },
    );
  }
}
