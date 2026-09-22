import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

/**
 * The scheduled job. Called by Vercel Cron (vercel.json) and by the GitHub
 * Actions keep-alive workflow.
 *
 *   1. Keep-alive: real queries against the Supabase API. A free Supabase
 *      project is paused after a week without activity; this is activity.
 *   2. run_daily_maintenance(): opens homes whose vacancy date has arrived
 *      (which notifies waiting tenants in their in-app Inbox) and expires
 *      abandoned checkouts. Throttled to once an hour in the database.
 *
 * Both are harmless to repeat. If CRON_SECRET is set (Vercel sends it as a
 * bearer token), the request must carry it. Kheja_Link sends no email or SMS.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    return NextResponse.json({ ok: false, error: "Supabase is not configured." }, { status: 503 });
  }

  const secret = process.env.CRON_SECRET;
  if (secret && request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ ok: false, error: "Unauthorised." }, { status: 401 });
  }

  const db = createClient(url, anonKey, { auth: { persistSession: false } });

  const [ping, maintenance] = await Promise.all([
    db.from("property_types").select("id", { head: true, count: "exact" }),
    db.rpc("run_daily_maintenance"),
  ]);

  const ok = !ping.error && !maintenance.error;
  return NextResponse.json(
    {
      ok,
      at: new Date().toISOString(),
      keepAlive: ping.error ? "failed" : "ok",
      maintenance: maintenance.error ? "failed" : maintenance.data,
    },
    { status: ok ? 200 : 502 },
  );
}
