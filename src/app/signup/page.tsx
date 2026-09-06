import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import SignUpForm from "@/components/SignUpForm";

export const metadata: Metadata = {
  title: "Create an account",
  description:
    "Join Kheja_Link to save homes you like, contact landlords directly, or list your own property.",
};

export default function SignUpPage() {
  return (
    <AuthShell
      title="Join Kheja_Link."
      subtitle="Find your next home, or list one of your own."
      footer={
        <>
          Already have an account?{" "}
          <Link href="/login" className="text-blue-600 hover:underline">
            Sign in
          </Link>
        </>
      }
    >
      <SignUpForm />
    </AuthShell>
  );
}
