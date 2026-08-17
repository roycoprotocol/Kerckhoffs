import Link from "next/link";
import { notFound } from "next/navigation";
import { CHAINS, chainBySlug } from "@/config/chains";
import { amKindsFor } from "@/lib/catalog";
import { fetchMeta, hasSubgraph } from "@/lib/subgraph";
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

  const amKinds = amKindsFor(cfg.chainId);
  const daySlugs = CHAINS.filter((c) => amKindsFor(c.chainId).includes("day")).map((c) => c.slug);
  const meta = hasSubgraph(cfg.chainId) ? await fetchMeta(cfg.chainId).catch(() => null) : null;

  return (
    <div className="min-h-screen">
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-[1160px] items-center gap-3 px-6 pb-2.5 pt-3.5">
          <Link href={`/${chain}`} className="flex items-baseline gap-2.5">
            <span className="text-[13px] font-semibold tracking-[0.22em]">ROYCO</span>
            <span className="text-[13px] font-semibold text-body">Access Control</span>
          </Link>
          <div className="flex-1" />
          {meta && (
            <span className="mr-1.5 font-mono text-[11px] tracking-[0.08em] text-muted">
              INDEXED BLOCK {meta.block.number}
            </span>
          )}
          <CommandSearch chainId={cfg.chainId} slug={chain} />
          <ChainSwitcher slug={chain} daySlugs={daySlugs} />
        </div>
        <Nav slug={chain} amKinds={amKinds} />
      </header>
      <main className="mx-auto max-w-[1160px] px-6 pb-24 pt-9">{children}</main>
    </div>
  );
}
