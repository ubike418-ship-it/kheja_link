"use client";

import { motion, AnimatePresence } from "framer-motion";
import { Menu, X, Search, User, Heart, LayoutDashboard, LogOut, Plus } from "lucide-react";
import { useState, useEffect, useRef } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import Logo from "@/components/Logo";
import { signOutAction } from "@/lib/actions/auth";
import type { ProfileRow } from "@/lib/supabase/database.types";

type NavbarProps = {
  /** Set on the homepage, where categories filter in place instead of navigating. */
  onCategorySelect?: (category: string) => void;
  profile?: ProfileRow | null;
};

const navLinks = [
  { name: "Search Rentals", href: "/properties", category: "hunt" },
  { name: "List Your House", href: "/dashboard/properties/new", category: "list" },
  { name: "Apartments", href: "/properties?type=apartment", category: "apartments" },
  { name: "Bedsitters", href: "/properties?type=bedsitter", category: "bedsitters" },
  { name: "Student Rooms", href: "/properties?type=single_room", category: "rooms" },
  { name: "Shops", href: "/properties?type=shop", category: "shops" },
];

export default function Navbar({ onCategorySelect, profile }: NavbarProps) {
  const router = useRouter();
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isAccountOpen, setIsAccountOpen] = useState(false);
  const [searchValue, setSearchValue] = useState("");
  const searchInputRef = useRef<HTMLInputElement>(null);
  const accountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  // Lock body scroll while the full-screen mobile menu is open.
  useEffect(() => {
    document.body.style.overflow = isMobileMenuOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [isMobileMenuOpen]);

  useEffect(() => {
    if (isSearchOpen) searchInputRef.current?.focus();
  }, [isSearchOpen]);

  useEffect(() => {
    if (!isAccountOpen) return;
    const onClick = (event: MouseEvent) => {
      if (accountRef.current && !accountRef.current.contains(event.target as Node)) {
        setIsAccountOpen(false);
      }
    };
    const onKey = (event: KeyboardEvent) => event.key === "Escape" && setIsAccountOpen(false);
    document.addEventListener("mousedown", onClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [isAccountOpen]);

  const handleLinkClick = (category?: string, href?: string) => {
    setIsMobileMenuOpen(false);
    // On the homepage the circular menu filters in place; everywhere else we
    // navigate to the full search page with the same filter applied.
    if (category && onCategorySelect && category !== "list") {
      onCategorySelect(category);
      document.getElementById("listings")?.scrollIntoView({ behavior: "smooth" });
      return;
    }
    if (href) router.push(href);
  };

  const submitSearch = (event: React.FormEvent) => {
    event.preventDefault();
    const q = searchValue.trim();
    setIsSearchOpen(false);
    setIsMobileMenuOpen(false);
    router.push(q ? `/properties?q=${encodeURIComponent(q)}` : "/properties");
  };

  const isLandlord = profile?.role === "landlord" || profile?.role === "admin";
  const firstName = profile?.full_name?.split(" ")[0];

  return (
    <>
      <motion.nav
        initial={{ y: -100 }}
        animate={{ y: 0 }}
        className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500 ${
          isScrolled ? "py-4 px-6 md:px-12" : "py-6 px-6 md:px-12"
        }`}
      >
        <div
          className={`max-w-7xl mx-auto flex items-center justify-between transition-all duration-500 ${
            isScrolled
              ? "bg-white/80 dark:bg-zinc-900/80 backdrop-blur-xl border border-white/20 dark:border-zinc-800/50 shadow-2xl rounded-[2rem] px-6 py-3"
              : ""
          }`}
        >
          <Logo size={40} />

          {/* Desktop Nav */}
          <div className="hidden md:flex items-center gap-6">
            {navLinks.slice(0, 4).map((item) => (
              <button
                key={item.name}
                onClick={() => handleLinkClick(item.category, item.href)}
                className="text-sm font-bold text-zinc-600 dark:text-zinc-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors"
              >
                {item.name}
              </button>
            ))}
          </div>

          <div className="flex items-center gap-4">
            <button
              onClick={() => setIsSearchOpen((open) => !open)}
              aria-label="Search rentals"
              aria-expanded={isSearchOpen}
              className="p-2 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded-full transition-colors"
            >
              <Search className="w-5 h-5" />
            </button>

            <Link
              href="/favorites"
              aria-label="Saved homes"
              className="hidden sm:block p-2 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded-full transition-colors"
            >
              <Heart className="w-5 h-5" />
            </Link>

            <div className="h-6 w-[1px] bg-zinc-200 dark:bg-zinc-800 hidden sm:block" />

            {profile ? (
              <div className="relative hidden sm:block" ref={accountRef}>
                <button
                  onClick={() => setIsAccountOpen((open) => !open)}
                  aria-haspopup="menu"
                  aria-expanded={isAccountOpen}
                  className="flex items-center gap-2 pl-2 pr-4 py-1.5 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-full font-bold text-sm hover:scale-105 transition-transform"
                >
                  <span className="w-7 h-7 bg-blue-500 rounded-full flex items-center justify-center text-white text-xs font-black uppercase">
                    {firstName?.[0] ?? <User className="w-4 h-4" />}
                  </span>
                  <span className="max-w-[7rem] truncate">{firstName ?? "Account"}</span>
                </button>

                <AnimatePresence>
                  {isAccountOpen && (
                    <motion.div
                      initial={{ opacity: 0, y: 8, scale: 0.96 }}
                      animate={{ opacity: 1, y: 0, scale: 1 }}
                      exit={{ opacity: 0, y: 8, scale: 0.96 }}
                      transition={{ duration: 0.15 }}
                      role="menu"
                      className="absolute right-0 mt-3 w-60 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-3xl shadow-2xl overflow-hidden p-2"
                    >
                      <div className="px-4 py-3">
                        <p className="text-sm font-black text-zinc-900 dark:text-white truncate">
                          {profile.full_name ?? "Your account"}
                        </p>
                        <p className="text-[10px] font-black uppercase tracking-widest text-zinc-400">
                          {profile.role}
                        </p>
                      </div>
                      <div className="h-[1px] bg-zinc-100 dark:bg-zinc-800 mx-2 mb-2" />

                      {isLandlord && (
                        <>
                          <MenuLink href="/dashboard" icon={LayoutDashboard} onNavigate={() => setIsAccountOpen(false)}>
                            Dashboard
                          </MenuLink>
                          <MenuLink href="/dashboard/properties/new" icon={Plus} onNavigate={() => setIsAccountOpen(false)}>
                            List a house
                          </MenuLink>
                        </>
                      )}
                      <MenuLink href="/favorites" icon={Heart} onNavigate={() => setIsAccountOpen(false)}>
                        Saved homes
                      </MenuLink>
                      <MenuLink href="/account" icon={User} onNavigate={() => setIsAccountOpen(false)}>
                        Profile
                      </MenuLink>

                      <form action={signOutAction}>
                        <button
                          type="submit"
                          role="menuitem"
                          className="w-full flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-bold text-red-600 hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
                        >
                          <LogOut className="w-4 h-4" />
                          Sign out
                        </button>
                      </form>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            ) : (
              <Link
                href="/login"
                className="hidden sm:flex items-center gap-2 pl-2 pr-4 py-1.5 bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-full font-bold text-sm hover:scale-105 transition-transform"
              >
                <span className="w-7 h-7 bg-blue-500 rounded-full flex items-center justify-center">
                  <User className="w-4 h-4 text-white" />
                </span>
                <span>Login</span>
              </Link>
            )}

            <button
              onClick={() => setIsMobileMenuOpen((open) => !open)}
              aria-label={isMobileMenuOpen ? "Close menu" : "Open menu"}
              aria-expanded={isMobileMenuOpen}
              className="md:hidden p-2 text-zinc-900 dark:text-white relative z-50"
            >
              {isMobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>

        {/* Inline search, revealed by the magnifier */}
        <AnimatePresence>
          {isSearchOpen && (
            <motion.form
              initial={{ opacity: 0, y: -12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -12 }}
              onSubmit={submitSearch}
              className="max-w-7xl mx-auto mt-3"
            >
              <div className="flex items-center gap-2 p-2 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 rounded-[2rem] shadow-2xl">
                <Search className="w-5 h-5 text-blue-500 ml-4 shrink-0" />
                <input
                  ref={searchInputRef}
                  value={searchValue}
                  onChange={(event) => setSearchValue(event.target.value)}
                  onKeyDown={(event) => event.key === "Escape" && setIsSearchOpen(false)}
                  placeholder="Search homes, areas or house types…"
                  aria-label="Search rentals"
                  className="flex-1 h-12 bg-transparent outline-none font-medium text-zinc-900 dark:text-white placeholder-zinc-400"
                />
                <button
                  type="submit"
                  className="px-6 h-12 bg-blue-600 text-white rounded-2xl font-bold hover:bg-blue-700 transition-colors shrink-0"
                >
                  Search
                </button>
              </div>
            </motion.form>
          )}
        </AnimatePresence>
      </motion.nav>

      {/* Mobile Menu */}
      <AnimatePresence>
        {isMobileMenuOpen && (
          <motion.div
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="fixed inset-0 z-40 bg-white dark:bg-black pt-32 px-10 md:hidden overflow-y-auto"
          >
            <div className="flex flex-col min-h-full">
              <motion.div
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.1 }}
                className="mb-12"
              >
                <span className="text-zinc-400 dark:text-zinc-500 text-xs font-black uppercase tracking-[0.3em]">
                  Quick Links
                </span>
              </motion.div>

              <div className="flex flex-col gap-8">
                {navLinks.map((item, index) => (
                  <motion.div
                    key={item.name}
                    initial={{ opacity: 0, x: -30 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.2 + index * 0.05 }}
                  >
                    <button
                      onClick={() => handleLinkClick(item.category, item.href)}
                      className="text-4xl md:text-5xl font-black text-zinc-900 dark:text-white hover:text-blue-600 dark:hover:text-blue-600 transition-colors tracking-tighter block text-left w-full"
                    >
                      {item.name}
                    </button>
                  </motion.div>
                ))}
              </div>

              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.6 }}
                className="mt-auto pb-12 pt-20 space-y-4"
              >
                <div className="h-[1px] bg-zinc-100 dark:bg-zinc-800 w-full mb-10" />
                {profile ? (
                  <>
                    <Link
                      href={isLandlord ? "/dashboard" : "/favorites"}
                      onClick={() => setIsMobileMenuOpen(false)}
                      className="w-full h-20 bg-blue-600 text-white rounded-[2rem] font-black text-xl shadow-2xl shadow-blue-600/20 active:scale-95 transition-all flex items-center justify-center"
                    >
                      {isLandlord ? "Go to Dashboard" : "Saved Homes"}
                    </Link>
                    <form action={signOutAction}>
                      <button
                        type="submit"
                        className="w-full h-16 rounded-[2rem] font-black text-lg text-zinc-500 border border-zinc-200 dark:border-zinc-800 active:scale-95 transition-all"
                      >
                        Sign out
                      </button>
                    </form>
                  </>
                ) : (
                  <Link
                    href="/signup"
                    onClick={() => setIsMobileMenuOpen(false)}
                    className="w-full h-20 bg-blue-600 text-white rounded-[2rem] font-black text-xl shadow-2xl shadow-blue-600/20 active:scale-95 transition-all flex items-center justify-center"
                  >
                    Get Started
                  </Link>
                )}
              </motion.div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

function MenuLink({
  href,
  icon: Icon,
  children,
  onNavigate,
}: {
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
  onNavigate: () => void;
}) {
  return (
    <Link
      href={href}
      role="menuitem"
      onClick={onNavigate}
      className="flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-bold text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
    >
      <Icon className="w-4 h-4" />
      {children}
    </Link>
  );
}
