"use client";

import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Loader2, UserPlus, MailCheck, Home, KeyRound } from "lucide-react";
import { toast } from "sonner";
import { AuthField, authInputClass } from "@/components/AuthShell";
import { signUpAction } from "@/lib/actions/auth";
import type { ActionResult } from "@/lib/types";

export default function SignUpForm() {
  const router = useRouter();
  const [role, setRole] = useState<"seeker" | "landlord">("seeker");

  const [state, formAction] = useActionState<
    ActionResult<{ needsConfirmation: boolean }> | null,
    FormData
  >(signUpAction, null);

  useEffect(() => {
    if (!state) return;
    if (state.ok && !state.data.needsConfirmation) {
      toast.success("Welcome to Kheja_Link.");
      router.push("/");
      router.refresh();
    } else if (!state.ok) {
      toast.error(state.error);
    }
  }, [state, router]);

  const fieldError = (name: string) =>
    state && !state.ok ? state.fieldErrors?.[name]?.[0] : undefined;

  // Email confirmation is required on this project, so there is no session yet.
  if (state?.ok && state.data.needsConfirmation) {
    return (
      <div className="text-center space-y-5 py-4">
        <MailCheck className="w-14 h-14 text-emerald-600 mx-auto" />
        <div className="space-y-2">
          <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">
            Check your email
          </h2>
          <p className="text-sm font-medium text-zinc-500 leading-relaxed">
            We sent you a confirmation link. Click it and you&apos;ll be signed straight in to
            Kheja_Link.
          </p>
        </div>
        <Link
          href="/login"
          className="inline-flex items-center justify-center w-full h-14 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl font-black"
        >
          Go to sign in
        </Link>
      </div>
    );
  }

  return (
    <form action={formAction} className="space-y-5">
      <input type="hidden" name="role" value={role} />

      {/* Role picker — this is what decides whether you can list houses */}
      <div className="space-y-2">
        <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
          I want to
        </span>
        <div className="grid grid-cols-2 gap-3">
          <RoleOption
            active={role === "seeker"}
            onClick={() => setRole("seeker")}
            icon={Home}
            title="Find a house"
            body="Search and save homes"
          />
          <RoleOption
            active={role === "landlord"}
            onClick={() => setRole("landlord")}
            icon={KeyRound}
            title="List a house"
            body="Rent out my property"
          />
        </div>
      </div>

      <AuthField label="Full name" error={fieldError("fullName")}>
        <input
          name="fullName"
          required
          autoComplete="name"
          placeholder="e.g. Amina Kimathi"
          className={authInputClass}
        />
      </AuthField>

      <AuthField label="Email" error={fieldError("email")}>
        <input
          name="email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          className={authInputClass}
        />
      </AuthField>

      <AuthField label="Phone (optional)" error={fieldError("phone")}>
        <input
          name="phone"
          type="tel"
          autoComplete="tel"
          placeholder="+254 712 345 678"
          className={authInputClass}
        />
      </AuthField>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <AuthField label="Password" error={fieldError("password")}>
          <input
            name="password"
            type="password"
            required
            minLength={8}
            autoComplete="new-password"
            placeholder="At least 8 characters"
            className={authInputClass}
          />
        </AuthField>
        <AuthField label="Confirm" error={fieldError("confirmPassword")}>
          <input
            name="confirmPassword"
            type="password"
            required
            minLength={8}
            autoComplete="new-password"
            placeholder="Repeat password"
            className={authInputClass}
          />
        </AuthField>
      </div>

      <SubmitButton />

      <p className="text-center text-xs font-medium text-zinc-400">
        By creating an account you agree to our{" "}
        <Link href="/terms" className="font-black text-blue-600 hover:underline">
          terms
        </Link>{" "}
        and{" "}
        <Link href="/privacy" className="font-black text-blue-600 hover:underline">
          privacy policy
        </Link>
        .
      </p>
    </form>
  );
}

function RoleOption({
  active,
  onClick,
  icon: Icon,
  title,
  body,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  body: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`p-4 rounded-2xl border text-left transition-colors ${
        active
          ? "bg-blue-600 border-blue-600 text-white"
          : "bg-zinc-50 dark:bg-zinc-800 border-zinc-200 dark:border-zinc-700 text-zinc-600 dark:text-zinc-300 hover:border-blue-500"
      }`}
    >
      <Icon className="w-5 h-5 mb-2" />
      <span className="block text-sm font-black">{title}</span>
      <span className={`block text-[11px] font-medium ${active ? "text-blue-100" : "text-zinc-400"}`}>
        {body}
      </span>
    </button>
  );
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full h-16 bg-blue-600 text-white rounded-2xl font-black text-lg flex items-center justify-center gap-2 hover:bg-blue-700 active:scale-[0.98] transition-all shadow-lg shadow-blue-600/20 disabled:opacity-70"
    >
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <UserPlus className="w-5 h-5" />}
      {pending ? "Creating account…" : "Create account"}
    </button>
  );
}
