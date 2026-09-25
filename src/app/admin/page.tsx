import Link from "next/link";
import {
  Users,
  Home,
  Lock,
  Wallet,
  HandCoins,
  MessageSquare,
  AlertTriangle,
  ArrowRight,
  type LucideIcon,
} from "lucide-react";
import { createClient, getCurrentProfile } from "@/lib/supabase/server";
import { formatPrice, formatRelativeDate } from "@/lib/format";
import { Badge, ErrorState, PageHeader } from "@/components/admin/AdminUI";

export const metadata = { title: "Overview — Admin" };

type Overview = {
  users: number;
  tenants: number;
  landlords: number;
  new_users_7d: number;
  listings: number;
  published: number;
  drafts: number;
  available_now: number;
  unlocks_today: number;
  unlocks_7d: number;
  unlocks_open_now: number;
  revenue_today: number;
  revenue_7d: number;
  revenue_total: number;
  refunds_to_send: number;
  refunds_paid_total: number;
  duplicates_to_refund: number;
  houses_to_review: number;
  messages_new: number;
  payments_failed_24h: number;
  currency: string;
};

type RecentUnlock = {
  id: string;
  amount: number;
  currency: string;
  paid_at: string | null;
  expires_at: string | null;
  user: { full_name: string | null } | null;
  property: { title: string; slug: string } | null;
};

/**
 * The back office's front page: how the business is doing and what needs a
 * person today. Every figure comes from admin_overview(), which refuses anyone
 * who is not an admin.
 */
export default async function AdminOverviewPage() {
  const supabase = await createClient();
  const [{ data, error }, { data: recent }, me] = await Promise.all([
    supabase.rpc("admin_overview"),
    supabase
      .from("contact_unlocks")
      .select(
        "id, amount, currency, paid_at, expires_at, user:profiles!contact_unlocks_user_id_fkey ( full_name ), property:properties ( title, slug )",
      )
      .eq("status", "paid")
      .order("paid_at", { ascending: false })
      .limit(8),
    getCurrentProfile(),
  ]);

  if (error || !data) {
    return <ErrorState text="Could not load the overview. Make sure migration 0016 has been run, then refresh." />;
  }

  const hour = Number(
    new Date().toLocaleString("en-KE", { hour: "numeric", hour12: false, timeZone: "Africa/Nairobi" }),
  );
  const greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening";
  const firstName = me?.full_name?.split(" ")[0];

  const o = data as unknown as Overview;
  const money = (n: number) => formatPrice(Number(n), o.currency);
  const unlocks = (recent ?? []) as unknown as RecentUnlock[];

  const todo: { count: number; label: string; href: string; icon: LucideIcon; tone: string }[] = [
    { count: o.messages_new, label: "new messages to answer", href: "/admin/messages", icon: MessageSquare, tone: "text-blue-600" },
    { count: o.houses_to_review, label: "houses to review", href: "/admin/refunds", icon: Home, tone: "text-purple-600" },
    { count: o.refunds_to_send, label: "approved refunds to send", href: "/admin/refunds", icon: HandCoins, tone: "text-emerald-600" },
    { count: o.duplicates_to_refund, label: "duplicate payments to refund", href: "/admin/payments", icon: AlertTriangle, tone: "text-amber-600" },
    { count: o.payments_failed_24h, label: "failed payment attempts (24h)", href: "/admin/payments", icon: AlertTriangle, tone: "text-red-600" },
  ].filter((t) => t.count > 0);

  return (
    <div className="space-y-8">
      <PageHeader
        title={`${greeting}${firstName ? `, ${firstName}` : ""}`}
        description="How Kheja_Link is doing today, and what needs you."
        meta={new Date().toLocaleDateString("en-KE", {
          weekday: "long",
          day: "numeric",
          month: "long",
          year: "numeric",
          timeZone: "Africa/Nairobi",
        })}
        actions={
          <>
            <Link
              href="/admin/payments"
              className="flex items-center gap-2 h-11 px-5 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-sm font-black text-zinc-700 dark:text-zinc-200 hover:border-blue-500"
            >
              <Wallet className="w-4 h-4" /> Payments
            </Link>
            <Link
              href="/admin/settings"
              className="flex items-center gap-2 h-11 px-5 rounded-2xl bg-blue-600 text-white text-sm font-black hover:bg-blue-700 shadow-lg shadow-blue-600/20"
            >
              Prices &amp; settings
            </Link>
          </>
        }
      />

      <section className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <Stat icon={Wallet} tone="bg-emerald-600" label="Unlock revenue today" value={money(o.revenue_today)}
          sub={`${money(o.revenue_7d)} this week · ${money(o.revenue_total)} all time`} />
        <Stat icon={Lock} tone="bg-blue-600" label="Unlocks today" value={String(o.unlocks_today)}
          sub={`${o.unlocks_7d} this week · ${o.unlocks_open_now} open right now`} />
        <Stat icon={Users} tone="bg-purple-600" label="Accounts" value={String(o.users)}
          sub={`${o.tenants} tenants · ${o.landlords} landlords · ${o.new_users_7d} new this week`} />
        <Stat icon={Home} tone="bg-amber-500" label="Published listings" value={String(o.published)}
          sub={`${o.available_now} free now · ${o.drafts} drafts · ${o.listings} in total`} />
      </section>

      <section className="grid lg:grid-cols-[1fr_1.3fr] gap-6">
        <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-5">
          <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">Needs you today</h2>
          {todo.length === 0 ? (
            <p className="text-zinc-500 font-medium">Nothing waiting. Everything is answered, reviewed and paid.</p>
          ) : (
            <ul className="space-y-2">
              {todo.map((t) => (
                <li key={t.label}>
                  <Link
                    href={t.href}
                    className="flex items-center gap-3 p-4 rounded-2xl bg-zinc-50 dark:bg-zinc-800/60 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
                  >
                    <t.icon className={`w-5 h-5 shrink-0 ${t.tone}`} />
                    <span className="font-black text-zinc-900 dark:text-white">{t.count}</span>
                    <span className="font-bold text-zinc-600 dark:text-zinc-300 flex-1">{t.label}</span>
                    <ArrowRight className="w-4 h-4 text-zinc-400" />
                  </Link>
                </li>
              ))}
            </ul>
          )}
          <p className="text-xs font-bold text-zinc-400">
            Refunds paid so far: {money(o.refunds_paid_total)}
          </p>
        </div>

        <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-5">
          <div className="flex items-center justify-between">
            <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">Latest unlocks</h2>
            <Link href="/admin/payments" className="text-xs font-black text-blue-600 hover:text-blue-700">
              All payments
            </Link>
          </div>
          {unlocks.length === 0 ? (
            <p className="text-zinc-500 font-medium">No unlocks yet.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
              {unlocks.map((u) => {
                const open = u.expires_at && new Date(u.expires_at).getTime() > Date.now();
                return (
                  <li key={u.id} className="py-3 flex items-center gap-3">
                    <div className="min-w-0 flex-1">
                      <p className="font-black text-zinc-900 dark:text-white truncate">
                        {u.property?.title ?? "A listing"}
                      </p>
                      <p className="text-xs font-bold text-zinc-400">
                        {u.user?.full_name ?? "A tenant"} · {formatRelativeDate(u.paid_at)}
                      </p>
                    </div>
                    <span className="font-black text-zinc-900 dark:text-white">{formatPrice(u.amount, u.currency)}</span>
                    <Badge tone={open ? "green" : "zinc"}>{open ? "Open" : "Ended"}</Badge>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>
    </div>
  );
}

function Stat({
  icon: Icon,
  tone,
  label,
  value,
  sub,
}: {
  icon: LucideIcon;
  tone: string;
  label: string;
  value: string;
  sub: string;
}) {
  return (
    <div className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-4">
      <span className={`w-11 h-11 rounded-2xl ${tone} text-white flex items-center justify-center`}>
        <Icon className="w-5 h-5" />
      </span>
      <div className="space-y-1">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{label}</p>
        <p className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">{value}</p>
        <p className="text-xs font-bold text-zinc-500">{sub}</p>
      </div>
    </div>
  );
}
