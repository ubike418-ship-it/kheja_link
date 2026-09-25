import { NextResponse } from "next/server";
import { isValidReference, loadCheckout, serviceClient, userClient } from "@/lib/payments/paystack";

/**
 * Starts a card payment and returns Paystack's secure card page.
 *
 * Two products share this route, told apart by the reference prefix:
 *
 *   kl_…  the contact unlock for one listing (contact_unlock_fee, KES 500)
 *   kh_…  the retired house hunting pass — only checkouts already open
 *
 * The caller must be signed in and the payment must be theirs: the pending
 * row is read as that tenant, so Row Level Security refuses anyone else's.
 * The amount comes from that row, which the database priced from
 * app_settings, and the email is the account's own — nothing the app sends
 * changes what is charged. Only Paystack's confirmation marks it paid.
 *
 * Without PAYSTACK_SECRET_KEY, payments fall back to demo mode only when
 * PAYMENTS_DEMO_MODE=true, so a missing key in production never hands out an
 * unlock for free.
 */

export const dynamic = "force-dynamic";

type Body = { reference?: string; propertyTitle?: string };

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
        channels: ["card"],
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

export async function POST(request: Request) {
  let body: Body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  if (!isValidReference(reference)) {
    return NextResponse.json({ error: "A valid reference is required." }, { status: 400 });
  }

  const db = userClient(request);
  if (!db) return NextResponse.json({ error: "Sign in to continue." }, { status: 401 });

  const {
    data: { user },
  } = await db.auth.getUser();
  if (!user?.email) {
    return NextResponse.json({ error: "Your session has expired. Sign in again." }, { status: 401 });
  }

  const checkout = await loadCheckout(db, reference);
  if (!checkout) {
    return NextResponse.json({ error: "That payment could not be found. Please start again." }, { status: 404 });
  }
  if (checkout.status === "paid") {
    return NextResponse.json({ mode: "already_paid", paid: true, unlocked: true });
  }
  if (checkout.status !== "pending") {
    return NextResponse.json({ error: "That payment has expired. Please start again." }, { status: 409 });
  }

  const secret = process.env.PAYSTACK_SECRET_KEY;

  if (!secret) {
    const admin = serviceClient();
    if (process.env.PAYMENTS_DEMO_MODE !== "true" || !admin) {
      return NextResponse.json(
        { error: "Payments are not available right now. Please try again later." },
        { status: 503 },
      );
    }

    const { data: confirmed, error } = await admin.rpc(
      checkout.product === "hunting_fee" ? "confirm_hunting_payment" : "confirm_contact_unlock",
      { p_reference: reference, p_provider: "demo", p_amount_received: checkout.amount },
    );
    if (error) {
      return NextResponse.json({ error: "Could not complete the payment." }, { status: 500 });
    }
    return NextResponse.json({
      mode: "demo",
      paid: confirmed === true,
      unlocked: confirmed === true,
      message: "Demo mode — completed without taking a payment.",
    });
  }

  return paystackCheckout(secret, {
    email: user.email,
    amount: checkout.amount,
    currency: checkout.currency || "KES",
    reference,
    metadata: {
      product: checkout.product,
      property: checkout.product === "contact_unlock" ? (body.propertyTitle?.slice(0, 160) ?? null) : null,
    },
  });
}
