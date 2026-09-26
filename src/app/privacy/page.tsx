import type { Metadata } from "next";
import LegalPage, { type LegalSection } from "@/components/LegalPage";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "What Kheja_Link collects in the app and on the website, why, who can see it, and how to delete your account.",
};

/**
 * Covers the Android app and the website. Keep it in step with the Google Play
 * Data safety form and with AdSense's disclosure requirements.
 */
const sections: LegalSection[] = [
  {
    heading: "Who we are",
    paragraphs: [
      "Kheja_Link is a long-term rental platform for Meru, Kenya, available as an Android app and at www.khejalink.name.ng. This policy covers both. Questions go to hello@khejalink.co.ke or WhatsApp +254 710 655709.",
    ],
  },
  {
    heading: "What we collect",
    paragraphs: ["We keep the collection deliberately small:"],
    bullets: [
      "Account details: your name, email address, password (stored only as a secure hash by Supabase Auth) and, if you give it, your phone number, and whether you use Kheja_Link as a tenant or a landlord.",
      "Listings (landlords): everything you type into a listing, the photos and videos you upload, the contact numbers you add, and the exact location of the house. The exact location is only collected if you tap “pin my location” in the listing editor, and only at that moment — never in the background.",
      "Messages: the name, contact details and message you send to the Kheja_Link team about a listing, and our reply.",
      "Requests, saved homes and alerts: the homes you save, request or ask to be told about, and the searches you set alerts for.",
      "Payments: which listings you unlocked, the amount, the payment reference and when your 3-hour access ends. M-Pesa and card payments are processed by Paystack; we never see your M-Pesa PIN or card number. To stop anyone flooding a phone with payment prompts, we keep a one-way fingerprint of the number a prompt was sent to, not the number itself.",
      "Houses you give us: the area, rent, landlord's name and phone number you provide, so we can check the house and process your refund.",
      "Basic usage: a view count per listing and whether you have read your in-app notifications. The app has no analytics or advertising SDKs.",
    ],
  },
  {
    heading: "Why we hold it",
    paragraphs: [
      "To run your account; to show listings to house hunters; to unlock a listing's contacts and location after you pay, for the time you paid for; to answer your messages and process refunds; to tell you, inside the app, when a home you care about becomes available; and to keep the platform free of fraud and abuse.",
      "We do not sell your personal data.",
    ],
  },
  {
    heading: "Who can see what",
    paragraphs: [
      "Access is enforced in the database itself (Supabase Row Level Security), not only in the app.",
    ],
    bullets: [
      "Published listings, their photos, the area and the landlord's description of the location, and the landlord's display name are public.",
      "A listing's phone numbers, exact address and map pin are shown only to tenants who have paid to unlock that listing, for the time they paid for, and to the landlord.",
      "Your email and phone number are never shown publicly.",
      "Messages you send about a listing are read only by the Kheja_Link team and you.",
      "Your saved homes, alerts, payments and notifications are private to you. Kheja_Link administrators can see accounts, payments and messages to run the service and handle refunds.",
    ],
  },
  {
    heading: "Who we share it with",
    paragraphs: ["Only the providers that run the service, each under their own security and privacy commitments:"],
    bullets: [
      "Supabase — database, sign-in and file storage.",
      "Vercel — hosts the website and the payment server.",
      "Paystack — processes M-Pesa and card payments.",
      "Google — shows advertising on the website (see Advertising and cookies). The Android app shows no ads.",
      "When you open a WhatsApp, TikTok, phone or Google Maps link, that service's own privacy policy applies.",
    ],
  },
  {
    id: "cookies",
    heading: "Advertising and cookies",
    paragraphs: [
      "The website keeps you signed in with a session cookie, which is essential and is not used for advertising.",
      "The website shows ads through Google AdSense. Google and its partners use cookies to serve ads based on your previous visits to this and other websites. You can turn off personalised advertising at adssettings.google.com, and learn how Google uses data at policies.google.com/technologies/partner-sites. You can also opt out of some third-party vendors' use of cookies at www.aboutads.info.",
      "The Android app does not show ads and does not use advertising identifiers.",
    ],
  },
  {
    id: "delete",
    heading: "Deleting your account",
    paragraphs: [
      "You can delete your account yourself at any time: in the app, go to Account and tap “Delete my account”; on the website, sign in and go to your Account page. Deletion is immediate and permanent and removes your profile, listings, saved homes, alerts, requests, messages, unlock records and notifications.",
      "If you can no longer sign in, email hello@khejalink.co.ke from the address on your account and we will delete it within 7 days. More at www.khejalink.name.ng/delete-account.",
      "The photos and videos you uploaded are removed from our storage at the same time, and so are your payment records with us. Paystack keeps its own record of a payment under its own policy.",
    ],
  },
  {
    heading: "How long we keep it",
    paragraphs: [
      "We keep your data while your account exists. Unfinished payment checkouts are discarded after an hour. When you delete your account, your data is deleted as described above.",
    ],
  },
  {
    heading: "Your rights",
    paragraphs: [
      "Under Kenya's Data Protection Act, 2019 you can ask to see, correct or delete your personal data, and object to how it is used. You can edit your profile and listings at any time in the app or on the website, and delete your account yourself. For anything else, contact us.",
    ],
  },
  {
    heading: "Children",
    paragraphs: [
      "Kheja_Link is for adults renting or letting homes. It is not directed at children under 18, and we do not knowingly collect their data.",
    ],
  },
  {
    heading: "Keeping it safe",
    paragraphs: [
      "All traffic is encrypted in transit (HTTPS). Passwords are hashed by Supabase Auth and never visible to us. Access to personal data is restricted by database policy, payments are confirmed only by Paystack, and the app does not allow its data to be backed up to other devices.",
    ],
  },
  {
    heading: "Changes",
    paragraphs: [
      "If we change this policy we will update the date at the top of this page, and tell you in the app if the change is significant.",
    ],
  },
];

export default async function PrivacyPage() {
  const profile = await getCurrentProfile();
  return (
    <LegalPage
      kicker="Legal"
      title="Privacy Policy"
      updated="26 September 2026"
      intro="This explains exactly what Kheja_Link collects in the Android app and on the website, why we need it, who can see it, and how to delete your account."
      sections={sections}
      profile={profile}
    />
  );
}
