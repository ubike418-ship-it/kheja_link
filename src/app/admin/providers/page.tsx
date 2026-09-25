import Link from "next/link";
import { Plus, Truck, Wifi, Sparkles, Phone, Mail, MapPin } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import ProviderRowActions from "@/components/admin/ProviderRowActions";
import { EmptyState, ErrorState, PageHeader, Panel } from "@/components/admin/AdminUI";
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

  const live = providers.filter((p) => p.is_active && p.approval_status === "approved").length;

  return (
    <>
      <PageHeader
        title="Service providers"
        description={
          <>
            Movers, internet and cleaning companies are onboarded by the Kheja_Link team — there is no
            public sign-up. Only providers that are <strong>approved</strong> and <strong>live</strong>{" "}
            appear under listings in the app.
          </>
        }
        meta={`${providers.length} providers · ${live} live`}
        actions={
          <Link
            href="/admin/providers/new"
            className="flex items-center justify-center gap-2 px-5 h-11 bg-blue-600 text-white rounded-2xl text-sm font-black hover:bg-blue-700 transition-colors shadow-lg shadow-blue-600/20"
          >
            <Plus className="w-4 h-4" />
            Add provider
          </Link>
        }
      />

      {error ? (
        <ErrorState text="Could not load providers. Refresh to try again." />
      ) : providers.length === 0 ? (
        <Panel>
          <EmptyState icon={Truck} title="No providers yet" text="Add the first company you have an agreement with." />
        </Panel>
      ) : (
        <Panel title={`${providers.length} ${providers.length === 1 ? "provider" : "providers"}`} flush>
        <div>
          {providers.map((p) => {
            const Category = CATEGORY[p.category] ?? CATEGORY.movers;
            return (
              <div
                key={p.id}
                className="px-6 py-5 border-t border-zinc-100 dark:border-zinc-800 first:border-t-0 flex flex-col lg:flex-row lg:items-center gap-5"
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
        </Panel>
      )}
    </>
  );
}
