import { redirect } from "next/navigation";
import { ShieldCheck } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import AdminNav from "@/components/admin/AdminNav";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * The Kheja_Link team's back office. The page guard below is only for a
 * friendly message: every table behind it is admin-only under RLS.
 *
 * Make someone an admin in the Supabase SQL editor:
 *   update public.profiles set role = 'admin' where id = '<user id>';
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login?next=/admin");

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-4 sm:px-6">
        <div className="max-w-7xl mx-auto">
          {profile.role === "admin" ? (
            <div className="space-y-10">
              <AdminNav />
              {children}
            </div>
          ) : (
            <div className="max-w-xl mx-auto text-center space-y-6 py-20">
              <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-900 rounded-[2rem] flex items-center justify-center mx-auto rotate-12">
                <ShieldCheck className="w-12 h-12 text-zinc-400" />
              </div>
              <h1 className="text-4xl font-black text-zinc-900 dark:text-white tracking-tighter">
                Admins only
              </h1>
              <p className="text-zinc-500 font-medium leading-relaxed">
                This area is for the Kheja_Link team. If you should have access, ask an existing
                admin to upgrade your account.
              </p>
            </div>
          )}
        </div>
      </main>

      <Footer />
    </div>
  );
}
