"use client";

import { Heart, Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { toggleFavoriteAction } from "@/lib/actions/favorites";

/** Standalone save control for the detail page, where the card's heart is absent. */
export default function FavoriteButton({
  propertyId,
  initiallyFavorited = false,
  className,
}: {
  propertyId: string;
  initiallyFavorited?: boolean;
  className?: string;
}) {
  const router = useRouter();
  const [isLiked, setIsLiked] = useState(initiallyFavorited);
  const [isPending, startTransition] = useTransition();

  const toggle = () => {
    const next = !isLiked;
    setIsLiked(next);
    startTransition(async () => {
      const result = await toggleFavoriteAction(propertyId);
      if (!result.ok) {
        setIsLiked(!next);
        toast.error(result.error, {
          action: { label: "Sign in", onClick: () => router.push("/login") },
        });
        return;
      }
      setIsLiked(result.data.favorited);
      toast.success(result.message ?? "Saved.");
    });
  };

  return (
    <button
      onClick={toggle}
      disabled={isPending}
      aria-pressed={isLiked}
      className={
        className ??
        "flex items-center justify-center gap-2 px-6 h-14 rounded-2xl font-black border border-zinc-200 dark:border-zinc-800 text-zinc-700 dark:text-zinc-300 hover:border-blue-500 transition-colors disabled:opacity-70"
      }
    >
      {isPending ? (
        <Loader2 className="w-5 h-5 animate-spin" />
      ) : (
        <Heart className={`w-5 h-5 ${isLiked ? "fill-red-500 text-red-500" : ""}`} />
      )}
      {isLiked ? "Saved" : "Save"}
    </button>
  );
}
