import { createHmac } from "node:crypto";
import { NextResponse } from "next/server";
import {
  isValidReference,
  kenyanMsisdn,
  loadCheckout,
  localMsisdn,
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
 *
 * Every attempt is logged before Paystack is asked, and limits are checked
 * against that log first, so nobody can use this endpoint to flood a phone
 * with M-Pesa prompts — theirs or anyone else's.
 */

/** Attempts allowed in a window: per payment, per account, per phone number. */
const LIMITS = {
  reference: { max: 3, minutes: 10 },
  user: { max: 6, minutes: 30 },
  msisdn: { max: 5, minutes: 30 },
} as const;

/** A one-way fingerprint of the number, so the log holds no phone numbers. */
function msisdnHash(msisdn: string): string {
  return createHmac("sha256", process.env.SUPABASE_SERVICE_ROLE_KEY ?? "kheja")
    .update(msisdn)
    .digest("hex");
}

export const dynamic = "force-dynamic";

type Body = { reference?: string; phone?: string };

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

  const email = user.email;
  if (!email) {
    return NextResponse.json(
      { error: "Your account has no email address, which the payment needs." },
      { status: 400 },
    );
  }

  // Without the service role nothing can be logged, limited or recorded as
  // paid, so do not take anyone's money.
  const admin = serviceClient();
  if (!admin) {
    return NextResponse.json(
      { error: "Payments are not available right now. Please try again later." },
      { status: 503 },
    );
  }

  const hash = msisdnHash(phone);
  const since = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();
  const count = async (column: "reference" | "user_id" | "msisdn_hash", value: string, minutes: number) => {
    const { count: n } = await admin
      .from("payment_attempts")
      .select("id", { count: "exact", head: true })
      .eq(column, value)
      .eq("channel", "mobile_money")
      .gte("created_at", since(minutes));
    return n ?? 0;
  };
  const [byReference, byUser, byNumber] = await Promise.all([
    count("reference", reference, LIMITS.reference.minutes),
    count("user_id", user.id, LIMITS.user.minutes),
    count("msisdn_hash", hash, LIMITS.msisdn.minutes),
  ]);
  if (
    byReference >= LIMITS.reference.max ||
    byUser >= LIMITS.user.max ||
    byNumber >= LIMITS.msisdn.max
  ) {
    return NextResponse.json(
      {
        error:
          "Too many payment attempts. Wait a few minutes, check your phone for an M-Pesa " +
          "prompt, then try again.",
      },
      { status: 429 },
    );
  }

  // Logged before Paystack is asked, so parallel requests count too.
  const { data: attempt } = await admin
    .from("payment_attempts")
    .insert({
      reference,
      product: checkout.product,
      channel: "mobile_money",
      status: "pending",
      user_id: user.id,
      msisdn_hash: hash,
    })
    .select("id")
    .single();
  const recordOutcome = async (row: { status: string; displayText?: string | null; message?: string | null }) => {
    if (!attempt) return;
    await admin
      .from("payment_attempts")
      .update({ status: row.status, display_text: row.displayText ?? null, message: row.message ?? null })
      .eq("id", attempt.id)
      .then(
        () => undefined,
        () => undefined, // logging must never break a payment
      );
  };

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

  if (!charge.ok || !charge.data) {
    await recordOutcome({ status: "failed", message: charge.message });
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

  await recordOutcome({
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
