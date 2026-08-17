// ERC-20 name/symbol reads over RPC — the fallback naming path for Day markets whose subgraph
// rows predate tranche-name capture. Cached per (chain, address) for the process lifetime;
// token metadata is immutable in practice.
import { createPublicClient, http } from "viem";
import { chainById } from "@/config/chains";

const ERC20_ABI = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
] as const;

const cache = new Map<string, { name: string | null; symbol: string | null }>();

export async function fetchErc20Meta(
  chainId: number,
  address: string,
): Promise<{ name: string | null; symbol: string | null }> {
  const key = `${chainId}:${address.toLowerCase()}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const rpc = chainById(chainId)?.rpcUrl;
  if (!rpc) return { name: null, symbol: null };
  const client = createPublicClient({ transport: http(rpc) });
  const [name, symbol] = await Promise.all(
    (["name", "symbol"] as const).map((fn) =>
      client
        .readContract({ address: address as `0x${string}`, abi: ERC20_ABI, functionName: fn })
        .then((v) => v as string)
        .catch(() => null),
    ),
  );
  const out = { name, symbol };
  if (name || symbol) cache.set(key, out); // don't cache transient RPC failures
  return out;
}
