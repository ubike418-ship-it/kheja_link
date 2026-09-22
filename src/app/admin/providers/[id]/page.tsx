import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import ProviderForm from "@/components/admin/ProviderForm";
import { createClient } from "@/lib/supabase/server";
import type { PartnerRow } from "@/lib/supabase/database.types";

export const metadata = { title: "Edit provider — Admin" };

export default async function EditProviderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();

  const supabase = await createClient();
  const { data } = await supabase.from("partners").select("*").eq("id", id).maybeSingle();
  if (!data) notFound();

  return (
    <div className="space-y-8 max-w-4xl">
      <Link href="/admin/providers" className="inline-flex items-center gap-2 text-sm font-black text-zinc-500 hover:text-blue-600">
        <ArrowLeft className="w-4 h-4" /> All providers
      </Link>
      <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">{data.name}</h2>
      <ProviderForm provider={data as PartnerRow} />
    </div>
  );
}
