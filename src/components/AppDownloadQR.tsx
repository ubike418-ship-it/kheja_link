import QRCode from "qrcode";
import Image from "next/image";
import { Smartphone, ShieldCheck, Download } from "lucide-react";

/**
 * The "get the app" band.
 *
 * The QR is rendered to a data URI on the server, so there is no client-side
 * QR library in the bundle and nothing to load before it paints. Someone opens
 * the site on a laptop, scans with their phone, and the download starts —
 * no typing a URL across devices.
 */

const APK_URL =
  "https://github.com/ubike418-ship-it/kheja_link/releases/latest/download/app-arm64-v8a-release.apk";

const FEATURES = [
  "Search every home, filter by area, rent and amenities",
  "Save homes — and get told the moment one frees up",
  "Unlock a landlord's contact by M-Pesa, right in the app",
];

export default async function AppDownloadQR() {
  // Dark modules on a transparent ground, so the same image works in both themes.
  const qr = await QRCode.toDataURL(APK_URL, {
    errorCorrectionLevel: "M",
    margin: 1,
    width: 480,
    color: { dark: "#18181bff", light: "#ffffffff" },
  });

  return (
    <section id="get-the-app" className="px-6 pt-20 scroll-mt-32">
      <div className="max-w-7xl mx-auto">
        <div className="relative rounded-[4rem] overflow-hidden bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-10 md:p-16">
          <div className="absolute inset-0 opacity-60 bg-[radial-gradient(circle_at_top_left,_var(--tw-gradient-stops))] from-blue-500/10 via-transparent to-transparent" />

          <div className="relative z-10 grid grid-cols-1 lg:grid-cols-[1.3fr_auto] gap-12 lg:gap-20 items-center">
            <div className="space-y-8">
              <div className="flex items-center gap-2 text-blue-600 font-black uppercase tracking-[0.2em] text-[10px]">
                <Smartphone className="w-4 h-4" />
                <span>Kheja_Link for Android</span>
              </div>

              <h2 className="text-4xl md:text-6xl font-black text-zinc-900 dark:text-white tracking-tighter leading-[0.95]">
                Scan. Install. <br />
                Start hunting.
              </h2>

              <p className="text-lg md:text-xl text-zinc-500 dark:text-zinc-400 font-medium max-w-lg">
                Point your phone camera at the code and the app downloads. Your saved
                homes and account work across both.
              </p>

              <ul className="space-y-3">
                {FEATURES.map((feature) => (
                  <li key={feature} className="flex items-start gap-3">
                    <span className="w-5 h-5 rounded-full bg-emerald-500/15 flex items-center justify-center shrink-0 mt-0.5">
                      <ShieldCheck className="w-3 h-3 text-emerald-600" />
                    </span>
                    <span className="font-bold text-zinc-600 dark:text-zinc-400">
                      {feature}
                    </span>
                  </li>
                ))}
              </ul>

              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 pt-2">
                <a
                  href={APK_URL}
                  className="inline-flex items-center justify-center gap-2 px-8 h-16 bg-blue-600 text-white rounded-2xl font-black hover:bg-blue-700 transition-colors shadow-lg shadow-blue-600/20"
                >
                  <Download className="w-5 h-5" />
                  Download directly
                </a>
                <p className="text-xs font-bold text-zinc-400 max-w-[16rem] leading-relaxed">
                  Not on the Play Store yet, so Android will ask you to allow the
                  install. That prompt is expected.
                </p>
              </div>
            </div>

            {/* The code itself */}
            <div className="justify-self-center lg:justify-self-end">
              <div className="p-6 bg-white rounded-[2.5rem] border border-zinc-200 shadow-2xl shadow-blue-500/10">
                <Image
                  src={qr}
                  alt="QR code to download the Kheja_Link Android app"
                  width={240}
                  height={240}
                  unoptimized
                  className="w-[200px] h-[200px] md:w-[240px] md:h-[240px]"
                />
                <p className="mt-4 text-center text-[10px] font-black uppercase tracking-[0.2em] text-zinc-400">
                  Scan with your camera
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
