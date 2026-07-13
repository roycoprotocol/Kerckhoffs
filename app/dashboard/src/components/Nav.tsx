"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { CHAINS } from "@/config/chains";

export function ChainSwitcher({ slug }: { slug: string }) {
  const router = useRouter();
  const pathname = usePathname();
  return (
    <select
      value={slug}
      onChange={(e) => {
        const next = e.target.value;
        // Swap the leading /<slug> segment; drill-down paths reset to the chain root.
        const rest = pathname.replace(/^\/[^/]+/, "");
        const target = rest && !rest.startsWith("/role") && !rest.startsWith("/accounts") ? rest : "";
        router.push(`/${next}${target}`);
      }}
      className="rounded border border-border bg-panel px-2 py-1 text-sm"
    >
      {CHAINS.map((c) => (
        <option key={c.chainId} value={c.slug}>
          {c.name}
        </option>
      ))}
    </select>
  );
}

const TABS = [
  { seg: "", label: "Roles" },
  { seg: "contracts", label: "Directory" },
  { seg: "functions", label: "Functions" },
  { seg: "operations", label: "Pending ops" },
  { seg: "drift", label: "Drift" },
];

export function Nav({ slug }: { slug: string }) {
  const pathname = usePathname();
  return (
    <nav className="flex items-center gap-1 border-b border-border px-4 text-sm">
      {TABS.map((t) => {
        const href = `/${slug}${t.seg ? `/${t.seg}` : ""}`;
        const active = t.seg
          ? pathname.startsWith(href)
          : pathname === `/${slug}` || pathname.startsWith(`/${slug}/role`) || pathname.startsWith(`/${slug}/accounts`);
        return (
          <Link
            key={t.seg}
            href={href}
            className={`border-b-2 px-3 py-2 ${active ? "border-ok text-fg" : "border-transparent text-muted hover:text-fg"}`}
          >
            {t.label}
          </Link>
        );
      })}
      <Link
        href="/diff"
        className={`ml-auto border-b-2 px-3 py-2 ${pathname === "/diff" ? "border-ok text-fg" : "border-transparent text-muted hover:text-fg"}`}
      >
        Multi-chain diff
      </Link>
    </nav>
  );
}
