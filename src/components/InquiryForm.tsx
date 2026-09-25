"use client";

import { useActionState, useEffect, useRef } from "react";
import { useFormStatus } from "react-dom";
import { Send, CheckCircle2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { sendInquiryAction } from "@/lib/actions/inquiries";
import type { ActionResult } from "@/lib/types";

type Props = {
  propertyId: string;
  propertyTitle: string;
  defaultName?: string | null;
  defaultEmail?: string | null;
  defaultPhone?: string | null;
};

export default function InquiryForm({
  propertyId,
  propertyTitle,
  defaultName,
  defaultEmail,
  defaultPhone,
}: Props) {
  const [state, formAction] = useActionState<ActionResult | null, FormData>(sendInquiryAction, null);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Message sent.");
      formRef.current?.reset();
    } else {
      toast.error(state.error);
    }
  }, [state]);

  const fieldError = (name: string) =>
    state && !state.ok ? state.fieldErrors?.[name]?.[0] : undefined;

  if (state?.ok) {
    return (
      <div className="p-8 bg-emerald-50 dark:bg-emerald-950/30 border border-emerald-200 dark:border-emerald-900 rounded-[2.5rem] text-center space-y-4">
        <CheckCircle2 className="w-12 h-12 text-emerald-600 mx-auto" />
        <div className="space-y-1">
          <h3 className="text-xl font-black text-zinc-900 dark:text-white">Message sent</h3>
          <p className="text-sm font-medium text-zinc-600 dark:text-zinc-400">
            Kheja_Link has your message. Signed in? Our reply lands in your Inbox in the app —
            otherwise we will call you.
          </p>
        </div>
      </div>
    );
  }

  return (
    <form
      ref={formRef}
      action={formAction}
      className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-5"
    >
      <input type="hidden" name="propertyId" value={propertyId} />

      <div className="space-y-1">
        <h3 className="text-xl font-black text-zinc-900 dark:text-white tracking-tight">
          Message Kheja_Link
        </h3>
        <p className="text-sm font-medium text-zinc-500">
          Questions about this home come to our team, not the landlord. Sign in to get our reply
          in your in-app Inbox.
        </p>
      </div>

      <Field label="Your name" error={fieldError("name")}>
        <input
          name="name"
          required
          defaultValue={defaultName ?? ""}
          placeholder="e.g. Amina Kimathi"
          className="w-full h-14 px-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors"
        />
      </Field>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Field label="Email" error={fieldError("email")}>
          <input
            name="email"
            type="email"
            defaultValue={defaultEmail ?? ""}
            placeholder="you@example.com"
            className="w-full h-14 px-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors"
          />
        </Field>
        <Field label="Phone" error={fieldError("phone")}>
          <input
            name="phone"
            type="tel"
            defaultValue={defaultPhone ?? ""}
            placeholder="+254 7…"
            className="w-full h-14 px-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors"
          />
        </Field>
      </div>

      <Field label="Message" error={fieldError("message")}>
        <textarea
          name="message"
          required
          rows={4}
          defaultValue={`Hi, I'm interested in "${propertyTitle}". Is it still available?`}
          className="w-full p-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors resize-none"
        />
      </Field>

      <SubmitButton />
    </form>
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
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
      {pending ? "Sending…" : "Send to Kheja_Link"}
    </button>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-2">
      <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{label}</span>
      {children}
      {error && <span className="block text-xs font-bold text-red-600">{error}</span>}
    </label>
  );
}
