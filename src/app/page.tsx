import Link from "next/link";
import Hero from "@/components/Hero";
import HomeListings from "@/components/HomeListings";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import { getProperties } from "@/lib/queries/properties";
import { withFavoriteState } from "@/lib/queries/favorites";
import { getLocations } from "@/lib/queries/lookups";
import { getCurrentProfile } from "@/lib/supabase/server";

// Rendered per request: the navbar and the saved-home hearts depend on the
// visitor's session, which is read from cookies.
export const dynamic = "force-dynamic";

export default async function Home() {
  // The homepage should still render if the database is unreachable or has not
  // been migrated yet — visitors get the empty state rather than an error page.
  const [listing, locations, profile] = await Promise.all([
    getProperties({ perPage: 24, sort: "newest" }).catch(() => ({
      items: [],
      total: 0,
      page: 1,
      perPage: 24,
      pageCount: 1,
    })),
    getLocations().catch(() => []),
    getCurrentProfile().catch(() => null),
  ]);

  const properties = await withFavoriteState(listing.items).catch(() => listing.items);

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pb-32">
        <Hero locations={locations} />

        <HomeListings properties={properties} />

        {/* Call to Action */}
        <section className="px-6 pt-20">
          <div className="max-w-7xl mx-auto">
            <div className="relative rounded-[4rem] overflow-hidden bg-zinc-900 dark:bg-zinc-900 py-24 px-10 text-center shadow-3xl shadow-blue-500/10">
              <div className="absolute inset-0 opacity-40 bg-[radial-gradient(circle_at_top_right,_var(--tw-gradient-stops))] from-blue-600/30 via-transparent to-transparent" />
              <div className="absolute inset-0 opacity-40 bg-[radial-gradient(circle_at_bottom_left,_var(--tw-gradient-stops))] from-emerald-600/20 via-transparent to-transparent" />

              <div className="relative z-10 max-w-3xl mx-auto space-y-12">
                <div className="inline-block px-4 py-1.5 bg-blue-500/10 backdrop-blur-md border border-blue-500/20 rounded-full text-blue-400 text-xs font-black uppercase tracking-widest">
                  Start Your Journey
                </div>
                <h2 className="text-5xl md:text-7xl lg:text-8xl font-black text-white leading-[0.9] tracking-tighter">
                  Ready to find <br /> your next home?
                </h2>
                <p className="text-zinc-400 text-xl md:text-2xl font-medium tracking-tight">
                  Join thousands of Meru residents finding their dream spaces on Kheja_Link every month.
                </p>
                <div className="flex flex-col sm:flex-row items-center justify-center gap-6">
                  <Link
                    href="/properties"
                    className="w-full sm:w-auto px-12 h-20 bg-blue-600 text-white rounded-[2rem] font-black text-xl hover:scale-105 active:scale-95 transition-all duration-300 shadow-2xl shadow-blue-600/20 flex items-center justify-center"
                  >
                    Find a House
                  </Link>
                  <Link
                    href="/dashboard/properties/new"
                    className="w-full sm:w-auto px-12 h-20 bg-white/5 backdrop-blur-xl text-white rounded-[2rem] font-black text-xl hover:bg-white/10 transition-all duration-300 border border-white/10 flex items-center justify-center"
                  >
                    List Your Property
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
