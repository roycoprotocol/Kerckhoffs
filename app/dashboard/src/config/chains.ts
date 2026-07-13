// Per-chain configuration. Endpoints come from server env (see .env.example) so the same code
// targets a local graph-node in dev and Goldsky in prod. Factory addresses mirror
// src/registry/Factory.sol.

export interface ChainConfig {
  chainId: number;
  slug: string; // URL segment
  name: string;
  factory: `0x${string}`;
  hasVaults: boolean; // Concrete vaults + Makina slots (mainnet only today)
  subgraphUrl?: string;
  rpcUrl?: string;
}

const FACTORY_CREATE2 = "0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C" as const;
const FACTORY_BASE = "0x568c9709DaA2f7B7cc66AbC3E41DA0f0A339551A" as const;

export const CHAINS: ChainConfig[] = [
  { chainId: 1, slug: "ethereum", name: "Ethereum", factory: FACTORY_CREATE2, hasVaults: true },
  { chainId: 43114, slug: "avalanche", name: "Avalanche", factory: FACTORY_CREATE2, hasVaults: false },
  { chainId: 42161, slug: "arbitrum", name: "Arbitrum", factory: FACTORY_CREATE2, hasVaults: false },
  { chainId: 8453, slug: "base", name: "Base", factory: FACTORY_BASE, hasVaults: false },
].map((c) => ({
  ...c,
  subgraphUrl: process.env[`SUBGRAPH_URL_${c.chainId}`] || undefined,
  rpcUrl: process.env[`RPC_URL_${c.chainId}`] || undefined,
}));

export function chainBySlug(slug: string): ChainConfig | undefined {
  return CHAINS.find((c) => c.slug === slug);
}
export function chainById(chainId: number): ChainConfig | undefined {
  return CHAINS.find((c) => c.chainId === chainId);
}
export const DEFAULT_CHAIN = CHAINS[0];
