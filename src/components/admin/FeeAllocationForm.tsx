"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { AuthField, authInputClass } from "@/components/AuthShell";
import { saveFeeAllocationAction } from "@/lib/actions/admin";
import type { ActionResult } from "@/lib/types";

function Submit() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="flex items-center justify-center gap-2 px-6 h-14 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl font-black disabled:opacity-60"
    >
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Plus className="w-5 h-5" />}
      Save share
    </button>
  );
}

/** Adds or updates one party's share. Same product + party overwrites. */
export default function FeeAllocationForm() {
  const router = useRouter();
  const [state, formAction] = useActionState<ActionResult | null, FormData>(saveFeeAllocationAction, null);

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Saved.");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);

  const err = (f: string) => (state && !state.ok ? state.fieldErrors?.[f]?.[0] : undefined);

  return (
    <form
      action={formAction}
      className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] grid sm:grid-cols-2 lg:grid-cols-5 gap-4 items-end"
    >
      <AuthField label="Product" error={err("product")}>
        <select name="product" defaultValue="hunting_fee" className={authInputClass}>
          <option value="hunting_fee">Hunting fee</option>
          <option value="landlord_listing_fee">Landlord listing fee</option>
          <option value="provider_onboarding_fee">Provider onboarding fee</option>
        </select>
      </AuthField>
      <AuthField label="Party" error={err("party")}>
        <input name="party" required placeholder="platform, partner, landlord" className={authInputClass} />
      </AuthField>
      <AuthField label="Share %" error={err("sharePercent")}>
        <input name="sharePercent" type="number" min={0} max={100} step="0.01" required className={authInputClass} />
      </AuthField>
      <label className="flex items-center gap-3 h-14 px-4 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-black text-sm text-zinc-700 dark:text-zinc-200">
        <input type="checkbox" name="isActive" defaultChecked className="w-5 h-5 accent-blue-600" />
        Active
      </label>
      <Submit />
    </form>
  );
}
