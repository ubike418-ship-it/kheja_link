/**
 * What the Kheja_Link assistant knows about Kheja_Link.
 *
 * Every answer is either a stated fact about how the product works or is
 * generated from live database figures passed in as `stats`. Nothing here
 * invents listings, prices or availability — if a question needs real data,
 * the answer reads it from `stats` rather than guessing.
 */

export type SiteStats = {
  total: number;
  minPrice: number;
  maxPrice: number;
  locations: string[];
  types: { name: string; slug: string; count: number }[];
  amenities: string[];
  cheapest?: { title: string; price: string; slug: string } | null;
};

export type KnowledgeAnswer = {
  message: string;
  /** An in-app link that helps the person act on the answer. */
  href?: string;
  hrefLabel?: string;
  /** Follow-up chips, so the conversation has somewhere obvious to go. */
  suggestions?: string[];
};

export type KnowledgeEntry = {
  id: string;
  /** Higher wins when several entries match. */
  priority: number;
  patterns: RegExp[];
  answer: (stats: SiteStats) => KnowledgeAnswer;
};

const list = (items: string[]): string => {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
};

const money = (amount: number) =>
  `KSh ${new Intl.NumberFormat("en-KE", { maximumFractionDigits: 0 }).format(amount)}`;

/**
 * Ordered by specificity, not by topic: `matchKnowledge` scores every entry and
 * takes the best, so a narrow pattern must outrank a broad one via `priority`.
 */
export const KNOWLEDGE: KnowledgeEntry[] = [
  // ---------------------------------------------------------------------------
  // About the product
  // ---------------------------------------------------------------------------
  {
    id: "what-is-kheja",
    priority: 60,
    patterns: [
      /\bwhat (is|are) (this|kheja|kheja_?link)\b/,
      /\b(about|tell me about) (this (site|app|platform)|kheja_?link)\b/,
      /\bwho are you\b/,
      /\bwhat (do|can) you do\b/,
      /\bhow does (this|kheja_?link) work\b/,
      /\bwhat can i do here\b/,
    ],
    answer: (stats) => ({
      message:
        `Kheja_Link is a rental listing platform for Meru, Kenya. We focus only on long-term rentals — ` +
        `apartments, bedsitters, single rooms, family homes and shops — not short stays.\n\n` +
        `Right now there ${stats.total === 1 ? "is" : "are"} ${stats.total} ` +
        `${stats.total === 1 ? "home" : "homes"} listed across ${stats.locations.length} areas of Meru.\n\n` +
        `You can search and filter for free without an account, see photos and full details, and contact ` +
        `the landlord directly — we never sit in the middle of the deal. If you have a house to rent out, ` +
        `you can list it yourself.`,
      href: "/properties",
      hrefLabel: "Browse all homes",
      suggestions: ["What areas do you cover?", "Is it free?", "How do I list my house?"],
    }),
  },
  {
    id: "areas-covered",
    priority: 70,
    patterns: [
      /\b(what|which) (areas|places|towns|locations|estates|neighbou?rhoods)\b/,
      /\bwhere (do you|are you|does kheja).*(cover|operate|have|list)\b/,
      /\bareas (do you )?(cover|serve|have)\b/,
      /\blist of (areas|locations)\b/,
      /\bwhich parts of meru\b/,
    ],
    answer: (stats) => ({
      message:
        `We cover ${stats.locations.length} areas across Meru County: ${list(stats.locations)}.\n\n` +
        `Meru Town and Makutano have the most listings, and the MUST area is where most student rooms are. ` +
        `You can filter by any of these on the search page.`,
      href: "/properties",
      hrefLabel: "Search by area",
      suggestions: ["Show me houses in Makutano", "Rooms near MUST", "What types of houses?"],
    }),
  },
  {
    id: "types-available",
    priority: 70,
    patterns: [
      /\b(what|which) (kind|kinds|type|types|sort|sorts) of (house|home|propert|place|unit|rental)/,
      /\bwhat (houses|homes|properties) do you have\b/,
      /\btypes? (do you have|available|of listing)\b/,
      /\bdo you have (apartments|bedsitters|shops|rooms|maisonettes|bungalows)\b/,
    ],
    answer: (stats) => {
      const withCounts = stats.types
        .filter((t) => t.count > 0)
        .map((t) => `• ${t.name} — ${t.count} listed`);
      const empty = stats.types.filter((t) => t.count === 0).map((t) => t.name);

      return {
        message:
          `Here's what's on Kheja_Link right now:\n\n${withCounts.join("\n")}` +
          (empty.length
            ? `\n\nWe also support ${list(empty)}, though none are listed at the moment.`
            : ""),
        href: "/properties",
        hrefLabel: "Browse everything",
        suggestions: ["Show me apartments", "Show me bedsitters", "Shops to let"],
      };
    },
  },
  {
    id: "how-many",
    priority: 75,
    patterns: [
      /\bhow many (houses|homes|listings|properties|rentals|units)\b/,
      /\bnumber of (houses|homes|listings|properties)\b/,
      /\bhow many.*(do you have|are (there|listed|available))\b/,
    ],
    answer: (stats) => ({
      message:
        `There ${stats.total === 1 ? "is" : "are"} currently ${stats.total} published ` +
        `${stats.total === 1 ? "home" : "homes"} on Kheja_Link, spread across ${stats.locations.length} ` +
        `areas of Meru, with rents from ${money(stats.minPrice)} to ${money(stats.maxPrice)} a month.\n\n` +
        `New homes are added regularly, so it's worth checking back.`,
      href: "/properties",
      hrefLabel: "See all listings",
      suggestions: ["What's the cheapest?", "What areas do you cover?"],
    }),
  },
  {
    id: "price-range",
    priority: 65,
    patterns: [
      /\b(what|how much).*(price range|rent range|range of (price|rent))\b/,
      /\bhow much (are|do) (the |your )?(house|home|rent|rental|place)/,
      /\bwhat.*(rents?|prices?) (like|start|range)\b/,
      /\b(average|typical) (rent|price)\b/,
      /\bcheapest\b/,
      /\bmost expensive\b/,
    ],
    answer: (stats) => ({
      message:
        `Rents on Kheja_Link run from ${money(stats.minPrice)} to ${money(stats.maxPrice)} a month.\n\n` +
        `As a rough guide for Meru: single rooms and student housing sit at the bottom of that range, ` +
        `bedsitters in the middle, and family homes and executive apartments at the top. Shops are priced ` +
        `on footfall rather than size.\n\n` +
        (stats.cheapest
          ? `The lowest right now is ${stats.cheapest.title} at ${stats.cheapest.price}.\n\n`
            : "") +
        `Tell me your budget — something like "2 bedroom under 30k" — and I'll show you what fits.`,
      href: "/properties?sort=price_asc",
      hrefLabel: "Cheapest first",
      suggestions: ["Under 15k", "2 bedroom under 30k", "Premium units"],
    }),
  },

  // ---------------------------------------------------------------------------
  // Cost and accounts
  // ---------------------------------------------------------------------------
  {
    id: "is-it-free",
    priority: 80,
    patterns: [
      /\b(is|are) (it|this|kheja_?link|the (app|site|service)) free\b/,
      /\bdo (i|you) (have to |need to )?pay\b/,
      /\b(how much|what).*(cost|charge|fee|commission).*(use|search|list|post|you)\b/,
      /\b(any|hidden) (fees|charges|commission)\b/,
      /\bfree to (use|search|list|post)\b/,
      /\bdo you charge\b/,
    ],
    answer: () => ({
      message:
        `Yes — Kheja_Link is free.\n\n` +
        `For house hunters: searching, filtering, saving homes and messaging landlords all cost nothing, ` +
        `and you don't even need an account to browse or send an inquiry.\n\n` +
        `For landlords: listing a property is free too.\n\n` +
        `We don't take a commission on rent, and we never handle your money — rent and deposits go ` +
        `directly between you and the landlord.`,
      suggestions: ["How do I list my house?", "Is it safe?", "Do I need an account?"],
    }),
  },
  {
    id: "need-account",
    priority: 80,
    patterns: [
      /\b(do|must) i (need|have to) (an? )?(account|sign ?up|register|log ?in)\b/,
      /\bwithout an account\b/,
      /\bcan i (browse|search|look|use).*(without|no) (account|signing|login)\b/,
      /\bwhy (should|do) i (sign ?up|register|create an account)\b/,
    ],
    answer: () => ({
      message:
        `No account needed to browse.\n\n` +
        `You can search, filter, view full listings with photos, and even send a landlord a message ` +
        `as a guest.\n\n` +
        `An account only unlocks three things:\n` +
        `• Saving homes to a shortlist that follows you between the website and the app\n` +
        `• Keeping track of messages you've sent\n` +
        `• Listing your own property, if you're a landlord\n\n` +
        `Signing up takes about a minute and is free.`,
      href: "/signup",
      hrefLabel: "Create an account",
      suggestions: ["How do I save a home?", "How do I list my house?"],
    }),
  },
  {
    id: "how-to-signup",
    priority: 72,
    patterns: [
      /\bhow (do|can) i (sign ?up|register|create an account|make an account)\b/,
      /\bcreate (an )?account\b/,
      /\bsign ?up (process|steps)?\b/,
    ],
    answer: () => ({
      message:
        `Head to the sign-up page, choose whether you're looking for a house or listing one, ` +
        `and enter your name, email and a password.\n\n` +
        `We'll email you a confirmation link — click it and you're in. You can switch between a ` +
        `house-hunter and landlord account later from your profile, so the choice isn't permanent.`,
      href: "/signup",
      hrefLabel: "Sign up",
      suggestions: ["I didn't get the confirmation email", "How do I list my house?"],
    }),
  },
  {
    id: "login-trouble",
    priority: 85,
    patterns: [
      /\b(forgot|reset|lost|change) (my )?password\b/,
      /\bcan'?t (log ?in|sign ?in|access my account)\b/,
      /\b(didn'?t|not|never) (get|receive).*(email|confirmation|link)\b/,
      /\blogin (problem|issue|not working)\b/,
      /\bconfirm(ation)? email\b/,
    ],
    answer: () => ({
      message:
        `A few things to try:\n\n` +
        `• **Forgot your password?** On the sign-in page, tap "Forgot your password?" and we'll email ` +
        `you a reset link.\n` +
        `• **No confirmation email?** Check your spam folder first — it usually lands there. The link ` +
        `expires after a while, so if it's old, sign up again with the same address.\n` +
        `• **"Email not confirmed"?** You need to click the link in that email before your first sign-in.\n\n` +
        `Still stuck? Email hello@khejalink.name.ng and we'll sort it out.`,
      href: "/login",
      hrefLabel: "Go to sign in",
      suggestions: ["Is it free?", "How do I contact support?"],
    }),
  },

  // ---------------------------------------------------------------------------
  // Using the site as a house hunter
  // ---------------------------------------------------------------------------
  {
    id: "how-to-search",
    priority: 62,
    patterns: [
      /\bhow (do|can) i (search|find|look for|browse)\b/,
      /\bhow (does|do) (the )?(search|filter|filtering) work\b/,
      /\bhow (do|can) i filter\b/,
      /\bfind (a|me a) (house|home|place)\b(?!.*\d)/,
    ],
    answer: (stats) => ({
      message:
        `Two ways.\n\n` +
        `**Just ask me.** Say something like "2 bedroom in Makutano under 30k" or "rooms near MUST" ` +
        `and I'll search the live listings for you.\n\n` +
        `**Or use the search page**, where you can filter by house type, area, bedrooms, maximum rent and ` +
        `amenities (${list(stats.amenities.slice(0, 4))} and more), then sort by price, newest or most viewed.\n\n` +
        `Every search has a shareable link, so you can send one to someone else.`,
      href: "/properties",
      hrefLabel: "Open search",
      suggestions: ["2 bedroom in Makutano under 30k", "Rooms near MUST", "Shops in Meru Town"],
    }),
  },
  {
    id: "how-to-save",
    priority: 75,
    patterns: [
      /\b(how (do|can) i )?(save|favourite|favorite|shortlist|bookmark)\b/,
      /\bsaved (homes|houses|properties|list)\b/,
      /\bwhere (are|do i find) my (saved|favourite|favorite)\b/,
      /\bheart (icon|button)\b/,
    ],
    answer: () => ({
      message:
        `Tap the heart on any listing and it's added to your shortlist.\n\n` +
        `You'll need to be signed in, because your saved homes are private to you — nobody else, ` +
        `including landlords, can see what you've saved.\n\n` +
        `The list syncs between the website and the Android app, so you can save on your laptop and ` +
        `pull it up on your phone at a viewing.`,
      href: "/favorites",
      hrefLabel: "My saved homes",
      suggestions: ["Do I need an account?", "Show me apartments"],
    }),
  },
  {
    id: "contact-landlord",
    priority: 78,
    patterns: [
      /\bhow (do|can) i (contact|reach|call|message|talk to|get in touch with).*(landlord|owner|agent|caretaker)\b/,
      /\b(contact|call|message|whatsapp) (the )?(landlord|owner|agent)\b/,
      /\bhow (do|can) i (arrange|book|schedule) (a )?(viewing|visit)\b/,
      /\bcan i see the house\b/,
    ],
    answer: () => ({
      message:
        `Open any listing and you'll find three ways to reach the landlord directly:\n\n` +
        `• **Call** — dials their number\n` +
        `• **WhatsApp** — opens a chat with the listing already referenced\n` +
        `• **Send a message** — a short form; no account required, just leave an email or phone number ` +
        `so they can reply\n\n` +
        `Your message goes straight to the person who posted the house. Kheja_Link doesn't act as an ` +
        `agent or take a cut.\n\n` +
        `When you arrange a viewing, go during daylight and never pay anything before seeing the place.`,
      href: "/properties",
      hrefLabel: "Find a home",
      suggestions: ["Is it safe?", "What should I check at a viewing?"],
    }),
  },

  // ---------------------------------------------------------------------------
  // Landlord side
  // ---------------------------------------------------------------------------
  {
    id: "how-to-list",
    priority: 90,
    patterns: [
      /\bhow (do|can) i (list|post|advertise|upload|add|put up|rent out)\b/,
      /\b(list|post|advertise|rent out) (my|a|our) (house|home|property|room|shop|apartment|place|unit)\b/,
      /\bi (have|want to rent out|own) a (house|property|room|shop|apartment)\b/,
      /\bbecome a landlord\b/,
      /\bi'?m a landlord\b/,
      /\badd (a )?(listing|property)\b/,
    ],
    answer: () => ({
      message:
        `Listing on Kheja_Link is free and takes a few minutes:\n\n` +
        `1. Create an account (or open your profile if you already have one) and choose **landlord**\n` +
        `2. Go to your dashboard and tap **New listing**\n` +
        `3. Add photos, the rent, location, house type, bedrooms and amenities\n` +
        `4. Set it to **Published** and save\n\n` +
        `It appears in search straight away. You can save it as a draft first if you're not ready, and ` +
        `mark it **Rented** later to take it off search without deleting it.\n\n` +
        `Good photos matter more than anything else — they're the main reason people click.`,
      href: "/dashboard/properties/new",
      hrefLabel: "List a house",
      suggestions: ["Is listing free?", "Where do I see my inquiries?", "What is the verified badge?"],
    }),
  },
  {
    id: "manage-listings",
    priority: 82,
    patterns: [
      /\bhow (do|can) i (edit|change|update|delete|remove|unpublish|take down)\b.*(listing|property|house|advert)\b/,
      /\b(edit|update|delete|remove) my (listing|property|house)\b/,
      /\bmark (as )?rented\b/,
      /\bmy (listings|properties|dashboard)\b/,
    ],
    answer: () => ({
      message:
        `Everything lives in your landlord dashboard, under **My Listings**.\n\n` +
        `From there you can edit any listing, swap photos, change the rent, or flip its status:\n\n` +
        `• **Published** — visible in search\n` +
        `• **Draft** — only you can see it\n` +
        `• **Rented** — taken off search, but kept so you can re-publish later\n` +
        `• **Archived** — hidden away\n\n` +
        `Deleting removes it permanently, along with its photos.`,
      href: "/dashboard/properties",
      hrefLabel: "My listings",
      suggestions: ["Where do I see my inquiries?", "How do I list my house?"],
    }),
  },
  {
    id: "inquiries",
    priority: 82,
    patterns: [
      /\b(where|how).*(see|find|read|check|get).*(inquir|enquir|message|lead)\b/,
      /\bmy (inquiries|enquiries|messages|leads)\b/,
      /\bwho (has )?(contacted|messaged|asked about)\b/,
    ],
    answer: () => ({
      message:
        `Messages about your houses land in your dashboard under **Inquiries** — on the website and in ` +
        `the Android app.\n\n` +
        `Each one shows the person's name, message and contact details, with buttons to reply by email or ` +
        `call them. You can mark them New, Read, Responded or Closed to keep track.\n\n` +
        `Only you can see inquiries on your own listings; no other landlord can read them.\n\n` +
        `Reply quickly — the first landlord to respond usually gets the tenant.`,
      href: "/dashboard/inquiries",
      hrefLabel: "My inquiries",
      suggestions: ["How do I edit a listing?", "What is the verified badge?"],
    }),
  },
  {
    id: "verified-badge",
    priority: 84,
    patterns: [
      /\b(what|what'?s) (is |does )?(the )?verified\b/,
      /\bverified (badge|landlord|tick|mark)\b/,
      /\bhow (do|can) i (get|become) verified\b/,
    ],
    answer: () => ({
      message:
        `A verified badge means our team has confirmed the landlord's identity and that they're entitled ` +
        `to let the property.\n\n` +
        `It's a signal of good faith, not a guarantee — always still view a house in person and see the ` +
        `paperwork before paying anything.\n\n` +
        `If you're a landlord and want to be verified, email hello@khejalink.name.ng from the address on ` +
        `your account.`,
      suggestions: ["Is it safe?", "How do I list my house?"],
    }),
  },

  // ---------------------------------------------------------------------------
  // Trust and safety
  // ---------------------------------------------------------------------------
  {
    id: "safety",
    priority: 88,
    patterns: [
      /\b(is (it|this) )?(safe|secure|legit|genuine|trustworthy|real)\b/,
      /\b(scam|scams|fraud|fraudulent|fake|cheat|swindl|conned|con\s?artist)\b/,
      /\bhow do i (know|avoid|protect)\b/,
      /\bsafety (tips|advice)\b/,
      /\bcan i trust\b/,
    ],
    answer: () => ({
      message:
        `Kheja_Link never handles your money — rent and deposits go directly between you and the ` +
        `landlord — so the safety rules are on you. These are the ones that matter:\n\n` +
        `• **Never send a deposit, viewing fee or booking fee before seeing the house in person.** This ` +
        `is the single most common scam.\n` +
        `• View during daylight, and take someone with you if you can.\n` +
        `• Ask to see ownership or management documents before signing.\n` +
        `• Be suspicious of rent far below the going rate for the area — it's the oldest trick there is.\n` +
        `• Get a written, signed tenancy agreement before you move in.\n` +
        `• Pay traceably and always get a receipt.\n\n` +
        `If a listing looks fraudulent, email hello@khejalink.name.ng and we'll take it down.`,
      href: "/help#safety",
      hrefLabel: "Full safety guide",
      suggestions: ["What should I check at a viewing?", "What is the verified badge?"],
    }),
  },
  {
    id: "viewing-checklist",
    priority: 86,
    patterns: [
      /\bwhat (should|do) i (check|look for|ask|inspect)\b/,
      /\b(viewing|inspection) (checklist|tips)\b/,
      /\bbefore (i )?(rent|move in|pay|sign)\b/,
    ],
    answer: () => ({
      message:
        `Worth checking on a viewing in Meru:\n\n` +
        `• **Water** — is it county supply, borehole or a tank? How often does it actually run?\n` +
        `• **Power** — prepaid tokens or a shared meter? Shared meters cause disputes.\n` +
        `• **Security** — is there a gate, a caretaker, lighting at night?\n` +
        `• **Water pressure and drainage** — run the taps and flush.\n` +
        `• **Damp** — look at ceiling corners and behind doors.\n` +
        `• **The road in** — how is it when it rains?\n` +
        `• **Deposit and notice terms** — how many months, and what gets you refunded?\n\n` +
        `Most landlords in Meru ask one to two months' deposit plus the first month's rent. Get every ` +
        `figure in writing before you pay.`,
      href: "/help#safety",
      hrefLabel: "More safety advice",
      suggestions: ["Is it safe?", "How do I contact a landlord?"],
    }),
  },
  {
    id: "deposit",
    priority: 84,
    patterns: [
      /\bdeposit\b/,
      /\bhow (much|many months).*(upfront|advance|down)\b/,
      /\badvance rent\b/,
    ],
    answer: () => ({
      message:
        `Deposit terms are set by each landlord, and every listing shows how many months they ask for.\n\n` +
        `In Meru the norm is one to two months' deposit plus the first month's rent upfront. A deposit ` +
        `should be refundable at the end of your tenancy, less any genuine damage.\n\n` +
        `Two rules worth holding to: never pay a deposit before viewing the house in person, and always ` +
        `get a signed agreement and a receipt.`,
      suggestions: ["What should I check at a viewing?", "Is it safe?"],
    }),
  },
  {
    id: "report",
    priority: 84,
    patterns: [
      /\b(report|flag|complain about)\b.*(listing|landlord|advert|property|scam)\b/,
      /\bwrong (information|price|photos)\b/,
      /\b(listing|house) (is|was) (already )?(rented|taken|gone|fake)\b/,
    ],
    answer: () => ({
      message:
        `Please tell us — email hello@khejalink.name.ng with the listing's link and what's wrong.\n\n` +
        `We remove listings that turn out to be fraudulent, and we nudge landlords who leave rented ` +
        `houses up. Reports like yours are the main way we keep the listings honest.`,
      href: "/help#contact",
      hrefLabel: "Contact us",
      suggestions: ["Is it safe?"],
    }),
  },

  // ---------------------------------------------------------------------------
  // Support, policy, apps
  // ---------------------------------------------------------------------------
  {
    id: "contact-support",
    priority: 80,
    patterns: [
      /\b(contact|reach|email|call|talk to|speak to) (you|support|kheja|customer|the team|admin)\b/,
      /\b(support|help|customer (care|service)) (email|number|contact|line)\b/,
      /\byour (email|phone|number|contact|address|office)\b/,
      /\bwhere are you (based|located)\b/,
    ],
    answer: () => ({
      message:
        `You can reach the Kheja_Link team at:\n\n` +
        `• **Email** — hello@khejalink.name.ng\n` +
        `• **Phone** — +254 710 655 709\n` +
        `• **Office** — Greenwood Mall, Meru Town, Kenya\n\n` +
        `For anything about a specific house, though, contacting the landlord directly from the listing ` +
        `is much faster.`,
      href: "/help#contact",
      hrefLabel: "Help centre",
      suggestions: ["Is it safe?", "How do I list my house?"],
    }),
  },
  {
    id: "privacy",
    priority: 80,
    patterns: [
      /\b(privacy|my data|personal (data|information)|gdpr)\b/,
      /\bwho can see my\b/,
      /\bdo you (sell|share) (my )?(data|information)\b/,
      /\bdelete my (account|data)\b/,
    ],
    answer: () => ({
      message:
        `We keep as little as possible, and access is enforced by the database itself rather than just ` +
        `in code:\n\n` +
        `• Your **email is never shown publicly**. A phone number only appears if you deliberately add ` +
        `one to a listing.\n` +
        `• **Saved homes are private to you** — landlords can't see them.\n` +
        `• An **inquiry is readable only by the landlord it was sent to, and by you**.\n` +
        `• We don't sell your data or run advertising trackers.\n\n` +
        `To delete your account and everything attached to it, email hello@khejalink.name.ng.`,
      href: "/privacy",
      hrefLabel: "Privacy policy",
      suggestions: ["How do I contact support?", "Is it safe?"],
    }),
  },
  {
    id: "mobile-app",
    priority: 80,
    patterns: [
      /\b(android|ios|iphone|mobile) app\b/,
      /\bdo you have an app\b/,
      /\b(download|install|get) the app\b/,
      /\bapk\b/,
      /\bplay store\b/,
    ],
    answer: () => ({
      message:
        `Yes — there's a Kheja_Link Android app with everything the website has: search, filters, photo ` +
        `galleries, saved homes and the landlord dashboard. Your account and shortlist sync between them.\n\n` +
        `It isn't on the Play Store yet, so you install it from our releases page. An iOS version is ` +
        `built but not yet published.`,
      href: "https://github.com/ubike418-ship-it/kheja_link/releases/latest",
      hrefLabel: "Download the Android app",
      suggestions: ["Do I need an account?", "How do I save a home?"],
    }),
  },
  {
    id: "student-housing",
    priority: 86,
    patterns: [
      /\b(student|campus|university|college|hostel)\b/,
      /\bmust\b(?!\s+(be|have|do))/,
      /\bmeru university\b/,
    ],
    answer: (stats) => {
      const rooms = stats.types.find((t) => t.slug === "single_room");
      return {
        message:
          `Student housing in Meru is concentrated around the MUST area in Nchiru, plus Milimani and ` +
          `Kaaga for those who don't mind a short commute.\n\n` +
          (rooms && rooms.count > 0
            ? `We have ${rooms.count} single room${rooms.count === 1 ? "" : "s"} listed right now, and ` +
              `bedsitters too if you want your own kitchen and bathroom.\n\n`
            : "") +
          `Single rooms are the cheapest option; bedsitters cost more but are self-contained. Ask about ` +
          `water and whether electricity is on a shared or private meter — that's where costs bite.`,
        href: "/properties?location=must-area",
        hrefLabel: "Rooms near MUST",
        suggestions: ["Under 10k", "Bedsitters in Makutano", "What areas do you cover?"],
      };
    },
  },
  {
    id: "shops-commercial",
    priority: 78,
    patterns: [
      /\b(shops?|stalls?|retail|commercial|business premises|godowns?|office space)\b/,
    ],
    answer: (stats) => {
      const shops = stats.types.find((t) => t.slug === "shop");
      return {
        message:
          `Yes — Kheja_Link lists commercial space as well as homes.` +
          (shops && shops.count > 0
            ? ` There ${shops.count === 1 ? "is" : "are"} ${shops.count} shop${shops.count === 1 ? "" : "s"} ` +
              `available right now.`
            : "") +
          `\n\nMeru Town's main street carries the highest footfall and prices accordingly; Makutano's ` +
          `arcades are cheaper and suit smaller stalls. Ask about three-phase power if you need it, and ` +
          `whether there's a rear store room.`,
        href: "/properties?type=shop",
        hrefLabel: "Browse shops",
        suggestions: ["Shops in Meru Town", "What's the price range?"],
      };
    },
  },
  {
    id: "thanks",
    priority: 95,
    patterns: [/^(thanks|thank you|asante|ok|okay|cool|nice|great|good|perfect)[\s!.]*$/],
    answer: () => ({
      message: `Anytime. Anything else you'd like to know about Kheja_Link or the homes on it?`,
      suggestions: ["What areas do you cover?", "Is it safe?", "Show me apartments"],
    }),
  },
  {
    id: "greeting",
    priority: 95,
    patterns: [
      /^(hi|hey|hello|niaje|sasa|habari|mambo|yo|good (morning|afternoon|evening))[\s!.,]*$/,
    ],
    answer: (stats) => ({
      message:
        `Hi! I'm the Kheja_Link assistant. I can search all ${stats.total} homes on the platform, or ` +
        `answer anything about how Kheja_Link works.\n\n` +
        `Try "2 bedroom in Makutano under 30k", or ask me something like "how do I list my house?"`,
      suggestions: ["What areas do you cover?", "Is it free?", "2 bedroom under 30k"],
    }),
  },
];

/**
 * Scores every entry against the message and returns the best match, or null
 * when nothing is confident enough to answer.
 */
export function matchKnowledge(query: string): KnowledgeEntry | null {
  const text = query.toLowerCase().trim();
  let best: { entry: KnowledgeEntry; score: number } | null = null;

  for (const entry of KNOWLEDGE) {
    let hits = 0;
    for (const pattern of entry.patterns) {
      if (pattern.test(text)) hits += 1;
    }
    if (hits === 0) continue;

    // Priority dominates; extra pattern hits break ties.
    const score = entry.priority * 10 + hits;
    if (!best || score > best.score) best = { entry, score };
  }

  return best?.entry ?? null;
}
