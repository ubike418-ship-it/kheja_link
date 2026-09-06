import type { Metadata } from "next";
import Link from "next/link";
import { Heart, Search } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import PropertyCard from "@/components/PropertyCard";
import { getFavoriteProperties } from "@/lib/queries/favorites";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Saved Homes",
  description: "The homes you have saved on Kheja_Link.",
  robots: { index: false, follow: false },
};

export default async function FavoritesPage() {
  // The middleware already redirects signed-out visitors to /login.
  const [properties, profile] = await Promise.all([getFavoriteProperties(), getCurrentProfile()]);

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-7xl mx-auto space-y-12">
          <header className="space-y-4">
            <div className="flex items-center gap-2 text-blue-600 font-black uppercase tracking-[0.2em] text-[10px]">
              <Heart className="w-4 h-4" />
              <span>Your shortlist</span>
            </div>
            <h1 className="text-5xl md:text-7xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Saved Homes
            </h1>
            <p className="text-lg font-medium text-zinc-500">
              {properties.length === 0
                ? "Nothing saved yet."
                : `${properties.length} ${properties.length === 1 ? "home" : "homes"} on your list.`}
            </p>
          </header>

          {properties.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-12">
              {properties.map((property) => (
                <PropertyCard key={property.id} property={property} />
              ))}
            </div>
          ) : (
            <div className="py-32 text-center space-y-6">
              <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-900 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
                <Heart className="w-12 h-12 text-zinc-300" />
              </div>
              <div className="space-y-2">
                <h2 className="text-2xl font-black text-zinc-900 dark:text-white">
                  No saved homes yet
                </h2>
                <p className="text-zinc-500 font-medium max-w-md mx-auto">
                  Tap the heart on any listing and it will wait for you here — handy when you are
                  comparing a few places.
                </p>
              </div>
              <Link
                href="/properties"
                className="inline-flex items-center gap-2 px-8 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors"
              >
                <Search className="w-5 h-5" />
                Start searching
              </Link>
            </div>
          )}
        </div>
      </main>

      <Footer />
    </div>
  );
}
