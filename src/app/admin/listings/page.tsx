import Link from "next/link";
import { Home, ExternalLink } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ActionSelect, ActionToggle } from "@/components/admin/AdminInlineForms";
import { setListingPremiumAction, setListingStatusAction } from "@/lib/actions/admin";
import { formatRelativeDate, formatRent } from "@/lib/format";
import type { PricePeriod, PropertyStatus } from "@/lib/supabase/database.types";

export const metadata = { title: "Listings — Admin" };

type Listing = {
  id: string;
  title: string;
  slug: string;
  status: PropertyStatus;
  availability: string;
  is_premium: boolean;
  price_amount: number;
  price_period: PricePeriod;
  price_currency: string;
  view_count: number;
  like_count: number;
  created_at: string;
  owner: { full_name: string | null } | null;
  location: { name: string } | null;
};

const STATUS_OPTIONS = [
  { value: "published", label: "Published" },
  { value: "draft", label: "Draft" },
  { value: "rented", label: "Rented" },
  { value: "archived", label: "Archived (hidden)" },
];

type Search = Promise<{ q?: string; status?: string }>;

/**
 * Every listing, drafts included. Admins can take a listing down (archive),
 * put it back, or mark it premium. Editing the details stays with the landlord.
 */
export default async function AdminListingsPage({ searchParams }: { searchParams: Search }) {
  const { q = "", status = "" } = await searchParams;
  const supabase = await createClient();

  let query = supabase
    .from("properties")
    .select(
      "id, title, slug, status, availability, is_premium, price_amount, price_period, price_currency, view_count, like_count, created_at, owner:profiles!properties_owner_id_fkey ( full_name ), location:locations ( name )",
    )
    .order("created_at", { ascending: false })
    .limit(500);
  if (status) query = query.eq("status", status as PropertyStatus);
  if (q.trim()) query = query.ilike("title", `%${q.trim().replace(/[%_]/g, "")}%`);

  const { data, error } = await query;
  const rows = (data ?? []) as unknown as Listing[];

  return (
    <div className="space-y-8">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Listings</h2>
        <p className="text-zinc-500 font-medium">
          Every listing on Kheja_Link. Archive anything misleading or fraudulent to take it off the
          site at once; landlords still edit their own details.
        </p>
      </div>

      <form className="flex flex-col sm:flex-row gap-3">
        <input
          name="q"
          defaultValue={q}
          placeholder="Search by title"
          className="h-12 px-5 flex-1 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-medium outline-none focus:border-blue-500"
        />
        <select
          name="status"
          defaultValue={status}
          className="h-12 px-4 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-bold outline-none"
        >
          <option value="">Every status</option>
          {STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
        <button className="h-12 px-6 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-sm font-black">
          Filter
        </button>
      </form>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load listings. Refresh to try again.
        </p>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <Home className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No listings match</p>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{rows.length} listings</p>
          {rows.map((p) => (
            <article
              key={p.id}
              className="p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] flex flex-col lg:flex-row lg:items-center gap-4"
            >
              <div className="min-w-0 flex-1 space-y-1">
                <Link
                  href={`/properties/${p.slug}`}
                  className="flex items-center gap-1.5 font-black text-zinc-900 dark:text-white hover:text-blue-600"
                >
                  <span className="truncate">{p.title}</span>
                  <ExternalLink className="w-3.5 h-3.5 shrink-0" />
                </Link>
                <p className="text-xs font-bold text-zinc-500">
                  {formatRent(p.price_amount, p.price_period, p.price_currency)} · {p.location?.name ?? "Meru"} ·{" "}
                  {p.owner?.full_name ?? "Landlord"}
                </p>
                <p className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-400">
                  Added {formatRelativeDate(p.created_at)} · {p.availability.replace("_", " ")} · {p.view_count} views ·{" "}
                  {p.like_count} likes
                </p>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <ActionSelect
                  label={`Status of ${p.title}`}
                  value={p.status}
                  options={
                    STATUS_OPTIONS.some((s) => s.value === p.status)
                      ? STATUS_OPTIONS
                      : [{ value: p.status, label: p.status }, ...STATUS_OPTIONS]
                  }
                  action={setListingStatusAction.bind(null, p.id)}
                />
                <ActionToggle
                  on={p.is_premium}
                  action={setListingPremiumAction.bind(null, p.id)}
                  labels={["Premium", "Standard"]}
                />
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
