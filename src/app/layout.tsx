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

/** Google AdSense publisher ID (also in public/ads.txt and public/app-ads.txt). */
const ADSENSE_CLIENT = "ca-pub-3771359841277271";

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
  // AdSense site-ownership verification (the meta-tag method).
  other: { "google-adsense-account": ADSENSE_CLIENT },
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
      <head>
        {/* Google AdSense: verifies the site and serves ads. Exactly Google's
            snippet — a plain async script in the head of every page. */}
        <script
          async
          src={`https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT}`}
          crossOrigin="anonymous"
        />
      </head>
      <body className="antialiased">
        {children}
        <AIChatAssistant />
        <Toaster position="bottom-center" richColors closeButton />
      </body>
    </html>
  );
}
