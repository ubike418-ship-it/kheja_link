import { PieChart } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import SettingRow from "@/components/admin/SettingRow";
import FeeAllocationForm from "@/components/admin/FeeAllocationForm";
import PaymentsHealth from "@/components/admin/PaymentsHealth";
import DeleteButton from "@/components/admin/DeleteButton";
import { Badge, EmptyState, ErrorState, PageHeader, Panel } from "@/components/admin/AdminUI";
import { deleteFeeAllocationAction } from "@/lib/actions/admin";
import type { AppSettingRow, FeeAllocationRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Business settings — Admin" };

/**
 * Shown here, grouped and in this order, with plain names. Anything else in
 * app_settings is internal (markers, the maintenance stamp, the retired
 * House Hunting pass).
 */
const GROUPS: { title: string; description: string; keys: [key: string, label: string][] }[] = [
  {
    title: "Pricing",
    description:
      "What unlocking a listing costs, how long it stays open, and the refund for giving us a house. The refund must stay below the unlock price.",
    keys: [
      ["contact_unlock_fee", "Unlock price"],
      ["contact_unlock_hours", "Unlock lasts (hours)"],
      ["house_refund_amount", "House refund"],
      ["contact_unlock_currency", "Currency"],
    ],
  },
  {
    title: "Listings",
    description: "What landlords pay to list, and the free-listing offer shown to them.",
    keys: [
      ["landlord_listing_fee", "Listing fee"],
      ["landlord_listing_fee_offer_label", "Offer wording"],
      ["landlord_listing_fee_offer_ends_on", "Offer ends on"],
    ],
  },
  {
    title: "Features",
    description: "Switch parts of the apps on or off without a new release.",
    keys: [
      ["tenant_notifications_enabled", "Vacancy and match alerts"],
      ["stays_enabled", "Short-term Stays"],
      ["service_provider_registration_enabled", "Provider self-registration"],
      ["service_provider_onboarding_fee", "Provider onboarding fee"],
    ],
  },
  {
    title: "Support line",
    description: "Kheja_Link's own number, released to tenants with an unlocked listing's contacts.",
    keys: [
      ["management_name", "Name shown"],
      ["management_phone", "Phone number"],
    ],
  },
];

export default async function SettingsPage() {
  const supabase = await createClient();
  const [{ data: settings, error }, { data: allocations }] = await Promise.all([
    supabase.from("app_settings").select("*"),
    supabase.from("fee_allocations").select("*").order("product").order("party"),
  ]);

  const byKey = new Map(((settings ?? []) as AppSettingRow[]).map((s) => [s.key, s]));
  const shares = (allocations ?? []) as FeeAllocationRow[];
  const lastRun = byKey.get("last_maintenance_at")?.value;

  const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://www.khejalink.name.ng").replace(/\/$/, "");

  return (
    <>
      <PageHeader
        title="Business settings"
        description="Prices and switches both apps read at runtime — change them here instead of in code. An unlock is always charged at the price set here when the tenant taps “Unlock contact”."
        meta={lastRun ? `Last daily maintenance: ${new Date(lastRun).toLocaleString("en-KE", { timeZone: "Africa/Nairobi" })}` : undefined}
      />

      <PaymentsHealth siteUrl={siteUrl} />

      {error ? (
        <ErrorState text="Could not load settings. Refresh to try again." />
      ) : byKey.size === 0 ? (
        <ErrorState text="No settings found. Run supabase/migrations/0012 to 0016 first." />
      ) : (
        GROUPS.map((group) => {
          const rows = group.keys
            .map(([key, label]) => ({ setting: byKey.get(key), label }))
            .filter((r): r is { setting: AppSettingRow; label: string } => !!r.setting);
          if (rows.length === 0) return null;
          return (
            <Panel key={group.title} title={group.title} description={group.description} flush>
              {rows.map((r) => (
                <SettingRow key={r.setting.key} setting={r.setting} label={r.label} />
              ))}
            </Panel>
          );
        })
      )}

      <Panel
        title="How fees are split"
        description="Each confirmed payment records the split in force at that moment, so changing a share only affects future payments. Whatever the active shares do not cover goes to the platform."
        flush
      >
        {shares.length === 0 ? (
          <EmptyState icon={PieChart} title="No shares yet" text="Everything goes to the platform until you add a share." />
        ) : (
          shares.map((a) => (
            <div
              key={a.id}
              className="px-6 py-4 border-t border-zinc-100 dark:border-zinc-800 first:border-t-0 flex flex-wrap items-center gap-4"
            >
              <div className="flex-1 min-w-0">
                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                  {a.product.replace(/_/g, " ")}
                </p>
                <p className="text-lg font-black text-zinc-900 dark:text-white capitalize">{a.party.replace(/_/g, " ")}</p>
              </div>
              {!a.is_active && <Badge>Inactive</Badge>}
              <p className={`text-2xl font-black tracking-tighter ${a.is_active ? "text-blue-600" : "text-zinc-400 line-through"}`}>
                {Number(a.share_percent)}%
              </p>
              <DeleteButton
                action={deleteFeeAllocationAction.bind(null, a.id)}
                itemName={`the ${a.party.replace(/_/g, " ")} share`}
                consequence="Future payments no longer give this party a share; payments already made keep the split they were recorded with."
              />
            </div>
          ))
        )}
        <div className="p-6 border-t border-zinc-100 dark:border-zinc-800">
          <FeeAllocationForm />
        </div>
      </Panel>
    </>
  );
}
