import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { UserCog } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ProfileForm from "@/components/ProfileForm";
import DeleteAccountSection from "@/components/DeleteAccountSection";
import { getCurrentProfile, getCurrentUser } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Your Profile",
  robots: { index: false, follow: false },
};

export default async function AccountPage() {
  const [profile, user] = await Promise.all([getCurrentProfile(), getCurrentUser()]);

  // Middleware normally catches this; belt and braces for direct server hits.
  if (!user || !profile) redirect("/login?next=/account");

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-2xl mx-auto space-y-10">
          <header className="space-y-4">
            <div className="flex items-center gap-2 text-blue-600 font-black uppercase tracking-[0.2em] text-[10px]">
              <UserCog className="w-4 h-4" />
              <span>Account</span>
            </div>
            <h1 className="text-5xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Your Profile
            </h1>
          </header>

          <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem]">
            <ProfileForm profile={profile} email={user.email} />
          </div>

          <DeleteAccountSection />
        </div>
      </main>

      <Footer />
    </div>
  );
}
