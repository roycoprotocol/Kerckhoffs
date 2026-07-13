import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Royco Access Control",
  description: "Onchain access-control command center — roles, holders, timelocks, and drift across chains.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
