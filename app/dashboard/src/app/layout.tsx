import type { Metadata } from "next";
import { Inter, Shippori_Mincho_B1, Fragment_Mono } from "next/font/google";
import "./globals.css";

const sans = Inter({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-sans" });
const serif = Shippori_Mincho_B1({ subsets: ["latin"], weight: "600", variable: "--font-serif" });
const mono = Fragment_Mono({ subsets: ["latin"], weight: "400", variable: "--font-mono" });

const TITLE = "Royco Access Control";
const DESCRIPTION =
  "Onchain access-control command center — roles, holders, timelocks, and markets across chains.";

const SITE_URL = "https://security.royco.org";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  applicationName: TITLE,
  openGraph: {
    type: "website",
    siteName: TITLE,
    url: SITE_URL,
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${sans.variable} ${serif.variable} ${mono.variable}`}>
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
