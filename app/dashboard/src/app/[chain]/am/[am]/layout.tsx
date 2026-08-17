import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { managerFor, parseAmKind } from "@/lib/catalog";
import { AmSubNav } from "@/components/Nav";
import { AmBadge, Eyebrow, Mono } from "@/components/ui";

// AccessManager section: validates the [am] segment (404 when the chain lacks that AM — e.g.
// /avalanche/am/day) and frames the Roles / Functions / Pending ops subviews.
export default async function AmLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ chain: string; am: string }>;
}) {
  const { chain, am } = await params;
  const cfg = chainBySlug(chain);
  const kind = parseAmKind(am);
  if (!cfg || !kind) notFound();
  const mgr = managerFor(cfg.chainId, kind);
  if (!mgr) notFound();

  const accent = kind === "day" ? "Day" : "Dawn";
  return (
    <>
      <Eyebrow>Access Manager · {cfg.name}</Eyebrow>
      <div className="mt-1.5 flex flex-wrap items-center gap-3.5">
        <h1 className="font-serif text-3xl font-semibold">
          <span className="text-ok">{accent}</span> AM.
        </h1>
        <AmBadge kind={kind} />
        <span className="text-[13px] text-body">{mgr.name}</span>
        <Mono className="text-muted">{mgr.address}</Mono>
      </div>
      <div className="mt-6">
        <AmSubNav slug={chain} am={kind} />
      </div>
      {children}
    </>
  );
}
