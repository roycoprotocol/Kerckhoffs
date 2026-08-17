// Shared search-result building for the ⌘K palette and the Search page. Pure & client-safe:
// everything comes from the statically-imported catalog/labels.
import { amKindsFor, roleName, rolesFor, shorten } from "@/lib/catalog";
import { searchLabels } from "@/lib/labels";

export interface SearchResult {
  kind: "role" | "address";
  href: string;
  primary: string;
  secondary: string;
  category?: string;
}

export function buildSearchResults(chainId: number, slug: string, q: string, limit = 8): SearchResult[] {
  const needle = q.trim().toLowerCase();
  if (!needle) return [];
  const out: SearchResult[] = [];

  // An arbitrary pasted address always resolves — the address page shows any contract's state.
  if (/^0x[0-9a-f]{40}$/.test(needle)) {
    out.push({
      kind: "address",
      href: `/${slug}/address/${needle}`,
      primary: "View contract state",
      secondary: shorten(needle),
      category: "external",
    });
  }
  // A bare numeric query is treated as a role id on each AM.
  if (/^\d{1,20}$/.test(needle)) {
    for (const am of amKindsFor(chainId)) {
      out.push({
        kind: "role",
        href: `/${slug}/am/${am}/role/${needle}`,
        primary: roleName(chainId, am, needle),
        secondary: `${am} · role ${needle}`,
      });
    }
  }

  // Shared role names produce one hit per AM — they are distinct on-chain roles.
  out.push(
    ...amKindsFor(chainId).flatMap((am) =>
      rolesFor(chainId, am)
        .filter((r) => r.name.toLowerCase().includes(needle))
        .map<SearchResult>((r) => ({
          kind: "role",
          href: `/${slug}/am/${am}/role/${r.id}`,
          primary: r.name,
          secondary: `${am} · role ${r.id}`,
        }))
        .slice(0, limit),
    ),
  );
  out.push(
    ...searchLabels(chainId, needle, limit).map<SearchResult>((l) => ({
      kind: "address",
      href: `/${slug}/address/${l.address}`,
      primary: l.name,
      secondary: shorten(l.address),
      category: l.category,
    })),
  );
  return out.slice(0, limit * 2);
}
