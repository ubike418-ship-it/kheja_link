import { Moon, Phone, Mail, MapPin, Home } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import WaitlistStatusSelect from "@/components/admin/WaitlistStatusSelect";
import DeleteButton from "@/components/admin/DeleteButton";
import { EmptyState, ErrorState, PageHeader } from "@/components/admin/AdminUI";
import { deleteWaitlistEntryAction } from "@/lib/actions/admin";
import { formatRelativeDate } from "@/lib/format";
import type { StaysWaitlistRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Stays waitlist — Admin" };

export default async function StaysWaitlistPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("stays_waitlist")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(500);

  const rows = (data ?? []) as StaysWaitlistRow[];
  const fresh = rows.filter((r) => r.status === "new").length;

  return (
    <>
      <PageHeader
        title="Stays waitlist"
        description={
          <>
            People who want to host short stays once the feature launches. Stays is switched off (see{" "}
            <strong>Short-term Stays</strong> in Business settings), so nobody can list a short stay yet.
          </>
        }
        meta={`${rows.length} on the list · ${fresh} not contacted yet`}
      />

      {error ? (
        <ErrorState text="Could not load the waitlist. Refresh to try again." />
      ) : rows.length === 0 ? (
        <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem]">
          <EmptyState icon={Moon} title="No one yet" text="Hosts who register interest in the app appear here." />
        </div>
      ) : (
        <div className="grid md:grid-cols-2 2xl:grid-cols-3 gap-4">
          {rows.map((r) => (
            <article
              key={r.id}
              className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-4"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-lg font-black text-zinc-900 dark:text-white truncate">{r.full_name}</p>
                  <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                    Joined {formatRelativeDate(r.created_at)}
                  </p>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <WaitlistStatusSelect id={r.id} status={r.status} />
                  <DeleteButton
                    action={deleteWaitlistEntryAction.bind(null, r.id)}
                    itemName={`${r.full_name} from the waitlist`}
                  />
                </div>
              </div>
              <div className="space-y-1.5 text-sm font-bold text-zinc-600 dark:text-zinc-300">
                {r.phone && (
                  <a href={`tel:${r.phone}`} className="flex items-center gap-2 hover:text-blue-600">
                    <Phone className="w-4 h-4 text-zinc-400" /> {r.phone}
                  </a>
                )}
                {r.email && (
                  <a href={`mailto:${r.email}`} className="flex items-center gap-2 hover:text-blue-600 break-all">
                    <Mail className="w-4 h-4 text-zinc-400" /> {r.email}
                  </a>
                )}
                {r.location && (
                  <p className="flex items-center gap-2">
                    <MapPin className="w-4 h-4 text-zinc-400" /> {r.location}
                  </p>
                )}
                {(r.property_count || r.property_type) && (
                  <p className="flex items-center gap-2">
                    <Home className="w-4 h-4 text-zinc-400" />
                    {[
                      r.property_count
                        ? `${r.property_count} ${r.property_count === 1 ? "property" : "properties"}`
                        : null,
                      r.property_type,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                )}
              </div>
              {r.message && (
                <p className="text-sm font-medium text-zinc-500 leading-relaxed p-4 rounded-2xl bg-zinc-50 dark:bg-zinc-800/60">
                  {r.message}
                </p>
              )}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
