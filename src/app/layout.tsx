import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";
import { Toaster } from "@/components/ui/sonner";
import AIChatAssistant from "@/components/AIChatAssistant";
import { getSiteUrl } from "@/lib/supabase/env";
import "./globals.css";

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
  display: "swap",
});

const siteUrl = getSiteUrl();

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Kheja_Link | Find Your Next Home in Meru",
    template: "%s | Kheja_Link",
  },
  description:
    "Kheja_Link is the modern way to find long-term rentals in Meru, Kenya — apartments, bedsitters, single rooms, family homes and shops, all verified and searchable in one place.",
  keywords: [
    "Kheja_Link",
    "houses for rent in Meru",
    "Meru rentals",
    "apartments Meru",
    "bedsitters Meru",
    "student rooms MUST",
    "shops to let Meru",
  ],
  applicationName: "Kheja_Link",
  openGraph: {
    type: "website",
    siteName: "Kheja_Link",
    title: "Kheja_Link | Find Your Next Home in Meru",
    description:
      "Discover, search and filter long-term rentals across Meru — then unlock the landlord's contact and call them directly.",
    url: siteUrl,
  },
  twitter: {
    card: "summary_large_image",
    title: "Kheja_Link | Find Your Next Home in Meru",
    description: "The modern way to find long-term rentals in Meru, Kenya.",
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fafafa" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={geist.variable}>
      <body className="antialiased">
        {children}
        <AIChatAssistant />
        <Toaster position="bottom-center" richColors closeButton />
      </body>
    </html>
  );
}
