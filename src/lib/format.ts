import type { PricePeriod } from "./supabase/database.types";

const NUMBER = new Intl.NumberFormat("en-KE", { maximumFractionDigits: 0 });

const CURRENCY_SYMBOL: Record<string, string> = {
  KES: "KSh",
  USD: "$",
  EUR: "EUR",
  GBP: "GBP",
};

/**
 * "KSh 45,000" — matches the copy the design already used, but derived from a
 * real numeric column so it can also be sorted and range-filtered.
 */
export function formatPrice(amount: number, currency = "KES"): string {
  const symbol = CURRENCY_SYMBOL[currency?.trim()] ?? currency?.trim() ?? "KSh";
  return `${symbol} ${NUMBER.format(amount)}`;
}

/** "KSh 45,000 / month" */
export function formatRent(amount: number, period: PricePeriod = "month", currency = "KES"): string {
  return `${formatPrice(amount, currency)} / ${period}`;
}

/** "1,800 sqft" — null-safe, because size is optional on a listing. */
export function formatSize(sqft: number | null | undefined): string | null {
  if (!sqft) return null;
  return `${NUMBER.format(sqft)} sqft`;
}

/** "Makutano, Meru" */
export function formatLocation(
  location: { name: string; area?: string | null; county?: string } | null | undefined,
): string {
  if (!location) return "Location on request";
  const tail = location.county ?? location.area;
  return tail && tail !== location.name ? `${location.name}, ${tail}` : location.name;
}

export function formatRelativeDate(iso: string | null | undefined): string {
  if (!iso) return "";
  const then = new Date(iso).getTime();
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return `${days} days ago`;
  if (days < 30) return `${Math.floor(days / 7)} week${days < 14 ? "" : "s"} ago`;
  if (days < 365) return `${Math.floor(days / 30)} month${days < 60 ? "" : "s"} ago`;
  return new Date(iso).toLocaleDateString("en-KE", { month: "short", year: "numeric" });
}

/** URL-safe slug, with a short random suffix so listing titles can repeat. */
export function slugify(input: string, withSuffix = true): string {
  const base = input
    .toLowerCase()
    // NFKD splits accents into combining marks, which the next line then drops.
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  const safe = base || "listing";
  return withSuffix ? `${safe}-${Math.random().toString(36).slice(2, 7)}` : safe;
}

/** Strips everything but digits and a leading +, for tel: and wa.me links. */
export function normalisePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const cleaned = phone.replace(/[^\d+]/g, "");
  return cleaned.replace(/\D/g, "").length >= 7 ? cleaned : null;
}

export function whatsappLink(phone: string | null | undefined, message?: string): string | null {
  const cleaned = normalisePhone(phone);
  if (!cleaned) return null;
  const digits = cleaned.replace(/\D/g, "");
  const query = message ? `?text=${encodeURIComponent(message)}` : "";
  return `https://wa.me/${digits}${query}`;
}

/**
 * How a listing's availability reads to a tenant. Null when the home is simply
 * free now, so cards stay clean. Mirrors Property.availabilityLabel in the app.
 */
export function availabilityLabel(
  availability: string | null | undefined,
  availableFrom: string | null | undefined,
): { label: string; tone: "amber" | "purple" | "zinc" } | null {
  const date = availableFrom
    ? new Date(availableFrom).toLocaleDateString("en-KE", { day: "numeric", month: "short" })
    : null;
  switch (availability) {
    case "notice_given":
      return { label: date ? `Available from ${date}` : "Coming available", tone: "purple" };
    case "occupied":
      return { label: "Currently occupied", tone: "amber" };
    case "unavailable":
      return { label: "Temporarily unavailable", tone: "zinc" };
    default:
      return null;
  }
}
