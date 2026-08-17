// Calldata decoding for the operation detail page. The selector catalog (selectors.json, built
// from the audited Solidity's method identifiers) supplies the canonical signature; viem does the
// ABI decode. Fails soft: unknown selector or a non-canonical signature (some artifacts emit
// struct names instead of expanded tuples) → null, and the page falls back to raw hex.
import { decodeFunctionData, parseAbiItem, type AbiFunction } from "viem";
import { selectorSignature } from "@/lib/catalog";

export interface DecodedArg {
  name: string;
  type: string;
  value: string;
  isAddress: boolean; // plain `address` args render as AddressLabel links
}
export interface DecodedCall {
  name: string;
  signature: string;
  args: DecodedArg[];
}

function stringify(v: unknown): string {
  if (typeof v === "bigint") return v.toString();
  if (Array.isArray(v)) return `[${v.map(stringify).join(", ")}]`;
  if (v !== null && typeof v === "object")
    return `{ ${Object.entries(v)
      .map(([k, x]) => `${k}: ${stringify(x)}`)
      .join(", ")} }`;
  return String(v);
}

export function decodeCalldata(data: string): DecodedCall | null {
  const signature = selectorSignature(data.slice(0, 10));
  if (!signature) return null;
  try {
    const fn = parseAbiItem(`function ${signature}`) as AbiFunction;
    const { args = [] } = decodeFunctionData({ abi: [fn], data: data as `0x${string}` });
    return {
      name: fn.name,
      signature,
      args: (args as unknown[]).map((v, i) => {
        const input = fn.inputs[i];
        return {
          name: input?.name || `arg${i}`,
          type: input?.type ?? "?",
          value: stringify(v),
          isAddress: input?.type === "address",
        };
      }),
    };
  } catch {
    return null;
  }
}
