import type { LucideIcon } from "lucide-react";
import { AlertTriangle } from "lucide-react";

/**
 * The back office's shared pieces, so every page has the same structure:
 * a header (title, one-line purpose, actions), panels, and the same badges,
 * empty and error states.
 */

export function PageHeader({
  title,
  description,
  actions,
  meta,
}: {
  title: string;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  /** Small counts under the description, e.g. "12 accounts". */
  meta?: React.ReactNode;
}) {
  return (
    <header className="flex flex-col md:flex-row md:items-end justify-between gap-5 pb-6 border-b border-zinc-200 dark:border-zinc-800">
      <div className="space-y-2 max-w-2xl">
        <h1 className="text-3xl md:text-4xl font-black text-zinc-900 dark:text-white tracking-tighter">{title}</h1>
        {description && <p className="text-zinc-500 font-medium leading-relaxed">{description}</p>}
        {meta && <div className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{meta}</div>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2 shrink-0">{actions}</div>}
    </header>
  );
}

export function Panel({
  title,
  description,
  actions,
  children,
  flush = false,
}: {
  title?: string;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  children: React.ReactNode;
  /** No inner padding — for tables and lists that run edge to edge. */
  flush?: boolean;
}) {
  return (
    <section className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] overflow-hidden">
      {(title || actions) && (
        <div className="flex flex-wrap items-start justify-between gap-3 px-6 pt-6 pb-4">
          <div className="space-y-1">
            {title && <h2 className="text-lg font-black text-zinc-900 dark:text-white tracking-tight">{title}</h2>}
            {description && <p className="text-sm font-medium text-zinc-500">{description}</p>}
          </div>
          {actions}
        </div>
      )}
      <div className={flush ? "" : "px-6 pb-6"}>{children}</div>
    </section>
  );
}

const TONES = {
  green: "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300",
  amber: "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300",
  blue: "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300",
  red: "bg-red-50 text-red-700 dark:bg-red-950/40 dark:text-red-300",
  purple: "bg-purple-50 text-purple-700 dark:bg-purple-950/40 dark:text-purple-300",
  zinc: "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400",
} as const;

export type Tone = keyof typeof TONES;

export function Badge({ tone = "zinc", children }: { tone?: Tone; children: React.ReactNode }) {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 rounded-full text-[10px] font-black uppercase tracking-[0.12em] whitespace-nowrap ${TONES[tone]}`}
    >
      {children}
    </span>
  );
}

export function EmptyState({ icon: Icon, title, text }: { icon: LucideIcon; title: string; text?: string }) {
  return (
    <div className="py-16 px-6 text-center space-y-3">
      <span className="w-14 h-14 rounded-2xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mx-auto">
        <Icon className="w-7 h-7 text-zinc-400" />
      </span>
      <p className="text-lg font-black text-zinc-900 dark:text-white">{title}</p>
      {text && <p className="text-sm text-zinc-500 font-medium max-w-md mx-auto">{text}</p>}
    </div>
  );
}

export function ErrorState({ text }: { text: string }) {
  return (
    <div className="flex items-start gap-3 p-5 rounded-[2rem] bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-900 text-red-700 dark:text-red-300 font-bold">
      <AlertTriangle className="w-5 h-5 shrink-0 mt-0.5" />
      {text}
    </div>
  );
}

/** A search box and filters that submit as a GET form, so filters live in the URL. */
export function Toolbar({ children }: { children: React.ReactNode }) {
  return <form className="flex flex-col sm:flex-row gap-3">{children}</form>;
}

export const toolbarInput =
  "h-12 px-5 flex-1 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-medium outline-none focus:border-blue-500";
export const toolbarSelect =
  "h-12 px-4 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-bold outline-none focus:border-blue-500";
export const toolbarButton =
  "h-12 px-6 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-sm font-black hover:opacity-90";

/** One row in a list panel. */
export function Row({ children, highlight = false }: { children: React.ReactNode; highlight?: boolean }) {
  return (
    <div
      className={`px-6 py-4 flex flex-col lg:flex-row lg:items-center gap-4 border-t border-zinc-100 dark:border-zinc-800 first:border-t-0 ${
        highlight ? "bg-blue-50/50 dark:bg-blue-950/20" : ""
      }`}
    >
      {children}
    </div>
  );
}
