import Link from "next/link";
import { redirect } from "next/navigation";
import { KeyRound, ArrowRight } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import DashboardNav from "@/components/DashboardNav";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login?next=/dashboard");

  const isLandlord = profile.role === "landlord" || profile.role === "admin";

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-7xl mx-auto">
          {isLandlord ? (
            <div className="space-y-10">
              <DashboardNav />
              {children}
            </div>
          ) : (
            // A house hunter who lands here is not blocked — they are shown how
            // to become a landlord, which is a one-click change on their profile.
            <div className="max-w-xl mx-auto text-center space-y-6 py-20">
              <div className="w-24 h-24 bg-blue-50 dark:bg-blue-950/40 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
                <KeyRound className="w-12 h-12 text-blue-600" />
              </div>
              <div className="space-y-2">
                <h1 className="text-4xl font-black text-zinc-900 dark:text-white tracking-tighter">
                  Want to list a house?
                </h1>
                <p className="text-zinc-500 font-medium leading-relaxed">
                  Your account is currently set up for house hunting. Switch it to a landlord account
                  and you can publish listings, upload photos and manage inquiries from right here.
                </p>
              </div>
              <Link
                href="/account"
                className="inline-flex items-center gap-2 px-8 h-16 bg-blue-600 text-white rounded-2xl font-black text-lg hover:bg-blue-700 transition-colors shadow-lg shadow-blue-600/20"
              >
                Become a landlord
                <ArrowRight className="w-5 h-5" />
              </Link>
            </div>
          )}
        </div>
      </main>

      <Footer />
    </div>
  );
}
