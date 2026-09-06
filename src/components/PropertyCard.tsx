"use client";

import { motion } from "framer-motion";
import { Heart, MapPin, BedDouble, Bath, Square, Phone, ArrowUpRight, Loader2 } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { toggleFavoriteAction } from "@/lib/actions/favorites";
import { formatLocation, formatRent, formatSize, normalisePhone } from "@/lib/format";
import type { PropertyListItem } from "@/lib/types";

const FALLBACK_IMAGE =
  "data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='800' height='600'%3E%3Crect width='800' height='600' fill='%23e4e4e7'/%3E%3C/svg%3E";

export default function PropertyCard({ property }: { property: PropertyListItem }) {
  const router = useRouter();
  const [isLiked, setIsLiked] = useState(Boolean(property.is_favorited));
  const [isPending, startTransition] = useTransition();

  const cover = property.images?.[0];
  const size = formatSize(property.size_sqft);
  const phone = normalisePhone(property.contact_phone);
  const href = `/properties/${property.slug}`;

  const handleToggleFavorite = (event: React.MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();

    // Optimistic — reverted below if the server disagrees.
    const next = !isLiked;
    setIsLiked(next);

    startTransition(async () => {
      const result = await toggleFavoriteAction(property.id);
      if (!result.ok) {
        setIsLiked(!next);
        toast.error(result.error, {
          action: { label: "Sign in", onClick: () => router.push("/login") },
        });
        return;
      }
      setIsLiked(result.data.favorited);
      toast.success(result.message ?? "Saved.");
    });
  };

  return (
    <motion.div
      layout
      initial={{ opacity: 0, scale: 0.95 }}
      whileInView={{ opacity: 1, scale: 1 }}
      viewport={{ once: true }}
      whileHover={{ y: -12 }}
      className="group relative bg-white dark:bg-zinc-900 rounded-[3rem] overflow-hidden border border-zinc-100 dark:border-zinc-800 shadow-sm hover:shadow-3xl hover:shadow-blue-500/10 transition-all duration-500"
    >
      {/* Image Container */}
      <div className="relative h-80 w-full overflow-hidden">
        <Link href={href} aria-label={property.title} className="absolute inset-0 z-10" />
        <Image
          src={cover?.public_url ?? FALLBACK_IMAGE}
          alt={cover?.alt_text ?? property.title}
          fill
          sizes="(max-width: 768px) 100vw, (max-width: 1280px) 50vw, 33vw"
          className="object-cover transition-transform duration-1000 group-hover:scale-110"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-60 group-hover:opacity-80 transition-opacity duration-500" />

        {/* Badges */}
        <div className="absolute top-6 left-6 right-6 flex justify-between items-center z-20">
          <div className="flex items-center gap-2">
            <span className="px-4 py-2 bg-white/10 backdrop-blur-xl border border-white/20 rounded-2xl text-[10px] font-black text-white uppercase tracking-widest">
              {property.property_type?.name ?? "Rental"}
            </span>
            {property.is_premium && (
              <span className="px-3 py-2 bg-amber-500/90 backdrop-blur-xl rounded-2xl text-[10px] font-black text-white uppercase tracking-widest">
                Premium
              </span>
            )}
          </div>
          <button
            onClick={handleToggleFavorite}
            disabled={isPending}
            aria-pressed={isLiked}
            aria-label={isLiked ? "Remove from saved homes" : "Save this home"}
            className="w-12 h-12 flex items-center justify-center bg-white/10 backdrop-blur-xl border border-white/20 rounded-2xl shadow-lg group/heart hover:bg-white/20 transition-all disabled:opacity-70"
          >
            {isPending ? (
              <Loader2 className="w-5 h-5 text-white animate-spin" />
            ) : (
              <Heart
                className={`w-5 h-5 transition-all duration-300 ${
                  isLiked ? "fill-red-500 text-red-500 scale-125" : "text-white group-hover/heart:scale-110"
                }`}
              />
            )}
          </button>
        </div>

        {/* Price Tag */}
        <div className="absolute bottom-6 left-6 z-20 pointer-events-none">
          <div className="flex flex-col">
            <span className="text-white/70 text-xs font-bold uppercase tracking-widest mb-1">
              {property.price_period === "year" ? "Annual Rent" : "Monthly Rent"}
            </span>
            <div className="text-3xl font-black text-white tracking-tighter">
              {formatRent(property.price_amount, property.price_period, property.price_currency).replace(
                / \/ (month|year)$/,
                "",
              )}
            </div>
          </div>
        </div>

        {/* Floating Action */}
        <div className="absolute bottom-6 right-6 z-20 translate-y-4 opacity-0 group-hover:translate-y-0 group-hover:opacity-100 transition-all duration-500 pointer-events-none">
          <div className="w-12 h-12 bg-blue-600 rounded-2xl flex items-center justify-center text-white shadow-xl shadow-blue-600/30">
            <ArrowUpRight className="w-6 h-6" />
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-8 space-y-6">
        <div className="space-y-2">
          <h3 className="text-2xl font-black text-zinc-900 dark:text-white leading-tight group-hover:text-blue-600 transition-colors duration-300">
            <Link href={href}>{property.title}</Link>
          </h3>
          <div className="flex items-center gap-1.5 text-zinc-500 dark:text-zinc-400">
            <MapPin className="w-4 h-4 text-blue-500 shrink-0" />
            <span className="text-sm font-bold tracking-tight">{formatLocation(property.location)}</span>
          </div>
        </div>

        <div className="flex items-center justify-between py-5 border-y border-zinc-100 dark:border-zinc-800">
          {property.bedrooms > 0 && (
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 bg-blue-50 dark:bg-blue-900/20 rounded-xl flex items-center justify-center">
                <BedDouble className="w-4 h-4 text-blue-600" />
              </div>
              <span className="text-sm font-black text-zinc-900 dark:text-white">
                {property.bedrooms}
              </span>
            </div>
          )}
          {property.bathrooms > 0 && (
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 bg-emerald-50 dark:bg-emerald-900/20 rounded-xl flex items-center justify-center">
                <Bath className="w-4 h-4 text-emerald-600" />
              </div>
              <span className="text-sm font-black text-zinc-900 dark:text-white">
                {property.bathrooms}
              </span>
            </div>
          )}
          {size && (
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 bg-purple-50 dark:bg-purple-900/20 rounded-xl flex items-center justify-center">
                <Square className="w-4 h-4 text-purple-600" />
              </div>
              <span className="text-sm font-black text-zinc-900 dark:text-white">{size}</span>
            </div>
          )}
        </div>

        <div className="flex items-center gap-3">
          <Link
            href={href}
            className="flex-1 h-14 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-2xl font-black text-sm hover:scale-[1.02] active:scale-95 transition-all duration-300 flex items-center justify-center"
          >
            View Details
          </Link>
          {phone ? (
            <a
              href={`tel:${phone}`}
              aria-label={`Call about ${property.title}`}
              className="w-14 h-14 flex items-center justify-center bg-blue-600 text-white rounded-2xl hover:bg-blue-700 hover:rotate-12 transition-all duration-300 shadow-lg shadow-blue-600/20 shrink-0"
            >
              <Phone className="w-6 h-6" />
            </a>
          ) : (
            <Link
              href={`${href}#contact`}
              aria-label={`Contact the landlord about ${property.title}`}
              className="w-14 h-14 flex items-center justify-center bg-blue-600 text-white rounded-2xl hover:bg-blue-700 hover:rotate-12 transition-all duration-300 shadow-lg shadow-blue-600/20 shrink-0"
            >
              <Phone className="w-6 h-6" />
            </Link>
          )}
        </div>
      </div>
    </motion.div>
  );
}
