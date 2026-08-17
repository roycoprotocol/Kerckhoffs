export { shorten } from "@/lib/catalog";
import { chainById } from "@/config/chains";

export function explorerTx(chainId: number, hash: string): string {
  return `${chainById(chainId)?.explorerUrl ?? "https://etherscan.io"}/tx/${hash}`;
}
export function explorerAddress(chainId: number, address: string): string {
  return `${chainById(chainId)?.explorerUrl ?? "https://etherscan.io"}/address/${address}`;
}

export function fmtDelay(seconds: number): string {
  if (!seconds) return "immediate";
  const d = 86400,
    h = 3600;
  if (seconds % d === 0) return `${seconds / d}d`;
  if (seconds % h === 0) return `${seconds / h}h`;
  return `${seconds}s`;
}

export function fmtTime(unix: number): string {
  return new Date(unix * 1000).toISOString().slice(0, 16).replace("T", " ") + "Z";
}

// "seniorTranche" → "Senior Tranche", "dayEntryPoint" → "Day Entry Point". For display of
// catalog type/component names — never applied to function selectors.
export function humanize(s: string): string {
  return s
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/^./, (c) => c.toUpperCase())
    .replace(/\b(ydm|lpt|lp|uups)\b/gi, (m) => m.toUpperCase());
}

export function fmtDurationUntil(unixTarget: number, nowUnix: number): string {
  const delta = unixTarget - nowUnix;
  if (delta <= 0) return "now";
  return `in ${fmtDelay(delta)}`;
}
