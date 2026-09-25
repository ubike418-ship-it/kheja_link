import Link from "next/link";
import { Wallet, AlertTriangle, ListChecks } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import DeleteButton from "@/components/admin/DeleteButton";
import { Badge, EmptyState, ErrorState, PageHeader, Panel, type Tone } from "@/components/admin/AdminUI";
import { deletePaymentAttemptAction, deleteUnlockAction } from "@/lib/actions/admin";
import { formatPrice, formatRelativeDate } from "@/lib/format";

export const metadata = { title: "Payments — Admin" };

type Unlock = {
  id: string;
  amount: number;
  amount_received: number | null;
  currency: string;
  status: string;
  provider: string;
  provider_ref: string | null;
  duplicate_payment: boolean;
  created_at: string;
  paid_at: string | null;
  expires_at: string | null;
  user: { full_name: string | null; phone: string | null } | null;
  property: { title: string; slug: string } | null;
};

type Attempt = {
  id: string;
  reference: string;
  channel: string;
  status: string;
  message: string | null;
  created_at: string;
};

const TONE: Record<string, Tone> = {
  paid: "green",
  success: "green",
  pending: "amber",
  send_otp: "amber",
  failed: "zinc",
  duplicate: "red",
};

const th = "px-6 py-3 text-[10px] font-black uppercase tracking-[0.15em] text-zinc-400 text-left whitespace-nowrap";
const td = "px-6 py-4 align-middle";

/**
 * The unlock ledger and the raw log of what was asked of Paystack — enough to
 * answer "I paid and nothing happened" without leaving the back office.
 */
export default async function AdminPaymentsPage() {
  const supabase = await createClient();
  const [{ data: unlockData, error }, { data: attemptData }] = await Promise.all([
    supabase
      .from("contact_unlocks")
      .select(
        "id, amount, amount_received, currency, status, provider, provider_ref, duplicate_payment, created_at, paid_at, expires_at, user:profiles!contact_unlocks_user_id_fkey ( full_name, phone ), property:properties ( title, slug )",
      )
      .neq("status", "pending")
      .order("created_at", { ascending: false })
      .limit(300),
    supabase
      .from("payment_attempts")
      .select("id, reference, channel, status, message, created_at")
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  const unlocks = (unlockData ?? []) as unknown as Unlock[];
  const attempts = (attemptData ?? []) as Attempt[];
  const paid = unlocks.filter((u) => u.status === "paid");
  const duplicates = unlocks.filter((u) => u.duplicate_payment);
  const openNow = paid.filter((u) => u.expires_at && new Date(u.expires_at).getTime() > Date.now()).length;
  const takings = paid.reduce((sum, u) => sum + Number(u.amount_received ?? u.amount), 0);
  const currency = unlocks[0]?.currency ?? "KES";

  return (
    <>
      <PageHeader
        title="Payments"
        description="Every unlock payment, when its 3-hour window closes, and every attempt made with Paystack. A payment only counts once Paystack confirms it."
        meta={`${paid.length} paid · ${formatPrice(takings, currency)} taken · ${openNow} open right now`}
      />

      {duplicates.length > 0 && (
        <div className="p-6 rounded-[2rem] bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 space-y-2">
          <p className="flex items-center gap-2 font-black text-amber-800 dark:text-amber-300">
            <AlertTriangle className="w-5 h-5" /> {duplicates.length} duplicate payment
            {duplicates.length === 1 ? "" : "s"} to refund by M-Pesa
          </p>
          <ul className="text-sm font-bold text-amber-800/80 dark:text-amber-300/80 space-y-1">
            {duplicates.map((d) => (
              <li key={d.id}>
                {d.user?.full_name ?? "A tenant"} {d.user?.phone ? `(${d.user.phone})` : ""} ·{" "}
                {formatPrice(d.amount_received ?? d.amount, d.currency)} · ref {d.provider_ref}
              </li>
            ))}
          </ul>
          <p className="text-xs font-bold text-amber-700/70 dark:text-amber-400/70">
            Once refunded, delete the record so it leaves this list.
          </p>
        </div>
      )}

      {error ? (
        <ErrorState text="Could not load payments. Refresh to try again." />
      ) : (
        <Panel title="Unlocks" description="Paid, failed and duplicate. Checkouts still waiting for a PIN are not shown." flush>
          {unlocks.length === 0 ? (
            <EmptyState icon={Wallet} title="No payments yet" text="Unlocks appear here once a tenant pays." />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-y border-zinc-100 dark:border-zinc-800 bg-zinc-50/60 dark:bg-zinc-800/30">
                  <tr>
                    <th className={th}>Tenant</th>
                    <th className={th}>Listing</th>
                    <th className={th}>Amount</th>
                    <th className={th}>Status</th>
                    <th className={th}>Window</th>
                    <th className={th}>Reference</th>
                    <th className={th}>
                      <span className="sr-only">Delete</span>
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800 font-bold text-zinc-700 dark:text-zinc-300">
                  {unlocks.map((u) => {
                    const open = u.expires_at && new Date(u.expires_at).getTime() > Date.now();
                    const label = u.duplicate_payment ? "duplicate" : u.status;
                    return (
                      <tr key={u.id} className="hover:bg-zinc-50/60 dark:hover:bg-zinc-800/30">
                        <td className={`${td} whitespace-nowrap`}>
                          {u.user?.full_name ?? "—"}
                          {u.user?.phone && <span className="block text-xs text-zinc-400">{u.user.phone}</span>}
                        </td>
                        <td className={`${td} max-w-[16rem] truncate`}>
                          {u.property ? (
                            <Link href={`/properties/${u.property.slug}`} className="hover:text-blue-600">
                              {u.property.title}
                            </Link>
                          ) : (
                            "—"
                          )}
                        </td>
                        <td className={`${td} whitespace-nowrap`}>
                          {formatPrice(u.amount_received ?? u.amount, u.currency)}
                          <span className="block text-xs text-zinc-400">
                            {formatRelativeDate(u.paid_at ?? u.created_at)}
                          </span>
                        </td>
                        <td className={td}>
                          <Badge tone={TONE[label] ?? "zinc"}>{label}</Badge>
                        </td>
                        <td className={`${td} whitespace-nowrap text-xs`}>
                          {u.status !== "paid"
                            ? "—"
                            : open
                              ? `Open until ${new Date(u.expires_at!).toLocaleTimeString("en-KE", {
                                  hour: "numeric",
                                  minute: "2-digit",
                                  timeZone: "Africa/Nairobi",
                                })}`
                              : "Ended"}
                        </td>
                        <td className={`${td} text-xs text-zinc-400 font-mono`}>{u.provider_ref}</td>
                        <td className={`${td} text-right`}>
                          <DeleteButton
                            action={deleteUnlockAction.bind(null, u.id)}
                            itemName="this payment record"
                            consequence={
                              u.status === "paid" && open
                                ? "The tenant loses access to this listing straight away, and the payment leaves your revenue figures."
                                : "It leaves the ledger and your revenue figures."
                            }
                          />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Panel>
      )}

      <Panel title="Attempts with Paystack" description="The last 100 prompts and card checkouts, newest first." flush>
        {attempts.length === 0 ? (
          <EmptyState icon={ListChecks} title="No attempts logged yet" />
        ) : (
          attempts.map((a) => (
            <div
              key={a.id}
              className="px-6 py-3 flex flex-wrap items-center gap-3 text-sm font-bold border-t border-zinc-100 dark:border-zinc-800 first:border-t-0"
            >
              <Badge tone={TONE[a.status] ?? "amber"}>{a.status.replace("_", " ")}</Badge>
              <span className="text-zinc-700 dark:text-zinc-300">{a.channel.replace("_", " ")}</span>
              <span className="text-zinc-400 flex-1 min-w-0 truncate">{a.message ?? ""}</span>
              <span className="text-xs text-zinc-400 font-mono hidden md:inline">{a.reference}</span>
              <span className="text-xs text-zinc-400">{formatRelativeDate(a.created_at)}</span>
              <DeleteButton
                action={deletePaymentAttemptAction.bind(null, a.id)}
                itemName="this log entry"
                consequence="Only the log line goes; the payment itself is unaffected."
              />
            </div>
          ))
        )}
      </Panel>
    </>
  );
}
