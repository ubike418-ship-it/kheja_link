"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { setWaitlistStatusAction } from "@/lib/actions/admin";
import type { WaitlistStatus } from "@/lib/supabase/database.types";

const OPTIONS: { value: WaitlistStatus; label: string }[] = [
  { value: "new", label: "New" },
  { value: "contacted", label: "Contacted" },
  { value: "onboarded", label: "Onboarded" },
  { value: "declined", label: "Declined" },
];

export default function WaitlistStatusSelect({ id, status }: { id: string; status: WaitlistStatus }) {
  const router = useRouter();
  const [pending, start] = useTransition();

  return (
    <div className="relative shrink-0">
      <select
        value={status}
        disabled={pending}
        aria-label="Waitlist status"
        onChange={(e) =>
          start(async () => {
            const result = await setWaitlistStatusAction(id, e.target.value as WaitlistStatus);
            if (result.ok) router.refresh();
            else toast.error(result.error);
          })
        }
        className="h-11 pl-4 pr-9 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 appearance-none disabled:opacity-60"
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
  );
}
