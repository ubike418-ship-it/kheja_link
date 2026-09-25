import type { Metadata } from "next";
import InquiryList from "@/components/InquiryList";
import { getInquiriesForOwner } from "@/lib/queries/inquiries";

export const metadata: Metadata = {
  title: "Inquiries",
  robots: { index: false, follow: false },
};

export default async function InquiriesPage() {
  // RLS restricts this to inquiries on listings the signed-in user owns.
  const inquiries = await getInquiriesForOwner().catch(() => []);

  return (
    <div className="space-y-8">
      <header className="space-y-3">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-blue-600">
          Your leads
        </p>
        <h1 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter">
          Inquiries
        </h1>
        <p className="text-lg font-medium text-zinc-500 max-w-2xl">
          Messages tenants sent about your houses before questions moved to the Kheja_Link team.
          New questions now come to us, and tenants who unlock a listing call you directly.
        </p>
      </header>

      <InquiryList inquiries={inquiries} />
    </div>
  );
}
