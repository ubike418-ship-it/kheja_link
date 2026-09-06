"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient, getCurrentUser } from "@/lib/supabase/server";
import { getSiteUrl } from "@/lib/supabase/env";
import { fieldErrorsOf, profileSchema, signInSchema, signUpSchema } from "@/lib/validation";
import type { ActionResult } from "@/lib/types";

/**
 * Auth server actions.
 *
 * The Supabase project requires email confirmation, so signUp does not produce
 * a session — the UI has to tell people to check their inbox. `/auth/callback`
 * exchanges the link's code for a real session.
 */

export async function signUpAction(
  _prev: ActionResult<{ needsConfirmation: boolean }> | null,
  formData: FormData,
): Promise<ActionResult<{ needsConfirmation: boolean }>> {
  const parsed = signUpSchema.safeParse({
    fullName: formData.get("fullName"),
    email: formData.get("email"),
    phone: formData.get("phone") ?? "",
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
    role: formData.get("role") ?? "seeker",
  });

  if (!parsed.success) {
    return { ok: false, error: "Please fix the highlighted fields.", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      emailRedirectTo: `${getSiteUrl()}/auth/callback`,
      data: {
        full_name: parsed.data.fullName,
        phone: parsed.data.phone || null,
        role: parsed.data.role,
      },
    },
  });

  if (error) {
    return { ok: false, error: humaniseAuthError(error.message) };
  }

  // With confirmations on, Supabase returns a user but no session.
  const needsConfirmation = !data.session;
  if (!needsConfirmation) revalidatePath("/", "layout");

  return {
    ok: true,
    data: { needsConfirmation },
    message: needsConfirmation
      ? "Almost there — check your email to confirm your account."
      : "Welcome to Kheja_Link.",
  };
}

export async function signInAction(
  _prev: ActionResult<{ redirectTo: string }> | null,
  formData: FormData,
): Promise<ActionResult<{ redirectTo: string }>> {
  const parsed = signInSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!parsed.success) {
    return { ok: false, error: "Please fix the highlighted fields.", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);

  if (error) return { ok: false, error: humaniseAuthError(error.message) };

  revalidatePath("/", "layout");

  const next = String(formData.get("next") ?? "");
  return { ok: true, data: { redirectTo: safeRedirect(next) } };
}

export async function signOutAction(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/");
}

export async function updateProfileAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const user = await getCurrentUser();
  if (!user) return { ok: false, error: "Please sign in first." };

  const parsed = profileSchema.safeParse({
    fullName: formData.get("fullName"),
    phone: formData.get("phone") ?? "",
    bio: formData.get("bio") ?? "",
    role: formData.get("role") ?? "seeker",
  });

  if (!parsed.success) {
    return { ok: false, error: "Please fix the highlighted fields.", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("profiles")
    .update({
      full_name: parsed.data.fullName,
      phone: parsed.data.phone || null,
      bio: parsed.data.bio || null,
      role: parsed.data.role,
    })
    .eq("id", user.id);

  if (error) return { ok: false, error: `Could not save your profile: ${error.message}` };

  revalidatePath("/account");
  revalidatePath("/dashboard");
  return { ok: true, data: undefined, message: "Profile updated." };
}

export async function requestPasswordResetAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  if (!email.includes("@")) return { ok: false, error: "Enter a valid email address." };

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${getSiteUrl()}/auth/callback?next=/account`,
  });

  // Always report success: telling a stranger whether an address is registered
  // is an account-enumeration leak.
  return {
    ok: true,
    data: undefined,
    message: "If that address has an account, a reset link is on its way.",
  };
}

/** Only ever redirect within this app. */
function safeRedirect(next: string): string {
  if (!next || !next.startsWith("/") || next.startsWith("//")) return "/";
  return next;
}

function humaniseAuthError(message: string): string {
  const lower = message.toLowerCase();
  if (lower.includes("invalid login credentials")) return "That email and password do not match.";
  if (lower.includes("email not confirmed")) {
    return "Please confirm your email address first — check your inbox for the link.";
  }
  if (lower.includes("already registered") || lower.includes("already been registered")) {
    return "An account with that email already exists. Try signing in instead.";
  }
  if (lower.includes("rate limit") || lower.includes("too many")) {
    return "Too many attempts. Please wait a moment and try again.";
  }
  return message;
}
