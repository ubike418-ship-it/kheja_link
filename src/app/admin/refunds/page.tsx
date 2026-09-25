import Link from "next/link";
import { HandCoins, Phone, MapPin, Home, UserRound, CalendarDays } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getUnlockPricing } from "@/lib/queries/pricing";
import { HouseReviewForm, RefundPaidForm } from "@/components/admin/AdminInlineForms";
import DeleteButton from "@/components/admin/DeleteButton";
import { Badge, EmptyState, ErrorState, PageHeader, type Tone } from "@/components/admin/AdminUI";
import { deleteHouseSubmissionAction } from "@/lib/actions/admin";
import { formatPrice, formatRelativeDate } from "@/lib/format";
import type { HouseSubmissionRow, RefundStatus, UnlockRefundRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Houses & refunds — Admin" };

type Submission = HouseSubmissionRow & {
  location: { name: string } | null;
  property_type: { name: string } | null;
  tenant: { full_name: string | null; phone: string | null } | null;
  refund: UnlockRefundRow | UnlockRefundRow[] | null;
};

const REFUND: Record<RefundStatus, { label: string; tone: Tone }> = {
  pending: { label: "Refund pending review", tone: "amber" },
  approved: { label: "Refund approved — send it", tone: "blue" },
  paid: { label: "Refund paid", tone: "green" },
  rejected: { label: "No refund", tone: "zinc" },
};

const FILTERS = [
  { value: "", label: "All" },
  { value: "review", label: "To review" },
  { value: "send", label: "Refunds to send" },
  { value: "done", label: "Done" },
] as const;

type Search = Promise<{ show?: string }>;

/**
 * Houses tenants gave us. Approving one approves the tenant's refund (when they
 * have a paid unlock to refund against); the admin then sends the money by
 * M-Pesa and marks it paid here. The tenant hears about every step in-app.
 */
export default async function AdminRefundsPage({ searchParams }: { searchParams: Search }) {
  const { show = "" } = await searchParams;
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

  const all = (data ?? []) as unknown as Submission[];
  const refundOf = (s: Submission) => (Array.isArray(s.refund) ? (s.refund[0] ?? null) : s.refund);
  const toReview = all.filter((s) => s.status === "pending");
  const toSend = all.filter((s) => refundOf(s)?.status === "approved");
  const done = all.filter((s) => s.status !== "pending" && refundOf(s)?.status !== "approved");
  const rows = show === "review" ? toReview : show === "send" ? toSend : show === "done" ? done : all;
  const countOf = (v: string) =>
    v === "review" ? toReview.length : v === "send" ? toSend.length : v === "done" ? done.length : all.length;
  const paidOut = all.reduce((sum, s) => {
    const r = refundOf(s);
    return r?.status === "paid" ? sum + Number(r.amount) : sum;
  }, 0);

  return (
    <>
      <PageHeader
        title="Houses & refunds"
        description={`A tenant who paid ${formatPrice(pricing.unlockFee, pricing.currency)} to unlock a listing and then gives us a house gets ${formatPrice(pricing.refundAmount, pricing.currency)} back once you approve the house. Send it by M-Pesa, then mark it paid. Both amounts are in Business settings.`}
        meta={`${toReview.length} to review · ${toSend.length} to send · ${formatPrice(paidOut, pricing.currency)} refunded so far`}
      />

      <section className="grid sm:grid-cols-3 gap-4">
        {[
          { step: "1", title: "Review the house", text: "Call the landlord, then approve or reject.", count: toReview.length, tone: "text-amber-600" },
          { step: "2", title: "Send the refund", text: "Pay the tenant by M-Pesa.", count: toSend.length, tone: "text-blue-600" },
          { step: "3", title: "Mark it paid", text: "Add the M-Pesa reference; the tenant is told.", count: null, tone: "text-emerald-600" },
        ].map((s) => (
          <div key={s.step} className="p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] flex gap-4">
            <span className={`text-3xl font-black tracking-tighter ${s.tone}`}>{s.step}</span>
            <div className="space-y-1">
              <p className="font-black text-zinc-900 dark:text-white">
                {s.title}
                {s.count !== null && s.count > 0 && <span className={`ml-2 ${s.tone}`}>({s.count})</span>}
              </p>
              <p className="text-xs font-bold text-zinc-500">{s.text}</p>
            </div>
          </div>
        ))}
      </section>

      <nav className="flex gap-2 overflow-x-auto scrollbar-hide" aria-label="Filter houses">
        {FILTERS.map((f) => {
          const active = f.value === show;
          return (
            <Link
              key={f.label}
              href={f.value ? `/admin/refunds?show=${f.value}` : "/admin/refunds"}
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
        <ErrorState text="Could not load houses. Refresh to try again." />
      ) : rows.length === 0 ? (
        <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem]">
          <EmptyState icon={HandCoins} title={show ? "Nothing here" : "No houses yet"} text="Houses tenants give us from the app appear here." />
        </div>
      ) : (
        <div className="grid xl:grid-cols-2 gap-4">
          {rows.map((s) => {
            const refund = refundOf(s);
            const where = [s.area, s.location?.name].filter(Boolean).join(", ");
            return (
              <article
                key={s.id}
                className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-4"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 space-y-2">
                    <p className="text-lg font-black text-zinc-900 dark:text-white">
                      {[s.bedrooms != null ? `${s.bedrooms}-bedroom` : null, s.property_type?.name ?? "House"]
                        .filter(Boolean)
                        .join(" ")}
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      <Badge tone={s.status === "approved" ? "green" : s.status === "rejected" ? "red" : "amber"}>
                        House {s.status}
                      </Badge>
                      {refund && <Badge tone={REFUND[refund.status].tone}>{REFUND[refund.status].label}</Badge>}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-400">
                      {formatRelativeDate(s.created_at)}
                    </span>
                    <DeleteButton
                      action={deleteHouseSubmissionAction.bind(null, s.id)}
                      itemName="this house"
                      consequence={
                        refund && refund.status !== "paid"
                          ? "Its refund is cancelled and removed too, and the tenant's unlock can earn a refund again."
                          : "Its refund record goes with it."
                      }
                    />
                  </div>
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

                {s.notes && (
                  <p className="text-sm font-medium text-zinc-500 leading-relaxed p-4 rounded-2xl bg-zinc-50 dark:bg-zinc-800/60">
                    {s.notes}
                  </p>
                )}
                {s.admin_note && <p className="text-xs font-bold text-zinc-400">Your note: &ldquo;{s.admin_note}&rdquo;</p>}

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
    </>
  );
}
