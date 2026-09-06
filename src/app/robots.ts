import type { MetadataRoute } from "next";
import { getSiteUrl } from "@/lib/supabase/env";

export default function robots(): MetadataRoute.Robots {
  const siteUrl = getSiteUrl();
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // Nothing behind a login should be crawled.
      disallow: ["/dashboard", "/account", "/favorites", "/auth", "/login", "/signup"],
    },
    sitemap: `${siteUrl}/sitemap.xml`,
  };
}
