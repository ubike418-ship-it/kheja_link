import { createClient } from "@/lib/supabase/server";
import SettingRow from "@/components/admin/SettingRow";
import FeeAllocationForm from "@/components/admin/FeeAllocationForm";
import PaymentsHealth from "@/components/admin/PaymentsHealth";
import type { AppSettingRow, FeeAllocationRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Business settings — Admin" };

/** Shown here in this order; anything else in app_settings is internal. */
const EDITABLE = [
  "hunting_fee",
  "hunting_fee_currency",
  "hunting_fee_unlocks_contacts",
  "contact_unlock_fee",
  "landlord_listing_fee",
  "landlord_listing_fee_offer_label",
  "landlord_listing_fee_offer_ends_on",
  "stays_enabled",
  "service_provider_registration_enabled",
  "service_provider_onboarding_fee",
  "tenant_notifications_enabled",
  "management_name",
  "management_phone",
];

export default async function SettingsPage() {
  const supabase = await createClient();
  const [{ data: settings, error }, { data: allocations }] = await Promise.all([
    supabase.from("app_settings").select("*"),
    supabase.from("fee_allocations").select("*").order("product").order("party"),
  ]);

  const byKey = new Map(((settings ?? []) as AppSettingRow[]).map((s) => [s.key, s]));
  const rows = EDITABLE.map((key) => byKey.get(key)).filter((s): s is AppSettingRow => !!s);
  const shares = (allocations ?? []) as FeeAllocationRow[];
  const lastRun = byKey.get("last_maintenance_at")?.value;

  const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://www.khejalink.name.ng").replace(/\/$/, "");

  return (
    <div className="space-y-12">
      <PaymentsHealth siteUrl={siteUrl} />

      <section className="space-y-6">
        <div className="space-y-2 max-w-2xl">
          <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Business settings</h2>
          <p className="text-zinc-500 font-medium">
            Prices and switches both apps read at runtime — change them here instead of in code. The
            hunting fee is always charged at the amount set here when the tenant starts paying.
          </p>
          {lastRun && (
            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
              Last daily maintenance: {new Date(lastRun).toLocaleString("en-KE")}
            </p>
          )}
        </div>

        {error ? (
          <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
            Could not load settings. Refresh to try again.
          </p>
        ) : rows.length === 0 ? (
          <p className="p-6 rounded-[2rem] bg-amber-50 dark:bg-amber-950/30 text-amber-800 dark:text-amber-300 font-bold">
            No settings found. Run supabase/migrations/0012_hunting_availability_requests.sql first.
          </p>
        ) : (
          <div className="space-y-3">
            {rows.map((s) => (
              <SettingRow key={s.key} setting={s} />
            ))}
          </div>
        )}
      </section>

      <section className="space-y-6">
        <div className="space-y-2 max-w-2xl">
          <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">How fees are split</h2>
          <p className="text-zinc-500 font-medium">
            Each confirmed payment records the split in force at that moment, so changing a share
            only affects future payments. Whatever the active shares do not cover goes to the platform.
          </p>
        </div>

        <div className="grid gap-3">
          {shares.map((a) => (
            <div
              key={a.id}
              className="p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] flex flex-wrap items-center justify-between gap-3"
            >
              <div>
                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                  {a.product.replace(/_/g, " ")}
                </p>
                <p className="text-lg font-black text-zinc-900 dark:text-white">{a.party.replace(/_/g, " ")}</p>
              </div>
              <p className={`text-2xl font-black tracking-tighter ${a.is_active ? "text-blue-600" : "text-zinc-400 line-through"}`}>
                {Number(a.share_percent)}%
              </p>
            </div>
          ))}
        </div>

        <FeeAllocationForm />
      </section>
    </div>
  );
}
