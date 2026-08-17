import Link from "next/link";
import type { ReactNode } from "react";
import type { AmKind, ControllingAm } from "@/model";

export function Panel({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`overflow-hidden rounded-xl border border-border bg-panel ${className}`}>{children}</div>;
}

// Mono uppercase eyebrow label (the design language's section marker).
export function Eyebrow({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`font-mono text-[11px] uppercase tracking-[0.1em] text-muted ${className}`}>{children}</div>
  );
}

// Serif page title with an optional green accent word, preceded by an eyebrow. Titles end with a
// period per the design language ("Dawn Markets.", "Roles.").
export function PageTitle({
  eyebrow,
  accent,
  title,
  right,
  subtitle,
}: {
  eyebrow?: ReactNode;
  accent?: string;
  title: string;
  right?: ReactNode;
  subtitle?: ReactNode;
}) {
  return (
    <div className="mb-6">
      {eyebrow && (
        <div className="flex items-baseline justify-between">
          <Eyebrow>{eyebrow}</Eyebrow>
        </div>
      )}
      <div className="mt-1.5 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <h1 className="font-serif text-2xl font-semibold md:text-3xl">
          {accent && <span className="text-ok">{accent}</span>}
          {accent ? " " : ""}
          {title}
        </h1>
        {right}
      </div>
      {subtitle && <p className="mt-2 max-w-xl text-sm text-body">{subtitle}</p>}
    </div>
  );
}

// Inline mono stat for page-title right slots: label + number.
export function InlineStat({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-baseline gap-2">
      <span className="font-mono text-[11px] uppercase tracking-[0.1em] text-muted">{label}</span>
      <span className="font-mono text-xl text-fg">{value}</span>
    </div>
  );
}

export function Mono({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <span className={`font-mono text-xs ${className}`}>{children}</span>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="rounded-xl border border-border bg-panel p-8 text-center text-sm text-muted">{children}</div>;
}

export function SubgraphMissing({ chainName }: { chainName: string }) {
  return (
    <Empty>
      No subgraph endpoint configured for <b>{chainName}</b>. Set <Mono>SUBGRAPH_URL_&lt;chainId&gt;</Mono> in the
      environment (a local graph-node in dev, or the Goldsky URL in prod).
    </Empty>
  );
}

// Wide tables scroll horizontally INSIDE their panel on small screens (min-w keeps columns from
// crushing); pass minW="min-w-0" for genuinely narrow tables.
export function Table({
  head,
  children,
  minW = "min-w-[640px]",
}: {
  head?: ReactNode;
  children: ReactNode;
  minW?: string;
}) {
  return (
    <div className="no-scrollbar overflow-x-auto">
      <table className={`w-full ${minW} md:min-w-0 border-collapse text-sm`}>
        {head && (
          <thead>
            <tr className="bg-head-tint text-left font-mono text-[11px] uppercase tracking-[0.1em] text-muted">
              {head}
            </tr>
          </thead>
        )}
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}
export const Th = ({ children, className = "" }: { children?: ReactNode; className?: string }) => (
  <th className={`px-4 py-2.5 font-normal ${className}`}>{children}</th>
);
export const Td = ({
  children,
  className = "",
  colSpan,
}: {
  children?: ReactNode;
  className?: string;
  colSpan?: number;
}) => (
  <td colSpan={colSpan} className={`border-t border-border2 px-4 py-2.5 align-top ${className}`}>
    {children}
  </td>
);

// Controlling-AccessManager badge. Dawn = bronze, Day = brand green, migrating = amber.
const AM_BADGE_STYLE: Record<ControllingAm, string> = {
  dawn: "text-bronze bg-bronze-tint",
  day: "text-ok bg-ok-tint",
  migrating: "text-med bg-med-tint",
  unknown: "text-muted border border-border",
};
const AM_BADGE_TEXT: Record<ControllingAm, string> = {
  dawn: "dawn",
  day: "day",
  migrating: "migrating",
  unknown: "no AM",
};
export function AmBadge({ kind }: { kind: ControllingAm }) {
  return (
    <span className={`inline-block rounded-md px-2 py-0.5 text-[11px] font-medium ${AM_BADGE_STYLE[kind]}`}>
      {AM_BADGE_TEXT[kind]}
    </span>
  );
}

// Green tint pill — the design language's in-table link/action treatment.
export function PillLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-block rounded-md bg-ok-tint px-2 py-0.5 text-xs font-medium !text-ok hover:!text-[#128A3F]"
    >
      {children}
    </Link>
  );
}

// Role links are AM-scoped: the same role id exists independently on the Dawn and Day AMs.
export function RoleLink({ slug, am, id, name }: { slug: string; am: AmKind; id: string; name: string }) {
  return <PillLink href={`/${slug}/am/${am}/role/${id}`}>{name}</PillLink>;
}
export function AccountLink({ slug, address, label }: { slug: string; address: string; label: ReactNode }) {
  return (
    <Link href={`/${slug}/accounts/${address}`} className="font-mono text-xs hover:text-ok">
      {label}
    </Link>
  );
}
