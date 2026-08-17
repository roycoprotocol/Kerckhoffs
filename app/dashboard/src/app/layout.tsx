import type { Metadata } from "next";
import { Inter, Shippori_Mincho_B1, Fragment_Mono } from "next/font/google";
import "./globals.css";

const sans = Inter({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-sans" });
const serif = Shippori_Mincho_B1({ subsets: ["latin"], weight: "600", variable: "--font-serif" });
const mono = Fragment_Mono({ subsets: ["latin"], weight: "400", variable: "--font-mono" });

export const metadata: Metadata = {
  title: "Royco Access Control",
  description: "Onchain access-control command center — roles, holders, timelocks, and markets across chains.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${sans.variable} ${serif.variable} ${mono.variable}`}>
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
