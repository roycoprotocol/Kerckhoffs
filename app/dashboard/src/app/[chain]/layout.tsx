import Link from "next/link";
import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { ChainSwitcher, Nav } from "@/components/Nav";
import { CommandSearch } from "@/components/CommandSearch";

export default async function ChainLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ chain: string }>;
}) {
  const { chain } = await params;
  const cfg = chainBySlug(chain);
  if (!cfg) notFound();

  return (
    <div className="min-h-screen">
      <header className="flex items-center gap-3 border-b border-border px-4 py-3">
        <Link href={`/${chain}`} className="font-semibold">
          Royco <span className="text-muted">Access Control</span>
        </Link>
        <div className="ml-auto flex items-center gap-3">
          <CommandSearch chainId={cfg.chainId} slug={chain} />
          <ChainSwitcher slug={chain} />
        </div>
      </header>
      <Nav slug={chain} />
      <main className="mx-auto max-w-6xl p-6">{children}</main>
    </div>
  );
}
