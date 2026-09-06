"use client";

import { motion } from "framer-motion";
import { Search, MapPin, Sparkles } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import type { LocationRow } from "@/lib/supabase/database.types";

export default function Hero({ locations = [] }: { locations?: LocationRow[] }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const value = query.trim();
    setIsSubmitting(true);

    // If the text is exactly an area we know, filter by that location — it is a
    // far better result than a fuzzy text match.
    const match = locations.find(
      (location) => location.name.toLowerCase() === value.toLowerCase(),
    );

    if (match) router.push(`/properties?location=${match.slug}`);
    else if (value) router.push(`/properties?q=${encodeURIComponent(value)}`);
    else router.push("/properties");
  };

  return (
    <section className="relative min-h-[90vh] flex flex-col items-center justify-center pt-20 px-6 overflow-hidden">
      {/* Animated Background Shapes */}
      <div className="absolute inset-0 -z-10 overflow-hidden" aria-hidden="true">
        <motion.div
          animate={{ scale: [1, 1.2, 1], rotate: [0, 90, 0], x: [0, 50, 0], y: [0, 30, 0] }}
          transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
          className="absolute top-[-10%] left-[-10%] w-[50%] h-[50%] bg-blue-400/30 blur-[120px] rounded-full"
        />
        <motion.div
          animate={{ scale: [1, 1.3, 1], rotate: [0, -90, 0], x: [0, -40, 0], y: [0, -20, 0] }}
          transition={{ duration: 25, repeat: Infinity, ease: "linear" }}
          className="absolute bottom-[-10%] right-[-10%] w-[60%] h-[60%] bg-emerald-400/30 blur-[150px] rounded-full"
        />
        <motion.div
          animate={{ scale: [1, 1.5, 1], x: [0, 100, 0], y: [0, -50, 0] }}
          transition={{ duration: 30, repeat: Infinity, ease: "linear" }}
          className="absolute top-[20%] right-[10%] w-[30%] h-[30%] bg-purple-400/20 blur-[100px] rounded-full"
        />

        {/* Floating elements */}
        <motion.div
          animate={{ y: [0, -20, 0], rotate: [0, 10, 0] }}
          transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
          className="absolute top-[20%] left-[15%] w-12 h-12 bg-white/10 backdrop-blur-sm border border-white/20 rounded-2xl hidden lg:block"
        />
        <motion.div
          animate={{ y: [0, 20, 0], rotate: [0, -10, 0] }}
          transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
          className="absolute bottom-[30%] right-[15%] w-16 h-16 bg-white/10 backdrop-blur-sm border border-white/20 rounded-full hidden lg:block"
        />
      </div>

      {/* Content */}
      <div className="relative z-10 max-w-5xl w-full text-center space-y-12">
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 1, ease: [0.22, 1, 0.36, 1] }}
          className="space-y-6"
        >
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2, duration: 0.5 }}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/50 dark:bg-zinc-900/50 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 text-sm font-bold shadow-sm"
          >
            <Sparkles className="w-4 h-4 text-blue-500" />
            <span>Meru&apos;s Next-Gen Rental Platform</span>
          </motion.div>
          <h1 className="text-6xl md:text-8xl lg:text-9xl font-black tracking-tighter text-zinc-900 dark:text-white leading-[0.9] text-balance">
            Find Your <br />
            <span className="relative inline-block">
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 via-emerald-500 to-purple-600">
                Dream Space.
              </span>
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: "100%" }}
                transition={{ delay: 1, duration: 1 }}
                className="absolute -bottom-2 left-0 h-2 bg-gradient-to-r from-blue-600 to-transparent rounded-full opacity-30"
              />
            </span>
          </h1>
          <p className="text-xl md:text-3xl text-zinc-600 dark:text-zinc-400 max-w-3xl mx-auto font-medium tracking-tight">
            The professional way to find long-term rentals, apartments, shops, and bedsitters in Meru.
            <span className="text-zinc-900 dark:text-white font-bold ml-1">
              Reliable, verified, and modern.
            </span>
          </p>
        </motion.div>

        {/* Search Bar */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.8 }}
          className="relative max-w-3xl mx-auto w-full group"
        >
          <div className="absolute -inset-1 bg-gradient-to-r from-blue-600 to-emerald-600 rounded-3xl blur opacity-25 group-hover:opacity-50 transition duration-1000 group-hover:duration-200" />
          <form
            onSubmit={handleSubmit}
            className="relative flex flex-col md:flex-row items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] shadow-2xl"
          >
            <div className="flex-1 flex items-center gap-3 px-4 w-full">
              <MapPin className="text-blue-500 w-5 h-5 shrink-0" aria-hidden="true" />
              <input
                type="text"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                list="kheja-hero-locations"
                placeholder="Where in Meru? (e.g. Makutano, Nkubu)"
                aria-label="Search by area, house type or keyword"
                className="w-full h-12 bg-transparent border-none focus:ring-0 text-zinc-900 dark:text-white placeholder-zinc-400 font-medium outline-none"
              />
              <datalist id="kheja-hero-locations">
                {locations.map((location) => (
                  <option key={location.id} value={location.name} />
                ))}
              </datalist>
            </div>
            <div className="h-8 w-[1px] bg-zinc-200 dark:bg-zinc-800 hidden md:block" />
            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full md:w-auto px-8 h-12 bg-blue-600 text-white rounded-2xl font-bold flex items-center justify-center gap-2 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 shadow-lg shadow-blue-500/20 disabled:opacity-70"
            >
              <Search className="w-5 h-5" />
              <span>{isSubmitting ? "Searching…" : "Explore Now"}</span>
            </button>
          </form>
        </motion.div>
      </div>
    </section>
  );
}
