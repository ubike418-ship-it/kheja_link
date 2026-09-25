"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Check, Globe, Lock, ShieldCheck } from "lucide-react";
import DeleteButton from "@/components/admin/DeleteButton";
import { toast } from "sonner";
import { saveSettingAction } from "@/lib/actions/admin";
import type { AppSettingRow } from "@/lib/supabase/database.types";

const BOOLEAN = new Set([
  "stays_enabled",
  "service_provider_registration_enabled",
  "tenant_notifications_enabled",
]);

/** Switching these on exposes something that is not built yet. */
const UNFINISHED = new Set(["stays_enabled", "service_provider_registration_enabled"]);

/** Settings that may be left empty, so the dustbin clears them. */
const CLEARABLE = new Set([
  "landlord_listing_fee_offer_label",
  "landlord_listing_fee_offer_ends_on",
  "service_provider_onboarding_fee",
]);

export default function SettingRow({ setting, label }: { setting: AppSettingRow; label?: string }) {
  const router = useRouter();
  const [value, setValue] = useState(setting.value);
  const [pending, start] = useTransition();
  const dirty = value !== setting.value;
  const isBool = BOOLEAN.has(setting.key);

  const save = (next: string) =>
    start(async () => {
      if (
        UNFINISHED.has(setting.key) &&
        next === "true" &&
        !window.confirm("This feature is not finished. Turn it on anyway?")
      ) {
        setValue(setting.value);
        return;
      }
      const result = await saveSettingAction(setting.key, next);
      if (result.ok) {
        toast.success(result.message ?? "Saved.");
        router.refresh();
      } else {
        toast.error(result.error);
        setValue(setting.value);
      }
    });

  return (
    <div className="px-6 py-5 border-t border-zinc-100 dark:border-zinc-800 first:border-t-0 flex flex-col md:flex-row md:items-center gap-4">
      <div className="min-w-0 flex-1 space-y-1">
        <div className="flex items-center gap-2">
          <p className="font-black text-zinc-900 dark:text-white">{label ?? setting.key}</p>
          {setting.is_public ? (
            <Globe className="w-3.5 h-3.5 text-zinc-400 shrink-0" aria-label="Visible to the apps" />
          ) : (
            <Lock className="w-3.5 h-3.5 text-zinc-400 shrink-0" aria-label="Private" />
          )}
        </div>
        {setting.description && <p className="text-sm font-medium text-zinc-500">{setting.description}</p>}
        {label && <p className="text-[10px] font-mono text-zinc-400">{setting.key}</p>}
      </div>

      <div className="flex items-center gap-2 md:w-[22rem] shrink-0">
        {isBool ? (
          <button
            type="button"
            role="switch"
            aria-checked={value === "true"}
            aria-label={setting.key}
            disabled={pending}
            onClick={() => {
              const next = value === "true" ? "false" : "true";
              setValue(next);
              save(next);
            }}
            className={`relative w-14 h-8 rounded-full transition-colors disabled:opacity-60 ${
              value === "true" ? "bg-blue-600" : "bg-zinc-300 dark:bg-zinc-700"
            }`}
          >
            <span
              className={`absolute top-1 w-6 h-6 bg-white rounded-full shadow transition-all ${
                value === "true" ? "left-7" : "left-1"
              }`}
            />
          </button>
        ) : (
          <>
            <input
              value={value}
              onChange={(e) => setValue(e.target.value)}
              aria-label={setting.key}
              className="flex-1 min-w-0 h-12 px-4 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-bold text-zinc-900 dark:text-white outline-none focus:border-blue-500"
            />
            <button
              type="button"
              disabled={!dirty || pending}
              onClick={() => save(value.trim())}
              className="h-12 px-4 bg-blue-600 text-white rounded-2xl font-black disabled:opacity-40 inline-flex items-center gap-1.5"
            >
              {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
              Save
            </button>
          </>
        )}
        {isBool && pending && <Loader2 className="w-4 h-4 animate-spin text-zinc-400" />}
        {CLEARABLE.has(setting.key) ? (
          <DeleteButton
            action={() => saveSettingAction(setting.key, "")}
            itemName={`the value of "${label ?? setting.key}"`}
            consequence="The setting is left empty, which the apps treat as not set."
          />
        ) : (
          <span
            title="Required by the apps — it can be changed but not deleted"
            className="inline-flex items-center justify-center w-10 h-10 text-zinc-300 dark:text-zinc-600 shrink-0"
          >
            <ShieldCheck className="w-4 h-4" aria-label="Required" />
          </span>
        )}
      </div>
    </div>
  );
}
