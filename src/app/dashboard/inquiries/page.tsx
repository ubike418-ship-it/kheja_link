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
          People who have asked about your houses. Reply quickly — the first landlord to respond
          usually gets the tenant.
        </p>
      </header>

      <InquiryList inquiries={inquiries} />
    </div>
  );
}
