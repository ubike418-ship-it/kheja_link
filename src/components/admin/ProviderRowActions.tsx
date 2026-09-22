"use client";

import Link from "next/link";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, X, Power, Pencil, Trash2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { deleteProviderAction, setProviderStatusAction } from "@/lib/actions/admin";
import type { ApprovalStatus } from "@/lib/supabase/database.types";
import type { ActionResult } from "@/lib/types";

const button =
  "inline-flex items-center gap-1.5 px-4 h-11 rounded-2xl text-sm font-black transition-colors disabled:opacity-50";

export default function ProviderRowActions({
  id,
  name,
  approvalStatus,
  isActive,
}: {
  id: string;
  name: string;
  approvalStatus: ApprovalStatus;
  isActive: boolean;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();

  const run = (fn: () => Promise<ActionResult>) =>
    start(async () => {
      const result = await fn();
      if (result.ok) {
        toast.success(result.message ?? "Done.");
        router.refresh();
      } else {
        toast.error(result.error);
      }
    });

  return (
    <div className="flex flex-wrap items-center gap-2 shrink-0">
      {pending && <Loader2 className="w-4 h-4 animate-spin text-zinc-400" />}

      {approvalStatus !== "approved" && (
        <button
          type="button"
          disabled={pending}
          onClick={() => run(() => setProviderStatusAction(id, { approvalStatus: "approved", isActive: true }))}
          className={`${button} bg-emerald-600 text-white hover:bg-emerald-700`}
        >
          <Check className="w-4 h-4" /> Approve
        </button>
      )}
      {approvalStatus === "pending" && (
        <button
          type="button"
          disabled={pending}
          onClick={() => run(() => setProviderStatusAction(id, { approvalStatus: "rejected" }))}
          className={`${button} bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 hover:text-red-600`}
        >
          <X className="w-4 h-4" /> Reject
        </button>
      )}
      {approvalStatus === "approved" && (
        <button
          type="button"
          disabled={pending}
          onClick={() => run(() => setProviderStatusAction(id, { isActive: !isActive }))}
          className={`${button} ${
            isActive
              ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 hover:text-amber-600"
              : "bg-blue-600 text-white hover:bg-blue-700"
          }`}
        >
          <Power className="w-4 h-4" /> {isActive ? "Disable" : "Make live"}
        </button>
      )}
      <Link
        href={`/admin/providers/${id}`}
        className={`${button} bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 hover:text-blue-600`}
      >
        <Pencil className="w-4 h-4" /> Edit
      </Link>
      <button
        type="button"
        disabled={pending}
        aria-label={`Delete ${name}`}
        onClick={() => {
          if (window.confirm(`Delete ${name}? This cannot be undone.`)) run(() => deleteProviderAction(id));
        }}
        className={`${button} px-3 text-zinc-400 hover:text-red-600`}
      >
        <Trash2 className="w-4 h-4" />
      </button>
    </div>
  );
}
