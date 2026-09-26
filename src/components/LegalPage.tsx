import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import type { ProfileRow } from "@/lib/supabase/database.types";

export type LegalSection = {
  id?: string;
  heading: string;
  paragraphs: string[];
  bullets?: string[];
};

/** Shared shell for the Terms and Privacy pages, in the site's own design language. */
export default function LegalPage({
  kicker,
  title,
  updated,
  intro,
  sections,
  profile,
}: {
  kicker: string;
  title: string;
  updated: string;
  intro: string;
  sections: LegalSection[];
  profile: ProfileRow | null;
}) {
  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-3xl mx-auto space-y-12">
          <header className="space-y-4">
            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
              {kicker}
            </p>
            <h1 className="text-5xl md:text-7xl font-black text-zinc-900 dark:text-white tracking-tighter">
              {title}
            </h1>
            <p className="text-sm font-bold text-zinc-400">Last updated {updated}</p>
            <p className="text-lg font-medium text-zinc-600 dark:text-zinc-400 leading-relaxed">
              {intro}
            </p>
          </header>

          <div className="space-y-10">
            {sections.map((section) => (
              <section key={section.heading} id={section.id} className="space-y-4 scroll-mt-32">
                <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">
                  {section.heading}
                </h2>
                {section.paragraphs.map((paragraph) => (
                  <p
                    key={paragraph}
                    className="text-zinc-600 dark:text-zinc-400 font-medium leading-relaxed"
                  >
                    {paragraph}
                  </p>
                ))}
                {section.bullets && (
                  <ul className="space-y-2 pl-1">
                    {section.bullets.map((bullet) => (
                      <li key={bullet} className="flex gap-3">
                        <span className="w-1.5 h-1.5 rounded-full bg-blue-600 mt-2.5 shrink-0" />
                        <span className="text-zinc-600 dark:text-zinc-400 font-medium leading-relaxed">
                          {bullet}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </section>
            ))}
          </div>

          <p className="pt-8 border-t border-zinc-200 dark:border-zinc-800 text-sm font-medium text-zinc-500">
            Questions about this page? Email{" "}
            <a href="mailto:ubike418@gmail.com" className="font-black text-blue-600 hover:underline">
              ubike418@gmail.com
            </a>
            .
          </p>
        </div>
      </main>

      <Footer />
    </div>
  );
}
