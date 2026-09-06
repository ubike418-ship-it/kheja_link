import type { Metadata } from "next";
import Link from "next/link";
import { LifeBuoy, ShieldCheck, Mail, Phone, MapPin } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Help Centre",
  description:
    "How Kheja_Link works, how to stay safe when house hunting in Meru, and how to reach us.",
};

const faqs = [
  {
    q: "Is Kheja_Link free to use?",
    a: "Yes. Searching, filtering, saving homes and contacting landlords are all free for house hunters. You do not even need an account to browse or send an inquiry.",
  },
  {
    q: "Do I need an account?",
    a: "Only to save homes to your shortlist, keep track of your messages, or list a property of your own. Browsing and searching are open to everyone.",
  },
  {
    q: "How do I list my house?",
    a: "Create an account and choose the landlord option (or switch on your profile page at any time). You can then add photos, rent, location and amenities, and publish it — it appears in search straight away.",
  },
  {
    q: "How do I contact a landlord?",
    a: "Every listing has a call and WhatsApp button, plus a message form. Your message goes directly to the landlord who posted the house — Kheja_Link never sits in the middle of the deal.",
  },
  {
    q: "What does 'verified' mean?",
    a: "A verified badge means our team has confirmed the landlord's identity and their right to let the property. Always still view a house in person before paying anything.",
  },
];

const safetyTips = [
  "Never send a deposit, viewing fee or booking fee before you have seen the house in person.",
  "Meet during daylight hours, and take someone with you if you can.",
  "Ask to see ownership or management documents before signing anything.",
  "Be wary of rent far below the going rate for the area — it is the oldest trick there is.",
  "Get a written, signed tenancy agreement before you move in or pay a deposit.",
  "Pay through traceable means, and always get a receipt.",
];

export default async function HelpPage() {
  const profile = await getCurrentProfile();

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-3xl mx-auto space-y-16">
          <header className="space-y-4">
            <div className="flex items-center gap-2 text-blue-600 font-black uppercase tracking-[0.2em] text-[10px]">
              <LifeBuoy className="w-4 h-4" />
              <span>Support</span>
            </div>
            <h1 className="text-5xl md:text-7xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Help Centre
            </h1>
          </header>

          <section className="space-y-6">
            <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Common questions
            </h2>
            <div className="space-y-4">
              {faqs.map((faq) => (
                <details
                  key={faq.q}
                  className="group p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl"
                >
                  <summary className="font-black text-lg text-zinc-900 dark:text-white cursor-pointer list-none flex items-center justify-between gap-4">
                    {faq.q}
                    <span className="text-blue-600 text-2xl leading-none group-open:rotate-45 transition-transform shrink-0">
                      +
                    </span>
                  </summary>
                  <p className="mt-4 text-zinc-600 dark:text-zinc-400 font-medium leading-relaxed">
                    {faq.a}
                  </p>
                </details>
              ))}
            </div>
          </section>

          <section id="safety" className="space-y-6 scroll-mt-32">
            <div className="flex items-center gap-3">
              <ShieldCheck className="w-8 h-8 text-emerald-600" />
              <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
                Safety tips
              </h2>
            </div>
            <ul className="space-y-3">
              {safetyTips.map((tip) => (
                <li
                  key={tip}
                  className="flex gap-4 p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl"
                >
                  <span className="w-2 h-2 rounded-full bg-emerald-500 mt-2.5 shrink-0" />
                  <span className="font-medium text-zinc-600 dark:text-zinc-400 leading-relaxed">
                    {tip}
                  </span>
                </li>
              ))}
            </ul>
          </section>

          <section id="contact" className="space-y-6 scroll-mt-32">
            <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
              Contact us
            </h2>
            <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-5">
              <a
                href="mailto:hello@khejalink.co.ke"
                className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400 hover:text-blue-600 transition-colors"
              >
                <span className="w-11 h-11 rounded-2xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center">
                  <Mail className="w-5 h-5 text-blue-600" />
                </span>
                <span className="font-bold">hello@khejalink.co.ke</span>
              </a>
              <a
                href="tel:+254710655709"
                className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400 hover:text-emerald-600 transition-colors"
              >
                <span className="w-11 h-11 rounded-2xl bg-emerald-50 dark:bg-emerald-900/20 flex items-center justify-center">
                  <Phone className="w-5 h-5 text-emerald-600" />
                </span>
                <span className="font-bold">+254 710 655 709</span>
              </a>
              <div className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400">
                <span className="w-11 h-11 rounded-2xl bg-purple-50 dark:bg-purple-900/20 flex items-center justify-center">
                  <MapPin className="w-5 h-5 text-purple-600" />
                </span>
                <span className="font-bold">Greenwood Mall, Meru Town, Kenya</span>
              </div>
            </div>
          </section>

          <p className="text-center font-medium text-zinc-500">
            Ready to look?{" "}
            <Link href="/properties" className="font-black text-blue-600 hover:underline">
              Browse every home on Kheja_Link
            </Link>
            .
          </p>
        </div>
      </main>

      <Footer />
    </div>
  );
}
