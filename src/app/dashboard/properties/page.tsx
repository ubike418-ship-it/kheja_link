import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { Building2, Eye, Pencil, Plus, ExternalLink } from "lucide-react";
import { getMyProperties } from "@/lib/queries/properties";
import { getCurrentProfile } from "@/lib/supabase/server";
import { formatLocation, formatRelativeDate, formatRent } from "@/lib/format";
import PropertyStatusControl from "@/components/PropertyStatusControl";
import StatusPill from "@/components/StatusPill";

export const metadata: Metadata = {
  title: "My Listings",
  robots: { index: false, follow: false },
};

export default async function MyPropertiesPage() {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login?next=/dashboard/properties");

  const properties = await getMyProperties(profile.id);

  return (
    <div className="space-y-8">
      <header className="space-y-3">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
          Your portfolio
        </p>
        <h1 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          My Listings
        </h1>
      </header>

      {properties.length === 0 ? (
        <div className="py-24 text-center space-y-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-800 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
            <Building2 className="w-12 h-12 text-zinc-300" />
          </div>
          <div className="space-y-2">
            <h2 className="text-2xl font-black text-zinc-900 dark:text-white">Nothing here yet</h2>
            <p className="text-zinc-500 font-medium max-w-md mx-auto">
              Your listings will appear here once you add one.
            </p>
          </div>
          <Link
            href="/dashboard/properties/new"
            className="inline-flex items-center gap-2 px-8 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors"
          >
            <Plus className="w-5 h-5" />
            Create a listing
          </Link>
        </div>
      ) : (
        <div className="space-y-4">
          {properties.map((property) => (
            <div
              key={property.id}
              className="flex flex-col lg:flex-row lg:items-center gap-6 p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem]"
            >
              <span className="relative w-full lg:w-40 h-40 lg:h-28 rounded-2xl overflow-hidden bg-zinc-100 dark:bg-zinc-800 shrink-0">
                {property.images[0] ? (
                  <Image
                    src={property.images[0].public_url}
                    alt=""
                    fill
                    sizes="(max-width: 1024px) 100vw, 160px"
                    className="object-cover"
                  />
                ) : (
                  <span className="absolute inset-0 flex items-center justify-center">
                    <Building2 className="w-8 h-8 text-zinc-300" />
                  </span>
                )}
              </span>

              <div className="min-w-0 flex-1 space-y-2">
                <div className="flex flex-wrap items-center gap-3">
                  <h2 className="text-xl font-black text-zinc-900 dark:text-white truncate">
                    {property.title}
                  </h2>
                  <StatusPill status={property.status} />
                </div>
                <p className="text-sm font-bold text-zinc-400">
                  {formatLocation(property.location)} ·{" "}
                  {formatRent(property.price_amount, property.price_period, property.price_currency)}
                </p>
                <p className="flex items-center gap-4 text-xs font-bold text-zinc-400">
                  <span className="flex items-center gap-1">
                    <Eye className="w-3.5 h-3.5" />
                    {property.view_count} views
                  </span>
                  <span>Added {formatRelativeDate(property.created_at).toLowerCase()}</span>
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-3 shrink-0">
                <PropertyStatusControl propertyId={property.id} status={property.status} />
                <Link
                  href={`/dashboard/properties/${property.id}/edit`}
                  className="flex items-center gap-2 px-5 h-12 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-sm font-black hover:scale-[1.02] transition-transform"
                >
                  <Pencil className="w-4 h-4" />
                  Edit
                </Link>
                {property.status === "published" && (
                  <Link
                    href={`/properties/${property.slug}`}
                    aria-label={`View ${property.title} live`}
                    className="w-12 h-12 flex items-center justify-center rounded-2xl border border-zinc-200 dark:border-zinc-800 text-zinc-500 hover:border-blue-500 hover:text-blue-600 transition-colors"
                  >
                    <ExternalLink className="w-4 h-4" />
                  </Link>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
