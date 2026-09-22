"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { setPropertyAvailabilityAction } from "@/lib/actions/properties";
import type { Availability } from "@/lib/supabase/database.types";

const OPTIONS: { value: Availability; label: string }[] = [
  { value: "available", label: "Available now" },
  { value: "notice_given", label: "Available from a date" },
  { value: "occupied", label: "Occupied" },
  { value: "unavailable", label: "Temporarily unavailable" },
];

const selectClass =
  "h-12 pl-4 pr-10 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 cursor-pointer disabled:opacity-60 appearance-none";

/** The landlord's "Set availability", next to the listing status. */
export default function PropertyAvailabilityControl({
  propertyId,
  availability,
  availableFrom,
}: {
  propertyId: string;
  availability: Availability;
  availableFrom: string | null;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [choice, setChoice] = useState<Availability>(availability);
  const [date, setDate] = useState(availableFrom ?? "");
  const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);

  const save = (next: Availability, from: string) =>
    start(async () => {
      const result = await setPropertyAvailabilityAction({
        propertyId,
        availability: next,
        availableFrom: from,
      });
      if (result.ok) {
        toast.success(result.message ?? "Updated.");
        router.refresh();
      } else {
        toast.error(result.error);
        setChoice(availability);
      }
    });

  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative">
        <select
          value={choice}
          disabled={pending}
          aria-label="Availability"
          onChange={(e) => {
            const next = e.target.value as Availability;
            setChoice(next);
            // A future date needs choosing first; everything else saves at once.
            if (next !== "notice_given") save(next, "");
          }}
          className={selectClass}
        >
          {OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        {pending && (
          <Loader2 className="w-4 h-4 animate-spin text-zinc-400 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
        )}
      </div>
      {choice === "notice_given" && (
        <div className="flex items-center gap-2">
          <input
            type="date"
            min={tomorrow}
            value={date}
            onChange={(e) => setDate(e.target.value)}
            aria-label="Available from"
            className="h-12 px-3 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-bold text-zinc-700 dark:text-zinc-200 outline-none focus:border-blue-500"
          />
          <button
            type="button"
            disabled={pending || !date}
            onClick={() => save("notice_given", date)}
            className="inline-flex items-center gap-1.5 px-4 h-12 bg-purple-600 text-white rounded-2xl text-sm font-black disabled:opacity-50"
          >
            <CalendarClock className="w-4 h-4" /> Set date
          </button>
        </div>
      )}
    </div>
  );
}
