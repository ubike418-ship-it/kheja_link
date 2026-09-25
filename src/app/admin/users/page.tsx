import { Users, Phone, Mail } from "lucide-react";
import { createClient, getCurrentProfile } from "@/lib/supabase/server";
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
} from "@/components/admin/AdminUI";
import { deleteUserAction, setUserRoleAction, setUserVerifiedAction } from "@/lib/actions/admin";
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

const ROLE_TONE = { seeker: "blue", landlord: "green", admin: "purple" } as const;

type Search = Promise<{ q?: string; role?: string }>;

/** Every account. Emails come from admin_list_users(), which is admin-only. */
export default async function AdminUsersPage({ searchParams }: { searchParams: Search }) {
  const { q = "", role = "" } = await searchParams;
  const supabase = await createClient();
  const [{ data, error }, me] = await Promise.all([supabase.rpc("admin_list_users"), getCurrentProfile()]);

  const all = (data ?? []) as AdminUser[];
  const term = q.trim().toLowerCase();
  const rows = all.filter(
    (u) =>
      (!role || u.role === role) &&
      (!term || [u.full_name, u.email, u.phone].some((v) => v?.toLowerCase().includes(term))),
  );
  const count = (r: UserRole) => all.filter((u) => u.role === r).length;

  return (
    <>
      <PageHeader
        title="Users"
        description="Every tenant, landlord and admin. Change a role, give a landlord the verified badge, or delete an account. Only make someone an admin if they work for Kheja_Link."
        meta={`${all.length} accounts · ${count("seeker")} tenants · ${count("landlord")} landlords · ${count("admin")} admins`}
      />

      <Toolbar>
        <input name="q" defaultValue={q} placeholder="Search name, email or phone" className={toolbarInput} />
        <select name="role" defaultValue={role} className={toolbarSelect}>
          <option value="">All roles</option>
          {ROLE_OPTIONS.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}s
            </option>
          ))}
        </select>
        <button className={toolbarButton}>Filter</button>
      </Toolbar>

      {error ? (
        <ErrorState text="Could not load accounts. Make sure migration 0016 has been run, then refresh." />
      ) : (
        <Panel title={`${rows.length} ${rows.length === 1 ? "account" : "accounts"}`} flush>
          {rows.length === 0 ? (
            <EmptyState icon={Users} title="No accounts match" text="Try another name, email or role." />
          ) : (
            rows.map((u) => {
              const isMe = u.id === me?.id;
              return (
                <Row key={u.id}>
                  <div className="flex items-center gap-4 min-w-0 flex-1">
                    <span className="w-11 h-11 rounded-2xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-sm font-black text-zinc-600 dark:text-zinc-300 shrink-0">
                      {(u.full_name ?? u.email ?? "?")[0]?.toUpperCase()}
                    </span>
                    <div className="min-w-0 space-y-1">
                      <p className="flex items-center gap-2 font-black text-zinc-900 dark:text-white">
                        <span className="truncate">{u.full_name ?? "No name"}</span>
                        <Badge tone={ROLE_TONE[u.role]}>{ROLE_OPTIONS.find((r) => r.value === u.role)?.label}</Badge>
                        {isMe && <Badge tone="blue">You</Badge>}
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
                    {!isMe && (
                      <DeleteButton
                        action={deleteUserAction.bind(null, u.id)}
                        itemName={`the account of ${u.full_name ?? u.email ?? "this user"}`}
                        consequence={`Their sign-in goes, and with it their ${u.listings} listing${u.listings === 1 ? "" : "s"}, unlocks, saved homes, messages and notifications.`}
                      />
                    )}
                  </div>
                </Row>
              );
            })
          )}
        </Panel>
      )}
    </>
  );
}
