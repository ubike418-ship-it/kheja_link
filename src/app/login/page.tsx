import { Suspense } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import LoginForm from "@/components/LoginForm";

export const metadata: Metadata = {
  title: "Sign in",
  description: "Sign in to Kheja_Link to save homes, message landlords and manage your listings.",
};

export default function LoginPage() {
  return (
    <AuthShell
      title="Welcome back."
      subtitle="Sign in to pick up where you left off."
      footer={
        <>
          New to Kheja_Link?{" "}
          <Link href="/signup" className="text-blue-600 hover:underline">
            Create an account
          </Link>
        </>
      }
    >
      <Suspense fallback={<div className="h-72 animate-pulse rounded-2xl bg-zinc-100 dark:bg-zinc-800" />}>
        <LoginForm />
      </Suspense>
    </AuthShell>
  );
}
