import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Where Supabase sends people after they click an email link (signup
 * confirmation, magic link, password reset). Exchanges the one-time code for a
 * real session cookie, then drops them where they were headed.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const rawNext = searchParams.get("next") ?? "/";

  // Never bounce a visitor to another site on our say-so.
  const next = rawNext.startsWith("/") && !rawNext.startsWith("//") ? rawNext : "/";

  if (!code) {
    const error = searchParams.get("error_description") ?? "That link is invalid or has expired.";
    return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent(error)}`);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent("That link is invalid or has expired.")}`,
    );
  }

  return NextResponse.redirect(`${origin}${next}`);
}
