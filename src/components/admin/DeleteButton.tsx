"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import type { ActionResult } from "@/lib/types";

/**
 * The dustbin on every row of the back office.
 *
 * Nothing is deleted on the first tap: it opens a confirmation that names the
 * item and says what else goes with it. `action` is a server action already
 * bound to the row (e.g. deleteListingAction.bind(null, id)); Row Level
 * Security still decides whether the delete is allowed.
 */
export default function DeleteButton({
  action,
  itemName,
  consequence,
  label,
  redirectTo,
}: {
  action: () => Promise<ActionResult>;
  /** What is being deleted, e.g. `the listing "Kinoru Heights"`. */
  itemName: string;
  /** What else goes with it, shown in the confirmation. */
  consequence?: string;
  /** Show a text label next to the icon. */
  label?: string;
  /** Where to go afterwards, when deleting from the item's own page. */
  redirectTo?: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();

  const confirm = () =>
    start(async () => {
      const result = await action();
      if (result.ok) {
        toast.success(result.message ?? "Deleted.");
        setOpen(false);
        if (redirectTo) router.push(redirectTo);
        else router.refresh();
      } else {
        toast.error(result.error);
      }
    });

  return (
    <AlertDialog open={open} onOpenChange={(next) => !pending && setOpen(next)}>
      <AlertDialogTrigger asChild>
        <button
          type="button"
          aria-label={`Delete ${itemName}`}
          title="Delete"
          className={`inline-flex items-center justify-center gap-1.5 h-10 rounded-2xl text-xs font-black text-zinc-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-950/40 border border-transparent hover:border-red-200 dark:hover:border-red-900 transition-colors shrink-0 ${
            label ? "px-3.5" : "w-10"
          }`}
        >
          <Trash2 className="w-4 h-4" />
          {label}
        </button>
      </AlertDialogTrigger>
      <AlertDialogContent className="rounded-[2rem]">
        <AlertDialogHeader>
          <span className="w-12 h-12 rounded-2xl bg-red-50 dark:bg-red-950/40 flex items-center justify-center">
            <Trash2 className="w-6 h-6 text-red-600" />
          </span>
          <AlertDialogTitle className="text-2xl font-black tracking-tight">Delete {itemName}?</AlertDialogTitle>
          <AlertDialogDescription className="font-medium leading-relaxed">
            {consequence ? `${consequence} ` : ""}This cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending} className="rounded-2xl h-11 font-black">
            Keep it
          </AlertDialogCancel>
          <button
            type="button"
            onClick={confirm}
            disabled={pending}
            className="inline-flex items-center justify-center gap-2 h-11 px-5 rounded-2xl bg-red-600 hover:bg-red-700 text-white text-sm font-black disabled:opacity-60"
          >
            {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
            Delete
          </button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
