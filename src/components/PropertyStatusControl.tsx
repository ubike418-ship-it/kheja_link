"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { setPropertyStatusAction } from "@/lib/actions/properties";
import type { PropertyStatus } from "@/lib/supabase/database.types";

const OPTIONS: { value: Exclude<PropertyStatus, "pending">; label: string }[] = [
  { value: "published", label: "Published" },
  { value: "draft", label: "Draft" },
  { value: "rented", label: "Rented" },
  { value: "archived", label: "Archived" },
];

/** Quick status flip without opening the whole listing form. */
export default function PropertyStatusControl({
  propertyId,
  status,
}: {
  propertyId: string;
  status: PropertyStatus;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const change = (next: string) => {
    startTransition(async () => {
      const result = await setPropertyStatusAction(
        propertyId,
        next as Exclude<PropertyStatus, "pending">,
      );
      if (result.ok) {
        toast.success(result.message ?? "Updated.");
        router.refresh();
      } else {
        toast.error(result.error);
      }
    });
  };

  return (
    <div className="relative">
      <select
        value={status === "pending" ? "draft" : status}
        onChange={(event) => change(event.target.value)}
        disabled={isPending}
        aria-label="Listing status"
        className="h-12 pl-4 pr-10 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 cursor-pointer disabled:opacity-60 appearance-none"
      >
        {OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {isPending && (
        <Loader2 className="w-4 h-4 animate-spin text-zinc-400 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
      )}
    </div>
  );
}
