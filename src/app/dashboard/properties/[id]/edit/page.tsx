import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ExternalLink } from "lucide-react";
import { getMyPropertyById } from "@/lib/queries/properties";
import { getAmenities, getLocations, getPropertyTypes } from "@/lib/queries/lookups";
import { getCurrentProfile } from "@/lib/supabase/server";
import PropertyForm from "@/components/PropertyForm";

export const metadata: Metadata = {
  title: "Edit Listing",
  robots: { index: false, follow: false },
};

export default async function EditPropertyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const profile = await getCurrentProfile();
  if (!profile) redirect(`/login?next=/dashboard/properties/${id}/edit`);

  const [property, types, locations, amenities] = await Promise.all([
    getMyPropertyById(id, profile.id),
    getPropertyTypes(),
    getLocations(),
    getAmenities(),
  ]);

  if (!property) notFound();

  return (
    <div className="space-y-10">
      <header className="space-y-3">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
          Editing listing
        </p>
        <h1 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          {property.title}
        </h1>
        {property.status === "published" && (
          <Link
            href={`/properties/${property.slug}`}
            className="inline-flex items-center gap-1.5 text-sm font-black text-blue-600 hover:text-blue-700"
          >
            View the live listing
            <ExternalLink className="w-4 h-4" />
          </Link>
        )}
      </header>

      <PropertyForm
        types={types}
        locations={locations}
        amenities={amenities}
        defaultPhone={profile.phone}
        property={property}
      />
    </div>
  );
}
