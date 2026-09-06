"use client";

import { useRef, useState, useTransition } from "react";
import Image from "next/image";
import { ImagePlus, Loader2, X, Star } from "lucide-react";
import { toast } from "sonner";
import { uploadPropertyImageAction } from "@/lib/actions/properties";

const MAX_IMAGES = 12;

/**
 * Uploads straight into Supabase Storage and keeps the resulting public URLs in
 * hidden inputs, so the parent form submits them alongside everything else.
 * The first image is the cover.
 */
export default function PropertyImageUploader({
  initialUrls = [],
}: {
  initialUrls?: string[];
}) {
  const [urls, setUrls] = useState<string[]>(initialUrls);
  const [isPending, startTransition] = useTransition();
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFiles = (files: FileList | null) => {
    if (!files?.length) return;

    const room = MAX_IMAGES - urls.length;
    if (room <= 0) {
      toast.error(`You can upload up to ${MAX_IMAGES} photos.`);
      return;
    }

    const batch = Array.from(files).slice(0, room);

    startTransition(async () => {
      for (const file of batch) {
        const formData = new FormData();
        formData.append("file", file);
        const result = await uploadPropertyImageAction(formData);
        if (result.ok) {
          setUrls((current) => [...current, result.data.url]);
        } else {
          toast.error(`${file.name}: ${result.error}`);
        }
      }
    });

    if (inputRef.current) inputRef.current.value = "";
  };

  const remove = (url: string) => setUrls((current) => current.filter((u) => u !== url));

  const makeCover = (url: string) =>
    setUrls((current) => [url, ...current.filter((u) => u !== url)]);

  return (
    <div className="space-y-4">
      {urls.map((url) => (
        <input key={url} type="hidden" name="imageUrls" value={url} />
      ))}

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
        {urls.map((url, index) => (
          <div
            key={url}
            className="relative aspect-[4/3] rounded-2xl overflow-hidden bg-zinc-100 dark:bg-zinc-800 group border border-zinc-200 dark:border-zinc-700"
          >
            <Image src={url} alt="" fill sizes="200px" className="object-cover" />

            {index === 0 && (
              <span className="absolute top-2 left-2 px-2 py-1 bg-blue-600 text-white rounded-lg text-[9px] font-black uppercase tracking-widest">
                Cover
              </span>
            )}

            <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
              {index !== 0 && (
                <button
                  type="button"
                  onClick={() => makeCover(url)}
                  aria-label="Make this the cover photo"
                  className="w-9 h-9 rounded-xl bg-white/20 backdrop-blur text-white flex items-center justify-center hover:bg-white/30"
                >
                  <Star className="w-4 h-4" />
                </button>
              )}
              <button
                type="button"
                onClick={() => remove(url)}
                aria-label="Remove photo"
                className="w-9 h-9 rounded-xl bg-red-500/90 text-white flex items-center justify-center hover:bg-red-600"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>
        ))}

        {urls.length < MAX_IMAGES && (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            disabled={isPending}
            className="aspect-[4/3] rounded-2xl border-2 border-dashed border-zinc-300 dark:border-zinc-700 flex flex-col items-center justify-center gap-2 text-zinc-400 hover:border-blue-500 hover:text-blue-600 transition-colors disabled:opacity-60"
          >
            {isPending ? (
              <Loader2 className="w-7 h-7 animate-spin" />
            ) : (
              <ImagePlus className="w-7 h-7" />
            )}
            <span className="text-[10px] font-black uppercase tracking-widest">
              {isPending ? "Uploading…" : "Add photos"}
            </span>
          </button>
        )}
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/avif"
        multiple
        onChange={(event) => handleFiles(event.target.files)}
        className="sr-only"
      />

      <p className="text-xs font-medium text-zinc-400">
        JPEG, PNG, WebP or AVIF, up to 5 MB each. The first photo is used as the cover — hover any
        other photo to promote it.
      </p>
    </div>
  );
}
