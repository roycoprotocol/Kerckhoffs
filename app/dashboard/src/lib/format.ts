import type { Severity } from "@/model";

export { shorten } from "@/lib/catalog";

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

export function fmtDurationUntil(unixTarget: number, nowUnix: number): string {
  const delta = unixTarget - nowUnix;
  if (delta <= 0) return "now";
  return `in ${fmtDelay(delta)}`;
}

export function severityClass(sev: Severity): string {
  return sev === "HIGH" ? "text-high" : sev === "MEDIUM" ? "text-med" : "text-low";
}
export function severityBg(sev: Severity): string {
  return sev === "HIGH"
    ? "bg-high/15 text-high"
    : sev === "MEDIUM"
      ? "bg-med/15 text-med"
      : "bg-low/15 text-low";
}
