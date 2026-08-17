import Link from "next/link";
import type { AmKind, Category, Label } from "@/model";
import { resolveLabel } from "@/lib/labels";
import { kernelForParent, shorten } from "@/lib/catalog";
import { explorerAddress, humanize } from "@/lib/format";

// Muted, warm palette per the royco.org design language: greens / bronzes / warm grays only.
const CAT_COLOR: Record<string, string> = {
  factory: "#8A6F47",
  multisig: "#4B4A49",
  market: "#16A34A",
  vault: "#7C9A6D",
  strategy: "#B07D2B",
  entrypoint: "#5E8C7A",
  syncer: "#868584",
  agent: "#A18A69",
  lp: "#C0A15E",
  protocol: "#6B8296",
  external: "#A6A5A3",
};

export function categoryColor(cat: Category | string): string {
  return CAT_COLOR[cat] ?? CAT_COLOR.external;
}

// Markets are colored by their controlling AM — matching the AmBadge palette — so dawn and day
// markets read apart at a glance everywhere a market name appears.
export const AM_COLOR: Record<AmKind, string> = { dawn: "#8A6F47", day: "#16A34A" };

function labelColor(l: Label): string {
  if (l.category === "market" && l.manager) return AM_COLOR[l.manager];
  return categoryColor(l.category);
}

// Multisigs are marked by a wallet glyph instead of a plain dot, so signer quorums read apart
// from contracts at a glance in any table.
function WalletIcon({ color }: { color: string }) {
  return (
    <svg
      width="11"
      height="11"
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth="2.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="shrink-0"
      aria-label="multisig"
    >
      <path d="M19 7V5a1 1 0 0 0-1-1H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h14a1 1 0 0 0 1-1v-4" />
      <path d="M21 11h-6a2 2 0 0 0 0 4h6a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1z" />
    </svg>
  );
}

export function CategoryDot({ category, color }: { category: Category | string; color?: string }) {
  if (category === "multisig") return <WalletIcon color={color ?? categoryColor(category)} />;
  return (
    <span
      className="inline-block h-2 w-2 shrink-0 rounded-full"
      style={{ backgroundColor: color ?? categoryColor(category) }}
    />
  );
}

export function CategoryBadge({ category }: { category: Category | string }) {
  const c = categoryColor(category);
  return (
    <span
      className="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[11px] font-medium"
      style={{ backgroundColor: `${c}1e`, color: c }}
    >
      <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ backgroundColor: c }} />
      {category}
    </span>
  );
}

// Display form of a label: never raw camelCase outside function names. Market components read
// "sUSDai · Accountant"; infra names are humanized ("dayEntryPoint" → "Day Entry Point"); market
// and token names (sUSDai, roywstETH) pass through untouched.
const INFRA_CATEGORIES = new Set(["factory", "entrypoint", "syncer"]);
export function displayName(l: Label): string {
  if (l.parent && l.subtype) return `${l.parent} · ${humanize(l.subtype)}`;
  return INFRA_CATEGORIES.has(l.category) ? humanize(l.name) : l.name;
}

// A contract address as a block-explorer link (etherscan/arbiscan/…), mono, opens a new tab.
export function AddrLink({
  chainId,
  address,
  short = false,
  className = "",
}: {
  chainId: number;
  address: string;
  short?: boolean;
  className?: string;
}) {
  return (
    <a
      href={explorerAddress(chainId, address)}
      target="_blank"
      rel="noreferrer"
      className={`whitespace-nowrap font-mono text-xs text-muted hover:!text-ok ${className}`}
    >
      {short ? (
        <>{shorten(address)} ↗</>
      ) : (
        // Full addresses would widen the page past a phone viewport — shorten below md.
        <>
          <span className="md:hidden">{shorten(address)}</span>
          <span className="max-md:hidden">{address}</span> ↗
        </>
      )}
    </a>
  );
}

const chipClass =
  "inline-flex items-center gap-1.5 whitespace-nowrap rounded-md border border-border bg-panel px-2 py-0.5 text-xs font-medium text-body transition-colors hover:border-ok hover:!text-ok";

// A target address as navigable chip(s). Market components split into TWO buttons — the market
// (→ market detail) and the component (→ address page). Known standalone contracts are ONE
// button; unknown addresses render as plain mono text.
export function TargetChip({ chainId, slug, address }: { chainId: number; slug: string; address: string }) {
  const l = resolveLabel(chainId, address);
  if (!l.known) return <span className="font-mono text-xs text-muted">{shorten(address)}</span>;
  if (l.parent && l.subtype) {
    const kernel = l.kernel ?? kernelForParent(chainId, l.parent);
    const kind = l.manager ?? "dawn";
    return (
      <span className="inline-flex items-center gap-1">
        {kernel ? (
          <Link href={`/${slug}/markets/${kind}/${kernel}`} className={chipClass}>
            <CategoryDot category={l.category} color={labelColor(l)} />
            {l.parent}
          </Link>
        ) : (
          <span className={chipClass}>
            <CategoryDot category={l.category} color={labelColor(l)} />
            {l.parent}
          </span>
        )}
        <Link href={`/${slug}/address/${address}`} className={chipClass}>
          {humanize(l.subtype)}
        </Link>
      </span>
    );
  }
  return (
    <Link href={`/${slug}/address/${address}`} className={chipClass}>
      <CategoryDot category={l.category} color={labelColor(l)} />
      {displayName(l)}
    </Link>
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
      <CategoryDot category={l.category} color={labelColor(l)} />
      <span className={l.known ? "" : "font-mono text-xs text-muted"}>{displayName(l)}</span>
      {l.pendingDeployment && <span className="text-[11px] text-med">pending</span>}
      {showAddress && l.known && <span className="font-mono text-[11px] text-muted">{shorten(address)}</span>}
    </Link>
  );
}
