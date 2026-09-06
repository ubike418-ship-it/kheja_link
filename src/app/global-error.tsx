"use client";

/**
 * Last-resort boundary: catches errors thrown in the root layout itself, so it
 * has to render its own <html> and cannot rely on any app styling.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: "2rem",
          background: "#fafafa",
          color: "#18181b",
          fontFamily:
            "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
        }}
      >
        <div style={{ maxWidth: 480, textAlign: "center" }}>
          <h1 style={{ fontSize: "2rem", fontWeight: 900, letterSpacing: "-0.03em", margin: 0 }}>
            Something went wrong
          </h1>
          <p style={{ color: "#71717a", fontWeight: 500, lineHeight: 1.6, marginTop: "1rem" }}>
            Kheja_Link ran into an unexpected problem. Try again — if it keeps happening, let us know
            at hello@khejalink.co.ke.
          </p>
          {error.digest && (
            <p style={{ color: "#a1a1aa", fontSize: "0.75rem", marginTop: "0.5rem" }}>
              Reference: {error.digest}
            </p>
          )}
          <button
            onClick={reset}
            style={{
              marginTop: "2rem",
              padding: "0 2rem",
              height: 56,
              border: "none",
              borderRadius: "1rem",
              background: "#2563eb",
              color: "#fff",
              fontWeight: 900,
              fontSize: "1rem",
              cursor: "pointer",
            }}
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
