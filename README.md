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

**[Download Kheja_Link for Android](https://github.com/ubike418-ship-it/kheja_link/releases/download/v1.4.0/app-arm64-v8a-release.apk)** (27 MB) — works on almost every phone from the last several years.

Older 32-bit devices want [this build](https://github.com/ubike418-ship-it/kheja_link/releases/download/v1.4.0/app-armeabi-v7a-release.apk) instead, and all builds are listed on the [releases page](https://github.com/ubike418-ship-it/kheja_link/releases/latest).

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
- Inquiries can be **inserted** by anyone (guests included), but since 0015 only addressed to
  Kheja_Link (`recipient = 'admin'`). They are **read** only by the admins and the original
  sender; landlords keep read access to the inquiries sent to them before 0015.
- Phone numbers and email addresses are never publicly selectable from `profiles`; public
  listing pages read the restricted `public_profiles` view instead.
- Storage objects can only be written into a folder named after the uploader's own user id.

---

## House hunting, availability, requests and alerts (0012)

[`supabase/migrations/0012_hunting_availability_requests.sql`](supabase/migrations/0012_hunting_availability_requests.sql)
adds the house hunting pass (retired in 0015), property availability and vacancy dates, "notify me"
subscriptions, house requests, notification preferences, the Stays waitlist, manual approval
for service providers, and (with `0014_payment_charges.sql`) in-app M-Pesa payments. **All notifications are in-app** (the Inbox tab); Kheja_Link
sends no email or SMS — see `0013_in_app_notifications_only.sql`.

> **Run the migration before deploying this code.** Both apps now select the new
> `availability` column; against an un-migrated database, listings fail to load. Paste the
> migration into the Supabase SQL Editor (or re-run `setup.sql`, which includes it), then deploy.

**Business rules live in the database**, in `app_settings` — edit them at `/admin/settings`
rather than in code: `contact_unlock_fee` (500), `house_refund_amount` (200),
`landlord_listing_fee` (0), the free-listing offer label and optional end date, `stays_enabled`
(false), `service_provider_registration_enabled` (false) and more. How each hunting fee is split
is in `fee_allocations` (100% platform until agreed otherwise); every confirmed payment records
the split in force at the time.

## Pricing: one unlock price, refunds for houses (0015)

[`supabase/migrations/0015_uniform_unlock_refunds.sql`](supabase/migrations/0015_uniform_unlock_refunds.sql):

- **Unlocking a listing costs `contact_unlock_fee` (KES 500)** — the same for every tenant and
  every listing — and gives the landlord's and caretaker's numbers and the exact location. It
  is charged once per listing, when the tenant taps **Unlock contact**. The old KES 150 price is
  gone.
- **The database sets the price.** A trigger prices every `contact_unlocks` row from
  `app_settings`, whatever an app sends; `start_contact_unlock()` resumes an open checkout
  rather than opening a second; `confirm_contact_unlock()` refuses an underpayment and never
  records a second paid unlock for the same listing (a stray second payment is flagged
  `duplicate_payment` and the admins are told, for a manual refund).
- **Give us a house, get `house_refund_amount` (KES 200) back.** A tenant who paid for an unlock
  submits a vacant house in the app (`house_submissions`). An admin approves it at
  `/admin/refunds`, which approves the refund (`unlock_refunds`: pending → approved → paid);
  the admin sends the money by M-Pesa and marks it paid. One refund per paid unlock. Each step
  is an in-app notification.
- **No free messages to landlords.** New inquiries go to the admins (`/admin/messages`), who
  reply in-app; the reply lands in the sender's Inbox.
- **Existing access is kept**: unlocks paid at KES 150 and House Hunting passes bought before
  0015 keep working. The pass itself is no longer sold.

## Security, the locked location and 3-hour unlocks (0016)

[`supabase/migrations/0016_security_location_lock_3h_unlocks.sql`](supabase/migrations/0016_security_location_lock_3h_unlocks.sql),
from a pre-launch security review:

- **Sign-up can no longer create an admin.** The role in sign-up metadata is clamped to tenant
  or landlord, and a guard stops any non-admin writing a privileged profile row.
- **Landlord phone numbers are no longer public.** `profiles` is readable only by its owner and
  admins; everyone else reads `public_profiles` (name, avatar, badge).
- **The location is locked.** Everyone sees the area and the landlord's description of the
  location (`nearby`); the street, building and Google Maps pin come only through
  `get_property_contact()`. Search no longer indexes the street.
- **An unlock lasts `contact_unlock_hours` (3) from payment**, then the listing locks again and
  the tenant pays again to reopen it.
- **Rate limits**: 5 messages an hour per account/phone/email; M-Pesa prompts limited per
  payment, per account and per phone number (the payment server checks `payment_attempts`).
- **Back office**: `admin_overview()` and `admin_list_users()` power `/admin` — Overview,
  Users, Listings, Payments, Messages, Houses & refunds, Service providers, Stays, Settings.

The website also sends security headers (CSP, HSTS, no framing, nosniff), card checkout requires
the signed-in owner of the payment, and the Android app disables backups and cleartext HTTP.

### Going live: reset the data

[`supabase/reset_for_production.sql`](supabase/reset_for_production.sql) is **not** a migration.
Run it once, by hand, after 0016: it deletes every account except the demo landlord (and all
their activity), keeps the demo landlord's sample listings, areas, types, amenities, providers
and prices, then shows how to make your own account the admin.

### Payments

Tenants pay **inside Kheja_Link's own screens**: they choose M-Pesa, type their number, and
approve the prompt on their phone. Paystack is the processor behind that, used as an API —
the app never opens a Paystack page for M-Pesa and never holds a key.

```
app  ──▶  /api/payments/charge   ──▶  Paystack  /charge          (start an M-Pesa charge)
app  ──▶  /api/payments/status   ──▶  Paystack  /transaction/verify/:ref
Paystack ──▶  /api/payments/webhook                               (signed, independent)
```

The amount always comes from the pending row in our own database, read as the signed-in
tenant, so nothing the app sends can change what is charged. A payment is marked paid only
after Paystack itself confirms it — through the signed webhook, or through the server-side
verify — so a payment still completes if the webhook is slow. Underpayments are refused and
confirming twice does nothing.

**Cards** are the one thing that leaves the app: "Pay by card" opens Paystack's secure page
for the same payment. Taking card numbers in our own screens would make Kheja_Link liable
for PCI-DSS compliance, which Paystack also requires before allowing it.

Set up in Paystack → **Settings → API Keys & Webhooks**:

| Setting | Value |
| --- | --- |
| Webhook URL (live) | `https://www.khejalink.name.ng/api/payments/webhook` |
| `PAYSTACK_SECRET_KEY` on Vercel | the **live** secret key, `sk_live_…` |
| `SUPABASE_SERVICE_ROLE_KEY` on Vercel | required — without it no payment can be recorded |

**Admin → Business settings** shows a live Payments panel: whether the key works, whether the
account has KES enabled, whether payments can be recorded, and the webhook URL to paste.

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
| `PAYMENTS_DEMO_MODE` | `true` only for testing payments without Paystack — unlocks are then granted without charging. Never in production |

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
