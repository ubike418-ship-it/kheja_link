import Link from "next/link";
import { Plus, Truck, Wifi, Sparkles, Phone, Mail, MapPin } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import ProviderRowActions from "@/components/admin/ProviderRowActions";
import type { PartnerRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Service providers — Admin" };

const CATEGORY = {
  movers: { label: "Movers", icon: Truck },
  isp: { label: "Internet", icon: Wifi },
  cleaning: { label: "Cleaning", icon: Sparkles },
} as const;

function StatusBadge({ provider }: { provider: PartnerRow }) {
  const live = provider.is_active && provider.approval_status === "approved";
  const tone = live
    ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300"
    : provider.approval_status === "rejected"
      ? "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300"
      : provider.approval_status === "pending"
        ? "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300"
        : "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400";
  const label = live ? "Live" : provider.approval_status === "approved" ? "Disabled" : provider.approval_status;
  return (
    <span className={`px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-widest ${tone}`}>
      {label}
    </span>
  );
}

export default async function ProvidersPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("partners")
    .select("*")
    .order("category")
    .order("sort_order");

  const providers = (data ?? []) as PartnerRow[];

  return (
    <div className="space-y-8">
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
        <div className="space-y-2 max-w-2xl">
          <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
            Service providers
          </h2>
          <p className="text-zinc-500 font-medium">
            Movers, internet and cleaning companies are onboarded by the Kheja_Link team — there is
            no public sign-up. Only providers that are <strong>approved</strong> and{" "}
            <strong>live</strong> appear under listings in the app.
          </p>
        </div>
        <Link
          href="/admin/providers/new"
          className="flex items-center justify-center gap-2 px-6 h-14 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors shadow-lg shadow-blue-600/20 shrink-0"
        >
          <Plus className="w-5 h-5" />
          Add provider
        </Link>
      </div>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load providers. Refresh to try again.
        </p>
      ) : providers.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <Truck className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No providers yet</p>
          <p className="text-zinc-500 font-medium">Add the first company you have an agreement with.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {providers.map((p) => {
            const Category = CATEGORY[p.category] ?? CATEGORY.movers;
            return (
              <div
                key={p.id}
                className="p-5 sm:p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] flex flex-col lg:flex-row lg:items-center gap-5"
              >
                <div className="flex items-start gap-4 min-w-0 flex-1">
                  <div
                    className="w-16 h-16 rounded-2xl bg-white border border-zinc-200 dark:border-zinc-700 flex items-center justify-center overflow-hidden shrink-0"
                    style={{ color: p.brand_color }}
                  >
                    {p.logo_url ? (
                      <img src={p.logo_url} alt="" className="w-full h-full object-contain p-1.5" />
                    ) : (
                      <Category.icon className="w-7 h-7" />
                    )}
                  </div>
                  <div className="min-w-0 space-y-1.5">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="text-lg font-black text-zinc-900 dark:text-white truncate">{p.name}</p>
                      <StatusBadge provider={p} />
                      {p.is_ours && (
                        <span className="px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-widest bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300">
                          Partner
                        </span>
                      )}
                    </div>
                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                      {Category.label}
                      {p.tagline ? ` · ${p.tagline}` : ""}
                    </p>
                    <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm font-bold text-zinc-500">
                      {p.phone && (
                        <span className="inline-flex items-center gap-1.5">
                          <Phone className="w-3.5 h-3.5" /> {p.phone}
                        </span>
                      )}
                      {p.email && (
                        <span className="inline-flex items-center gap-1.5 break-all">
                          <Mail className="w-3.5 h-3.5" /> {p.email}
                        </span>
                      )}
                      {p.location && (
                        <span className="inline-flex items-center gap-1.5">
                          <MapPin className="w-3.5 h-3.5" /> {p.location}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
                <ProviderRowActions
                  id={p.id}
                  approvalStatus={p.approval_status}
                  isActive={p.is_active}
                  name={p.name}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
