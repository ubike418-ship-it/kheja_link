"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Loader2, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";
import PropertyImageUploader from "@/components/PropertyImageUploader";
import { createPropertyAction, deletePropertyAction, updatePropertyAction } from "@/lib/actions/properties";
import type { AmenityRow, LocationRow, PropertyTypeRow } from "@/lib/supabase/database.types";
import type { ActionResult, PropertyListItem } from "@/lib/types";

type Props = {
  types: PropertyTypeRow[];
  locations: LocationRow[];
  amenities: AmenityRow[];
  defaultPhone?: string | null;
  /** Present when editing an existing listing. */
  property?: (PropertyListItem & { amenity_ids: string[] }) | null;
};

const inputClass =
  "w-full h-14 px-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors";

export default function PropertyForm({
  types,
  locations,
  amenities,
  defaultPhone,
  property,
}: Props) {
  const router = useRouter();
  const isEditing = Boolean(property);

  const action = isEditing
    ? updatePropertyAction.bind(null, property!.id)
    : createPropertyAction;

  const [state, formAction] = useActionState<ActionResult<{ slug: string }> | null, FormData>(
    action,
    null,
  );

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Saved.");
      router.push("/dashboard/properties");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);

  const err = (name: string) => (state && !state.ok ? state.fieldErrors?.[name]?.[0] : undefined);

  const handleDelete = async () => {
    if (!property) return;
    if (!window.confirm(`Delete "${property.title}"? This cannot be undone.`)) return;
    const result = await deletePropertyAction(property.id);
    if (result.ok) {
      toast.success(result.message ?? "Listing deleted.");
      router.push("/dashboard/properties");
      router.refresh();
    } else {
      toast.error(result.error);
    }
  };

  return (
    <form action={formAction} className="space-y-10">
      {/* Photos */}
      <Section title="Photos" hint="Good photos are the single biggest reason people click.">
        <PropertyImageUploader
          initialUrls={property?.images.map((image) => image.public_url) ?? []}
        />
      </Section>

      {/* Basics */}
      <Section title="The basics">
        <Field label="Listing title" error={err("title")}>
          <input
            name="title"
            required
            defaultValue={property?.title ?? ""}
            placeholder="e.g. Modern 2BR Apartment in Makutano"
            className={inputClass}
          />
        </Field>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          <Field label="House type" error={err("propertyTypeId")}>
            <select
              name="propertyTypeId"
              required
              defaultValue={property?.property_type_id ?? ""}
              className={`${inputClass} cursor-pointer`}
            >
              <option value="" disabled>
                Choose a type
              </option>
              {types.map((type) => (
                <option key={type.id} value={type.id}>
                  {type.name}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Area" error={err("locationId")}>
            <select
              name="locationId"
              required
              defaultValue={property?.location_id ?? ""}
              className={`${inputClass} cursor-pointer`}
            >
              <option value="" disabled>
                Choose an area
              </option>
              {locations.map((location) => (
                <option key={location.id} value={location.id}>
                  {location.name}
                  {location.area ? ` — ${location.area}` : ""}
                </option>
              ))}
            </select>
          </Field>
        </div>

        <Field label="Describe the location — shown to everyone" error={err("locationDescription")}>
          <textarea
            name="locationDescription"
            rows={3}
            defaultValue={property?.nearby ?? ""}
            placeholder="e.g. Quiet estate 5 minutes' walk from Makutano stage, near Kinoru stadium, schools and the market. Tarmac to the gate."
            className={`${inputClass} h-auto py-4 resize-none`}
          />
        </Field>

        <Field label="Exact street / estate — only for tenants who unlock" error={err("addressLine")}>
          <input
            name="addressLine"
            defaultValue={property?.address_line ?? ""}
            placeholder="e.g. Off Meru–Maua Road, plot 42, green gate"
            className={inputClass}
          />
        </Field>

        <Field label="Description" error={err("description")}>
          <textarea
            name="description"
            rows={6}
            defaultValue={property?.description ?? ""}
            placeholder="Describe the house, the compound, water and power, and what is nearby."
            className="w-full p-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors resize-none"
          />
        </Field>
      </Section>

      {/* Rent */}
      <Section title="Rent and terms">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          <Field label="Rent (KSh)" error={err("priceAmount")}>
            <input
              name="priceAmount"
              type="number"
              min={1}
              step={500}
              required
              defaultValue={property?.price_amount ?? ""}
              placeholder="25000"
              className={inputClass}
            />
          </Field>
          <Field label="Per" error={err("pricePeriod")}>
            <select
              name="pricePeriod"
              defaultValue={property?.price_period ?? "month"}
              className={`${inputClass} cursor-pointer`}
            >
              <option value="month">Month</option>
              <option value="year">Year</option>
            </select>
          </Field>
          <Field label="Deposit (months)" error={err("depositMonths")}>
            <input
              name="depositMonths"
              type="number"
              min={0}
              max={24}
              defaultValue={property?.deposit_months ?? 1}
              className={inputClass}
            />
          </Field>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          <Field label="Bedrooms" error={err("bedrooms")}>
            <input
              name="bedrooms"
              type="number"
              min={0}
              max={50}
              defaultValue={property?.bedrooms ?? 0}
              className={inputClass}
            />
          </Field>
          <Field label="Bathrooms" error={err("bathrooms")}>
            <input
              name="bathrooms"
              type="number"
              min={0}
              max={50}
              defaultValue={property?.bathrooms ?? 0}
              className={inputClass}
            />
          </Field>
          <Field label="Size in sqft (optional)" error={err("sizeSqft")}>
            <input
              name="sizeSqft"
              type="number"
              min={1}
              defaultValue={property?.size_sqft ?? ""}
              placeholder="1200"
              className={inputClass}
            />
          </Field>
        </div>

        <Field label="Available from (optional)" error={err("availableFrom")}>
          <input
            name="availableFrom"
            type="date"
            defaultValue={property?.available_from ?? ""}
            className={inputClass}
          />
        </Field>

        <div className="flex flex-wrap gap-6 pt-2">
          <Checkbox name="isFurnished" defaultChecked={property?.is_furnished}>
            This home is furnished
          </Checkbox>
          <Checkbox name="isPremium" defaultChecked={property?.is_premium}>
            List as a premium unit
          </Checkbox>
        </div>
      </Section>

      {/* Amenities */}
      <Section title="Amenities" hint="Tick everything the house actually offers.">
        <div className="flex flex-wrap gap-3">
          {amenities.map((amenity) => (
            <label
              key={amenity.id}
              className="flex items-center gap-2 px-5 h-12 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-bold text-sm text-zinc-600 dark:text-zinc-300 cursor-pointer hover:border-blue-500 transition-colors has-[:checked]:bg-blue-600 has-[:checked]:text-white has-[:checked]:border-blue-600"
            >
              <input
                type="checkbox"
                name="amenityIds"
                value={amenity.id}
                defaultChecked={property?.amenity_ids.includes(amenity.id)}
                className="w-4 h-4 accent-white"
              />
              {amenity.name}
            </label>
          ))}
        </div>
      </Section>

      {/* Contact */}
      <Section title="How should people reach you?">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          <Field label="Phone" error={err("contactPhone")}>
            <input
              name="contactPhone"
              type="tel"
              defaultValue={property?.contact_phone ?? defaultPhone ?? ""}
              placeholder="+254 712 345 678"
              className={inputClass}
            />
          </Field>
          <Field label="WhatsApp (optional)" error={err("contactWhatsapp")}>
            <input
              name="contactWhatsapp"
              type="tel"
              defaultValue={property?.contact_whatsapp ?? ""}
              placeholder="+254 712 345 678"
              className={inputClass}
            />
          </Field>
        </div>
      </Section>

      {/* Status + submit */}
      <Section title="Visibility">
        <Field label="Status" error={err("status")}>
          <select
            name="status"
            defaultValue={property?.status === "pending" ? "draft" : (property?.status ?? "published")}
            className={`${inputClass} cursor-pointer`}
          >
            <option value="published">Published — visible to everyone</option>
            <option value="draft">Draft — only you can see it</option>
            <option value="rented">Rented — taken off the search</option>
            <option value="archived">Archived — hidden</option>
          </select>
        </Field>
      </Section>

      <div className="flex flex-col sm:flex-row items-center gap-4 pt-4">
        <SubmitButton isEditing={isEditing} />
        <Link
          href="/dashboard/properties"
          className="w-full sm:w-auto px-8 h-16 rounded-2xl font-black text-zinc-500 border border-zinc-200 dark:border-zinc-800 flex items-center justify-center hover:border-blue-500 transition-colors"
        >
          Cancel
        </Link>
        {isEditing && (
          <button
            type="button"
            onClick={handleDelete}
            className="w-full sm:w-auto sm:ml-auto px-8 h-16 rounded-2xl font-black text-red-600 border border-red-200 dark:border-red-900/50 flex items-center justify-center gap-2 hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
          >
            <Trash2 className="w-5 h-5" />
            Delete listing
          </button>
        )}
      </div>
    </form>
  );
}

function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-5">
      <div className="space-y-1">
        <h2 className="text-2xl font-black text-zinc-900 dark:text-white tracking-tight">{title}</h2>
        {hint && <p className="text-sm font-medium text-zinc-500">{hint}</p>}
      </div>
      {children}
    </section>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-2">
      <span className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">{label}</span>
      {children}
      {error && <span className="block text-xs font-bold text-red-600">{error}</span>}
    </label>
  );
}

function Checkbox({
  name,
  defaultChecked,
  children,
}: {
  name: string;
  defaultChecked?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className="flex items-center gap-3 font-bold text-zinc-700 dark:text-zinc-300 cursor-pointer">
      <input
        type="checkbox"
        name={name}
        defaultChecked={defaultChecked}
        className="w-5 h-5 accent-blue-600"
      />
      {children}
    </label>
  );
}

function SubmitButton({ isEditing }: { isEditing: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full sm:w-auto px-10 h-16 bg-blue-600 text-white rounded-2xl font-black text-lg flex items-center justify-center gap-2 hover:bg-blue-700 active:scale-[0.98] transition-all shadow-lg shadow-blue-600/20 disabled:opacity-70"
    >
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
      {pending ? "Saving…" : isEditing ? "Save changes" : "Publish listing"}
    </button>
  );
}
