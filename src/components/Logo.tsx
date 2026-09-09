import Image from "next/image";
import Link from "next/link";
import { cn } from "@/lib/utils";

type LogoProps = {
  /** Rendered mark size in pixels. */
  size?: number;
  /** Hide the wordmark and show the mark alone (used in tight spaces). */
  markOnly?: boolean;
  className?: string;
  wordmarkClassName?: string;
  href?: string | null;
};

/**
 * The Kheja_Link brand mark.
 *
 * The supplied logo is a photographic JPEG on a dark ground, so it is set in a
 * rounded tile — that keeps it looking deliberate on both the light and dark
 * themes rather than floating as a dark square.
 */
export function LogoMark({ size = 40, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn("relative block shrink-0", className)}
      style={{ width: size, height: size }}
    >
      {/* A blurred copy of the mark glowing behind it. The raw asset is a
          hard-edged photograph and reads as a screenshot without this. */}
      <span
        aria-hidden
        className="absolute -inset-[12%] rounded-[40%] opacity-55 blur-lg pointer-events-none"
        style={{
          backgroundImage: "url(/khejalink-logo.jpeg)",
          backgroundSize: "cover",
          backgroundPosition: "center",
        }}
      />
      <span className="relative block h-full w-full overflow-hidden rounded-2xl ring-1 ring-black/5 dark:ring-white/10 shadow-lg shadow-black/20">
        <Image
          src="/khejalink-logo.jpeg"
          alt=""
          width={size * 2}
          height={size * 2}
          className="h-full w-full object-cover blur-[0.3px]"
          priority
        />
        {/* A diagonal sheen, so the tile catches light like a real object. */}
        <span
          aria-hidden
          className="absolute inset-0 bg-gradient-to-br from-white/20 via-white/5 to-transparent"
        />
      </span>
    </span>
  );
}

export default function Logo({
  size = 40,
  markOnly = false,
  className,
  wordmarkClassName,
  href = "/",
}: LogoProps) {
  const content = (
    <>
      <LogoMark size={size} />
      {!markOnly && (
        <span
          className={cn(
            "text-2xl font-black tracking-tighter text-zinc-900 dark:text-white",
            wordmarkClassName,
          )}
        >
          KHEJA<span className="text-blue-600">_LINK</span>
        </span>
      )}
    </>
  );

  if (!href) {
    return <span className={cn("flex items-center gap-2", className)}>{content}</span>;
  }

  return (
    <Link
      href={href}
      aria-label="Kheja_Link home"
      className={cn("flex items-center gap-2 group", className)}
    >
      {content}
    </Link>
  );
}
