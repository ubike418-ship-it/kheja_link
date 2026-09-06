import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAmenities, getLocations, getPropertyTypes } from "@/lib/queries/lookups";
import { getCurrentProfile } from "@/lib/supabase/server";
import PropertyForm from "@/components/PropertyForm";

export const metadata: Metadata = {
  title: "List a House",
  robots: { index: false, follow: false },
};

export default async function NewPropertyPage() {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login?next=/dashboard/properties/new");

  const [types, locations, amenities] = await Promise.all([
    getPropertyTypes(),
    getLocations(),
    getAmenities(),
  ]);

  return (
    <div className="space-y-10">
      <header className="space-y-3">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
          New listing
        </p>
        <h1 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          List a House
        </h1>
        <p className="text-lg font-medium text-zinc-500 max-w-2xl">
          Fill this in once and your house is live across Kheja_Link. You can save it as a draft and
          come back to it at any time.
        </p>
      </header>

      <PropertyForm
        types={types}
        locations={locations}
        amenities={amenities}
        defaultPhone={profile.phone}
      />
    </div>
  );
}
