import Link from "next/link";
import { Home, ExternalLink } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ActionSelect, ActionToggle } from "@/components/admin/AdminInlineForms";
import DeleteButton from "@/components/admin/DeleteButton";
import {
  Badge,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  Row,
  Toolbar,
  toolbarButton,
  toolbarInput,
  toolbarSelect,
  type Tone,
} from "@/components/admin/AdminUI";
import { deleteListingAction, setListingPremiumAction, setListingStatusAction } from "@/lib/actions/admin";
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

  const STATUS_TONE: Record<string, Tone> = {
    published: "green",
    draft: "amber",
    rented: "blue",
    archived: "zinc",
    pending: "amber",
  };

  return (
    <>
      <PageHeader
        title="Listings"
        description="Every listing on Kheja_Link, drafts included. Archive anything misleading to take it off the site at once, mark premium homes, or delete a listing for good. Landlords still edit their own details."
        meta={`${rows.length} shown`}
      />

      <Toolbar>
        <input name="q" defaultValue={q} placeholder="Search by title" className={toolbarInput} />
        <select name="status" defaultValue={status} className={toolbarSelect}>
          <option value="">Every status</option>
          {STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
        <button className={toolbarButton}>Filter</button>
      </Toolbar>

      {error ? (
        <ErrorState text="Could not load listings. Refresh to try again." />
      ) : (
        <Panel title={`${rows.length} ${rows.length === 1 ? "listing" : "listings"}`} flush>
          {rows.length === 0 ? (
            <EmptyState icon={Home} title="No listings match" text="Try another title or status." />
          ) : (
            rows.map((p) => (
              <Row key={p.id}>
                <div className="min-w-0 flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <Link
                      href={`/properties/${p.slug}`}
                      className="flex items-center gap-1.5 font-black text-zinc-900 dark:text-white hover:text-blue-600 min-w-0"
                    >
                      <span className="truncate">{p.title}</span>
                      <ExternalLink className="w-3.5 h-3.5 shrink-0" />
                    </Link>
                    <Badge tone={STATUS_TONE[p.status] ?? "zinc"}>{p.status}</Badge>
                    {p.is_premium && <Badge tone="purple">Premium</Badge>}
                  </div>
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
                  <DeleteButton
                    action={deleteListingAction.bind(null, p.id)}
                    itemName={`"${p.title}"`}
                    consequence="The listing, its photos list, saved-home entries, requests, messages and unlock records all go. Archiving hides it without deleting."
                  />
                </div>
              </Row>
            ))
          )}
        </Panel>
      )}
    </>
  );
}
