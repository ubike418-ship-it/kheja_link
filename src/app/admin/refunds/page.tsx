import { HandCoins, Phone, MapPin, Home, UserRound, CalendarDays } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getUnlockPricing } from "@/lib/queries/pricing";
import { HouseReviewForm, RefundPaidForm } from "@/components/admin/AdminInlineForms";
import { formatPrice, formatRelativeDate } from "@/lib/format";
import type {
  HouseSubmissionRow,
  RefundStatus,
  UnlockRefundRow,
} from "@/lib/supabase/database.types";

export const metadata = { title: "Houses & refunds — Admin" };

type Submission = HouseSubmissionRow & {
  location: { name: string } | null;
  property_type: { name: string } | null;
  tenant: { full_name: string | null; phone: string | null } | null;
  refund: UnlockRefundRow | UnlockRefundRow[] | null;
};

const REFUND_STYLES: Record<RefundStatus, string> = {
  pending: "bg-amber-50 dark:bg-amber-950/30 text-amber-700 dark:text-amber-300",
  approved: "bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300",
  paid: "bg-emerald-50 dark:bg-emerald-950/30 text-emerald-700 dark:text-emerald-300",
  rejected: "bg-zinc-100 dark:bg-zinc-800 text-zinc-500",
};

const REFUND_LABELS: Record<RefundStatus, string> = {
  pending: "Refund pending review",
  approved: "Refund approved — send it",
  paid: "Refund paid",
  rejected: "No refund",
};

/**
 * Houses tenants gave us. Approving one approves the tenant's refund (when they
 * have a paid unlock to refund against); the admin then sends the money by
 * M-Pesa and marks it paid here. The tenant hears about every step in-app.
 */
export default async function AdminRefundsPage() {
  const supabase = await createClient();
  const [{ data, error }, pricing] = await Promise.all([
    supabase
      .from("house_submissions")
      .select(
        `*, location:locations ( name ), property_type:property_types ( name ),
         tenant:profiles!house_submissions_user_id_fkey ( full_name, phone ),
         refund:unlock_refunds ( * )`,
      )
      .order("created_at", { ascending: false })
      .limit(300),
    getUnlockPricing(),
  ]);

  const rows = (data ?? []) as unknown as Submission[];
  const refundOf = (s: Submission) => (Array.isArray(s.refund) ? (s.refund[0] ?? null) : s.refund);
  const toPay = rows.filter((s) => refundOf(s)?.status === "approved");
  const toReview = rows.filter((s) => s.status === "pending");

  return (
    <div className="space-y-8">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Houses &amp; refunds</h2>
        <p className="text-zinc-500 font-medium">
          A tenant who paid {formatPrice(pricing.unlockFee, pricing.currency)} to unlock a listing and then
          gives us a house gets {formatPrice(pricing.refundAmount, pricing.currency)} back once you approve
          the house. Send the refund by M-Pesa, then mark it paid. Both amounts are in Business settings.
        </p>
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
          {toReview.length} to review · {toPay.length} refund{toPay.length === 1 ? "" : "s"} to send
        </p>
      </div>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load houses. Refresh to try again.
        </p>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <HandCoins className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No houses yet</p>
          <p className="text-zinc-500 font-medium">Houses tenants give us from the app appear here.</p>
        </div>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {rows.map((s) => {
            const refund = refundOf(s);
            const where = [s.area, s.location?.name].filter(Boolean).join(", ");
            return (
              <article
                key={s.id}
                className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-4"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 space-y-1">
                    <p className="text-lg font-black text-zinc-900 dark:text-white">
                      {[s.bedrooms != null ? `${s.bedrooms}-bedroom` : null, s.property_type?.name ?? "House"]
                        .filter(Boolean)
                        .join(" ")}
                    </p>
                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                      {s.status} · {formatRelativeDate(s.created_at)}
                    </p>
                  </div>
                  {refund && (
                    <span
                      className={`px-3 py-1.5 rounded-full text-[10px] font-black uppercase tracking-[0.15em] shrink-0 ${REFUND_STYLES[refund.status]}`}
                    >
                      {REFUND_LABELS[refund.status]}
                    </span>
                  )}
                </div>

                <div className="space-y-1.5 text-sm font-bold text-zinc-600 dark:text-zinc-300">
                  {where && (
                    <p className="flex items-center gap-2">
                      <MapPin className="w-4 h-4 text-zinc-400 shrink-0" /> {where}
                    </p>
                  )}
                  <p className="flex items-center gap-2">
                    <Home className="w-4 h-4 text-zinc-400 shrink-0" />
                    {s.relationship === "moving_out" ? "Tenant is moving out" : "Landlord agrees to list"}
                    {s.rent_amount ? ` · ${formatPrice(s.rent_amount)} / month` : ""}
                  </p>
                  {s.available_from && (
                    <p className="flex items-center gap-2">
                      <CalendarDays className="w-4 h-4 text-zinc-400 shrink-0" /> Free from{" "}
                      {new Date(s.available_from).toLocaleDateString("en-KE", { day: "numeric", month: "short", year: "numeric" })}
                    </p>
                  )}
                  <a href={`tel:${s.landlord_phone}`} className="flex items-center gap-2 hover:text-blue-600">
                    <Phone className="w-4 h-4 text-zinc-400 shrink-0" />
                    Landlord{s.landlord_name ? ` ${s.landlord_name}` : ""}: {s.landlord_phone}
                  </a>
                  <p className="flex items-center gap-2">
                    <UserRound className="w-4 h-4 text-zinc-400 shrink-0" />
                    From {s.tenant?.full_name ?? "a tenant"}
                    {s.tenant?.phone && (
                      <a href={`tel:${s.tenant.phone}`} className="hover:text-blue-600">
                        · {s.tenant.phone}
                      </a>
                    )}
                  </p>
                </div>

                {s.notes && <p className="text-sm font-medium text-zinc-500 leading-relaxed">{s.notes}</p>}
                {s.admin_note && (
                  <p className="text-xs font-bold text-zinc-400">Your note: &ldquo;{s.admin_note}&rdquo;</p>
                )}

                {s.status === "pending" && <HouseReviewForm submissionId={s.id} />}
                {refund?.status === "approved" && (
                  <RefundPaidForm refundId={refund.id} amountLabel={formatPrice(refund.amount, refund.currency)} />
                )}
                {refund?.status === "paid" && (
                  <p className="text-xs font-black text-emerald-600">
                    {formatPrice(refund.amount, refund.currency)} paid
                    {refund.payout_reference ? ` · ref ${refund.payout_reference}` : ""}
                  </p>
                )}
              </article>
            );
          })}
        </div>
      )}
    </div>
  );
}
