"use client";

import { useActionState, useEffect, useRef, useState, useTransition } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Loader2, Save, Upload, ImageOff } from "lucide-react";
import { toast } from "sonner";
import { AuthField, authInputClass } from "@/components/AuthShell";
import { saveProviderAction, uploadProviderLogoAction } from "@/lib/actions/admin";
import type { PartnerRow } from "@/lib/supabase/database.types";
import type { ActionResult } from "@/lib/types";

const textareaClass =
  "w-full p-5 bg-zinc-50 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl font-medium text-zinc-900 dark:text-white outline-none focus:border-blue-500 transition-colors resize-none";

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function SubmitButton({ isNew }: { isNew: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="flex items-center justify-center gap-2 w-full sm:w-auto px-8 h-16 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors disabled:opacity-60"
    >
      {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
      {isNew ? "Add provider" : "Save changes"}
    </button>
  );
}

function Toggle({ name, label, hint, defaultChecked }: { name: string; label: string; hint: string; defaultChecked: boolean }) {
  return (
    <label className="flex items-start gap-4 p-5 bg-zinc-50 dark:bg-zinc-800/60 border border-zinc-200 dark:border-zinc-700 rounded-2xl cursor-pointer">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} className="mt-1 w-5 h-5 accent-blue-600" />
      <span className="space-y-1">
        <span className="block font-black text-zinc-900 dark:text-white">{label}</span>
        <span className="block text-sm font-medium text-zinc-500">{hint}</span>
      </span>
    </label>
  );
}

export default function ProviderForm({ provider }: { provider?: PartnerRow }) {
  const router = useRouter();
  const isNew = !provider;
  const [name, setName] = useState(provider?.name ?? "");
  const [slug, setSlug] = useState(provider?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(!isNew);
  const [logoUrl, setLogoUrl] = useState(provider?.logo_url ?? "");
  const [uploading, startUpload] = useTransition();
  const fileRef = useRef<HTMLInputElement>(null);

  const [state, formAction] = useActionState<ActionResult<{ id: string }> | null, FormData>(
    saveProviderAction,
    null,
  );

  useEffect(() => {
    if (!state) return;
    if (state.ok) {
      toast.success(state.message ?? "Saved.");
      router.push("/admin/providers");
      router.refresh();
    } else {
      toast.error(state.error);
    }
  }, [state, router]);

  const err = (field: string) => (state && !state.ok ? state.fieldErrors?.[field]?.[0] : undefined);

  const upload = (file: File) =>
    startUpload(async () => {
      const data = new FormData();
      data.set("file", file);
      const result = await uploadProviderLogoAction(data);
      if (result.ok) {
        setLogoUrl(result.data.url);
        toast.success("Logo uploaded. Save to keep it.");
      } else {
        toast.error(result.error);
      }
    });

  return (
    <form action={formAction} className="space-y-8">
      {provider && <input type="hidden" name="id" value={provider.id} />}
      <input type="hidden" name="logoUrl" value={logoUrl} />

      <section className="p-6 sm:p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-6">
        <h3 className="text-xl font-black text-zinc-900 dark:text-white tracking-tight">Company</h3>

        <div className="flex flex-col sm:flex-row gap-5 sm:items-center">
          <div className="w-28 h-28 rounded-[1.75rem] bg-white border border-zinc-200 dark:border-zinc-700 flex items-center justify-center overflow-hidden shrink-0">
            {logoUrl ? (
              <img src={logoUrl} alt="Logo preview" className="w-full h-full object-contain p-2" />
            ) : (
              <ImageOff className="w-8 h-8 text-zinc-300" />
            )}
          </div>
          <div className="space-y-2">
            <input
              ref={fileRef}
              type="file"
              accept="image/png,image/jpeg,image/webp,image/svg+xml"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) upload(file);
                e.target.value = "";
              }}
            />
            <button
              type="button"
              disabled={uploading}
              onClick={() => fileRef.current?.click()}
              className="inline-flex items-center gap-2 px-5 h-12 bg-zinc-100 dark:bg-zinc-800 rounded-2xl text-sm font-black text-zinc-700 dark:text-zinc-200 hover:text-blue-600 disabled:opacity-60"
            >
              {uploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
              {logoUrl ? "Replace logo" : "Upload logo"}
            </button>
            <p className="text-xs font-medium text-zinc-500">
              PNG, JPEG, WebP or SVG, up to 512 KB. Only use a logo the company has agreed to.
            </p>
            {logoUrl && (
              <button type="button" onClick={() => setLogoUrl("")} className="text-xs font-black text-zinc-400 hover:text-red-600">
                Remove logo
              </button>
            )}
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-5">
          <AuthField label="Company name" error={err("name")}>
            <input
              name="name"
              required
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                if (!slugTouched) setSlug(slugify(e.target.value));
              }}
              className={authInputClass}
            />
          </AuthField>
          <AuthField label="Slug (used in links)" error={err("slug")}>
            <input
              name="slug"
              required
              value={slug}
              onChange={(e) => {
                setSlugTouched(true);
                setSlug(e.target.value);
              }}
              className={authInputClass}
            />
          </AuthField>
          <AuthField label="Category" error={err("category")}>
            <select name="category" defaultValue={provider?.category ?? "movers"} className={authInputClass}>
              <option value="movers">Movers</option>
              <option value="isp">Internet / network provider</option>
              <option value="cleaning">Cleaning company</option>
            </select>
          </AuthField>
          <AuthField label="Tagline" error={err("tagline")}>
            <input name="tagline" defaultValue={provider?.tagline ?? ""} placeholder="e.g. House moving across Meru" className={authInputClass} />
          </AuthField>
        </div>

        <AuthField label="Description" error={err("description")}>
          <textarea name="description" rows={3} defaultValue={provider?.description ?? ""} className={textareaClass} />
        </AuthField>
        <div className="grid sm:grid-cols-2 gap-5">
          <AuthField label="Services (comma separated)" error={err("services")}>
            <input name="services" defaultValue={provider?.services?.join(", ") ?? ""} placeholder="Packing, Transport" className={authInputClass} />
          </AuthField>
          <AuthField label="Pricing information" error={err("pricingInfo")}>
            <input name="pricingInfo" defaultValue={provider?.pricing_info ?? ""} placeholder="e.g. From KSh 3,000 within Meru Town" className={authInputClass} />
          </AuthField>
        </div>
      </section>

      <section className="p-6 sm:p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-6">
        <h3 className="text-xl font-black text-zinc-900 dark:text-white tracking-tight">Contact</h3>
        <div className="grid sm:grid-cols-2 gap-5">
          <AuthField label="Phone" error={err("phone")}>
            <input name="phone" type="tel" defaultValue={provider?.phone ?? ""} placeholder="+254 712 345 678" className={authInputClass} />
          </AuthField>
          <AuthField label="Email" error={err("email")}>
            <input name="email" type="email" defaultValue={provider?.email ?? ""} className={authInputClass} />
          </AuthField>
          <AuthField label="Website" error={err("url")}>
            <input name="url" type="url" defaultValue={provider?.url ?? ""} placeholder="https://" className={authInputClass} />
          </AuthField>
          <AuthField label="Location" error={err("location")}>
            <input name="location" defaultValue={provider?.location ?? ""} placeholder="Meru Town" className={authInputClass} />
          </AuthField>
        </div>
      </section>

      <section className="p-6 sm:p-8 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2.5rem] space-y-6">
        <h3 className="text-xl font-black text-zinc-900 dark:text-white tracking-tight">Status and onboarding</h3>
        <div className="grid sm:grid-cols-3 gap-5">
          <AuthField label="Approval" error={err("approvalStatus")}>
            <select name="approvalStatus" defaultValue={provider?.approval_status ?? "pending"} className={authInputClass}>
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
            </select>
          </AuthField>
          <AuthField label="Brand colour" error={err("brandColor")}>
            <input name="brandColor" type="color" defaultValue={provider?.brand_color ?? "#2563EB"} className={`${authInputClass} p-2`} />
          </AuthField>
          <AuthField label="Sort order" error={err("sortOrder")}>
            <input name="sortOrder" type="number" min={0} defaultValue={provider?.sort_order ?? 10} className={authInputClass} />
          </AuthField>
          <AuthField label="Onboarding fee (KES, optional)" error={err("onboardingFee")}>
            <input name="onboardingFee" type="number" min={0} step="1" defaultValue={provider?.onboarding_fee ?? ""} className={authInputClass} />
          </AuthField>
        </div>
        <div className="grid sm:grid-cols-3 gap-4">
          <Toggle name="isActive" label="Live in the app" hint="Only takes effect once approved." defaultChecked={provider?.is_active ?? false} />
          <Toggle name="isOurs" label="Kheja_Link partner" hint="Marked as a partner under listings." defaultChecked={provider?.is_ours ?? false} />
          <Toggle name="onboardingPaid" label="Onboarding paid" hint="For your records; not charged by the app." defaultChecked={provider?.onboarding_paid ?? false} />
        </div>
      </section>

      <SubmitButton isNew={isNew} />
    </form>
  );
}
