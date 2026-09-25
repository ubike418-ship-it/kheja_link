"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { Mail, Phone, MessageSquare, Loader2, ExternalLink } from "lucide-react";
import { toast } from "sonner";
import { useRouter } from "next/navigation";
import { updateInquiryStatusAction } from "@/lib/actions/inquiries";
import { formatRelativeDate, normalisePhone } from "@/lib/format";
import type { InquiryStatus } from "@/lib/supabase/database.types";
import type { InquiryWithProperty } from "@/lib/types";

const FILTERS: { value: "all" | InquiryStatus; label: string }[] = [
  { value: "all", label: "All" },
  { value: "new", label: "New" },
  { value: "read", label: "Read" },
  { value: "responded", label: "Responded" },
  { value: "closed", label: "Closed" },
];

export default function InquiryList({ inquiries }: { inquiries: InquiryWithProperty[] }) {
  const router = useRouter();
  const [filter, setFilter] = useState<"all" | InquiryStatus>("all");
  const [isPending, startTransition] = useTransition();

  const visible = filter === "all" ? inquiries : inquiries.filter((i) => i.status === filter);

  const setStatus = (id: string, status: InquiryStatus) => {
    startTransition(async () => {
      const result = await updateInquiryStatusAction(id, status);
      if (result.ok) router.refresh();
      else toast.error(result.error);
    });
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] overflow-x-auto scrollbar-hide w-fit">
        {FILTERS.map((option) => {
          const count =
            option.value === "all"
              ? inquiries.length
              : inquiries.filter((i) => i.status === option.value).length;
          return (
            <button
              key={option.value}
              onClick={() => setFilter(option.value)}
              aria-pressed={filter === option.value}
              className={`flex items-center gap-2 px-5 h-11 rounded-2xl text-sm font-black whitespace-nowrap transition-colors ${
                filter === option.value
                  ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900"
                  : "text-zinc-500 hover:text-blue-600"
              }`}
            >
              {option.label}
              <span className="text-[10px] opacity-60">{count}</span>
            </button>
          );
        })}
      </div>

      {visible.length === 0 ? (
        <div className="py-24 text-center space-y-4 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <MessageSquare className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-zinc-500 font-medium max-w-md mx-auto">
            {inquiries.length === 0
              ? "No earlier inquiries. Tenants now reach you by unlocking your listing, or through the Kheja_Link team."
              : "No inquiries with that status."}
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {visible.map((inquiry) => {
            const phone = normalisePhone(inquiry.phone);
            return (
              <article
                key={inquiry.id}
                className={`p-6 bg-white dark:bg-zinc-900 border rounded-[2rem] space-y-4 transition-colors ${
                  inquiry.status === "new"
                    ? "border-blue-300 dark:border-blue-900"
                    : "border-zinc-200 dark:border-zinc-800"
                }`}
              >
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0">
                    <h2 className="text-lg font-black text-zinc-900 dark:text-white truncate">
                      {inquiry.name}
                    </h2>
                    {inquiry.property && (
                      <Link
                        href={`/properties/${inquiry.property.slug}`}
                        className="inline-flex items-center gap-1 text-[10px] font-black uppercase tracking-widest text-blue-600 hover:text-blue-700"
                      >
                        {inquiry.property.title}
                        <ExternalLink className="w-3 h-3" />
                      </Link>
                    )}
                  </div>
                  <span className="text-[10px] font-black uppercase tracking-widest text-zinc-400 shrink-0">
                    {formatRelativeDate(inquiry.created_at)}
                  </span>
                </div>

                <p className="text-zinc-600 dark:text-zinc-400 font-medium leading-relaxed whitespace-pre-line">
                  {inquiry.message}
                </p>

                <div className="flex flex-wrap items-center gap-3 pt-2 border-t border-zinc-100 dark:border-zinc-800">
                  {inquiry.email && (
                    <a
                      href={`mailto:${inquiry.email}?subject=${encodeURIComponent(
                        `Re: ${inquiry.property?.title ?? "your Kheja_Link inquiry"}`,
                      )}`}
                      className="flex items-center gap-2 px-4 h-11 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-sm font-black hover:scale-[1.02] transition-transform"
                    >
                      <Mail className="w-4 h-4" />
                      Reply by email
                    </a>
                  )}
                  {phone && (
                    <a
                      href={`tel:${phone}`}
                      className="flex items-center gap-2 px-4 h-11 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 hover:border-blue-500 transition-colors"
                    >
                      <Phone className="w-4 h-4" />
                      {inquiry.phone}
                    </a>
                  )}

                  <div className="relative sm:ml-auto">
                    <select
                      value={inquiry.status}
                      onChange={(event) => setStatus(inquiry.id, event.target.value as InquiryStatus)}
                      disabled={isPending}
                      aria-label={`Status of the inquiry from ${inquiry.name}`}
                      className="h-11 pl-4 pr-10 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl text-sm font-black text-zinc-600 dark:text-zinc-300 outline-none focus:border-blue-500 cursor-pointer disabled:opacity-60 appearance-none"
                    >
                      <option value="new">New</option>
                      <option value="read">Read</option>
                      <option value="responded">Responded</option>
                      <option value="closed">Closed</option>
                    </select>
                    {isPending && (
                      <Loader2 className="w-4 h-4 animate-spin text-zinc-400 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
                    )}
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </div>
  );
}
