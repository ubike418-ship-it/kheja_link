"use client";

import { useState, useTransition } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Filter, X, Search, SlidersHorizontal, Check } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { formatPrice } from "@/lib/format";
import { PROPERTY_SORTS } from "@/lib/types";
import type { AmenityRow, LocationRow, PropertyTypeRow } from "@/lib/supabase/database.types";

type Props = {
  types: PropertyTypeRow[];
  locations: LocationRow[];
  amenities: AmenityRow[];
  bounds: { min: number; max: number };
  resultCount: number;
};

/**
 * All filter state lives in the URL. That keeps every search shareable and
 * bookmarkable, lets the server do the querying, and means the back button
 * behaves the way people expect.
 */
export default function PropertyFilterPanel({
  types,
  locations,
  amenities,
  bounds,
  resultCount,
}: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [isPending, startTransition] = useTransition();
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState(params.get("q") ?? "");

  const selectedAmenities = new Set((params.get("amenities") ?? "").split(",").filter(Boolean));

  const activeCount = [
    params.get("type"),
    params.get("location"),
    params.get("minPrice"),
    params.get("maxPrice"),
    params.get("bedrooms"),
    params.get("furnished"),
    params.get("premium"),
    params.get("amenities"),
  ].filter(Boolean).length;

  const push = (mutate: (next: URLSearchParams) => void) => {
    const next = new URLSearchParams(params.toString());
    mutate(next);
    next.delete("page"); // any filter change returns to page one
    startTransition(() => {
      router.push(next.toString() ? `${pathname}?${next}` : pathname, { scroll: false });
    });
  };

  const setParam = (key: string, value: string | null) =>
    push((next) => (value ? next.set(key, value) : next.delete(key)));

  const toggleAmenity = (slug: string) =>
    push((next) => {
      const set = new Set(selectedAmenities);
      if (set.has(slug)) set.delete(slug);
      else set.add(slug);
      if (set.size) next.set("amenities", [...set].join(","));
      else next.delete("amenities");
    });

  const clearAll = () => {
    setQuery("");
    startTransition(() => router.push(pathname, { scroll: false }));
  };

  return (
    <div className="space-y-6">
      {/* Search + controls row */}
      <div className="flex flex-col lg:flex-row gap-4">
        <form
          onSubmit={(event) => {
            event.preventDefault();
            setParam("q", query.trim() || null);
          }}
          className="flex-1 flex items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] shadow-sm focus-within:border-blue-500 transition-colors"
        >
          <Search className="w-5 h-5 text-blue-500 ml-4 shrink-0" aria-hidden="true" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search homes, areas or house types…"
            aria-label="Search rentals"
            className="flex-1 h-12 bg-transparent outline-none font-medium text-zinc-900 dark:text-white placeholder-zinc-400 min-w-0"
          />
          {query && (
            <button
              type="button"
              onClick={() => {
                setQuery("");
                setParam("q", null);
              }}
              aria-label="Clear search"
              className="p-2 text-zinc-400 hover:text-zinc-900 dark:hover:text-white"
            >
              <X className="w-4 h-4" />
            </button>
          )}
          <button
            type="submit"
            className="px-6 h-12 bg-blue-600 text-white rounded-2xl font-bold hover:bg-blue-700 transition-colors shrink-0"
          >
            Search
          </button>
        </form>

        <div className="flex items-center gap-3">
          <button
            onClick={() => setIsOpen((open) => !open)}
            aria-expanded={isOpen}
            className={`flex items-center gap-2 px-6 h-16 rounded-2xl font-bold border transition-colors ${
              activeCount > 0
                ? "bg-blue-600 text-white border-blue-600"
                : "bg-white dark:bg-zinc-900 text-zinc-600 dark:text-zinc-400 border-zinc-200 dark:border-zinc-800 hover:border-blue-500"
            }`}
          >
            <Filter className="w-5 h-5" />
            <span>Filters</span>
            {activeCount > 0 && (
              <span className="w-6 h-6 rounded-full bg-white text-blue-600 text-xs font-black flex items-center justify-center">
                {activeCount}
              </span>
            )}
          </button>

          <div className="relative">
            <SlidersHorizontal className="w-4 h-4 text-zinc-400 absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none" />
            <select
              value={params.get("sort") ?? "newest"}
              onChange={(event) => setParam("sort", event.target.value === "newest" ? null : event.target.value)}
              aria-label="Sort results"
              className="h-16 pl-11 pr-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-2xl font-bold text-zinc-600 dark:text-zinc-400 outline-none focus:border-blue-500 appearance-none cursor-pointer"
            >
              {PROPERTY_SORTS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Result count + clear */}
      <div className="flex items-center justify-between gap-4">
        <p
          aria-live="polite"
          className={`text-sm font-bold text-zinc-500 transition-opacity ${isPending ? "opacity-50" : ""}`}
        >
          {resultCount === 0
            ? "No homes match these filters"
            : `${resultCount} ${resultCount === 1 ? "home" : "homes"} available`}
        </p>
        {activeCount > 0 && (
          <button
            onClick={clearAll}
            className="text-sm font-black text-blue-600 hover:text-blue-700 transition-colors"
          >
            Clear all filters
          </button>
        )}
      </div>

      {/* Expandable filter panel */}
      <AnimatePresence initial={false}>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
            className="overflow-hidden"
          >
            <div className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-8">
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <Field label="House type">
                  <Select
                    value={params.get("type") ?? ""}
                    onChange={(value) => setParam("type", value || null)}
                    placeholder="Any type"
                    options={types.map((t) => ({ value: t.slug, label: t.name }))}
                  />
                </Field>

                <Field label="Area">
                  <Select
                    value={params.get("location") ?? ""}
                    onChange={(value) => setParam("location", value || null)}
                    placeholder="Anywhere in Meru"
                    options={locations.map((l) => ({ value: l.slug, label: l.name }))}
                  />
                </Field>

                <Field label="Bedrooms">
                  <Select
                    value={params.get("bedrooms") ?? ""}
                    onChange={(value) => setParam("bedrooms", value || null)}
                    placeholder="Any"
                    options={[
                      { value: "1", label: "1+" },
                      { value: "2", label: "2+" },
                      { value: "3", label: "3+" },
                      { value: "4", label: "4+" },
                    ]}
                  />
                </Field>

                <Field label={`Max rent — ${formatPrice(Number(params.get("maxPrice")) || bounds.max)}`}>
                  <input
                    type="range"
                    min={bounds.min}
                    max={bounds.max}
                    step={1000}
                    defaultValue={Number(params.get("maxPrice")) || bounds.max}
                    onMouseUp={(event) =>
                      setParam("maxPrice", (event.target as HTMLInputElement).value)
                    }
                    onTouchEnd={(event) =>
                      setParam("maxPrice", (event.target as HTMLInputElement).value)
                    }
                    aria-label="Maximum monthly rent"
                    className="w-full h-14 accent-blue-600 cursor-pointer"
                  />
                </Field>
              </div>

              <div className="space-y-4">
                <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                  Must have
                </span>
                <div className="flex flex-wrap gap-2">
                  {amenities.map((amenity) => {
                    const active = selectedAmenities.has(amenity.slug);
                    return (
                      <button
                        key={amenity.id}
                        onClick={() => toggleAmenity(amenity.slug)}
                        aria-pressed={active}
                        className={`flex items-center gap-2 px-4 h-11 rounded-2xl text-sm font-bold border transition-colors ${
                          active
                            ? "bg-blue-600 text-white border-blue-600"
                            : "bg-zinc-50 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 border-zinc-200 dark:border-zinc-700 hover:border-blue-500"
                        }`}
                      >
                        {active && <Check className="w-4 h-4" />}
                        {amenity.name}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="flex flex-wrap gap-3">
                <Toggle
                  active={params.get("furnished") === "1"}
                  onClick={() => setParam("furnished", params.get("furnished") === "1" ? null : "1")}
                >
                  Furnished only
                </Toggle>
                <Toggle
                  active={params.get("premium") === "1"}
                  onClick={() => setParam("premium", params.get("premium") === "1" ? null : "1")}
                >
                  Premium units
                </Toggle>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-3">
      <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{label}</span>
      {children}
    </label>
  );
}

function Select({
  value,
  onChange,
  options,
  placeholder,
}: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
  placeholder: string;
}) {
  return (
    <select
      value={value}
      onChange={(event) => onChange(event.target.value)}
      className="w-full h-14 px-4 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-bold text-zinc-900 dark:text-white outline-none focus:border-blue-500 cursor-pointer"
    >
      <option value="">{placeholder}</option>
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  );
}

function Toggle({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      aria-pressed={active}
      className={`px-6 h-12 rounded-2xl text-sm font-black border transition-colors ${
        active
          ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 border-zinc-900 dark:border-white"
          : "bg-transparent text-zinc-500 border-zinc-200 dark:border-zinc-700 hover:border-blue-500"
      }`}
    >
      {children}
    </button>
  );
}
