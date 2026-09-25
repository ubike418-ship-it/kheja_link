import { createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

/**
 * Paystack webhook.
 *
 * Paystack signs every event with HMAC-SHA512 over the raw body using the
 * secret key. We verify that before trusting anything: without it, anyone who
 * learned the URL could unlock every listing for free.
 *
 * Point Paystack at https://<your-domain>/api/payments/webhook
 */

export const dynamic = "force-dynamic";

type PaystackEvent = {
  event?: string;
  data?: { reference?: string; status?: string; currency?: string; amount?: number };
};

export async function POST(request: Request) {
  const secret = process.env.PAYSTACK_SECRET_KEY;
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!secret || !supabaseUrl || !serviceKey) {
    // Never reveal which piece is missing.
    return NextResponse.json({ received: true }, { status: 200 });
  }

  // The signature covers the raw bytes, so read the body as text first.
  const raw = await request.text();
  const signature = request.headers.get("x-paystack-signature") ?? "";

  const expected = createHmac("sha512", secret).update(raw).digest("hex");

  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(signature, "utf8");
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return NextResponse.json({ error: "Invalid signature." }, { status: 401 });
  }

  let event: PaystackEvent;
  try {
    event = JSON.parse(raw) as PaystackEvent;
  } catch {
    return NextResponse.json({ error: "Invalid payload." }, { status: 400 });
  }

  const reference = event.data?.reference;

  if (
    event.event !== "charge.success" ||
    event.data?.status !== "success" ||
    !reference ||
    // Every Kheja_Link price is in shillings; anything else is not our charge.
    (event.data?.currency !== undefined && event.data.currency !== "KES")
  ) {
    // Acknowledge anything else so Paystack stops retrying.
    return NextResponse.json({ received: true });
  }

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // kh_ is the retired house hunting pass, kl_ the per-listing contact unlock.
  // Both are checked against what Paystack actually charged: the database
  // refuses an underpayment, and a retried event is a no-op.
  const amountReceived = typeof event.data?.amount === "number" ? event.data.amount / 100 : null;
  const { error } = reference.startsWith("kh_")
    ? await admin.rpc("confirm_hunting_payment", {
        p_reference: reference,
        p_provider: "paystack",
        p_amount_received: amountReceived,
      })
    : await admin.rpc("confirm_contact_unlock", {
        p_reference: reference,
        p_provider: "paystack",
        p_amount_received: amountReceived,
      });

  if (error) {
    // A non-2xx makes Paystack retry, which is what we want on a transient fault.
    return NextResponse.json({ error: "Could not confirm the payment." }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}
