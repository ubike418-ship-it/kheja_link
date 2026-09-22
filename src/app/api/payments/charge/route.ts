import { NextResponse } from "next/server";
import {
  isValidReference,
  kenyanMsisdn,
  loadCheckout,
  localMsisdn,
  logAttempt,
  paystack,
  serviceClient,
  userClient,
} from "@/lib/payments/paystack";

/**
 * Starts a payment from Kheja_Link's own screens.
 *
 * The tenant picks M-Pesa and types their number in the app; this asks
 * Paystack to charge it, and hands back what to show them — usually "approve
 * the prompt on your phone", in Paystack's own words so we never invent
 * instructions that do not match what the customer sees.
 *
 * The amount is read from the pending row in our database, as the signed-in
 * tenant, so it is both correct and theirs. The app cannot influence it.
 */

export const dynamic = "force-dynamic";

type Body = { reference?: string; phone?: string; email?: string };

export async function POST(request: Request) {
  let body: Body;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  if (!isValidReference(reference)) {
    return NextResponse.json({ error: "A valid payment reference is required." }, { status: 400 });
  }

  const phone = kenyanMsisdn(body.phone);
  if (!phone) {
    return NextResponse.json(
      { error: "Enter a Safaricom number like 0712 345 678.", field: "phone" },
      { status: 400 },
    );
  }

  const db = userClient(request);
  if (!db) {
    return NextResponse.json({ error: "Sign in to continue." }, { status: 401 });
  }

  const {
    data: { user },
  } = await db.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Your session has expired. Sign in again." }, { status: 401 });
  }

  const checkout = await loadCheckout(db, reference);
  if (!checkout) {
    return NextResponse.json(
      { error: "That payment could not be found. Please start again." },
      { status: 404 },
    );
  }
  if (checkout.status === "paid") {
    return NextResponse.json({ status: "success", message: "This is already paid for." });
  }
  if (checkout.status !== "pending") {
    return NextResponse.json(
      { error: "That payment has expired. Please start again." },
      { status: 409 },
    );
  }

  const email = body.email?.trim() || user.email;
  if (!email) {
    return NextResponse.json(
      { error: "Your account has no email address, which the payment needs." },
      { status: 400 },
    );
  }

  type Charge = { status?: string; display_text?: string; message?: string; reference?: string };

  const send = (msisdn: string) =>
    paystack<Charge>("/charge", {
      method: "POST",
      body: {
        email,
        amount: Math.round(checkout.amount * 100),
        currency: checkout.currency || "KES",
        reference,
        mobile_money: { phone: msisdn, provider: "mpesa" },
        metadata: { product: checkout.product, kheja_reference: reference },
      },
    });

  // Paystack's Kenyan examples use the local 07… form; send that if it
  // objects to the international one, rather than failing a valid number.
  let charge = await send(phone);
  if (!charge.ok && /phone/i.test(charge.message)) {
    charge = await send(localMsisdn(phone));
  }

  const admin = serviceClient();

  if (!charge.ok || !charge.data) {
    await logAttempt(admin, {
      reference,
      product: checkout.product,
      channel: "mobile_money",
      status: "failed",
      message: charge.message,
    });
    return NextResponse.json(
      {
        error:
          charge.status === 503
            ? "Payments are not available right now. Please try again later."
            : charge.message || "Could not start the payment. Please try again.",
      },
      { status: charge.status === 503 ? 503 : 502 },
    );
  }

  const paystackStatus = charge.data.status ?? "pending";
  const status =
    paystackStatus === "success"
      ? "success"
      : paystackStatus === "failed"
        ? "failed"
        : paystackStatus === "send_otp"
          ? "send_otp"
          : "pending";

  await logAttempt(admin, {
    reference,
    product: checkout.product,
    channel: "mobile_money",
    status,
    displayText: charge.data.display_text ?? null,
    message: charge.data.message ?? paystackStatus,
  });

  return NextResponse.json({
    status,
    reference,
    amount: checkout.amount,
    currency: checkout.currency,
    // Paystack's own words for the customer, e.g. "Please approve the
    // transaction on your phone". Shown as-is inside our screen.
    displayText:
      charge.data.display_text ??
      (status === "pending"
        ? "Check your phone and enter your M-Pesa PIN to approve the payment."
        : null),
    message: charge.data.message ?? null,
  });
}
