import type { Metadata } from "next";
import LegalPage, { type LegalSection } from "@/components/LegalPage";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Delete your Kheja_Link account",
  description: "How to delete your Kheja_Link account and data, in the app or on the website.",
};

/**
 * The account-deletion page Google Play asks for: public, reachable without
 * the app, and naming the app and developer. Linked from the privacy policy.
 */
const sections: LegalSection[] = [
  {
    heading: "In the Kheja_Link app",
    paragraphs: ["Deletion is immediate and you can do it yourself:"],
    bullets: [
      "Open the Kheja_Link app and sign in.",
      "Tap the Account tab.",
      "Scroll to the bottom and tap “Delete my account”.",
      "Type DELETE to confirm, then tap “Delete for good”.",
    ],
  },
  {
    heading: "On the website",
    paragraphs: [
      "Sign in at www.khejalink.name.ng/login, open your Account page (www.khejalink.name.ng/account), and use “Delete my account” at the bottom.",
    ],
  },
  {
    heading: "If you cannot sign in",
    paragraphs: [
      "Email hello@khejalink.co.ke, or WhatsApp +254 710 655709, from the email address or phone number on your account and ask us to delete it. We confirm your identity and delete the account within 7 days.",
    ],
  },
  {
    heading: "What is deleted",
    paragraphs: ["Everything linked to your account is permanently deleted:"],
    bullets: [
      "Your profile: name, email, phone number and password.",
      "Listings you published, with their photos, videos, contact numbers and exact location.",
      "Saved homes, alerts, house requests and houses you gave us.",
      "Messages you sent and the replies, your unlock and payment records with Kheja_Link, and your notifications.",
    ],
  },
  {
    heading: "What is kept",
    paragraphs: [
      "Nothing that identifies you. Paystack, which processes M-Pesa and card payments, keeps its own record of a payment under its own policy and the law.",
    ],
  },
];

export default async function DeleteAccountPage() {
  const profile = await getCurrentProfile();
  return (
    <LegalPage
      kicker="Kheja_Link · account"
      title="Delete your account"
      updated="26 September 2026"
      intro="Kheja_Link (the Android app and www.khejalink.name.ng) lets you delete your account and all its data at any time. Here is how."
      sections={sections}
      profile={profile}
    />
  );
}
