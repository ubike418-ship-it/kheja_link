"use client";

import { useState, useTransition } from "react";
import { Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { deleteMyAccountAction } from "@/lib/actions/auth";

/**
 * Deleting your own account. Two steps — the warning, then typing DELETE —
 * so it cannot happen by a slip. The server action signs the person out and
 * sends them home once the account is gone.
 */
export default function DeleteAccountSection() {
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState("");
  const [pending, start] = useTransition();

  return (
    <section className="p-8 bg-white dark:bg-zinc-900 border border-red-200 dark:border-red-900/60 rounded-[2.5rem] space-y-4">
      <div className="space-y-1">
        <h2 className="text-xl font-black text-zinc-900 dark:text-white tracking-tight">Delete your account</h2>
        <p className="text-sm font-medium text-zinc-500 leading-relaxed">
          Permanently deletes your Kheja_Link account and everything in it: your profile, listings,
          saved homes, alerts, requests, messages, unlocks and notifications. It cannot be undone.
        </p>
      </div>

      {!open ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="inline-flex items-center gap-2 h-11 px-5 rounded-2xl border border-red-200 dark:border-red-900 text-sm font-black text-red-600 hover:bg-red-50 dark:hover:bg-red-950/40"
        >
          <Trash2 className="w-4 h-4" /> Delete my account
        </button>
      ) : (
        <div className="space-y-3">
          <label className="block space-y-2">
            <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
              Type DELETE to confirm
            </span>
            <input
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              autoFocus
              placeholder="DELETE"
              className="w-full h-12 px-4 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-bold outline-none focus:border-red-500"
            />
          </label>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={typed.trim().toUpperCase() !== "DELETE" || pending}
              onClick={() =>
                start(async () => {
                  const result = await deleteMyAccountAction();
                  // On success the action redirects; only a failure returns here.
                  if (result && !result.ok) toast.error(result.error);
                })
              }
              className="inline-flex items-center gap-2 h-11 px-5 rounded-2xl bg-red-600 hover:bg-red-700 text-white text-sm font-black disabled:opacity-40"
            >
              {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
              Delete for good
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                setOpen(false);
                setTyped("");
              }}
              className="h-11 px-5 rounded-2xl text-sm font-black text-zinc-500 hover:text-zinc-900 dark:hover:text-white"
            >
              Keep my account
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
