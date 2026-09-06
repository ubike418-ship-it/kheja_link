"use client";

import { useActionState, useEffect, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Loader2, Save, Home, KeyRound } from "lucide-react";
import { toast } from "sonner";
import { AuthField, authInputClass } from "@/components/AuthShell";
import { updateProfileAction } from "@/lib/actions/auth";
import type { ProfileRow } from "@/lib/supabase/database.types";
import type { ActionResult } from "@/lib/types";

export default function ProfileForm({ profile, email }: { profile: ProfileRow; email?: string }) {
  const router = useRouter();
  const [role, setRole] = useState<"seeker" | "landlord">(
    profile.role === "landlord" ? "landlord" : "seeker",
  );

  const [state, formAction] = useActionState<ActionResult | null, FormData>(
    updateProfileAction,
    null,
  );

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Saved.");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);

  const fieldError = (name: string) =>
    state && !state.ok ? state.fieldErrors?.[name]?.[0] : undefined;

  // Admins keep their role: the database trigger refuses to let it be changed here.
  const isAdmin = profile.role === "admin";

  return (
    <form action={formAction} className="space-y-6">
      {!isAdmin && <input type="hidden" name="role" value={role} />}
      {isAdmin && <input type="hidden" name="role" value="landlord" />}

      <AuthField label="Full name" error={fieldError("fullName")}>
        <input
          name="fullName"
          required
          defaultValue={profile.full_name ?? ""}
          className={authInputClass}
        />
      </AuthField>

      <AuthField label="Email">
        <input
          value={email ?? ""}
          disabled
          className={`${authInputClass} opacity-60 cursor-not-allowed`}
        />
      </AuthField>

      <AuthField label="Phone" error={fieldError("phone")}>
        <input
          name="phone"
          type="tel"
          defaultValue={profile.phone ?? ""}
          placeholder="+254 712 345 678"
          className={authInputClass}
        />
      </AuthField>

      <AuthField label="About you" error={fieldError("bio")}>
        <textarea
          name="bio"
          rows={4}
          defaultValue={profile.bio ?? ""}
          placeholder="A short introduction house hunters will see on your listings."
          className="w-full p-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors resize-none"
        />
      </AuthField>

      {!isAdmin && (
        <div className="space-y-2">
          <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
            Account type
          </span>
          <div className="grid grid-cols-2 gap-3">
            <RoleOption
              active={role === "seeker"}
              onClick={() => setRole("seeker")}
              icon={Home}
              title="House hunter"
              body="Search and save homes"
            />
            <RoleOption
              active={role === "landlord"}
              onClick={() => setRole("landlord")}
              icon={KeyRound}
              title="Landlord"
              body="List and manage properties"
            />
          </div>
          <p className="text-xs font-medium text-zinc-400 pt-1">
            Switching to a landlord account unlocks the dashboard, where you can publish listings.
          </p>
        </div>
      )}

      <SubmitButton />
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
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
      {pending ? "Saving…" : "Save changes"}
    </button>
  );
}
