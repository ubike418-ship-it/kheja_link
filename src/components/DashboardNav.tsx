"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Building2, MessageSquare, Plus } from "lucide-react";

const tabs = [
  { href: "/dashboard", label: "Overview", icon: LayoutDashboard, exact: true },
  { href: "/dashboard/properties", label: "My Listings", icon: Building2, exact: false },
  { href: "/dashboard/inquiries", label: "Inquiries", icon: MessageSquare, exact: false },
];

export default function DashboardNav() {
  const pathname = usePathname();

  return (
    <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
      <nav className="flex items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] overflow-x-auto scrollbar-hide">
        {tabs.map((tab) => {
          const active = tab.exact
            ? pathname === tab.href
            : pathname.startsWith(tab.href) && !pathname.startsWith("/dashboard/properties/new");
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

      <Link
        href="/dashboard/properties/new"
        className="flex items-center justify-center gap-2 px-8 h-16 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors shadow-lg shadow-blue-600/20 shrink-0"
      >
        <Plus className="w-5 h-5" />
        New listing
      </Link>
    </div>
  );
}
