import { Moon, Phone, Mail, MapPin, Home } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import WaitlistStatusSelect from "@/components/admin/WaitlistStatusSelect";
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

  return (
    <div className="space-y-8">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Stays waitlist</h2>
        <p className="text-zinc-500 font-medium">
          People who want to host short stays once the feature launches. Stays is switched off
          (see <strong>stays_enabled</strong> in Business settings); nobody can list a short stay yet.
        </p>
      </div>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load the waitlist. Refresh to try again.
        </p>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <Moon className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No one yet</p>
          <p className="text-zinc-500 font-medium">Hosts who register interest in the app appear here.</p>
        </div>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {rows.map((r) => (
            <div
              key={r.id}
              className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-4"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-lg font-black text-zinc-900 dark:text-white truncate">{r.full_name}</p>
                  <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                    {new Date(r.created_at).toLocaleDateString("en-KE", { day: "numeric", month: "short", year: "numeric" })}
                  </p>
                </div>
                <WaitlistStatusSelect id={r.id} status={r.status} />
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
                    {[r.property_count ? `${r.property_count} ${r.property_count === 1 ? "property" : "properties"}` : null, r.property_type]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                )}
              </div>
              {r.message && <p className="text-sm font-medium text-zinc-500 leading-relaxed">{r.message}</p>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
