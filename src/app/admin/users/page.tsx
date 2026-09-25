import { Users, Phone, Mail } from "lucide-react";
import { createClient, getCurrentProfile } from "@/lib/supabase/server";
import { ActionSelect, ActionToggle } from "@/components/admin/AdminInlineForms";
import { setUserRoleAction, setUserVerifiedAction } from "@/lib/actions/admin";
import { formatRelativeDate } from "@/lib/format";
import type { UserRole } from "@/lib/supabase/database.types";

export const metadata = { title: "Users — Admin" };

type AdminUser = {
  id: string;
  email: string | null;
  full_name: string | null;
  phone: string | null;
  role: UserRole;
  is_verified: boolean;
  created_at: string;
  last_sign_in_at: string | null;
  listings: number;
  unlocks: number;
};

const ROLE_OPTIONS = [
  { value: "seeker", label: "Tenant" },
  { value: "landlord", label: "Landlord" },
  { value: "admin", label: "Admin" },
];

type Search = Promise<{ q?: string; role?: string }>;

/** Every account. Emails come from admin_list_users(), which is admin-only. */
export default async function AdminUsersPage({ searchParams }: { searchParams: Search }) {
  const { q = "", role = "" } = await searchParams;
  const supabase = await createClient();
  const [{ data, error }, me] = await Promise.all([supabase.rpc("admin_list_users"), getCurrentProfile()]);

  const term = q.trim().toLowerCase();
  const rows = ((data ?? []) as AdminUser[]).filter(
    (u) =>
      (!role || u.role === role) &&
      (!term ||
        [u.full_name, u.email, u.phone].some((v) => v?.toLowerCase().includes(term))),
  );

  return (
    <div className="space-y-8">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Users</h2>
        <p className="text-zinc-500 font-medium">
          Every tenant, landlord and admin. Change a role or give a landlord the verified badge. Only
          make someone an admin if they work for Kheja_Link — admins see every payment and message.
        </p>
      </div>

      <form className="flex flex-col sm:flex-row gap-3">
        <input
          name="q"
          defaultValue={q}
          placeholder="Search name, email or phone"
          className="h-12 px-5 flex-1 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-medium outline-none focus:border-blue-500"
        />
        <select
          name="role"
          defaultValue={role}
          className="h-12 px-4 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl text-sm font-bold outline-none"
        >
          <option value="">All roles</option>
          {ROLE_OPTIONS.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}s
            </option>
          ))}
        </select>
        <button className="h-12 px-6 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-sm font-black">
          Filter
        </button>
      </form>

      {error ? (
        <p className="p-6 rounded-[2rem] bg-red-50 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold">
          Could not load accounts. Make sure migration 0016 has been run, then refresh.
        </p>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center space-y-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[3rem]">
          <Users className="w-12 h-12 text-zinc-300 mx-auto" />
          <p className="text-xl font-black text-zinc-900 dark:text-white">No accounts match</p>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{rows.length} accounts</p>
          {rows.map((u) => (
            <article
              key={u.id}
              className="p-5 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] flex flex-col lg:flex-row lg:items-center gap-4"
            >
              <div className="min-w-0 flex-1 space-y-1">
                <p className="font-black text-zinc-900 dark:text-white truncate">
                  {u.full_name ?? "No name"} {u.id === me?.id && <span className="text-blue-600">(you)</span>}
                </p>
                <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs font-bold text-zinc-500">
                  {u.email && (
                    <span className="flex items-center gap-1.5 break-all">
                      <Mail className="w-3.5 h-3.5" /> {u.email}
                    </span>
                  )}
                  {u.phone && (
                    <a href={`tel:${u.phone}`} className="flex items-center gap-1.5 hover:text-blue-600">
                      <Phone className="w-3.5 h-3.5" /> {u.phone}
                    </a>
                  )}
                </div>
                <p className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-400">
                  Joined {formatRelativeDate(u.created_at)} · last sign-in{" "}
                  {u.last_sign_in_at ? formatRelativeDate(u.last_sign_in_at) : "never"} · {u.listings} listings ·{" "}
                  {u.unlocks} unlocks
                </p>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <ActionSelect
                  label={`Role of ${u.full_name ?? "this account"}`}
                  value={u.role}
                  options={ROLE_OPTIONS}
                  action={setUserRoleAction.bind(null, u.id)}
                  confirm={{
                    value: "admin",
                    message: `Make ${u.full_name ?? "this account"} an admin? They will see every payment, message and account.`,
                  }}
                />
                {u.role === "landlord" && (
                  <ActionToggle
                    on={u.is_verified}
                    action={setUserVerifiedAction.bind(null, u.id)}
                    labels={["Verified", "Not verified"]}
                  />
                )}
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
