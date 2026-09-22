import { NextResponse } from "next/server";
import { isValidReference, loadCheckout, userClient, verifyAndConfirm } from "@/lib/payments/paystack";

/**
 * Where a payment has got to, for Kheja_Link's own "waiting for your M-Pesa
 * PIN" screen.
 *
 * It asks Paystack directly rather than believing the app, and marks our row
 * paid only on Paystack's word. That also means a payment still completes if
 * the webhook is slow or misconfigured.
 */

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const reference = new URL(request.url).searchParams.get("reference")?.trim();
  if (!isValidReference(reference)) {
    return NextResponse.json({ error: "A valid payment reference is required." }, { status: 400 });
  }

  const db = userClient(request);
  if (!db) return NextResponse.json({ error: "Sign in to continue." }, { status: 401 });

  // Only the tenant who started this payment may ask about it.
  const checkout = await loadCheckout(db, reference);
  if (!checkout) {
    return NextResponse.json({ error: "That payment could not be found." }, { status: 404 });
  }
  if (checkout.status === "paid") {
    return NextResponse.json({ status: "success", message: "Payment received." });
  }

  const result = await verifyAndConfirm(reference);
  return NextResponse.json(result);
}
