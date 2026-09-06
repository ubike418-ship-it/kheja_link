import Link from "next/link";
import { Compass } from "lucide-react";
import Logo from "@/components/Logo";

export default function NotFound() {
  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans flex flex-col items-center justify-center px-6 text-center gap-8">
      <Logo size={56} />
      <div className="w-24 h-24 bg-zinc-100 dark:bg-zinc-900 rounded-[2rem] flex items-center justify-center rotate-12">
        <Compass className="w-12 h-12 text-zinc-300" />
      </div>
      <div className="space-y-3 max-w-md">
        <h1 className="text-5xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          Page not found
        </h1>
        <p className="text-zinc-500 font-medium">
          That home may have been rented out, or the link is wrong. Let&apos;s find you another one.
        </p>
      </div>
      <div className="flex flex-col sm:flex-row gap-4">
        <Link
          href="/properties"
          className="px-8 h-14 bg-blue-600 text-white rounded-2xl font-black flex items-center justify-center hover:bg-blue-700 transition-colors"
        >
          Search rentals
        </Link>
        <Link
          href="/"
          className="px-8 h-14 border border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 rounded-2xl font-black flex items-center justify-center hover:border-blue-500 transition-colors"
        >
          Back home
        </Link>
      </div>
    </div>
  );
}
