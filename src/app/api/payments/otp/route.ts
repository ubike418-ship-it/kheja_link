import { NextResponse } from "next/server";
import { isValidReference, loadCheckout, paystack, userClient } from "@/lib/payments/paystack";

/**
 * Some mobile-money providers ask for a one-time code instead of a prompt on
 * the phone. When Paystack replies `send_otp`, our screen collects the code
 * and posts it here — still our UI, Paystack's API underneath.
 */

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  let body: { reference?: string; otp?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  const otp = body.otp?.trim();

  if (!isValidReference(reference)) {
    return NextResponse.json({ error: "A valid payment reference is required." }, { status: 400 });
  }
  if (!otp || !/^\d{4,8}$/.test(otp)) {
    return NextResponse.json({ error: "Enter the code you were sent.", field: "otp" }, { status: 400 });
  }

  const db = userClient(request);
  if (!db) return NextResponse.json({ error: "Sign in to continue." }, { status: 401 });

  const checkout = await loadCheckout(db, reference);
  if (!checkout) {
    return NextResponse.json({ error: "That payment could not be found." }, { status: 404 });
  }

  const submitted = await paystack<{ status?: string; display_text?: string; message?: string }>(
    "/charge/submit_otp",
    { method: "POST", body: { otp, reference } },
  );

  if (!submitted.ok || !submitted.data) {
    return NextResponse.json(
      { error: submitted.message || "That code was not accepted. Please try again." },
      { status: 400 },
    );
  }

  const status = submitted.data.status === "success" ? "success" : "pending";
  return NextResponse.json({
    status,
    displayText: submitted.data.display_text ?? null,
    message: submitted.data.message ?? null,
  });
}
