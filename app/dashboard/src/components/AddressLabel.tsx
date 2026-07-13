import Link from "next/link";
import type { Category } from "@/model";
import { resolveLabel } from "@/lib/labels";
import { shorten } from "@/lib/catalog";

const CAT_COLOR: Record<string, string> = {
  factory: "#a06bff",
  multisig: "#5b8cff",
  market: "#2fd6c3",
  vault: "#3ecf8e",
  strategy: "#f5a623",
  entrypoint: "#38c2d6",
  syncer: "#8b95a7",
  agent: "#ff8fb0",
  lp: "#c0a15e",
  protocol: "#b26bff",
  external: "#5b6472",
};

export function categoryColor(cat: Category | string): string {
  return CAT_COLOR[cat] ?? CAT_COLOR.external;
}

export function CategoryDot({ category }: { category: Category | string }) {
  return <span className="inline-block h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: categoryColor(category) }} />;
}

export function CategoryBadge({ category }: { category: Category | string }) {
  const c = categoryColor(category);
  return (
    <span
      className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] font-medium"
      style={{ backgroundColor: `${c}22`, color: c }}
    >
      <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ backgroundColor: c }} />
      {category}
    </span>
  );
}

// Renders an address as its resolved label (category dot + name), linking to the address page.
export function AddressLabel({
  chainId,
  slug,
  address,
  showAddress = false,
  className = "",
}: {
  chainId: number;
  slug: string;
  address: string;
  showAddress?: boolean;
  className?: string;
}) {
  const l = resolveLabel(chainId, address);
  return (
    <Link href={`/${slug}/address/${address}`} className={`inline-flex items-center gap-1.5 hover:text-ok ${className}`}>
      <CategoryDot category={l.category} />
      <span className={l.known ? "" : "font-mono text-[13px] text-muted"}>{l.name}</span>
      {l.pendingDeployment && <span className="text-[11px] text-med">pending</span>}
      {showAddress && l.known && <span className="font-mono text-[11px] text-muted">{shorten(address)}</span>}
    </Link>
  );
}
