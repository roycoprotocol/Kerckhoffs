import Link from "next/link";
import type { ReactNode } from "react";
import type { Drift, Severity } from "@/model";
import { severityBg } from "@/lib/format";

export function Panel({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-lg border border-border bg-panel ${className}`}>{children}</div>;
}

export function PageTitle({ title, subtitle }: { title: string; subtitle?: ReactNode }) {
  return (
    <div className="mb-5">
      <h1 className="text-xl font-semibold">{title}</h1>
      {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
    </div>
  );
}

export function Mono({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <span className={`font-mono text-[13px] ${className}`}>{children}</span>;
}

export function SeverityPill({ sev, children }: { sev: Severity; children?: ReactNode }) {
  return (
    <span className={`inline-block rounded px-1.5 py-0.5 text-[11px] font-medium ${severityBg(sev)}`}>
      {children ?? sev}
    </span>
  );
}

export function DriftBadge({ drift }: { drift: Drift[] }) {
  if (!drift.length) return <span className="text-[11px] text-ok">in sync</span>;
  const high = drift.filter((d) => d.severity === "HIGH").length;
  const med = drift.filter((d) => d.severity === "MEDIUM").length;
  const low = drift.filter((d) => d.severity === "LOW").length;
  const sev: Severity = high ? "HIGH" : med ? "MEDIUM" : "LOW";
  return <SeverityPill sev={sev}>{[high && `${high} high`, med && `${med} med`, low && `${low} low`].filter(Boolean).join(" · ")}</SeverityPill>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="rounded-lg border border-border bg-panel p-8 text-center text-sm text-muted">{children}</div>;
}

export function SubgraphMissing({ chainName }: { chainName: string }) {
  return (
    <Empty>
      No subgraph endpoint configured for <b>{chainName}</b>. Set <Mono>SUBGRAPH_URL_&lt;chainId&gt;</Mono> in the
      environment (a local graph-node in dev, or the Goldsky URL in prod).
    </Empty>
  );
}

export function Table({ head, children }: { head: ReactNode; children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-border text-left text-[11px] uppercase tracking-wide text-muted">{head}</tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}
export const Th = ({ children, className = "" }: { children?: ReactNode; className?: string }) => (
  <th className={`px-3 py-2 font-medium ${className}`}>{children}</th>
);
export const Td = ({ children, className = "" }: { children?: ReactNode; className?: string }) => (
  <td className={`px-3 py-2 align-top ${className}`}>{children}</td>
);

export function RoleLink({ slug, id, name }: { slug: string; id: string; name: string }) {
  return (
    <Link href={`/${slug}/role/${id}`} className="hover:text-ok">
      {name}
    </Link>
  );
}
export function AccountLink({ slug, address, label }: { slug: string; address: string; label: ReactNode }) {
  return (
    <Link href={`/${slug}/accounts/${address}`} className="font-mono text-[13px] hover:text-ok">
      {label}
    </Link>
  );
}
