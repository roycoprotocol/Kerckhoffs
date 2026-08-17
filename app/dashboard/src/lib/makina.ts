// Makina governance-slot reads (main.md §7): live RPC via viem, not the subgraph. Reports the
// current slot values as-is — which addresses hold riskManager / riskManagerTimelock on each
// Machine. The machine list comes from the catalog's makinaSlots.
import { createPublicClient, http } from "viem";
import { chainById } from "@/config/chains";
import { getCatalog } from "@/lib/catalog";
import type { Address, MakinaSlotView } from "@/model";

const MACHINE_ABI = [
  { type: "function", name: "riskManager", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "riskManagerTimelock", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

export async function fetchMakinaSlots(chainId: number): Promise<MakinaSlotView[]> {
  const cat = getCatalog(chainId);
  const rpc = chainById(chainId)?.rpcUrl;
  if (!cat?.makinaSlots.length || !rpc) return [];

  const client = createPublicClient({ transport: http(rpc) });
  const out: MakinaSlotView[] = [];

  for (const s of cat.makinaSlots) {
    for (const slot of ["riskManager", "riskManagerTimelock"] as const) {
      let actual: Address | null = null;
      try {
        const v = await client.readContract({
          address: s.machine as Address,
          abi: MACHINE_ABI,
          functionName: slot,
        });
        actual = (v as string).toLowerCase() as Address;
      } catch {
        actual = null;
      }
      out.push({ vault: s.vault, slot, actual });
    }
  }
  return out;
}
