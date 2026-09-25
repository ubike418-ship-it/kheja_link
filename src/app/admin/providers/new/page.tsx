import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import ProviderForm from "@/components/admin/ProviderForm";
import { PageHeader } from "@/components/admin/AdminUI";

export const metadata = { title: "Add provider — Admin" };

export default function NewProviderPage() {
  return (
    <div className="space-y-8 max-w-4xl">
      <Link href="/admin/providers" className="inline-flex items-center gap-2 text-sm font-black text-zinc-500 hover:text-blue-600">
        <ArrowLeft className="w-4 h-4" /> All providers
      </Link>
      <PageHeader
        title="Add a provider"
        description="Only add companies Kheja_Link has an agreement with. New providers start as pending until you approve them."
      />
      <ProviderForm />
    </div>
  );
}
