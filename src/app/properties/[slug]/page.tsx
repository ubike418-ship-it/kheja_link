import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  BedDouble,
  Bath,
  Square,
  MapPin,
  Phone,
  MessageCircle,
  ShieldCheck,
  CalendarDays,
  Eye,
  Wallet,
  ArrowLeft,
  Sparkles,
  Lock,
} from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import PropertyCard from "@/components/PropertyCard";
import PropertyGallery from "@/components/PropertyGallery";
import InquiryForm from "@/components/InquiryForm";
import FavoriteButton from "@/components/FavoriteButton";
import { getPropertyBySlug, getSimilarProperties, recordPropertyView } from "@/lib/queries/properties";
import { getFavoriteIds, withFavoriteState } from "@/lib/queries/favorites";
import { getCurrentProfile, getCurrentUser } from "@/lib/supabase/server";
import {
  availabilityLabel,
  formatLocation,
  formatRelativeDate,
  formatRent,
  formatSize,
  normalisePhone,
  whatsappLink,
} from "@/lib/format";

export const dynamic = "force-dynamic";

type Params = Promise<{ slug: string }>;

export async function generateMetadata({ params }: { params: Params }): Promise<Metadata> {
  const { slug } = await params;
  const property = await getPropertyBySlug(slug).catch(() => null);

  if (!property) return { title: "Home not found" };

  const where = formatLocation(property.location);
  const rent = formatRent(property.price_amount, property.price_period, property.price_currency);

  return {
    title: property.title,
    description:
      property.description?.slice(0, 160) ??
      `${property.title} in ${where} — ${rent} on Kheja_Link.`,
    openGraph: {
      title: `${property.title} — ${rent}`,
      description: `${where} · ${property.property_type?.name ?? "Rental"} on Kheja_Link`,
      images: property.images[0]?.public_url ? [property.images[0].public_url] : undefined,
    },
  };
}

export default async function PropertyDetailPage({
  params,
  searchParams,
}: {
  params: Params;
  searchParams: Promise<{ report?: string }>;
}) {
  const { slug } = await params;
  const reporting = (await searchParams).report === "1";

  const [property, profile, user] = await Promise.all([
    getPropertyBySlug(slug).catch(() => null),
    getCurrentProfile(),
    getCurrentUser(),
  ]);

  if (!property) notFound();

  // Owners can preview their own drafts; everyone else only sees published homes.
  const isOwner = property.owner_id === user?.id;
  if (property.status !== "published" && !isOwner) notFound();

  const [favoriteIds, similar] = await Promise.all([
    getFavoriteIds(),
    getSimilarProperties(property),
  ]);
  const similarWithState = await withFavoriteState(similar);

  if (property.status === "published") void recordPropertyView(property.id);

  const phone = normalisePhone(property.contact_phone);
  const whatsapp = whatsappLink(
    property.contact_whatsapp ?? property.contact_phone,
    `Hi, I saw "${property.title}" on Kheja_Link. Is it still available?`,
  );
  const size = formatSize(property.size_sqft);
  const availability = availabilityLabel(property.availability, property.available_from);

  const facts = [
    property.bedrooms > 0 && { icon: BedDouble, label: "Bedrooms", value: String(property.bedrooms) },
    property.bathrooms > 0 && { icon: Bath, label: "Bathrooms", value: String(property.bathrooms) },
    size && { icon: Square, label: "Size", value: size },
    {
      icon: Wallet,
      label: "Deposit",
      value: `${property.deposit_months} ${property.deposit_months === 1 ? "month" : "months"}`,
    },
    property.available_from && {
      icon: CalendarDays,
      label: "Available",
      value: new Date(property.available_from).toLocaleDateString("en-KE", {
        day: "numeric",
        month: "short",
        year: "numeric",
      }),
    },
    { icon: Eye, label: "Views", value: String(property.view_count) },
  ].filter(Boolean) as { icon: typeof BedDouble; label: string; value: string }[];

  return (
    <div className="min-h-screen bg-[#fafafa] dark:bg-black font-sans selection:bg-blue-100 dark:selection:bg-blue-900/30">
      <Navbar profile={profile} />

      <main className="pt-32 md:pt-40 pb-32 px-6">
        <div className="max-w-7xl mx-auto space-y-12">
          <Link
            href="/properties"
            className="inline-flex items-center gap-2 text-sm font-black text-zinc-500 hover:text-blue-600 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            Back to search
          </Link>

          {isOwner && property.status !== "published" && (
            <div className="px-6 py-4 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-3xl">
              <p className="text-sm font-bold text-amber-900 dark:text-amber-200">
                This listing is a <strong>{property.status}</strong> — only you can see it. Publish it
                from your dashboard to make it visible to house hunters.
              </p>
            </div>
          )}

          {/* Header */}
          <header className="flex flex-col lg:flex-row lg:items-end justify-between gap-8">
            <div className="space-y-4">
              <div className="flex flex-wrap items-center gap-2">
                <span className="px-4 py-2 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl text-[10px] font-black uppercase tracking-widest">
                  {property.property_type?.name ?? "Rental"}
                </span>
                {property.is_premium && (
                  <span className="px-4 py-2 bg-amber-500 text-white rounded-2xl text-[10px] font-black uppercase tracking-widest">
                    Premium
                  </span>
                )}
                {property.is_furnished && (
                  <span className="px-4 py-2 bg-emerald-600 text-white rounded-2xl text-[10px] font-black uppercase tracking-widest">
                    Furnished
                  </span>
                )}
                {availability && (
                  <span
                    className={`px-4 py-2 text-white rounded-2xl text-[10px] font-black uppercase tracking-widest ${
                      availability.tone === "purple"
                        ? "bg-purple-600"
                        : availability.tone === "amber"
                          ? "bg-orange-600"
                          : "bg-zinc-600"
                    }`}
                  >
                    {availability.label}
                  </span>
                )}
              </div>
              <h1 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter leading-[0.95]">
                {property.title}
              </h1>
              <div className="flex items-center gap-1.5 text-zinc-500 dark:text-zinc-400">
                <MapPin className="w-5 h-5 text-blue-500 shrink-0" />
                <span className="font-bold">
                  {formatLocation(property.location)}
                </span>
              </div>
            </div>

            <div className="space-y-3 shrink-0">
              <div>
                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                  {property.price_period === "year" ? "Annual Rent" : "Monthly Rent"}
                </p>
                <p className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white tracking-tighter">
                  {formatRent(
                    property.price_amount,
                    property.price_period,
                    property.price_currency,
                  ).replace(/ \/ (month|year)$/, "")}
                </p>
              </div>
              <FavoriteButton
                propertyId={property.id}
                initiallyFavorited={favoriteIds.has(property.id)}
              />
            </div>
          </header>

          <div className="grid grid-cols-1 lg:grid-cols-[1.6fr_1fr] gap-12">
            {/* Left column */}
            <div className="space-y-12 min-w-0">
              <PropertyGallery images={property.images} title={property.title} />

              {/* Key facts */}
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                {facts.map((fact) => (
                  <div
                    key={fact.label}
                    className="p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl space-y-2"
                  >
                    <fact.icon className="w-5 h-5 text-blue-600" />
                    <p className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                      {fact.label}
                    </p>
                    <p className="text-lg font-black text-zinc-900 dark:text-white">{fact.value}</p>
                  </div>
                ))}
              </div>

              {property.description && (
                <section className="space-y-4">
                  <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
                    About this home
                  </h2>
                  <p className="text-lg leading-relaxed font-medium text-zinc-600 dark:text-zinc-400 whitespace-pre-line">
                    {property.description}
                  </p>
                </section>
              )}

              {property.amenities.length > 0 && (
                <section className="space-y-6">
                  <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
                    What&apos;s included
                  </h2>
                  <div className="flex flex-wrap gap-3">
                    {property.amenities.map((amenity) => (
                      <span
                        key={amenity.id}
                        className="flex items-center gap-2 px-5 h-12 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl font-bold text-sm text-zinc-700 dark:text-zinc-300"
                      >
                        <Sparkles className="w-4 h-4 text-blue-500" />
                        {amenity.name}
                      </span>
                    ))}
                  </div>
                </section>
              )}

              <section className="space-y-4">
                <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">
                  Location
                </h2>
                <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-4">
                  <div className="flex items-start gap-4">
                    <span className="w-12 h-12 rounded-2xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center shrink-0">
                      <MapPin className="w-6 h-6 text-blue-600" />
                    </span>
                    <div>
                      <p className="text-lg font-black text-zinc-900 dark:text-white">
                        {property.location?.name ?? "Meru"}
                      </p>
                      <p className="text-sm font-medium text-zinc-500">
                        {[property.location?.area, property.location?.county]
                          .filter(Boolean)
                          .join(", ")}
                      </p>
                    </div>
                  </div>
                  {property.nearby && (
                    <p className="text-base font-medium text-zinc-600 dark:text-zinc-300 leading-relaxed whitespace-pre-line">
                      {property.nearby}
                    </p>
                  )}
                  {!isOwner && (
                    <p className="flex items-start gap-2 p-4 rounded-2xl bg-zinc-50 dark:bg-zinc-800/60 text-sm font-bold text-zinc-500">
                      <Lock className="w-4 h-4 mt-0.5 shrink-0 text-blue-600" />
                      The exact street, building and Google Maps pin open with the landlord&apos;s
                      contact when you tap &ldquo;Unlock contact&rdquo; in the app.
                    </p>
                  )}
                </div>
              </section>
            </div>

            {/* Right column — sticky contact rail */}
            <aside id="contact" className="space-y-6 lg:sticky lg:top-32 lg:self-start scroll-mt-32">
              <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-6">
                <div className="flex items-center gap-4">
                  <span className="w-14 h-14 rounded-2xl bg-blue-600 text-white flex items-center justify-center text-xl font-black">
                    {property.owner?.full_name?.[0]?.toUpperCase() ?? "K"}
                  </span>
                  <div className="min-w-0">
                    <p className="font-black text-zinc-900 dark:text-white truncate">
                      {property.owner?.full_name ?? "Kheja_Link Landlord"}
                    </p>
                    <p className="flex items-center gap-1 text-[10px] font-black uppercase tracking-widest text-zinc-400">
                      {property.owner?.is_verified && (
                        <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
                      )}
                      {property.owner?.is_verified ? "Verified landlord" : "Landlord"}
                    </p>
                  </div>
                </div>

                {property.published_at && (
                  <p className="text-xs font-bold text-zinc-400">
                    Listed {formatRelativeDate(property.published_at).toLowerCase()}
                  </p>
                )}

                <div className="space-y-3">
                  {phone && (
                    <a
                      href={`tel:${phone}`}
                      className="w-full h-14 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl font-black flex items-center justify-center gap-2 hover:scale-[1.02] transition-transform"
                    >
                      <Phone className="w-5 h-5" />
                      Call landlord
                    </a>
                  )}
                  {whatsapp && (
                    <a
                      href={whatsapp}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="w-full h-14 bg-emerald-600 text-white rounded-2xl font-black flex items-center justify-center gap-2 hover:bg-emerald-700 transition-colors"
                    >
                      <MessageCircle className="w-5 h-5" />
                      WhatsApp
                    </a>
                  )}
                </div>
              </div>

              {!isOwner && (
                <div className="p-8 bg-gradient-to-br from-blue-600 to-blue-700 text-white rounded-[2.5rem] space-y-5">
                  <div className="flex items-center gap-2 text-[10px] font-black uppercase tracking-[0.2em] text-blue-100">
                    <Lock className="w-4 h-4" />
                    Unlock contact
                  </div>
                  {/* No price here on purpose: the amount first appears on the payment
                      screen in the app, after the tenant taps "Unlock contact". */}
                  <p className="text-2xl font-black tracking-tighter">
                    Get the landlord&apos;s and caretaker&apos;s numbers, the exact address and the
                    map pin.
                  </p>
                  <p className="text-sm font-medium text-blue-50 leading-relaxed">
                    Tap &ldquo;Unlock contact&rdquo; on this home in the Kheja_Link app. The
                    contacts, exact address and map pin stay open for 3 hours.
                  </p>
                  <Link
                    href="/#get-the-app"
                    className="w-full h-14 bg-white text-blue-700 rounded-2xl font-black flex items-center justify-center gap-2 hover:scale-[1.02] transition-transform"
                  >
                    Unlock in the app
                  </Link>
                </div>
              )}

              <InquiryForm
                key={reporting ? "report" : "message"}
                propertyId={property.id}
                propertyTitle={property.title}
                report={reporting}
                defaultName={profile?.full_name}
                defaultEmail={user?.email}
                defaultPhone={profile?.phone}
              />

              {!isOwner && (
                <p className="text-center">
                  <Link
                    href={reporting ? `/properties/${property.slug}#contact` : `/properties/${property.slug}?report=1#contact`}
                    scroll={false}
                    className="text-xs font-black text-zinc-400 hover:text-red-600"
                  >
                    {reporting ? "Ask a question instead" : "Report this listing"}
                  </Link>
                </p>
              )}

              <p className="px-4 text-xs font-medium text-zinc-400 leading-relaxed text-center">
                Never send a deposit before viewing a house in person. Read our{" "}
                <Link href="/help#safety" className="font-black text-blue-600 hover:underline">
                  safety tips
                </Link>
                .
              </p>
            </aside>
          </div>

          {similarWithState.length > 0 && (
            <section className="space-y-8 pt-12">
              <h2 className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white tracking-tighter">
                You might also like
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-12">
                {similarWithState.map((item) => (
                  <PropertyCard key={item.id} property={item} />
                ))}
              </div>
            </section>
          )}
        </div>
      </main>

      <Footer />
    </div>
  );
}
