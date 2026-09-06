/** Consistent status chip for a listing, used across the dashboard. */
export default function StatusPill({ status }: { status: string }) {
  const tone =
    status === "published"
      ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300"
      : status === "draft"
        ? "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300"
        : status === "rented"
          ? "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300"
          : "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400";

  return (
    <span
      className={`px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-widest shrink-0 ${tone}`}
    >
      {status}
    </span>
  );
}
