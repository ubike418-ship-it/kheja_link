import Link from "next/link";
import { MessageSquare, Phone, Mail, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { MessageStatusSelect, ReplyForm } from "@/components/admin/AdminInlineForms";
import DeleteButton from "@/components/admin/DeleteButton";
import { Badge, EmptyState, ErrorState, PageHeader } from "@/components/admin/AdminUI";
import { deleteMessageAction } from "@/lib/actions/admin";
import { formatRelativeDate } from "@/lib/format";
import type { InquiryStatus } from "@/lib/supabase/database.types";
import type { InquiryWithProperty } from "@/lib/types";

export const metadata = { title: "Messages — Admin" };

const FILTERS: { value: "" | InquiryStatus; label: string }[] = [
  { value: "", label: "All" },
  { value: "new", label: "New" },
  { value: "read", label: "Read" },
  { value: "responded", label: "Replied" },
  { value: "closed", label: "Closed" },
];

type Search = Promise<{ status?: string }>;

/**
 * Tenants no longer message landlords for free: every message from a listing
 * comes here. A reply is written into the row and lands in the sender's Inbox
 * as an in-app notification.
 */
export default async function AdminMessagesPage({ searchParams }: { searchParams: Search }) {
  const { status = "" } = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inquiries")
    .select("*, property:properties ( id, title, slug )")
    .eq("recipient", "admin")
    .order("created_at", { ascending: false })
    .limit(300);

  const all = (data ?? []) as unknown as InquiryWithProperty[];
  const rows = status ? all.filter((r) => r.status === status) : all;
  const countOf = (s: string) => (s ? all.filter((r) => r.status === s).length : all.length);

  return (
    <>
      <PageHeader
        title="Messages"
        description="What tenants ask about listings. Replies go to their Kheja_Link Inbox — there is no email or SMS. Someone who wrote without an account has no Inbox, so call them instead."
        meta={`${countOf("new")} new · ${all.length} in total`}
      />

      <nav className="flex gap-2 overflow-x-auto scrollbar-hide" aria-label="Filter messages">
        {FILTERS.map((f) => {
          const active = f.value === status;
          return (
            <Link
              key={f.label}
              href={f.value ? `/admin/messages?status=${f.value}` : "/admin/messages"}
              className={`flex items-center gap-2 px-4 h-10 rounded-2xl text-sm font-black whitespace-nowrap transition-colors ${
                active
                  ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900"
                  : "bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-zinc-500 hover:text-blue-600"
              }`}
            >
              {f.label}
              <span className={`text-xs ${active ? "opacity-70" : "text-zinc-400"}`}>{countOf(f.value)}</span>
            </Link>
          );
        })}
      </nav>

      {error ? (
        <ErrorState text="Could not load messages. Refresh to try again." />
      ) : rows.length === 0 ? (
        <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem]">
          <EmptyState
            icon={MessageSquare}
            title={status ? "Nothing here" : "No messages yet"}
            text="Questions tenants send from a listing appear here."
          />
        </div>
      ) : (
        <div className="grid xl:grid-cols-2 gap-4">
          {rows.map((r) => (
            <article
              key={r.id}
              className={`p-6 bg-white dark:bg-zinc-900 border rounded-[2rem] space-y-4 ${
                r.status === "new" ? "border-blue-300 dark:border-blue-800 shadow-lg shadow-blue-600/5" : "border-zinc-200 dark:border-zinc-800"
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 space-y-1">
                  <p className="flex items-center gap-2 text-lg font-black text-zinc-900 dark:text-white">
                    <span className="truncate">{r.name}</span>
                    {r.status === "new" && <Badge tone="blue">New</Badge>}
                  </p>
                  <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                    {formatRelativeDate(r.created_at)}
                    {r.property && (
                      <>
                        {" · "}
                        <Link href={`/properties/${r.property.slug}`} className="text-blue-600 hover:underline">
                          {r.property.title}
                        </Link>
                      </>
                    )}
                  </p>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <MessageStatusSelect id={r.id} status={r.status} />
                  <DeleteButton
                    action={deleteMessageAction.bind(null, r.id)}
                    itemName={`the message from ${r.name}`}
                    consequence="The message and your reply are removed from the back office and from the sender's history."
                  />
                </div>
              </div>

              <p className="text-sm font-medium text-zinc-600 dark:text-zinc-300 leading-relaxed whitespace-pre-line p-4 rounded-2xl bg-zinc-50 dark:bg-zinc-800/60">
                {r.message}
              </p>

              <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-sm font-bold text-zinc-600 dark:text-zinc-300">
                {r.phone && (
                  <a href={`tel:${r.phone}`} className="flex items-center gap-2 hover:text-blue-600">
                    <Phone className="w-4 h-4 text-zinc-400" /> {r.phone}
                  </a>
                )}
                {r.email && (
                  <span className="flex items-center gap-2 break-all">
                    <Mail className="w-4 h-4 text-zinc-400" /> {r.email}
                  </span>
                )}
                <span className="flex items-center gap-2">
                  <UserRound className="w-4 h-4 text-zinc-400" />
                  {r.sender_id ? "Has an account — reply lands in their Inbox" : "Guest — call to reply"}
                </span>
              </div>

              {r.replied_at && (
                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-emerald-600">
                  Replied {formatRelativeDate(r.replied_at).toLowerCase()}
                </p>
              )}
              {r.sender_id && <ReplyForm inquiryId={r.id} existingReply={r.admin_reply} />}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
