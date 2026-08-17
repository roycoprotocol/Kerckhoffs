"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { CHAINS } from "@/config/chains";
import type { AmKind } from "@/model";

export function ChainSwitcher({ slug, daySlugs }: { slug: string; daySlugs: string[] }) {
  const router = useRouter();
  const pathname = usePathname();
  return (
    <select
      value={slug}
      onChange={(e) => {
        const next = e.target.value;
        // Swap the leading /<slug> segment; drill-down paths reset to the chain root, and Day
        // paths reset when the target chain has no Day AM (Avalanche).
        const rest = pathname.replace(/^\/[^/]+/, "");
        const drillDown = /^\/(am\/[^/]+\/role|markets\/[^/]+\/0x|address|accounts)\//.test(rest);
        const dayOnly = rest.startsWith("/markets/day") || rest.startsWith("/am/day");
        const target = rest && !drillDown && !(dayOnly && !daySlugs.includes(next)) ? rest : "";
        router.push(`/${next}${target}`);
      }}
      className="rounded-md border border-border bg-panel px-2.5 py-1.5 text-[13px] text-fg"
    >
      {CHAINS.map((c) => (
        <option key={c.chainId} value={c.slug}>
          {c.name}
        </option>
      ))}
    </select>
  );
}

const tabClass = (active: boolean, secondary = false) =>
  `border-b-2 px-3 py-2.5 text-[13px] ${
    active
      ? "border-fg font-medium text-fg"
      : `border-transparent ${secondary ? "text-low" : "text-muted"} hover:text-fg`
  }`;

export function Nav({ slug, amKinds }: { slug: string; amKinds: AmKind[] }) {
  const pathname = usePathname();
  const hasDay = amKinds.includes("day");
  const tabs = [
    { seg: "overview", label: "Overview", show: true },
    { seg: "multisigs", label: "Multisigs", show: true },
    { seg: "markets/day", label: "Day Markets", show: hasDay },
    { seg: "markets/dawn", label: "Dawn Markets", show: true },
    { seg: "vaults", label: "Vaults", show: true },
    { seg: "periphery", label: "Periphery", show: true },
    { seg: "am/day", label: "Day AM", show: hasDay },
    { seg: "am/dawn", label: "Dawn AM", show: true },
  ];
  return (
    <nav className="mx-auto flex max-w-[1160px] items-center gap-0.5 px-6">
      {tabs
        .filter((t) => t.show)
        .map((t) => {
          const href = `/${slug}/${t.seg}`;
          return (
            <Link key={t.seg} href={href} className={tabClass(pathname.startsWith(href))}>
              {t.label}
            </Link>
          );
        })}
      <div className="flex-1" />
    </nav>
  );
}

// Secondary tab row inside an AM section (rendered by am/[am]/layout.tsx). Green underline.
export function AmSubNav({ slug, am }: { slug: string; am: AmKind }) {
  const pathname = usePathname();
  const base = `/${slug}/am/${am}`;
  const tabs = [
    { seg: "", label: "Roles" },
    { seg: "functions", label: "Functions" },
    { seg: "operations", label: "Pending ops" },
  ];
  return (
    <nav className="mb-7 flex items-center gap-0.5 border-b border-border text-[13px]">
      {tabs.map((t) => {
        const href = t.seg ? `${base}/${t.seg}` : base;
        const active = t.seg ? pathname.startsWith(href) : pathname === base || pathname.startsWith(`${base}/role`);
        return (
          <Link
            key={t.seg}
            href={href}
            className={`-mb-px border-b-2 px-3 py-2 ${
              active ? "border-ok font-medium text-fg" : "border-transparent text-muted hover:text-fg"
            }`}
          >
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}
