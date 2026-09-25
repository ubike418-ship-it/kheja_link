import Link from "next/link";
import { MessageSquare, Phone, Mail, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { MessageStatusSelect, ReplyForm } from "@/components/admin/AdminInlineForms";
import { formatRelativeDate } from "@/lib/format";
import type { InquiryWithProperty } from "@/lib/types";

export const metadata = { title: "Messages — Admin" };

/**
 * Tenants no longer message landlords for free: every message from a listing
 * comes here. A reply is written into the row and lands in the sender's Inbox
 * as an in-app notification.
 */
export default async function AdminMessagesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inquiries")
    .select("*, property:properties ( id, title, slug )")
    .eq("recipient", "admin")
    .order("created_at", { ascending: false })
    .limit(300);

  const rows = (data ?? []) as unknown as InquiryWithProperty[];
  const open = rows.filter((r) => r.status === "new").length;

  return (
    <div className="space-y-8">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Messages</h2>
        <p className="text-zinc-500 font-medium">
          What tenants ask about listings. Replies go to their Kheja_Link Inbox — there is no email
          or SMS. Someone who wrote without an account has no Inbox, so call them instead.
        </p>
        {open > 0 && (
          <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">{open} new</p>
        )}
      </div>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load messages. Refresh to try again.
        </p>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <MessageSquare className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No messages yet</p>
          <p className="text-zinc-500 font-medium">Questions tenants send from a listing appear here.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {rows.map((r) => (
            <article
              key={r.id}
              className={`p-6 bg-white dark:bg-zinc-900 border rounded-[2rem] space-y-4 ${
                r.status === "new" ? "border-blue-300 dark:border-blue-800" : "border-zinc-200 dark:border-zinc-800"
              }`}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 space-y-1">
                  <p className="text-lg font-black text-zinc-900 dark:text-white truncate">{r.name}</p>
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
                <MessageStatusSelect id={r.id} status={r.status} />
              </div>

              <p className="text-sm font-medium text-zinc-600 dark:text-zinc-300 leading-relaxed whitespace-pre-line">
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
    </div>
  );
}
