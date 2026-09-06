"use client";

import { useState } from "react";
import Image from "next/image";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronLeft, ChevronRight, ImageIcon } from "lucide-react";

type GalleryImage = {
  id: string;
  public_url: string;
  alt_text: string | null;
};

/**
 * The original card only ever rendered images[0], but the data model always
 * anticipated a set — this is the gallery that finally uses it.
 */
export default function PropertyGallery({
  images,
  title,
}: {
  images: GalleryImage[];
  title: string;
}) {
  const [index, setIndex] = useState(0);

  if (images.length === 0) {
    return (
      <div className="relative w-full aspect-[16/10] rounded-[3rem] bg-zinc-100 dark:bg-zinc-900 flex flex-col items-center justify-center gap-3 border border-zinc-200 dark:border-zinc-800">
        <ImageIcon className="w-12 h-12 text-zinc-300" />
        <p className="text-sm font-bold text-zinc-400">No photos yet</p>
      </div>
    );
  }

  const go = (delta: number) =>
    setIndex((current) => (current + delta + images.length) % images.length);

  const active = images[index];

  return (
    <div className="space-y-4">
      <div className="relative w-full aspect-[16/10] rounded-[3rem] overflow-hidden bg-zinc-100 dark:bg-zinc-900 group">
        <AnimatePresence mode="wait">
          <motion.div
            key={active.id}
            initial={{ opacity: 0, scale: 1.03 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
            className="absolute inset-0"
          >
            <Image
              src={active.public_url}
              alt={active.alt_text ?? title}
              fill
              priority
              sizes="(max-width: 1024px) 100vw, 60vw"
              className="object-cover"
            />
          </motion.div>
        </AnimatePresence>

        {images.length > 1 && (
          <>
            <button
              onClick={() => go(-1)}
              aria-label="Previous photo"
              className="absolute left-6 top-1/2 -translate-y-1/2 w-12 h-12 rounded-2xl bg-white/10 backdrop-blur-xl border border-white/20 text-white flex items-center justify-center hover:bg-white/20 transition-colors"
            >
              <ChevronLeft className="w-6 h-6" />
            </button>
            <button
              onClick={() => go(1)}
              aria-label="Next photo"
              className="absolute right-6 top-1/2 -translate-y-1/2 w-12 h-12 rounded-2xl bg-white/10 backdrop-blur-xl border border-white/20 text-white flex items-center justify-center hover:bg-white/20 transition-colors"
            >
              <ChevronRight className="w-6 h-6" />
            </button>
            <div className="absolute bottom-6 right-6 px-4 py-2 rounded-2xl bg-black/40 backdrop-blur-xl text-white text-xs font-black tracking-widest">
              {index + 1} / {images.length}
            </div>
          </>
        )}
      </div>

      {images.length > 1 && (
        <div className="flex gap-3 overflow-x-auto scrollbar-hide pb-1">
          {images.map((image, i) => (
            <button
              key={image.id}
              onClick={() => setIndex(i)}
              aria-label={`Show photo ${i + 1}`}
              aria-current={i === index}
              className={`relative w-28 h-20 shrink-0 rounded-2xl overflow-hidden transition-all ${
                i === index
                  ? "ring-2 ring-blue-600 ring-offset-2 ring-offset-[#fafafa] dark:ring-offset-black"
                  : "opacity-60 hover:opacity-100"
              }`}
            >
              <Image
                src={image.public_url}
                alt=""
                fill
                sizes="112px"
                className="object-cover"
              />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
