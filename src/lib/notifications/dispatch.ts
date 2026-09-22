import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Sends the email and SMS copies of notifications.
 *
 * The database writes one `notification_outbox` row per channel the user has
 * switched on (see notify_user() in 0012). This drains that queue. It runs on
 * the server only, with the service role key, because it has to read the
 * recipient's email address from auth.users — which no app can.
 *
 * Providers are optional and plugged in by environment variable:
 *
 *   Email  RESEND_API_KEY + NOTIFY_FROM_EMAIL           (https://resend.com)
 *   SMS    AFRICASTALKING_USERNAME + AFRICASTALKING_API_KEY
 *          (+ AFRICASTALKING_SENDER_ID if you have one)  (https://africastalking.com)
 *
 * A channel with no provider configured is marked `skipped`, not left pending:
 * switching a provider on later must not blast out weeks-old alerts.
 *
 * There is no automated calling. Phone follow-up is done by the Kheja_Link
 * team using the management line; this module does not pretend otherwise.
 */

type OutboxRow = {
  id: string;
  user_id: string;
  channel: "email" | "sms";
  subject: string;
  body: string | null;
  property_id: string | null;
  attempts: number;
};

type SendResult = { status: "sent" | "skipped" | "retry" | "failed"; error?: string };

const MAX_ATTEMPTS = 3;
const BATCH = 50;

export function serviceClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}

function siteUrl() {
  return (process.env.NEXT_PUBLIC_SITE_URL ?? "https://www.khejalink.name.ng").replace(/\/$/, "");
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function sendEmail(to: string, subject: string, body: string, link: string | null): Promise<SendResult> {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.NOTIFY_FROM_EMAIL;
  if (!key || !from) return { status: "skipped", error: "No email provider configured." };

  const html = `
    <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#18181b">
      <p style="font-size:11px;font-weight:900;letter-spacing:.2em;text-transform:uppercase;color:#2563eb;margin:0 0 12px">Kheja_Link</p>
      <h1 style="font-size:22px;margin:0 0 12px">${escapeHtml(subject)}</h1>
      <p style="font-size:15px;line-height:1.6;color:#52525b;margin:0 0 20px">${escapeHtml(body)}</p>
      ${
        link
          ? `<a href="${link}" style="display:inline-block;background:#2563eb;color:#fff;text-decoration:none;font-weight:700;padding:12px 20px;border-radius:14px">View property</a>`
          : ""
      }
      <p style="font-size:12px;color:#a1a1aa;margin-top:28px">You can change which alerts you get under Account → Notification preferences in the Kheja_Link app.</p>
    </div>`;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to, subject, html, text: `${subject}\n\n${body}${link ? `\n\n${link}` : ""}` }),
    });
    if (response.ok) return { status: "sent" };
    // 4xx other than rate limiting will not get better by retrying.
    if (response.status === 429 || response.status >= 500) {
      return { status: "retry", error: `Email provider returned ${response.status}.` };
    }
    return { status: "failed", error: `Email provider returned ${response.status}.` };
  } catch {
    return { status: "retry", error: "Could not reach the email provider." };
  }
}

/** Normalises Kenyan numbers to +2547… / +2541…; anything else is refused. */
function kenyanMsisdn(raw: string | null): string | null {
  if (!raw) return null;
  const digits = raw.replace(/[^\d+]/g, "");
  if (/^\+254[17]\d{8}$/.test(digits)) return digits;
  if (/^254[17]\d{8}$/.test(digits)) return `+${digits}`;
  if (/^0[17]\d{8}$/.test(digits)) return `+254${digits.slice(1)}`;
  return null;
}

async function sendSms(to: string, text: string): Promise<SendResult> {
  const username = process.env.AFRICASTALKING_USERNAME;
  const apiKey = process.env.AFRICASTALKING_API_KEY;
  if (!username || !apiKey) return { status: "skipped", error: "No SMS provider configured." };

  const host =
    username === "sandbox" ? "https://api.sandbox.africastalking.com" : "https://api.africastalking.com";
  const form = new URLSearchParams({ username, to, message: text.slice(0, 459) });
  if (process.env.AFRICASTALKING_SENDER_ID) form.set("from", process.env.AFRICASTALKING_SENDER_ID);

  try {
    const response = await fetch(`${host}/version1/messaging`, {
      method: "POST",
      headers: {
        apiKey,
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    });
    if (response.ok) return { status: "sent" };
    if (response.status === 429 || response.status >= 500) {
      return { status: "retry", error: `SMS provider returned ${response.status}.` };
    }
    return { status: "failed", error: `SMS provider returned ${response.status}.` };
  } catch {
    return { status: "retry", error: "Could not reach the SMS provider." };
  }
}

export async function dispatchOutbox(admin: SupabaseClient) {
  const { data, error } = await admin
    .from("notification_outbox")
    .select("id, user_id, channel, subject, body, property_id, attempts")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(BATCH);

  if (error) return { ok: false as const, error: "Could not read the outbox." };

  const rows = (data ?? []) as OutboxRow[];
  const tally = { sent: 0, skipped: 0, failed: 0, retry: 0 };
  const slugs = new Map<string, string | null>();

  for (const row of rows) {
    let link: string | null = null;
    if (row.property_id) {
      if (!slugs.has(row.property_id)) {
        const { data: property } = await admin
          .from("properties")
          .select("slug")
          .eq("id", row.property_id)
          .maybeSingle();
        slugs.set(row.property_id, (property as { slug?: string } | null)?.slug ?? null);
      }
      const slug = slugs.get(row.property_id);
      link = slug ? `${siteUrl()}/properties/${slug}` : null;
    }

    let result: SendResult;
    if (row.channel === "email") {
      const { data: user } = await admin.auth.admin.getUserById(row.user_id);
      const email = user?.user?.email;
      result = email
        ? await sendEmail(email, row.subject, row.body ?? "", link)
        : { status: "skipped", error: "The account has no email address." };
    } else {
      const { data: profile } = await admin
        .from("profiles")
        .select("phone")
        .eq("id", row.user_id)
        .maybeSingle();
      const phone = kenyanMsisdn((profile as { phone?: string | null } | null)?.phone ?? null);
      result = phone
        ? await sendSms(phone, `Kheja_Link: ${row.subject}. ${row.body ?? ""}`)
        : { status: "skipped", error: "No valid Kenyan phone number on the account." };
    }

    const attempts = row.attempts + 1;
    const status =
      result.status === "retry" ? (attempts >= MAX_ATTEMPTS ? "failed" : "pending") : result.status;

    await admin
      .from("notification_outbox")
      .update({
        status,
        attempts,
        last_error: result.error ?? null,
        sent_at: status === "sent" ? new Date().toISOString() : null,
      })
      .eq("id", row.id);

    tally[result.status] += 1;
  }

  return { ok: true as const, processed: rows.length, ...tally };
}
