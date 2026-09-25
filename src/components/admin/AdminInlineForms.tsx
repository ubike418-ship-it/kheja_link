"use client";

import { useActionState, useEffect, useTransition } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Loader2, Send, Check, X, HandCoins } from "lucide-react";
import { toast } from "sonner";
import {
  markRefundPaidAction,
  replyToMessageAction,
  reviewHouseAction,
  setMessageStatusAction,
} from "@/lib/actions/admin";
import type { InquiryStatus } from "@/lib/supabase/database.types";
import type { ActionResult } from "@/lib/types";

const inputClass =
  "w-full px-4 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors";

/** Toasts the result of a server action and refreshes the page on success. */
function useResultToast(state: ActionResult | null) {
  const router = useRouter();
  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Saved.");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);
}

function SubmitButton({
  label,
  icon: Icon,
  tone = "blue",
  name,
  value,
}: {
  label: string;
  icon: typeof Send;
  tone?: "blue" | "emerald" | "red";
  name?: string;
  value?: string;
}) {
  const { pending } = useFormStatus();
  const tones = {
    blue: "bg-blue-600 hover:bg-blue-700 text-white",
    emerald: "bg-emerald-600 hover:bg-emerald-700 text-white",
    red: "bg-red-50 dark:bg-red-950/40 text-red-600 hover:bg-red-100",
  };
  return (
    <button
      type="submit"
      name={name}
      value={value}
      disabled={pending}
      className={`h-11 px-5 rounded-2xl text-sm font-black flex items-center justify-center gap-2 transition-colors disabled:opacity-60 ${tones[tone]}`}
    >
      {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Icon className="w-4 h-4" />}
      {label}
    </button>
  );
}

export function ReplyForm({ inquiryId, existingReply }: { inquiryId: string; existingReply: string | null }) {
  const [state, action] = useActionState<ActionResult | null, FormData>(replyToMessageAction, null);
  useResultToast(state);

  return (
    <form action={action} className="space-y-3">
      <input type="hidden" name="inquiryId" value={inquiryId} />
      <textarea
        name="reply"
        required
        rows={3}
        maxLength={2000}
        defaultValue={existingReply ?? ""}
        placeholder="Reply in the app — it lands in their Inbox"
        className={`${inputClass} py-3 resize-none`}
      />
      <SubmitButton label={existingReply ? "Update reply" : "Send reply"} icon={Send} />
    </form>
  );
}

const MESSAGE_STATUSES: { value: InquiryStatus; label: string }[] = [
  { value: "new", label: "New" },
  { value: "read", label: "Read" },
  { value: "responded", label: "Responded" },
  { value: "closed", label: "Closed" },
];

export function MessageStatusSelect({ id, status }: { id: string; status: InquiryStatus }) {
  const router = useRouter();
  const [pending, start] = useTransition();

  return (
    <select
      value={status}
      disabled={pending}
      aria-label="Message status"
      onChange={(e) =>
        start(async () => {
          const result = await setMessageStatusAction(id, e.target.value as InquiryStatus);
          if (result.ok) router.refresh();
          else toast.error(result.error);
        })
      }
      className="h-11 pl-4 pr-9 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 disabled:opacity-60 shrink-0"
    >
      {MESSAGE_STATUSES.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

export function HouseReviewForm({ submissionId }: { submissionId: string }) {
  const [state, action] = useActionState<ActionResult | null, FormData>(reviewHouseAction, null);
  useResultToast(state);

  return (
    <form action={action} className="space-y-3">
      <input type="hidden" name="submissionId" value={submissionId} />
      <input
        name="note"
        maxLength={500}
        placeholder="Note to the tenant (optional)"
        className={`${inputClass} h-11`}
      />
      <div className="flex flex-wrap gap-2">
        <SubmitButton label="Approve house" icon={Check} tone="emerald" name="decision" value="approve" />
        <SubmitButton label="Reject" icon={X} tone="red" name="decision" value="reject" />
      </div>
    </form>
  );
}

export function RefundPaidForm({ refundId, amountLabel }: { refundId: string; amountLabel: string }) {
  const [state, action] = useActionState<ActionResult | null, FormData>(markRefundPaidAction, null);
  useResultToast(state);

  return (
    <form action={action} className="flex flex-col sm:flex-row gap-2">
      <input type="hidden" name="refundId" value={refundId} />
      <input
        name="reference"
        maxLength={60}
        placeholder="M-Pesa reference (optional)"
        className={`${inputClass} h-11 sm:flex-1`}
      />
      <SubmitButton label={`Mark ${amountLabel} paid`} icon={HandCoins} tone="blue" />
    </form>
  );
}

/**
 * A dropdown that saves itself: `action` is a server action already bound to
 * the row it changes (e.g. setUserRoleAction.bind(null, id)).
 */
export function ActionSelect({
  value,
  options,
  action,
  label,
  confirm,
}: {
  value: string;
  options: { value: string; label: string }[];
  action: (next: string) => Promise<ActionResult>;
  label: string;
  /** Asked before saving one particular value, e.g. before making someone an admin. */
  confirm?: { value: string; message: string };
}) {
  const router = useRouter();
  const [pending, start] = useTransition();

  return (
    <select
      value={value}
      disabled={pending}
      aria-label={label}
      onChange={(e) => {
        const next = e.target.value;
        if (confirm && next === confirm.value && !window.confirm(confirm.message)) return;
        start(async () => {
          const result = await action(next);
          if (result.ok) {
            toast.success(result.message ?? "Saved.");
            router.refresh();
          } else {
            toast.error(result.error);
          }
        });
      }}
      className="h-10 pl-3 pr-8 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-xs font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 disabled:opacity-60"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

/** An on/off pill that saves itself. */
export function ActionToggle({
  on,
  action,
  labels,
}: {
  on: boolean;
  action: (next: boolean) => Promise<ActionResult>;
  labels: [on: string, off: string];
}) {
  const router = useRouter();
  const [pending, start] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        start(async () => {
          const result = await action(!on);
          if (result.ok) {
            toast.success(result.message ?? "Saved.");
            router.refresh();
          } else {
            toast.error(result.error);
          }
        })
      }
      className={`h-10 px-4 rounded-2xl text-xs font-black transition-colors disabled:opacity-60 ${
        on
          ? "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300"
          : "bg-zinc-100 dark:bg-zinc-800 text-zinc-500"
      }`}
    >
      {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : on ? labels[0] : labels[1]}
    </button>
  );
}
