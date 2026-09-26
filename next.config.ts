import type { NextConfig } from "next";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseHost = supabaseUrl ? new URL(supabaseUrl).hostname : undefined;
const isProd = process.env.NODE_ENV === "production";

/**
 * Content Security Policy.
 *
 * Google AdSense loads scripts, images and ad frames from a long and changing
 * list of Google domains (googlesyndication, doubleclick, google.com and its
 * country domains, adtrafficquality, gstatic…), so scripts, frames, images and
 * connections are allowed from any HTTPS origin — naming them one by one
 * would silently block ads whenever Google adds a host. Still enforced: HTTPS
 * only, no plugins, no one may frame this site, forms post only here, and no
 * base-tag hijacking.
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline' https:${isProd ? "" : " 'unsafe-eval'"}`,
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self' data:",
  "img-src 'self' data: blob: https:",
  `media-src 'self' blob:${supabaseHost ? ` https://${supabaseHost}` : ""}`,
  `connect-src 'self' https:${supabaseHost ? ` wss://${supabaseHost}` : ""}`,
  "frame-ancestors 'none'",
  "frame-src https:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  ...(isProd ? ["upgrade-insecure-requests"] : []),
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  // Two years, subdomains included, eligible for browser preload lists.
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(self), payment=(), usb=(), interest-cohort=()",
  },
  // Ads open advertisers' pages in new windows; same-origin would break that.
  { key: "Cross-Origin-Opener-Policy", value: "same-origin-allow-popups" },
  { key: "X-DNS-Prefetch-Control", value: "on" },
];

const nextConfig: NextConfig = {
  // Do not advertise the framework.
  poweredByHeader: false,
  async headers() {
    return [
      { source: "/:path*", headers: securityHeaders },
      // Payment and admin responses are never cached anywhere.
      {
        source: "/api/:path*",
        headers: [{ key: "Cache-Control", value: "no-store, max-age=0" }],
      },
      {
        source: "/admin/:path*",
        headers: [
          { key: "Cache-Control", value: "no-store, max-age=0" },
          { key: "X-Robots-Tag", value: "noindex, nofollow" },
        ],
      },
    ];
  },
  images: {
    remotePatterns: [
      // Supabase Storage — where property images actually live.
      ...(supabaseHost
        ? ([
            {
              protocol: "https" as const,
              hostname: supabaseHost,
              pathname: "/storage/v1/object/public/**",
            },
          ])
        : []),
      // Unsplash — used by the seeded demo listings.
      { protocol: "https", hostname: "images.unsplash.com" },
    ],
  },
};

export default nextConfig;
