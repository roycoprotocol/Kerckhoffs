// Per-chain configuration. Endpoints come from server env (see .env.example) so the same code
// targets a local graph-node in dev and Goldsky in prod. AccessManager addresses live in the
// catalog (`managers[]` in catalog.<chainId>.json) — see lib/catalog.ts managersFor().

export interface ChainConfig {
  chainId: number;
  slug: string; // URL segment
  name: string;
  explorerUrl: string; // block-explorer base, no trailing slash
  subgraphUrl?: string;
  rpcUrl?: string;
}

// Public fallbacks for the few light eth_calls the dashboard makes (Makina slots, ERC-20
// metadata). An explicit RPC_URL_<chainId> env always wins.
const PUBLIC_RPC: Record<number, string> = {
  1: "https://ethereum-rpc.publicnode.com",
  43114: "https://avalanche-c-chain-rpc.publicnode.com",
  42161: "https://arbitrum-one-rpc.publicnode.com",
  8453: "https://base-rpc.publicnode.com",
};

export const CHAINS: ChainConfig[] = [
  { chainId: 1, slug: "ethereum", name: "Ethereum", explorerUrl: "https://etherscan.io" },
  { chainId: 43114, slug: "avalanche", name: "Avalanche", explorerUrl: "https://snowtrace.io" },
  { chainId: 42161, slug: "arbitrum", name: "Arbitrum", explorerUrl: "https://arbiscan.io" },
  { chainId: 8453, slug: "base", name: "Base", explorerUrl: "https://basescan.org" },
].map((c) => ({
  ...c,
  subgraphUrl: process.env[`SUBGRAPH_URL_${c.chainId}`] || undefined,
  rpcUrl: process.env[`RPC_URL_${c.chainId}`] || PUBLIC_RPC[c.chainId],
}));

export function chainBySlug(slug: string): ChainConfig | undefined {
  return CHAINS.find((c) => c.slug === slug);
}
export function chainById(chainId: number): ChainConfig | undefined {
  return CHAINS.find((c) => c.chainId === chainId);
}
export const DEFAULT_CHAIN = CHAINS[0];
