"use client";

import { useEffect } from "react";
import Link from "next/link";
import { AlertTriangle } from "lucide-react";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Surfaces in the Vercel function logs without shipping a third-party reporter.
    console.error("Kheja_Link route error:", error);
  }, [error]);

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans flex flex-col items-center justify-center px-6 text-center gap-8">
      <div className="w-24 h-24 bg-red-50 dark:bg-red-950/30 rounded-[2rem] flex items-center justify-center rotate-12">
        <AlertTriangle className="w-12 h-12 text-red-500" />
      </div>
      <div className="space-y-3 max-w-md">
        <h1 className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white tracking-tighter">
          Something went wrong
        </h1>
        <p className="text-zinc-500 font-medium">
          We could not load this page. Try again — if it keeps happening, let us know at
          ubike418@gmail.com.
        </p>
        {error.digest && <p className="text-xs font-bold text-zinc-400">Reference: {error.digest}</p>}
      </div>
      <div className="flex flex-col sm:flex-row gap-4">
        <button
          onClick={reset}
          className="px-8 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors"
        >
          Try again
        </button>
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
