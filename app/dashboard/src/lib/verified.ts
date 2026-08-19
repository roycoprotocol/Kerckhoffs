// Verified markets — the set of kernels listed on royco.org, fetched from its public paginated
// explore API. Loaded in the background (fire-and-forget at page load) into an in-process cache
// so reads are synchronous and rendering never blocks on royco.org; the static seed file bridges
// the very first render and any API outage.
import verifiedSeed from "@/metadata/verified-markets.json";

const EXPLORE_URL = "https://www.royco.org/api/v1/market/explore";
const PAGE_SIZE = 500;
const TTL_MS = 5 * 60_000;

interface ExploreRow {
  chainId: number;
  marketId: string;
  listingType?: string; // "verified" | "staging" | "deprecated"
}
interface ExploreResponse {
  data: ExploreRow[];
  page: { index: number; size: number; total: number };
}

const key = (chainId: number, kernel: string) => `${chainId}:${kernel.toLowerCase()}`;

// Bootstrap from the seed file so the first render (and API failures) degrade gracefully.
let verified = new Set<string>(
  Object.entries(verifiedSeed as Record<string, string[]>).flatMap(([chainId, kernels]) =>
    kernels.map((k) => key(Number(chainId), k)),
  ),
);
let loadedFromApi = false;
let warmedAt = 0;
let inflight: Promise<void> | null = null;

async function fetchAllPages(): Promise<Set<string>> {
  const out = new Set<string>();
  let index = 1;
  for (;;) {
    const res = await fetch(EXPLORE_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ page: { index, size: PAGE_SIZE } }),
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`royco explore HTTP ${res.status}`);
    const json = (await res.json()) as ExploreResponse;
    // Only listings royco.org itself marks verified — staging and deprecated listings don't count.
    for (const r of json.data ?? []) {
      if (r.listingType === "verified") out.add(key(r.chainId, r.marketId));
    }
    const totalPages = json.page?.total ?? 1;
    if (index >= totalPages || (json.data?.length ?? 0) < PAGE_SIZE) return out;
    index += 1;
  }
}

// Fire-and-forget warmer: call `void warmVerifiedMarkets()` at the start of a page render.
// Never throws; a failure keeps the previous set (or the seed).
export function warmVerifiedMarkets(): Promise<void> {
  if (loadedFromApi && Date.now() - warmedAt < TTL_MS) return Promise.resolve();
  if (inflight) return inflight;
  inflight = fetchAllPages()
    .then((set) => {
      if (set.size > 0) {
        verified = set;
        loadedFromApi = true;
        warmedAt = Date.now();
      }
    })
    .catch(() => {})
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

export function isVerifiedMarket(chainId: number, kernel: string): boolean {
  return verified.has(key(chainId, kernel));
}
