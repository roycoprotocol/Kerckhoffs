import Link from "next/link";
import { chainBySlug } from "@/config/chains";
import { managerFor } from "@/lib/catalog";
import { isVerifiedMarket } from "@/lib/verified";
import { fetchCurrentMarkets, MARKET_COMPONENTS, marketDisplay, marketName, roycoMarketUrl, ZERO_ADDR } from "@/lib/markets";
import { hasSubgraph } from "@/lib/subgraph";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddrLink, AM_COLOR } from "@/components/AddressLabel";
import { Filters } from "@/components/Filters";
import { LocalTime } from "@/components/LocalTime";
import { AmBadge, Empty, InlineStat, Mono, PageTitle, Panel, SubgraphMissing, Table, Td, Th } from "@/components/ui";
import type { AmKind } from "@/model";

// Shared implementation for the Dawn / Day markets tabs. Market data helpers (enumeration,
// display naming, component list, label overlay) live in lib/markets.ts; re-exported here for
// the pages that import from shared.
export { fetchCurrentMarkets, marketDisplay, marketName, MARKET_COMPONENTS, ZERO_ADDR } from "@/lib/markets";

export function UnverifiedBadge() {
  return (
    <span className="rounded-md bg-med-tint px-1.5 py-0.5 text-[11px] font-medium text-med">unverified</span>
  );
}

export async function MarketsPage({
  kind,
  params,
  searchParams,
}: {
  kind: AmKind;
  title: string;
  params: Promise<{ chain: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain } = await params;
  const sp = await searchParams;
  const cfg = chainBySlug(chain)!;
  const accent = kind === "dawn" ? "Dawn" : "Day";
  const eyebrow = `Markets · ${cfg.name}`;
  if (!hasSubgraph(cfg.chainId)) {
    return (
      <>
        <PageTitle eyebrow={eyebrow} accent={accent} title="Markets." />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  let markets;
  try {
    markets = await fetchCurrentMarkets(cfg.chainId, kind);
  } catch (e) {
    return (
      <>
        <PageTitle eyebrow={eyebrow} accent={accent} title="Markets." />
        <Empty>
          Failed to load subgraph: <Mono>{(e as Error).message}</Mono>
        </Empty>
      </>
    );
  }

  const q = param(sp, "q");
  const showAll = param(sp, "all") === "1";
  const verifiedCount = markets.filter((m) => isVerifiedMarket(cfg.chainId, m.kernel)).length;
  const unverifiedCount = markets.length - verifiedCount;
  const shown = markets.filter(
    (m) =>
      (showAll || isVerifiedMarket(cfg.chainId, m.kernel)) &&
      (!q ||
        includesCI(marketName(cfg.chainId, m), q) ||
        includesCI(m.deployer ?? "", q) ||
        MARKET_COMPONENTS.some((c) => includesCI(String(m[c.key] ?? ""), q))),
  );
  const contractCount = markets.reduce(
    (n, m) => n + MARKET_COMPONENTS.filter((c) => m[c.key] && m[c.key] !== ZERO_ADDR).length,
    0,
  );
  const factoryLabel = kind === "dawn" ? "the Dawn RoycoFactory" : "the Day factory";

  return (
    <>
      <PageTitle
        eyebrow={eyebrow}
        accent={accent}
        title="Markets."
        right={
          <div className="flex gap-8">
            <InlineStat label="Markets" value={markets.length} />
            <InlineStat label="Contracts" value={contractCount} />
          </div>
        }
      />
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex-1">
          <Filters searchPlaceholder="Filter markets…" />
        </div>
        {unverifiedCount > 0 ? (
          <Link
            href={showAll ? "?" : "?all=1"}
            className="whitespace-nowrap rounded-md border border-border bg-panel px-2.5 py-1 text-xs text-body hover:border-ok hover:!text-ok"
          >
            {showAll ? `Verified only (${verifiedCount})` : `Show all (${markets.length})`}
          </Link>
        ) : (
          markets.length > 0 && (
            <span className="whitespace-nowrap rounded-md border border-[rgba(22,163,74,0.25)] bg-ok-tint px-2.5 py-1 text-xs text-ok">
              All verified ({verifiedCount})
            </span>
          )
        )}
      </div>
      {shown.length === 0 ? (
        <Empty>
          {markets.length === 0
            ? `No ${accent} markets deployed yet on ${cfg.name}. Markets deployed through ${factoryLabel} appear here automatically.`
            : unverifiedCount > 0 && !showAll && !q
              ? `No verified ${accent} markets on ${cfg.name} yet — ${unverifiedCount} unverified deployment(s) hidden.`
              : "No markets match."}
        </Empty>
      ) : (
        <Panel className="mt-5">
          <Table
            head={
              <>
                <Th>Market</Th>
                <Th>Senior tranche</Th>
                <Th>Junior tranche</Th>
                {kind === "day" && <Th>LP tranche</Th>}
                <Th className="text-right">Deployed</Th>
                <Th />
              </>
            }
          >
            {shown.map((m) => (
              <tr key={m.id} className="hover:bg-[rgba(15,14,13,0.015)]">
                <Td>
                  <div className="flex items-center gap-2">
                    <Link
                      href={`/${chain}/markets/${kind}/${m.kernel}`}
                      className="inline-flex items-center gap-1.5 whitespace-nowrap text-[13.5px] font-semibold hover:text-ok"
                    >
                      <span
                        className="inline-block h-2 w-2 shrink-0 rounded-full"
                        style={{ backgroundColor: AM_COLOR[kind] }}
                      />
                      {marketDisplay(cfg.chainId, m).title}
                    </Link>
                    {marketDisplay(cfg.chainId, m).hint && (
                      <Mono className="text-[11px] text-muted">{marketDisplay(cfg.chainId, m).hint}</Mono>
                    )}
                    <AmBadge kind={kind} />
                    {!isVerifiedMarket(cfg.chainId, m.kernel) && <UnverifiedBadge />}
                  </div>
                </Td>
                <Td>
                  <AddrLink chainId={cfg.chainId} address={m.seniorTranche} short />
                </Td>
                <Td>
                  <AddrLink chainId={cfg.chainId} address={m.juniorTranche} short />
                </Td>
                {kind === "day" && (
                  <Td>
                    {m.liquidityProviderTranche && m.liquidityProviderTranche !== ZERO_ADDR ? (
                      <AddrLink chainId={cfg.chainId} address={m.liquidityProviderTranche} short />
                    ) : (
                      <span className="text-xs text-muted">—</span>
                    )}
                  </Td>
                )}
                <Td className="whitespace-nowrap text-right text-[13px] text-body">
                  <LocalTime unix={Number(m.timestamp)} />
                </Td>
                <Td className="whitespace-nowrap text-right">
                  {kind === "dawn" && isVerifiedMarket(cfg.chainId, m.kernel) && (
                    <a
                      href={roycoMarketUrl(cfg.chainId, m.kernel)}
                      target="_blank"
                      rel="noreferrer"
                      className="mr-3 text-xs !text-bronze"
                    >
                      royco.org ↗
                    </a>
                  )}
                  <Link href={`/${chain}/markets/${kind}/${m.kernel}`} className="text-xs !text-ok">
                    View ↗
                  </Link>
                </Td>
              </tr>
            ))}
          </Table>
        </Panel>
      )}
    </>
  );
}

export function marketsSupported(chainSlug: string, kind: AmKind): boolean {
  const cfg = chainBySlug(chainSlug);
  return !!cfg && !!managerFor(cfg.chainId, kind);
}
