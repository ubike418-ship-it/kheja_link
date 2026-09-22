# Kheja_Link

A modern rental-discovery platform for **Meru, Kenya**. Kheja_Link makes long-term house
hunting — apartments, bedsitters, single rooms, family homes and shops — simple, searchable
and transparent, and gives landlords a straightforward way to list and manage their properties.

This repository holds both clients:

| | |
| --- | --- |
| **Web** (repo root) | Next.js 15 (App Router), Tailwind CSS v4, deployed on Vercel |
| **Mobile** ([`mobile/`](mobile/)) | Flutter — Android, iOS and web |

Both talk to the **same Supabase project** (PostgreSQL, Auth, Storage, Row Level Security),
so a listing published on the web appears in the app immediately, and a home saved on the
phone shows up on the website under the same account.

See [`mobile/README.md`](mobile/README.md) for the Flutter app.

### Download the Android app

**[Download Kheja_Link for Android](https://github.com/ubike418-ship-it/kheja_link/releases/download/v1.3.1/app-arm64-v8a-release.apk)** (27 MB) — works on almost every phone from the last several years.

Older 32-bit devices want [this build](https://github.com/ubike418-ship-it/kheja_link/releases/download/v1.3.1/app-armeabi-v7a-release.apk) instead, and all builds are listed on the [releases page](https://github.com/ubike418-ship-it/kheja_link/releases/latest).

---

## Getting started

### 1. Install

```bash
npm install
```

### 2. Configure environment variables

```bash
cp .env.example .env.local
```

Fill in the values from your Supabase project (**Project Settings → API**):

| Variable | What it is |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Your project URL, e.g. `https://xxxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | The anon / public key. Safe in the browser — Row Level Security is what protects the data |
| `NEXT_PUBLIC_SITE_URL` | `http://localhost:3000` locally; your real domain in production |

> **Never** put the `service_role` key in a `NEXT_PUBLIC_` variable or in the Flutter app. It
> bypasses every Row Level Security policy. Only the payment server routes use it, as the
> server-only `SUPABASE_SERVICE_ROLE_KEY`.

### 3. Set up the database

Open the **SQL Editor** in your Supabase dashboard, paste in the contents of
[`supabase/setup.sql`](supabase/setup.sql), and run it. That single file creates the schema,
the Row Level Security policies, the storage buckets, and seed data (property types, Meru
locations, amenities and twelve demo listings).

It is idempotent — running it again is safe.

The seed creates a demo landlord so the dashboard is not empty:

```
demo.landlord@khejalink.co.ke  /  KhejaDemo2026!
```

**Delete that account before going live.**

### 4. Configure auth redirects

In Supabase → **Authentication → URL Configuration**, add these to *Redirect URLs*:

```
http://localhost:3000/auth/callback
https://your-domain.vercel.app/auth/callback
ke.co.khejalink://login-callback
```

The last one is the Flutter app's deep link, so email confirmations return to the app.

Set *Site URL* to your production domain.

### 5. Run it

```bash
npm run dev
```

Open <http://localhost:3000>.

---

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Development server (Turbopack) |
| `npm run build` | Production build |
| `npm run start` | Serve the production build |
| `npm run lint` | ESLint |
| `npm run typecheck` | `tsc --noEmit` |

---

## Architecture

```
mobile/                       The Flutter app (see mobile/README.md)
src/
├── app/                      Routes (App Router)
│   ├── page.tsx              Home — hero, category menu, featured listings
│   ├── properties/           Search + filters, and /properties/[slug] detail
│   ├── dashboard/            Landlord area: listings, editor, inquiries
│   ├── login, signup         Auth screens
│   ├── auth/callback         Exchanges the email link for a session
│   ├── favorites, account    Signed-in pages
│   ├── help, terms, privacy  Static content
│   └── sitemap.ts, robots.ts SEO
├── components/               UI. `ui/` holds the shadcn primitives
├── lib/
│   ├── supabase/             Browser, server and middleware clients + types
│   ├── queries/              Read paths (properties, favorites, inquiries, lookups)
│   ├── actions/              Write paths — server actions
│   ├── validation.ts         Zod schemas mirroring the DB constraints
│   └── format.ts             Currency, size, location and phone formatting
└── middleware.ts             Session refresh + route guards
supabase/
├── setup.sql                 Everything, in one paste-ready file
└── migrations/               The same thing, split into numbered migrations
```

### How authorization works

Authorization lives in the **database**, not in the application code. Every table has Row
Level Security enabled, so a forged request cannot read or write what it should not:

- Only `published` listings are publicly readable; a landlord additionally sees their own drafts.
- A landlord can only insert, update or delete rows where `owner_id = auth.uid()`.
- Favourites are readable and writable only by the user they belong to.
- Inquiries can be **inserted** by anyone (guests can contact a landlord) but **read** only by
  the listing's owner and the original sender.
- Phone numbers and email addresses are never publicly selectable from `profiles`; public
  listing pages read the restricted `public_profiles` view instead.
- Storage objects can only be written into a folder named after the uploader's own user id.

---

## House hunting, availability, requests and alerts (0012)

[`supabase/migrations/0012_hunting_availability_requests.sql`](supabase/migrations/0012_hunting_availability_requests.sql)
adds the KES 500 house hunting fee, property availability and vacancy dates, "notify me"
subscriptions, house requests, notification preferences, the Stays waitlist, and manual
approval for service providers. **All notifications are in-app** (the Inbox tab); Kheja_Link
sends no email or SMS — see `0013_in_app_notifications_only.sql`.

> **Run the migration before deploying this code.** Both apps now select the new
> `availability` column; against an un-migrated database, listings fail to load. Paste the
> migration into the Supabase SQL Editor (or re-run `setup.sql`, which includes it), then deploy.

**Business rules live in the database**, in `app_settings` — edit them at `/admin/settings`
rather than in code: `hunting_fee` (500), `landlord_listing_fee` (0), the free-listing offer
label and optional end date, `stays_enabled` (false), `service_provider_registration_enabled`
(false) and more. How each hunting fee is split is in `fee_allocations` (100% platform until
agreed otherwise); every confirmed payment records the split in force at the time.

**Payments** reuse the Paystack route and webhook. The fee is only ever marked paid by the
signed webhook, underpayments are refused, and a retried webhook changes nothing.

**Admin** (`/admin`): approve, edit and disable movers / internet / cleaning companies, see the
Stays waitlist, and edit business settings. Make an account an admin in the SQL Editor:

```sql
update public.profiles set role = 'admin' where id = '<user id>';
```

### Keeping the free Supabase project awake

A free Supabase project pauses after about a week without API activity. Two independent jobs
query it:

1. **GitHub Actions**, every hour — [`.github/workflows/supabase-keepalive.yml`](.github/workflows/supabase-keepalive.yml).
   Add repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
   GitHub switches scheduled workflows off after 60 days without commits; re-enable it from the
   Actions tab if you get that email.
2. **Vercel Cron**, daily — [`vercel.json`](vercel.json) calls `/api/cron/daily`.

Both also run `run_daily_maintenance()`, which opens homes whose vacancy date has arrived and
expires abandoned checkouts. This is a strong safeguard, not a guarantee: Supabase can change
its free-tier policy.

### Environment variables added

| Variable | What it is |
| --- | --- |
| `CRON_SECRET` | Optional. Protects `/api/cron/daily`, the keep-alive job |
| `PAYMENTS_DEMO_MODE` | `true` only for testing the hunting fee without Paystack. Never in production |

---

## Deploying to Vercel

1. Push this repository to GitHub.
2. In Vercel, **Add New → Project** and import it. The framework preset is detected
   automatically; leave the root directory as the repository root.
3. Under **Environment Variables**, add all three variables from `.env.example` for the
   Production, Preview and Development environments. Set `NEXT_PUBLIC_SITE_URL` to your real
   domain in Production.
4. Deploy.
5. Go back to Supabase → **Authentication → URL Configuration** and add your deployed
   `https://<domain>/auth/callback` to the redirect list.

---

## Licence

Private project. Developed by **ralph_tech**.
