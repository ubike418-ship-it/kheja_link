## Project Summary
Kheja_Link is a rental property discovery platform for Meru, Kenya. It focuses strictly on long-term rentals — apartments, family homes, shops, bedsitters and student rooms — rather than short-stay or Airbnb-style bookings. The interface is motion-centric, with an interactive circular category menu and a built-in assistant that searches live listings.

## Tech Stack
- **Framework**: Next.js 15 (App Router), React 19, TypeScript (strict)
- **Backend / Database**: Supabase — PostgreSQL, Auth, Storage, Row Level Security. **Supabase only**; do not introduce another database, ORM or auth library.
- **Styling**: Tailwind CSS v4 (CSS-first `@theme`, no tailwind.config), shadcn/ui primitives in `src/components/ui`
- **Animations**: Framer Motion
- **Icons**: Lucide React
- **Deployment**: Vercel

## Architecture
- `src/app/` — routes. Server components by default; `"use client"` only where interaction demands it.
- `src/components/` — feature components. `ui/` holds the shadcn primitives.
- `src/lib/supabase/` — `client.ts` (browser), `server.ts` (RSC / actions), `env.ts`, `database.types.ts`.
- `src/lib/queries/` — reads. `src/lib/actions/` — writes, as server actions.
- `supabase/migrations/` — schema, RLS and seed. `supabase/setup.sql` is all three concatenated.

## Conventions
- **Authorization belongs in RLS**, not in application code. Application checks exist only to produce friendly messages.
- Never use the `service_role` key. Never hard-code credentials — everything comes from `NEXT_PUBLIC_*` env vars.
- Prices are numeric (`price_amount` + `price_currency` + `price_period`) and formatted through `src/lib/format.ts`. Never store a formatted price string.
- Filter state lives in the URL query string, so every search is shareable and server-rendered.
- Validate every form with the Zod schemas in `src/lib/validation.ts`; they mirror the database CHECK constraints.
- Server actions return the `ActionResult` shape from `src/lib/types.ts`.
- Keep a loading state, an empty state and an error path for anything that touches the database.

## Design Guidelines
- **Branding**: "Kheja_Link" (formerly HouseHunt Meru / Hunt Meru / staysKenya). The logo is `public/khejalink-logo.jpeg`, rendered through `src/components/Logo.tsx`.
- **Aesthetics**: professional, modern, high-motion. Blue-600 primary with emerald, purple and amber accents; zinc-900/black dark mode.
- **Shape language**: heavily rounded — `rounded-2xl` for controls, `rounded-[2rem]`–`rounded-[4rem]` for cards and panels.
- **Type**: `font-black tracking-tighter` for display headings; `text-[10px] font-black uppercase tracking-[0.2em]` for eyebrow labels.
- Use professional terminology ("Monthly Rent", never "Per Night").
- Meru place names should stay accurate (Makutano, Nkubu, Meru Town, Kinoru, Milimani, MUST area).
- Preserve the existing design when adding features — this frontend was designed first and the backend was fitted to it.
