import type { MetadataRoute } from "next";
import { createClient } from "@/lib/supabase/server";
import { getSiteUrl } from "@/lib/supabase/env";

export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const siteUrl = getSiteUrl();

  const staticRoutes: MetadataRoute.Sitemap = [
    { url: siteUrl, changeFrequency: "daily", priority: 1 },
    { url: `${siteUrl}/properties`, changeFrequency: "daily", priority: 0.9 },
    { url: `${siteUrl}/help`, changeFrequency: "monthly", priority: 0.3 },
    { url: `${siteUrl}/terms`, changeFrequency: "yearly", priority: 0.2 },
    { url: `${siteUrl}/privacy`, changeFrequency: "yearly", priority: 0.2 },
  ];

  try {
    const supabase = await createClient();
    const { data } = await supabase
      .from("properties")
      .select("slug, updated_at")
      .eq("status", "published")
      .order("published_at", { ascending: false })
      .limit(1000);

    return [
      ...staticRoutes,
      ...(data ?? []).map((property) => ({
        url: `${siteUrl}/properties/${property.slug}`,
        lastModified: property.updated_at ? new Date(property.updated_at) : undefined,
        changeFrequency: "weekly" as const,
        priority: 0.7,
      })),
    ];
  } catch {
    // A sitemap is never worth failing a build over.
    return staticRoutes;
  }
}
