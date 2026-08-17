"use client";
// Human-readable timestamp in the VIEWER's timezone. Server-rendered HTML carries the UTC form;
// the client re-renders with the local zone on hydration (suppressHydrationWarning covers the
// mismatch). `withTime=false` drops the clock for date-only contexts.
import { useEffect, useState } from "react";

function fmtLocal(unix: number, withTime: boolean): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    ...(withTime ? { timeStyle: "short" as const } : {}),
  }).format(new Date(unix * 1000));
}

function fmtUtc(unix: number, withTime: boolean): string {
  const iso = new Date(unix * 1000).toISOString();
  return withTime ? iso.slice(0, 16).replace("T", " ") + " UTC" : iso.slice(0, 10);
}

export function LocalTime({
  unix,
  withTime = true,
  className = "",
}: {
  unix: number;
  withTime?: boolean;
  className?: string;
}) {
  const [local, setLocal] = useState<string | null>(null);
  useEffect(() => setLocal(fmtLocal(unix, withTime)), [unix, withTime]);
  return (
    <span suppressHydrationWarning className={className} title={fmtUtc(unix, true)}>
      {local ?? fmtUtc(unix, withTime)}
    </span>
  );
}
