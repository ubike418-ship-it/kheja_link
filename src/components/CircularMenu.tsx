"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Home, 
  PlusCircle, 
  Building2, 
  User, 
  LayoutGrid, 
  Sparkles,
  ArrowRight,
  ShoppingBag
} from "lucide-react";

const menuItems = [
  { id: "hunt", label: "Hunt a House", icon: Home, color: "bg-blue-600", activeColor: "#2563eb" },
  { id: "list", label: "List a House", icon: PlusCircle, color: "bg-emerald-600", activeColor: "#059669" },
  { id: "apartments", label: "Apartments", icon: Building2, color: "bg-purple-600", activeColor: "#9333ea" },
  { id: "shops", label: "Shops", icon: ShoppingBag, color: "bg-cyan-600", activeColor: "#0891b2" },
  { id: "rooms", label: "Single Rooms", icon: User, color: "bg-orange-600", activeColor: "#ea580c" },
  { id: "bedsitters", label: "Bedsitters", icon: LayoutGrid, color: "bg-pink-600", activeColor: "#db2777" },
  { id: "premium", label: "Premium Units", icon: Sparkles, color: "bg-amber-600", activeColor: "#d97706" },
];

export default function CircularMenu({
  value,
  onSelect,
}: {
  /** Controlled selection, so the page and the menu never disagree. */
  value?: string;
  onSelect: (id: string) => void;
}) {
  const [internalId, setInternalId] = useState("hunt");
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const selectedId = value ?? internalId;

  const handleSelect = (id: string) => {
    setInternalId(id);
    onSelect(id);
  };

  return (
    <div className="relative flex flex-col items-center justify-center py-10 md:py-20 overflow-visible">
      {/* Background Glow Effect */}
      <AnimatePresence mode="wait">
        <motion.div
          key={selectedId}
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 0.15, scale: 1 }}
          exit={{ opacity: 0, scale: 1.2 }}
          transition={{ duration: 0.8 }}
          className={`absolute inset-0 flex items-center justify-center blur-[120px] pointer-events-none z-0`}
          style={{ backgroundColor: menuItems.find(i => i.id === selectedId)?.activeColor }}
        />
      </AnimatePresence>

      <div className="relative z-10 flex flex-wrap justify-center gap-4 md:gap-8 max-w-6xl px-4">
        {menuItems.map((item) => {
          const isSelected = selectedId === item.id;
          const isHovered = hoveredId === item.id;
          const Icon = item.icon;

          return (
            <motion.button
              key={item.id}
              onClick={() => handleSelect(item.id)}
              onMouseEnter={() => setHoveredId(item.id)}
              onMouseLeave={() => setHoveredId(null)}
              aria-pressed={isSelected}
              aria-label={item.label}
              className="relative flex flex-col items-center group focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-4 rounded-3xl"
              whileHover={{ y: -5 }}
              whileTap={{ scale: 0.95 }}
            >
              <div className="relative flex items-center justify-center">
                <motion.div
                  animate={{
                    scale: isSelected ? 1.15 : isHovered ? 1.05 : 1,
                    backgroundColor: isSelected ? item.activeColor : "rgba(255, 255, 255, 0.9)",
                    boxShadow: isSelected 
                      ? `0 20px 40px -10px ${item.activeColor}66` 
                      : "0 10px 25px -5px rgba(0,0,0,0.05)",
                  }}
                  className={`w-16 h-16 md:w-24 md:h-24 rounded-full flex items-center justify-center backdrop-blur-md border transition-all duration-500 ${
                    isSelected ? "border-transparent" : "border-zinc-200/50 dark:border-zinc-800/50"
                  }`}
                >
                  <Icon 
                    className={`w-6 h-6 md:w-10 md:h-10 transition-all duration-500 ${
                      isSelected ? "text-white" : "text-zinc-500 group-hover:text-zinc-900 dark:group-hover:text-white"
                    } ${isHovered && !isSelected ? "scale-110" : ""}`} 
                  />
                  
                  {isSelected && (
                    <motion.div
                      layoutId="active-ring"
                      className="absolute -inset-2 rounded-full border-2 border-white/20 pointer-events-none"
                      initial={{ opacity: 0, scale: 0.8 }}
                      animate={{ opacity: 1, scale: 1 }}
                      transition={{ type: "spring", stiffness: 300, damping: 30 }}
                    />
                  )}
                </motion.div>
                
                {/* Selection indicator dot */}
                {isSelected && (
                  <motion.div 
                    layoutId="dot"
                    className="absolute -bottom-1 w-2 h-2 rounded-full"
                    style={{ backgroundColor: item.activeColor }}
                  />
                )}
              </div>
              
              <motion.span
                animate={{
                  opacity: isSelected || isHovered ? 1 : 0.6,
                  y: isSelected ? 4 : 0,
                  scale: isSelected ? 1.1 : 1,
                }}
                className={`mt-4 text-xs md:text-sm font-black tracking-tight uppercase transition-colors duration-500 ${
                  isSelected ? "text-zinc-900 dark:text-white" : "text-zinc-500"
                }`}
              >
                {item.label}
              </motion.span>
            </motion.button>
          );
        })}
      </div>

      {/* Floating Info Text */}
      <motion.div
        key={selectedId + "text"}
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        className="mt-12 flex items-center gap-2 px-6 py-2 bg-zinc-100 dark:bg-zinc-900 rounded-full border border-zinc-200 dark:border-zinc-800"
      >
        <div className={`w-2 h-2 rounded-full animate-pulse`} style={{ backgroundColor: menuItems.find(i => i.id === selectedId)?.activeColor }} />
        <span className="text-xs font-bold text-zinc-600 dark:text-zinc-400">
          Showing results for <span className="text-zinc-900 dark:text-white">{menuItems.find(i => i.id === selectedId)?.label}</span>
        </span>
      </motion.div>
    </div>
  );
}
