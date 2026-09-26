import type { Metadata } from "next";
import Link from "next/link";
import { LifeBuoy, ShieldCheck, Mail, Phone, MapPin } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import { getCurrentProfile } from "@/lib/supabase/server";
import { SOCIAL } from "@/lib/social";
import { TikTokIcon, WhatsAppIcon } from "@/components/SocialIcons";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Help Centre",
  description:
    "How Kheja_Link works, how to stay safe when house hunting in Meru, and how to reach us.",
};

/**
 * No amounts on this page on purpose: a tenant first sees the unlock price on
 * the payment screen in the app, when they tap "Unlock contact".
 */
const faqs = [
  {
    q: "Is Kheja_Link free to use?",
    a: "Searching, filtering, saving homes and messaging the Kheja_Link team are free. When you find a home you want, you unlock it in the app to get the landlord's and caretaker's numbers and the exact location — you see the amount and approve it by M-Pesa at that moment, and nothing is charged before.",
  },
  {
    q: "How does unlocking work?",
    a: "Tap \"Unlock contact\" on a listing in the app. The landlord's and caretaker's numbers, the exact address and the Google Maps pin open for 3 hours from when you pay. While they are open you are never charged again for that house; after 3 hours it locks, and you can unlock it again if you need to. It is not part of your rent or deposit, which you pay the landlord directly.",
  },
  {
    q: "Can I get money back?",
    a: "Yes — give us a house. After you have unlocked a listing, tell us about a vacant house (the one you are moving out of, or one whose landlord agrees to list with us). Once our team approves it, part of your unlock is refunded. You can follow it in the app under Unlocks & refunds.",
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
    a: `Unlock the listing in the app to get the landlord's and caretaker's numbers and the exact location, then call or WhatsApp them yourself. Questions before you unlock go to the Kheja_Link team through the message form on the listing — messages no longer go to landlords directly. Our reply appears in your in-app Inbox.`,
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
                href="mailto:ubike418@gmail.com"
                className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400 hover:text-blue-600 transition-colors"
              >
                <span className="w-11 h-11 rounded-2xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center">
                  <Mail className="w-5 h-5 text-blue-600" />
                </span>
                <span className="font-bold">ubike418@gmail.com</span>
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
              <a
                href={SOCIAL.whatsapp.url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400 hover:text-[#1da851] transition-colors"
              >
                <span className="w-11 h-11 rounded-2xl bg-[#25D366]/10 flex items-center justify-center">
                  <WhatsAppIcon className="w-5 h-5 text-[#1da851]" />
                </span>
                <span className="font-bold">WhatsApp {SOCIAL.whatsapp.number}</span>
              </a>
              <a
                href={SOCIAL.tiktok.url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-4 text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors"
              >
                <span className="w-11 h-11 rounded-2xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center">
                  <TikTokIcon className="w-5 h-5 text-zinc-900 dark:text-white" />
                </span>
                <span className="font-bold">TikTok {SOCIAL.tiktok.handle}</span>
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
