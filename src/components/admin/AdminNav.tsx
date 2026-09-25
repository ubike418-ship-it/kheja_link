"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Truck, Moon, SlidersHorizontal, MessageSquare, HandCoins } from "lucide-react";

const tabs = [
  { href: "/admin/messages", label: "Messages", icon: MessageSquare },
  { href: "/admin/refunds", label: "Houses & refunds", icon: HandCoins },
  { href: "/admin/providers", label: "Service providers", icon: Truck },
  { href: "/admin/stays", label: "Stays waitlist", icon: Moon },
  { href: "/admin/settings", label: "Business settings", icon: SlidersHorizontal },
];

export default function AdminNav() {
  const pathname = usePathname();

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">Kheja_Link admin</p>
        <h1 className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white tracking-tighter">
          Back office
        </h1>
      </div>
      <nav className="flex items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] overflow-x-auto scrollbar-hide">
        {tabs.map((tab) => {
          const active = pathname.startsWith(tab.href);
          return (
            <Link
              key={tab.href}
              href={tab.href}
              aria-current={active ? "page" : undefined}
              className={`flex items-center gap-2 px-5 h-12 rounded-2xl text-sm font-black whitespace-nowrap transition-colors ${
                active
                  ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900"
                  : "text-zinc-500 hover:text-blue-600"
              }`}
            >
              <tab.icon className="w-4 h-4" />
              {tab.label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
