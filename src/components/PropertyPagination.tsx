"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export default function PropertyPagination({
  page,
  pageCount,
}: {
  page: number;
  pageCount: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();

  if (pageCount <= 1) return null;

  const goTo = (target: number) => {
    const next = new URLSearchParams(params.toString());
    if (target <= 1) next.delete("page");
    else next.set("page", String(target));
    router.push(next.toString() ? `${pathname}?${next}` : pathname);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  // A compact window around the current page, so 40 pages do not blow out the row.
  const pages = Array.from({ length: pageCount }, (_, i) => i + 1).filter(
    (n) => n === 1 || n === pageCount || Math.abs(n - page) <= 1,
  );

  return (
    <nav aria-label="Pagination" className="flex items-center justify-center gap-2 pt-16">
      <button
        onClick={() => goTo(page - 1)}
        disabled={page <= 1}
        aria-label="Previous page"
        className="w-12 h-12 flex items-center justify-center rounded-2xl border border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-blue-500 hover:text-blue-600 transition-colors disabled:opacity-40 disabled:hover:border-zinc-200 disabled:hover:text-zinc-600"
      >
        <ChevronLeft className="w-5 h-5" />
      </button>

      {pages.map((n, index) => (
        <span key={n} className="flex items-center gap-2">
          {index > 0 && n - pages[index - 1] > 1 && (
            <span className="text-zinc-400 font-black px-1">…</span>
          )}
          <button
            onClick={() => goTo(n)}
            aria-current={n === page ? "page" : undefined}
            className={`w-12 h-12 rounded-2xl font-black transition-colors ${
              n === page
                ? "bg-blue-600 text-white"
                : "border border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-blue-500 hover:text-blue-600"
            }`}
          >
            {n}
          </button>
        </span>
      ))}

      <button
        onClick={() => goTo(page + 1)}
        disabled={page >= pageCount}
        aria-label="Next page"
        className="w-12 h-12 flex items-center justify-center rounded-2xl border border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-blue-500 hover:text-blue-600 transition-colors disabled:opacity-40 disabled:hover:border-zinc-200 disabled:hover:text-zinc-600"
      >
        <ChevronRight className="w-5 h-5" />
      </button>
    </nav>
  );
}
