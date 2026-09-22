import { CheckCircle2, XCircle, AlertTriangle, Webhook } from "lucide-react";
import { paystack } from "@/lib/payments/paystack";

/**
 * Is money actually going to work? Checked live, on the server, so the answer
 * is about production rather than about what someone remembers configuring.
 *
 * Nothing secret is rendered — only whether a key is present, and what
 * Paystack says back when we use it.
 */

type Row = { ok: boolean; label: string; detail: string };

export default async function PaymentsHealth({ siteUrl }: { siteUrl: string }) {
  const secret = process.env.PAYSTACK_SECRET_KEY ?? "";
  const hasService = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
  const mode = secret.startsWith("sk_live_")
    ? "live"
    : secret.startsWith("sk_test_")
      ? "test"
      : null;

  const rows: Row[] = [];

  if (!secret) {
    rows.push({
      ok: false,
      label: "Paystack key",
      detail: "PAYSTACK_SECRET_KEY is not set on this deployment. Payments cannot start.",
    });
  } else {
    const balance = await paystack<{ currency: string; balance: number }[]>("/balance");
    rows.push(
      mode === "live"
        ? { ok: true, label: "Paystack key", detail: "Live key (sk_live_…)." }
        : {
            ok: false,
            label: "Paystack key",
            detail:
              mode === "test"
                ? "Test key (sk_test_…). Real money will not move until you use the live key."
                : "The key does not look like a Paystack secret key.",
          },
    );
    rows.push(
      balance.ok
        ? {
            ok: true,
            label: "Paystack connection",
            detail: `Connected. Account currencies: ${
              (balance.data ?? []).map((b) => b.currency).join(", ") || "none returned"
            }.`,
          }
        : {
            ok: false,
            label: "Paystack connection",
            detail: balance.message || "Paystack refused the key.",
          },
    );

    const kes = (balance.data ?? []).some((b) => b.currency === "KES");
    if (balance.ok && !kes) {
      rows.push({
        ok: false,
        label: "KES payments",
        detail:
          "This Paystack account does not show a KES balance. Ask Paystack to enable Kenya / KES, " +
          "or M-Pesa charges will be rejected.",
      });
    }
  }

  rows.push(
    hasService
      ? { ok: true, label: "Payment confirmation", detail: "The server can record confirmed payments." }
      : {
          ok: false,
          label: "Payment confirmation",
          detail:
            "SUPABASE_SERVICE_ROLE_KEY is not set. Paystack's webhook cannot be verified and paid " +
            "money would not unlock anything. Add it in Vercel and redeploy.",
        },
  );

  const healthy = rows.every((r) => r.ok);

  return (
    <section className="space-y-6">
      <div className="space-y-2 max-w-2xl">
        <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Payments</h2>
        <p className="text-zinc-500 font-medium">
          Tenants pay inside Kheja_Link&apos;s own screens — they choose M-Pesa and approve the
          prompt on their phone. Paystack is used as the payment processor behind that.
        </p>
      </div>

      <div
        className={`p-6 rounded-[2rem] border ${
          healthy
            ? "bg-emerald-50 dark:bg-emerald-950/20 border-emerald-200 dark:border-emerald-900"
            : "bg-amber-50 dark:bg-amber-950/20 border-amber-200 dark:border-amber-900"
        }`}
      >
        <p className="flex items-center gap-2 font-black text-zinc-900 dark:text-white">
          {healthy ? (
            <CheckCircle2 className="w-5 h-5 text-emerald-600" />
          ) : (
            <AlertTriangle className="w-5 h-5 text-amber-600" />
          )}
          {healthy ? "Payments are ready" : "Payments need attention"}
        </p>
        <ul className="mt-4 space-y-3">
          {rows.map((r) => (
            <li key={r.label} className="flex items-start gap-3">
              {r.ok ? (
                <CheckCircle2 className="w-4 h-4 mt-0.5 text-emerald-600 shrink-0" />
              ) : (
                <XCircle className="w-4 h-4 mt-0.5 text-red-600 shrink-0" />
              )}
              <span className="text-sm">
                <span className="font-black text-zinc-900 dark:text-white">{r.label}: </span>
                <span className="font-medium text-zinc-600 dark:text-zinc-300">{r.detail}</span>
              </span>
            </li>
          ))}
        </ul>
      </div>

      <div className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] space-y-3">
        <p className="flex items-center gap-2 font-black text-zinc-900 dark:text-white">
          <Webhook className="w-5 h-5 text-blue-600" />
          Webhook URL
        </p>
        <p className="text-sm font-medium text-zinc-500">
          Paste this into Paystack → Settings → API Keys &amp; Webhooks → <strong>Webhook URL</strong>,
          for the live environment:
        </p>
        <code className="block p-4 bg-zinc-50 dark:bg-zinc-800 rounded-2xl text-sm font-bold break-all text-zinc-900 dark:text-white">
          {siteUrl}/api/payments/webhook
        </code>
        <p className="text-xs font-medium text-zinc-500">
          Paystack signs every event; anything unsigned is rejected. A payment also completes
          without the webhook, because the app asks the server to verify it with Paystack.
        </p>
      </div>
    </section>
  );
}
