"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Users,
  Home,
  Wallet,
  MessageSquare,
  HandCoins,
  Truck,
  Moon,
  SlidersHorizontal,
  ExternalLink,
  type LucideIcon,
} from "lucide-react";

type Item = { href: string; label: string; icon: LucideIcon; exact?: boolean; badge?: keyof Counts };

export type Counts = {
  messages: number;
  houses: number;
  refunds: number;
  duplicates: number;
};

const GROUPS: { title: string; items: Item[] }[] = [
  { title: "Dashboard", items: [{ href: "/admin", label: "Overview", icon: LayoutDashboard, exact: true }] },
  {
    title: "People",
    items: [
      { href: "/admin/users", label: "Users", icon: Users },
      { href: "/admin/messages", label: "Messages", icon: MessageSquare, badge: "messages" },
    ],
  },
  {
    title: "Marketplace",
    items: [
      { href: "/admin/listings", label: "Listings", icon: Home },
      { href: "/admin/refunds", label: "Houses & refunds", icon: HandCoins, badge: "houses" },
      { href: "/admin/providers", label: "Service providers", icon: Truck },
      { href: "/admin/stays", label: "Stays waitlist", icon: Moon },
    ],
  },
  {
    title: "Money",
    items: [{ href: "/admin/payments", label: "Payments", icon: Wallet, badge: "duplicates" }],
  },
  { title: "System", items: [{ href: "/admin/settings", label: "Business settings", icon: SlidersHorizontal }] },
];

const ALL = GROUPS.flatMap((g) => g.items);

export default function AdminSidebar({ counts, adminName }: { counts: Counts; adminName: string }) {
  const pathname = usePathname();
  const isActive = (item: Item) => (item.exact ? pathname === item.href : pathname.startsWith(item.href));
  const badgeFor = (item: Item) => {
    if (!item.badge) return 0;
    // Houses & refunds carries both queues.
    return item.badge === "houses" ? counts.houses + counts.refunds : counts[item.badge];
  };

  return (
    <>
      {/* Phones and tablets: one scrolling row. */}
      <nav
        aria-label="Admin sections"
        className="lg:hidden flex gap-2 p-2 -mx-1 overflow-x-auto scrollbar-hide bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[1.5rem]"
      >
        {ALL.map((item) => {
          const active = isActive(item);
          const badge = badgeFor(item);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={`flex items-center gap-2 px-4 h-11 rounded-2xl text-sm font-black whitespace-nowrap transition-colors ${
                active
                  ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900"
                  : "text-zinc-500 hover:text-blue-600"
              }`}
            >
              <item.icon className="w-4 h-4" />
              {item.label}
              {badge > 0 && (
                <span className="min-w-5 h-5 px-1.5 rounded-full bg-red-600 text-white text-[10px] flex items-center justify-center">
                  {badge}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {/* Desktop: a grouped sidebar that stays in view. */}
      <aside className="hidden lg:flex flex-col gap-6 sticky top-28 self-start w-64 shrink-0">
        <div className="p-5 bg-zinc-900 dark:bg-white rounded-[2rem] space-y-1">
          <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-400 dark:text-blue-600">
            Kheja_Link admin
          </p>
          <p className="text-lg font-black text-white dark:text-zinc-900 tracking-tight truncate">{adminName}</p>
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 text-xs font-bold text-zinc-400 dark:text-zinc-500 hover:text-white dark:hover:text-zinc-900"
          >
            View the site <ExternalLink className="w-3 h-3" />
          </Link>
        </div>

        <nav aria-label="Admin sections" className="space-y-5">
          {GROUPS.map((group) => (
            <div key={group.title} className="space-y-1">
              <p className="px-4 pb-1 text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{group.title}</p>
              {group.items.map((item) => {
                const active = isActive(item);
                const badge = badgeFor(item);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    className={`flex items-center gap-3 px-4 h-11 rounded-2xl text-sm font-black transition-colors ${
                      active
                        ? "bg-blue-600 text-white shadow-lg shadow-blue-600/20"
                        : "text-zinc-600 dark:text-zinc-400 hover:bg-white dark:hover:bg-zinc-900 hover:text-zinc-900 dark:hover:text-white"
                    }`}
                  >
                    <item.icon className="w-4 h-4 shrink-0" />
                    <span className="flex-1 truncate">{item.label}</span>
                    {badge > 0 && (
                      <span
                        className={`min-w-6 h-6 px-2 rounded-full text-[10px] flex items-center justify-center ${
                          active ? "bg-white text-blue-600" : "bg-red-600 text-white"
                        }`}
                      >
                        {badge}
                      </span>
                    )}
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>
      </aside>
    </>
  );
}
