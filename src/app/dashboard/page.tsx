import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { Building2, Eye, MessageSquare, FileEdit, CheckCircle2, ArrowRight, Plus } from "lucide-react";
import { getLandlordStats, getMyProperties } from "@/lib/queries/properties";
import { getInquiriesForOwner } from "@/lib/queries/inquiries";
import { getCurrentProfile } from "@/lib/supabase/server";
import { formatLocation, formatRelativeDate, formatRent } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const metadata: Metadata = {
  title: "Dashboard",
  robots: { index: false, follow: false },
};

export default async function DashboardPage() {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login?next=/dashboard");

  const [stats, properties, inquiries] = await Promise.all([
    getLandlordStats(profile.id),
    getMyProperties(profile.id),
    getInquiriesForOwner().catch(() => []),
  ]);

  const recent = properties.slice(0, 3);
  const recentInquiries = inquiries.slice(0, 4);

  const cards = [
    { icon: Building2, label: "Listings", value: stats.total, tone: "text-blue-600 bg-blue-50 dark:bg-blue-900/20" },
    { icon: CheckCircle2, label: "Published", value: stats.published, tone: "text-emerald-600 bg-emerald-50 dark:bg-emerald-900/20" },
    { icon: FileEdit, label: "Drafts", value: stats.drafts, tone: "text-amber-600 bg-amber-50 dark:bg-amber-900/20" },
    { icon: Eye, label: "Total views", value: stats.views, tone: "text-purple-600 bg-purple-50 dark:bg-purple-900/20" },
  ];

  return (
    <div className="space-y-12">
      <header className="space-y-3">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
          Landlord dashboard
        </p>
        <h1 className="text-5xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          {profile.full_name ? `Karibu, ${profile.full_name.split(" ")[0]}.` : "Karibu."}
        </h1>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {cards.map((card) => (
          <div
            key={card.label}
            className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-3"
          >
            <span className={`w-10 h-10 rounded-2xl flex items-center justify-center ${card.tone}`}>
              <card.icon className="w-5 h-5" />
            </span>
            <p className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
              {card.value}
            </p>
            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
              {card.label}
            </p>
          </div>
        ))}
      </div>

      {properties.length === 0 ? (
        <div className="py-24 text-center space-y-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-800 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
            <Building2 className="w-12 h-12 text-zinc-300" />
          </div>
          <div className="space-y-2">
            <h2 className="text-2xl font-black text-zinc-900 dark:text-white">No listings yet</h2>
            <p className="text-zinc-500 font-medium max-w-md mx-auto">
              Add your first house, upload a few photos and publish it. House hunters across Meru will
              see it straight away.
            </p>
          </div>
          <Link
            href="/dashboard/properties/new"
            className="inline-flex items-center gap-2 px-8 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors"
          >
            <Plus className="w-5 h-5" />
            Create your first listing
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* Recent listings */}
          <section className="space-y-5">
            <div className="flex items-center justify-between">
              <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">
                Recent listings
              </h2>
              <Link
                href="/dashboard/properties"
                className="flex items-center gap-1 text-xs font-black text-blue-600 hover:text-blue-700"
              >
                View all <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <div className="space-y-3">
              {recent.map((property) => (
                <Link
                  key={property.id}
                  href={`/dashboard/properties/${property.id}/edit`}
                  className="flex items-center gap-4 p-4 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl hover:border-blue-500 transition-colors group"
                >
                  <span className="relative w-20 h-16 rounded-2xl overflow-hidden bg-zinc-100 dark:bg-zinc-800 shrink-0">
                    {property.images[0] && (
                      <Image
                        src={property.images[0].public_url}
                        alt=""
                        fill
                        sizes="80px"
                        className="object-cover"
                      />
                    )}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block font-black text-zinc-900 dark:text-white truncate">
                      {property.title}
                    </span>
                    <span className="block text-xs font-bold text-zinc-400 truncate">
                      {formatLocation(property.location)} ·{" "}
                      {formatRent(property.price_amount, property.price_period, property.price_currency)}
                    </span>
                  </span>
                  <StatusPill status={property.status} />
                </Link>
              ))}
            </div>
          </section>

          {/* Recent inquiries */}
          <section className="space-y-5">
            <div className="flex items-center justify-between">
              <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">
                Latest inquiries
              </h2>
              <Link
                href="/dashboard/inquiries"
                className="flex items-center gap-1 text-xs font-black text-blue-600 hover:text-blue-700"
              >
                View all <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            {recentInquiries.length === 0 ? (
              <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl text-center space-y-2">
                <MessageSquare className="w-8 h-8 text-zinc-300 mx-auto" />
                <p className="text-sm font-bold text-zinc-400">
                  No earlier inquiries. Tenants now reach you by unlocking a listing, or through the
                  Kheja_Link team.
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {recentInquiries.map((inquiry) => (
                  <div
                    key={inquiry.id}
                    className="p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl space-y-2"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <p className="font-black text-zinc-900 dark:text-white truncate">
                        {inquiry.name}
                      </p>
                      <span className="text-[10px] font-black uppercase tracking-widest text-zinc-400 shrink-0">
                        {formatRelativeDate(inquiry.created_at)}
                      </span>
                    </div>
                    <p className="text-sm font-medium text-zinc-500 line-clamp-2">{inquiry.message}</p>
                    {inquiry.property && (
                      <p className="text-[10px] font-black uppercase tracking-widest text-blue-600 truncate">
                        {inquiry.property.title}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
