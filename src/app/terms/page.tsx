import type { Metadata } from "next";
import LegalPage, { type LegalSection } from "@/components/LegalPage";
import { getCurrentProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The terms that govern your use of Kheja_Link.",
};

const sections: LegalSection[] = [
  {
    heading: "What Kheja_Link is",
    paragraphs: [
      "Kheja_Link is a listing platform. We help people in Meru find long-term rental housing and help landlords advertise it. We are not an agent, a broker, or a party to any tenancy agreement.",
      "Every listing is created by the landlord or property manager who posted it. They are responsible for the accuracy of what they publish.",
    ],
  },
  {
    heading: "Your account",
    paragraphs: [
      "You must give accurate information when you create an account, keep your password to yourself, and tell us if you think someone else has access to it.",
      "You must be old enough to enter a tenancy agreement in Kenya to list a property.",
    ],
  },
  {
    heading: "Listing a property",
    paragraphs: ["By publishing a listing you confirm that:"],
    bullets: [
      "you own the property or are authorised to let it",
      "the rent, location, photographs and description are accurate and current",
      "you will take the listing down, or mark it rented, once it is no longer available",
      "you will not post the same unit repeatedly to gain visibility",
    ],
  },
  {
    heading: "What is not allowed",
    paragraphs: ["You may not use Kheja_Link to:"],
    bullets: [
      "advertise a property that does not exist or that you cannot let",
      "ask for a deposit or viewing fee before a viewing has taken place",
      "discriminate against anyone on grounds protected by Kenyan law",
      "harass other users, or scrape the platform automatically",
    ],
  },
  {
    heading: "Money",
    paragraphs: [
      "Kheja_Link never handles rent, deposits or any other payment between a tenant and a landlord. Any money you pay is paid directly to the other party, entirely at your own risk.",
      "Never pay anything before viewing a property in person.",
    ],
  },
  {
    heading: "Removing content",
    paragraphs: [
      "We may remove any listing, or suspend any account, that breaches these terms or that we reasonably believe to be fraudulent.",
    ],
  },
  {
    heading: "Liability",
    paragraphs: [
      "Kheja_Link is provided as-is. We work hard to keep listings accurate but we cannot guarantee them, and we are not liable for any loss arising from a tenancy you enter into, or from a listing that turns out to be inaccurate.",
      "Nothing here limits liability that cannot be limited under Kenyan law.",
    ],
  },
  {
    heading: "Governing law",
    paragraphs: ["These terms are governed by the laws of Kenya."],
  },
];

export default async function TermsPage() {
  const profile = await getCurrentProfile();
  return (
    <LegalPage
      kicker="Legal"
      title="Terms of Service"
      updated="6 September 2026"
      intro="These terms set out the rules for using Kheja_Link, both as someone looking for a house and as someone listing one."
      sections={sections}
      profile={profile}
    />
  );
}
