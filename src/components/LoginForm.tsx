"use client";

import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { Loader2, LogIn, Eye, EyeOff } from "lucide-react";
import { toast } from "sonner";
import { AuthField, authInputClass } from "@/components/AuthShell";
import { requestPasswordResetAction, signInAction } from "@/lib/actions/auth";
import type { ActionResult } from "@/lib/types";

export default function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") ?? "/";
  const [showPassword, setShowPassword] = useState(false);
  const [showReset, setShowReset] = useState(false);

  const [state, formAction] = useActionState<ActionResult<{ redirectTo: string }> | null, FormData>(
    signInAction,
    null,
  );

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success("Welcome back.");
      router.push(state.data.redirectTo || "/");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);

  const fieldError = (name: string) =>
    state && !state.ok ? state.fieldErrors?.[name]?.[0] : undefined;

  if (showReset) return <ResetForm onBack={() => setShowReset(false)} />;

  return (
    <form action={formAction} className="space-y-5">
      <input type="hidden" name="next" value={next} />

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

      <AuthField label="Password" error={fieldError("password")}>
        <div className="relative">
          <input
            name="password"
            type={showPassword ? "text" : "password"}
            required
            autoComplete="current-password"
            placeholder="••••••••"
            className={`${authInputClass} pr-14`}
          />
          <button
            type="button"
            onClick={() => setShowPassword((v) => !v)}
            aria-label={showPassword ? "Hide password" : "Show password"}
            className="absolute right-4 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-900 dark:hover:text-white"
          >
            {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
          </button>
        </div>
      </AuthField>

      <button
        type="button"
        onClick={() => setShowReset(true)}
        className="text-xs font-black text-blue-600 hover:text-blue-700 transition-colors"
      >
        Forgot your password?
      </button>

      <SubmitButton label="Sign in" pendingLabel="Signing in…" icon={LogIn} />

      <p className="text-center text-xs font-medium text-zinc-400">
        By signing in you agree to our{" "}
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

function ResetForm({ onBack }: { onBack: () => void }) {
  const [state, formAction] = useActionState<ActionResult | null, FormData>(
    requestPasswordResetAction,
    null,
  );

  useEffect(() => {
    if (!state) return;
    if (state.ok) toast.success(state.message ?? "Check your inbox.");
    else toast.error(state.error);
  }, [state]);

  return (
    <form action={formAction} className="space-y-5">
      <div className="space-y-1">
        <h2 className="text-xl font-black text-zinc-900 dark:text-white">Reset your password</h2>
        <p className="text-sm font-medium text-zinc-500">
          We&apos;ll email you a link to choose a new one.
        </p>
      </div>

      <AuthField label="Email">
        <input
          name="email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          className={authInputClass}
        />
      </AuthField>

      <SubmitButton label="Send reset link" pendingLabel="Sending…" icon={LogIn} />

      <button
        type="button"
        onClick={onBack}
        className="w-full text-xs font-black text-zinc-500 hover:text-blue-600 transition-colors"
      >
        Back to sign in
      </button>
    </form>
  );
}

function SubmitButton({
  label,
  pendingLabel,
  icon: Icon,
}: {
  label: string;
  pendingLabel: string;
  icon: React.ComponentType<{ className?: string }>;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full h-16 bg-blue-600 text-white rounded-2xl font-black text-lg flex items-center justify-center gap-2 hover:bg-blue-700 active:scale-[0.98] transition-all shadow-lg shadow-blue-600/20 disabled:opacity-70"
    >
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Icon className="w-5 h-5" />}
      {pending ? pendingLabel : label}
    </button>
  );
}
