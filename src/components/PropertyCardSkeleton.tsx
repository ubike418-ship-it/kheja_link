/** Matches PropertyCard's geometry so the grid does not jump when data lands. */
export default function PropertyCardSkeleton() {
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-[3rem] overflow-hidden border border-zinc-100 dark:border-zinc-800 animate-pulse">
      <div className="h-80 w-full bg-zinc-200 dark:bg-zinc-800" />
      <div className="p-8 space-y-6">
        <div className="space-y-3">
          <div className="h-7 w-3/4 rounded-full bg-zinc-200 dark:bg-zinc-800" />
          <div className="h-4 w-1/2 rounded-full bg-zinc-100 dark:bg-zinc-800/60" />
        </div>
        <div className="flex items-center justify-between py-5 border-y border-zinc-100 dark:border-zinc-800">
          {[0, 1, 2].map((i) => (
            <div key={i} className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-xl bg-zinc-100 dark:bg-zinc-800" />
              <div className="h-4 w-8 rounded-full bg-zinc-100 dark:bg-zinc-800" />
            </div>
          ))}
        </div>
        <div className="flex items-center gap-3">
          <div className="flex-1 h-14 rounded-2xl bg-zinc-200 dark:bg-zinc-800" />
          <div className="w-14 h-14 rounded-2xl bg-zinc-100 dark:bg-zinc-800" />
        </div>
      </div>
    </div>
  );
}

export function PropertyGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-12">
      {Array.from({ length: count }).map((_, index) => (
        <PropertyCardSkeleton key={index} />
      ))}
    </div>
  );
}
