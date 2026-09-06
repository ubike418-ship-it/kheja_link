import type { Metadata } from "next";
import LegalPage, { type LegalSection } from "@/components/LegalPage";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "What data Kheja_Link collects, why, and what control you have over it.",
};

const sections: LegalSection[] = [
  {
    heading: "What we collect",
    paragraphs: ["We keep the collection deliberately small:"],
    bullets: [
      "Account details: your name, email address and, if you give it, your phone number.",
      "Listing details: everything you type into a listing, including photographs you upload.",
      "Inquiries: the name, contact details and message you send to a landlord.",
      "Saved homes: the listings you add to your shortlist, which only you can see.",
      "Basic usage data: a per-listing view count. We do not run third-party advertising or analytics trackers.",
    ],
  },
  {
    heading: "Why we hold it",
    paragraphs: [
      "To run your account, show your listings to house hunters, pass your inquiry to the right landlord, and keep the platform free of fraud.",
      "We do not sell your data, and we do not share it with advertisers.",
    ],
  },
  {
    heading: "Who can see what",
    paragraphs: [
      "Access is enforced in the database itself, using Supabase Row Level Security, rather than only in the application code.",
    ],
    bullets: [
      "Published listings, their photographs, and the landlord's display name are public.",
      "Your email address is never shown publicly. A phone number is only visible if you deliberately add it to a listing as a contact number.",
      "An inquiry can only be read by the landlord who owns that listing and by you, the sender.",
      "Your saved homes are private to you. Nobody else can query them, including other landlords.",
    ],
  },
  {
    heading: "Where it is stored",
    paragraphs: [
      "Data is stored with Supabase (PostgreSQL and Supabase Storage) and the site is served by Vercel. Both hold data on our behalf under their own security commitments.",
    ],
  },
  {
    id: "cookies",
    heading: "Cookies",
    paragraphs: [
      "Kheja_Link sets one kind of cookie: the session cookie that keeps you signed in. It is essential to the service and is not used for tracking or advertising.",
      "Clearing it simply signs you out.",
    ],
  },
  {
    heading: "Your rights",
    paragraphs: [
      "You can edit or correct your profile at any time from your account page, and delete any listing you have published.",
      "To have your account and associated data deleted entirely, email hello@khejalink.co.ke and we will action it.",
    ],
  },
  {
    heading: "Keeping it safe",
    paragraphs: [
      "Passwords are hashed by Supabase Auth and are never visible to us. All traffic is encrypted in transit. Access to personal data is restricted by database policy rather than convention.",
    ],
  },
];

export default async function PrivacyPage() {
  const profile = await getCurrentProfile();
  return (
    <LegalPage
      kicker="Legal"
      title="Privacy Policy"
      updated="6 September 2026"
      intro="This explains exactly what Kheja_Link collects, why we need it, and who can see it."
      sections={sections}
      profile={profile}
    />
  );
}
