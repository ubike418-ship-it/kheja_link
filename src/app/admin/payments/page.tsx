import Link from "next/link";
import { Wallet, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
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

const STATUS_STYLE: Record<string, string> = {
  paid: "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300",
  pending: "bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300",
  failed: "bg-zinc-100 dark:bg-zinc-800 text-zinc-500",
  success: "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300",
};

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
      .limit(60),
  ]);

  const unlocks = (unlockData ?? []) as unknown as Unlock[];
  const attempts = (attemptData ?? []) as Attempt[];
  const duplicates = unlocks.filter((u) => u.duplicate_payment);

  return (
    <div className="space-y-10">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Payments</h2>
        <p className="text-zinc-500 font-medium">
          Every unlock payment, when its 3-hour window closes, and every attempt made with Paystack.
          A payment only counts as paid once Paystack confirms it.
        </p>
      </div>

      {duplicates.length > 0 && (
        <div className="p-6 rounded-[2rem] bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 space-y-2">
          <p className="flex items-center gap-2 font-black text-amber-800 dark:text-amber-300">
            <AlertTriangle className="w-5 h-5" /> {duplicates.length} duplicate payment
            {duplicates.length === 1 ? "" : "s"} to refund by hand
          </p>
          <ul className="text-sm font-bold text-amber-800/80 dark:text-amber-300/80 space-y-1">
            {duplicates.map((d) => (
              <li key={d.id}>
                {d.user?.full_name ?? "A tenant"} {d.user?.phone ? `(${d.user.phone})` : ""} ·{" "}
                {formatPrice(d.amount_received ?? d.amount, d.currency)} · ref {d.provider_ref}
              </li>
            ))}
          </ul>
        </div>
      )}

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load payments. Refresh to try again.
        </p>
      ) : unlocks.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <Wallet className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No payments yet</p>
        </div>
      ) : (
        <section className="space-y-3">
          <h3 className="text-xl font-black text-zinc-900 dark:text-white">Unlocks</h3>
          <div className="overflow-x-auto bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem]">
            <table className="w-full text-sm">
              <thead className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-400 text-left">
                <tr>
                  <th className="p-4">Tenant</th>
                  <th className="p-4">Listing</th>
                  <th className="p-4">Paid</th>
                  <th className="p-4">Status</th>
                  <th className="p-4">Window</th>
                  <th className="p-4">Reference</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800 font-bold text-zinc-700 dark:text-zinc-300">
                {unlocks.map((u) => {
                  const open = u.expires_at && new Date(u.expires_at).getTime() > Date.now();
                  const label = u.duplicate_payment ? "duplicate" : u.status;
                  return (
                    <tr key={u.id}>
                      <td className="p-4 whitespace-nowrap">
                        {u.user?.full_name ?? "—"}
                        {u.user?.phone && <span className="block text-xs text-zinc-400">{u.user.phone}</span>}
                      </td>
                      <td className="p-4 max-w-[16rem] truncate">
                        {u.property ? (
                          <Link href={`/properties/${u.property.slug}`} className="hover:text-blue-600">
                            {u.property.title}
                          </Link>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="p-4 whitespace-nowrap">
                        {formatPrice(u.amount_received ?? u.amount, u.currency)}
                        <span className="block text-xs text-zinc-400">{formatRelativeDate(u.paid_at ?? u.created_at)}</span>
                      </td>
                      <td className="p-4">
                        <span className={`px-2.5 py-1 rounded-full text-[10px] font-black uppercase tracking-[0.1em] ${STATUS_STYLE[u.status] ?? STATUS_STYLE.failed}`}>
                          {label}
                        </span>
                      </td>
                      <td className="p-4 whitespace-nowrap text-xs">
                        {u.status !== "paid"
                          ? "—"
                          : open
                            ? `Open until ${new Date(u.expires_at!).toLocaleTimeString("en-KE", { hour: "numeric", minute: "2-digit", timeZone: "Africa/Nairobi" })}`
                            : "Ended"}
                      </td>
                      <td className="p-4 text-xs text-zinc-400 font-mono">{u.provider_ref}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}

      <section className="space-y-3">
        <h3 className="text-xl font-black text-zinc-900 dark:text-white">Latest attempts with Paystack</h3>
        {attempts.length === 0 ? (
          <p className="text-zinc-500 font-medium">No attempts logged yet.</p>
        ) : (
          <ul className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] divide-y divide-zinc-100 dark:divide-zinc-800">
            {attempts.map((a) => (
              <li key={a.id} className="p-4 flex flex-wrap items-center gap-3 text-sm font-bold">
                <span className={`px-2.5 py-1 rounded-full text-[10px] font-black uppercase tracking-[0.1em] ${STATUS_STYLE[a.status] ?? STATUS_STYLE.pending}`}>
                  {a.status}
                </span>
                <span className="text-zinc-700 dark:text-zinc-300">{a.channel.replace("_", " ")}</span>
                <span className="text-zinc-400 flex-1 min-w-0 truncate">{a.message ?? ""}</span>
                <span className="text-xs text-zinc-400 font-mono">{a.reference}</span>
                <span className="text-xs text-zinc-400">{formatRelativeDate(a.created_at)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
