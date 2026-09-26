"use client";

import { motion } from "framer-motion";
import { Mail, Phone, MapPin } from "lucide-react";
import Link from "next/link";
import { LogoMark } from "@/components/Logo";
import { TikTokIcon, WhatsAppIcon } from "@/components/SocialIcons";
import { SOCIAL } from "@/lib/social";

const quickLinks = [
  { label: "Search Rentals", href: "/properties" },
  { label: "List Your House", href: "/dashboard/properties/new" },
  { label: "Apartments", href: "/properties?type=apartment" },
  { label: "Bedsitters", href: "/properties?type=bedsitter" },
  { label: "Student Rooms", href: "/properties?type=single_room" },
];

const supportLinks = [
  { label: "Help Center", href: "/help" },
  { label: "Safety Tips", href: "/help#safety" },
  { label: "Terms of Service", href: "/terms" },
  { label: "Privacy Policy", href: "/privacy" },
  { label: "Contact Us", href: "/help#contact" },
];

/** The only two channels Kheja_Link runs — see src/lib/social.ts. */
const socials = [
  { Icon: TikTokIcon, label: SOCIAL.tiktok.label, href: SOCIAL.tiktok.url, hover: "#ffffff", hoverBg: "rgba(255, 255, 255, 0.12)" },
  { Icon: WhatsAppIcon, label: SOCIAL.whatsapp.label, href: SOCIAL.whatsapp.url, hover: "#25D366", hoverBg: "rgba(37, 211, 102, 0.12)" },
];

export default function Footer() {
  return (
    <footer className="bg-zinc-950 text-white pt-24 pb-12 px-6 overflow-hidden">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-16 mb-20">
          {/* Brand */}
          <div className="space-y-8">
            <Link href="/" className="flex items-center gap-3 group" aria-label="Kheja_Link home">
              <motion.div
                whileHover={{ rotate: 12, scale: 1.1 }}
                transition={{ type: "spring", stiffness: 300 }}
              >
                <LogoMark size={56} />
              </motion.div>
              <span className="text-3xl font-black tracking-tighter">
                KHEJA<span className="text-blue-600">_LINK</span>
              </span>
            </Link>
            <p className="text-zinc-400 text-lg leading-relaxed font-medium">
              Meru&apos;s premier platform for professional house hunting. We simplify finding your next
              rental space with technology and transparency.
            </p>
            <div className="flex gap-4">
              {socials.map(({ Icon, label, href, hover, hoverBg }) => (
                <motion.a
                  key={label}
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={`Kheja_Link on ${label}`}
                  title={`Kheja_Link on ${label}`}
                  whileHover={{ y: -8, color: hover, backgroundColor: hoverBg }}
                  className="w-12 h-12 rounded-2xl bg-zinc-900 flex items-center justify-center text-zinc-400 transition-all duration-300"
                >
                  <Icon className="w-5 h-5" />
                </motion.a>
              ))}
            </div>
          </div>

          {/* Links */}
          <div>
            <h4 className="font-black mb-8 uppercase tracking-widest text-zinc-500 text-[10px]">
              Quick Links
            </h4>
            <ul className="space-y-5">
              {quickLinks.map((link) => (
                <li key={link.label}>
                  <Link
                    href={link.href}
                    className="text-zinc-400 hover:text-white transition-colors font-bold text-lg"
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          {/* Support */}
          <div>
            <h4 className="font-black mb-8 uppercase tracking-widest text-zinc-500 text-[10px]">
              Support
            </h4>
            <ul className="space-y-5">
              {supportLinks.map((link) => (
                <li key={link.label}>
                  <Link
                    href={link.href}
                    className="text-zinc-400 hover:text-white transition-colors font-bold text-lg"
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          {/* Contact */}
          <div className="space-y-8">
            <h4 className="font-black mb-8 uppercase tracking-widest text-zinc-500 text-[10px]">
              Get in Touch
            </h4>
            <div className="space-y-6">
              <a
                href="mailto:hello@khejalink.co.ke"
                className="flex items-center gap-4 text-zinc-400 group hover:text-white transition-colors"
              >
                <span className="w-10 h-10 rounded-xl bg-blue-500/10 flex items-center justify-center group-hover:bg-blue-500 transition-colors">
                  <Mail className="w-5 h-5 group-hover:text-white" />
                </span>
                <span className="font-bold">hello@khejalink.co.ke</span>
              </a>
              <a
                href="tel:+254710655709"
                className="flex items-center gap-4 text-zinc-400 group hover:text-white transition-colors"
              >
                <span className="w-10 h-10 rounded-xl bg-emerald-500/10 flex items-center justify-center group-hover:bg-emerald-500 transition-colors">
                  <Phone className="w-5 h-5 group-hover:text-white" />
                </span>
                <span className="font-bold">+254 710 655 709</span>
              </a>
              <a
                href={SOCIAL.whatsapp.url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-4 text-zinc-400 group hover:text-white transition-colors"
              >
                <span className="w-10 h-10 rounded-xl bg-[#25D366]/10 flex items-center justify-center group-hover:bg-[#25D366] transition-colors">
                  <WhatsAppIcon className="w-5 h-5 text-[#25D366] group-hover:text-white" />
                </span>
                <span className="font-bold">WhatsApp {SOCIAL.whatsapp.number}</span>
              </a>
              <a
                href={SOCIAL.tiktok.url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-4 text-zinc-400 group hover:text-white transition-colors"
              >
                <span className="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center group-hover:bg-white group-hover:text-black transition-colors">
                  <TikTokIcon className="w-5 h-5" />
                </span>
                <span className="font-bold">TikTok {SOCIAL.tiktok.handle}</span>
              </a>
              <div className="flex items-start gap-4 text-zinc-400">
                <span className="w-10 h-10 rounded-xl bg-purple-500/10 flex items-center justify-center shrink-0">
                  <MapPin className="w-5 h-5" />
                </span>
                <span className="font-bold leading-tight">Greenwood Mall, Meru Town, Kenya</span>
              </div>
            </div>
          </div>
        </div>

        <div className="pt-10 border-t border-zinc-900 flex flex-col md:flex-row justify-between items-center gap-6 text-zinc-500 text-sm font-medium">
          <div className="space-y-1 text-center md:text-left">
            <p>&copy; {new Date().getFullYear()} KHEJA_LINK. Built for the modern seeker.</p>
            <p className="text-[10px] uppercase tracking-[0.2em] font-black text-zinc-600">
              Developed by <span className="text-blue-500">ralph_tech</span>
            </p>
          </div>
          <div className="flex gap-10">
            <Link href="/privacy" className="hover:text-white transition-colors">
              Privacy
            </Link>
            <Link href="/terms" className="hover:text-white transition-colors">
              Terms
            </Link>
            <Link href="/privacy#cookies" className="hover:text-white transition-colors">
              Cookies
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
