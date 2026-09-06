import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import Logo from "@/components/Logo";

/**
 * Shared frame for the sign-in / sign-up screens: the same gradient-blob
 * treatment as the hero, so auth does not feel like a different product.
 */
export default function AuthShell({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
  footer: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans flex flex-col items-center justify-center px-6 py-16 relative overflow-hidden selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <div className="absolute inset-0 -z-10 overflow-hidden" aria-hidden="true">
        <div className="absolute top-[-20%] left-[-10%] w-[50%] h-[50%] bg-blue-400/20 blur-[120px] rounded-full" />
        <div className="absolute bottom-[-20%] right-[-10%] w-[55%] h-[55%] bg-emerald-400/20 blur-[150px] rounded-full" />
      </div>

      <div className="w-full max-w-md space-y-8">
        <div className="flex items-center justify-between">
          <Logo size={44} />
          <Link
            href="/"
            className="flex items-center gap-1.5 text-xs font-black uppercase tracking-widest text-zinc-400 hover:text-blue-600 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            Home
          </Link>
        </div>

        <div className="space-y-3">
          <h1 className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white tracking-tighter leading-[0.95]">
            {title}
          </h1>
          <p className="text-zinc-500 dark:text-zinc-400 font-medium">{subtitle}</p>
        </div>

        <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] shadow-2xl shadow-blue-500/5">
          {children}
        </div>

        <div className="text-center text-sm font-bold text-zinc-500">{footer}</div>
      </div>
    </div>
  );
}

export function AuthField({
  label,
  error,
  children,
}: {
  label: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-2">
      <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{label}</span>
      {children}
      {error && <span className="block text-xs font-bold text-red-600">{error}</span>}
    </label>
  );
}

export const authInputClass =
  "w-full h-14 px-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors";
