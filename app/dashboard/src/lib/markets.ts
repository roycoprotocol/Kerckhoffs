// Market enumeration + display naming + the dynamic component-label overlay.
//
// Markets are enumerated from factory deployment events (subgraph `Market` entities). Dawn market
// components are also in the generated catalog, but DAY market components exist nowhere statically
// — so pages call `warmMarketLabels(chainId)` before rendering and `resolveLabel` consults the
// overlay built here, making day components resolve (chips, humanized names, market links)
// exactly like catalog ones.
import type { Address, AmKind, Label } from "@/model";
import { amKindsFor, factoryFor, shorten, targetInfo } from "@/lib/catalog";
import { fetchErc20Meta } from "@/lib/erc20";
import { fetchMarkets, type SgMarket } from "@/lib/subgraph";

export const MARKET_COMPONENTS: { key: keyof SgMarket; label: string }[] = [
  { key: "kernel", label: "Kernel" },
  { key: "accountant", label: "Accountant" },
  { key: "seniorTranche", label: "Senior tranche" },
  { key: "juniorTranche", label: "Junior tranche" },
  { key: "liquidityProviderTranche", label: "LP tranche" },
  { key: "ydm", label: "YDM" },
  { key: "lptYdm", label: "LPT YDM" },
];

export const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

// Display name for a market. Dawn markets keep their catalog name; Day markets are named by the
// senior tranche's ERC-20 name, with the symbol as a secondary hint.
export function marketDisplay(chainId: number, m: SgMarket): { title: string; hint?: string } {
  const ti = targetInfo(chainId, m.kernel);
  if (m.kind === "dawn") {
    return { title: ti?.parent ?? m.seniorTrancheSymbol ?? `Market ${shorten(m.kernel)}` };
  }
  const title = m.seniorTrancheName ?? ti?.parent ?? m.seniorTrancheSymbol ?? `Market ${shorten(m.kernel)}`;
  const hint = m.seniorTrancheSymbol && m.seniorTrancheSymbol !== title ? m.seniorTrancheSymbol : undefined;
  return { title, hint };
}

export function marketName(chainId: number, m: SgMarket): string {
  return marketDisplay(chainId, m).title;
}

// The public royco.org market page (Dawn UI) — keyed by the market's kernel.
export function roycoMarketUrl(chainId: number, kernel: string): string {
  return `https://www.royco.org/market/${chainId}/${kernel.toLowerCase()}/underlying`;
}

export async function fetchCurrentMarkets(chainId: number, kind: AmKind): Promise<SgMarket[]> {
  // Only markets from the CURRENT registered factory: grafted subgraph stores retain markets
  // deployed through retired factories (e.g. the pre-production Day deployment) — real history,
  // but not part of the tracked control plane.
  const currentFactory = factoryFor(chainId, kind);
  const markets = await fetchMarkets(chainId, kind);
  const current = currentFactory ? markets.filter((m) => m.factory.toLowerCase() === currentFactory) : markets;
  // Day markets indexed before the subgraph captured tranche names: fill them over RPC so the
  // market is still named by its senior tranche.
  await Promise.all(
    current
      .filter((m) => m.kind === "day" && !m.seniorTrancheName && m.seniorTranche !== ZERO_ADDR)
      .map(async (m) => {
        const meta = await fetchErc20Meta(chainId, m.seniorTranche);
        m.seniorTrancheName = m.seniorTrancheName ?? meta.name;
        m.seniorTrancheSymbol = m.seniorTrancheSymbol ?? meta.symbol;
      }),
  );
  return current;
}

// ── dynamic component-label overlay ───────────────────────────────────────────

const OVERLAY_TTL_MS = 60_000; // matches the subgraph fetchers' ISR revalidation window

const overlayByChain = new Map<number, Map<string, Label>>();
const warmedAt = new Map<number, number>();
const warming = new Map<number, Promise<void>>();

// Populate the overlay for a chain (subgraph markets → one Label per component). Pages that
// render addresses call this once before their first resolveLabel; failures leave the previous
// overlay in place (labels degrade to shortened addresses, never break the page).
export function warmMarketLabels(chainId: number): Promise<void> {
  const at = warmedAt.get(chainId);
  if (at && Date.now() - at < OVERLAY_TTL_MS) return Promise.resolve();
  const inflight = warming.get(chainId);
  if (inflight) return inflight;

  const p = (async () => {
    const marketLists = await Promise.all(
      amKindsFor(chainId).map((kind) => fetchCurrentMarkets(chainId, kind).catch(() => [])),
    );
    const map = new Map<string, Label>();
    for (const m of marketLists.flat()) {
      const title = marketDisplay(chainId, m).title;
      const kernel = m.kernel.toLowerCase();
      for (const c of MARKET_COMPONENTS) {
        const addr = String(m[c.key] ?? "").toLowerCase();
        if (!addr || addr === ZERO_ADDR) continue;
        map.set(addr, {
          address: addr as Address,
          name: `${title}.${String(c.key)}`,
          category: "market",
          subtype: String(c.key),
          parent: title,
          manager: m.kind,
          kernel: kernel as Address,
          tags: [],
          isExternal: false,
          known: true,
        });
      }
    }
    overlayByChain.set(chainId, map);
    warmedAt.set(chainId, Date.now());
  })().finally(() => warming.delete(chainId));
  warming.set(chainId, p);
  return p;
}

export function marketLabelFor(chainId: number, address: string): Label | undefined {
  return overlayByChain.get(chainId)?.get(address.toLowerCase());
}
