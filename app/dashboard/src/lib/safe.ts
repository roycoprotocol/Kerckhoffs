// Safe (multisig) config, read from the public Safe Transaction Service. Used by the Overview
// pipeline to show the REAL signer quorum ("3 of 5") with a link to the Safe — verifiable, not
// decorative. Fails soft: null hides the quorum pill and keeps the plain Safe link.

const SAFE_SERVICE: Record<number, string> = {
  1: "https://safe-transaction-mainnet.safe.global",
  42161: "https://safe-transaction-arbitrum.safe.global",
  8453: "https://safe-transaction-base.safe.global",
  43114: "https://safe-transaction-avalanche.safe.global",
};
const SAFE_APP_CHAIN: Record<number, string> = { 1: "eth", 42161: "arb1", 8453: "base", 43114: "avax" };

export function safeAppUrl(chainId: number, address: string): string {
  const prefix = SAFE_APP_CHAIN[chainId] ?? "eth";
  return `https://app.safe.global/home?safe=${prefix}:${address}`;
}

export async function fetchSafeQuorum(
  chainId: number,
  address: string,
): Promise<{ threshold: number; owners: number } | null> {
  const base = SAFE_SERVICE[chainId];
  if (!base) return null;
  try {
    const res = await fetch(`${base}/api/v1/safes/${address}/`, { next: { revalidate: 3600 } });
    if (!res.ok) return null;
    const json = (await res.json()) as { threshold?: number; owners?: string[] };
    if (!json.threshold || !json.owners?.length) return null;
    return { threshold: json.threshold, owners: json.owners.length };
  } catch {
    return null;
  }
}
