import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import ProviderForm from "@/components/admin/ProviderForm";

export const metadata = { title: "Add provider — Admin" };

export default function NewProviderPage() {
  return (
    <div className="space-y-8 max-w-4xl">
      <Link href="/admin/providers" className="inline-flex items-center gap-2 text-sm font-black text-zinc-500 hover:text-blue-600">
        <ArrowLeft className="w-4 h-4" /> All providers
      </Link>
      <h2 className="text-3xl font-black text-zinc-900 dark:text-white tracking-tighter">Add a provider</h2>
      <ProviderForm />
    </div>
  );
}
