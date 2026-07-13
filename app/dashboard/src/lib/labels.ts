// Address labeling & categorization. Merges catalog targets/actors (category + hierarchy from
// ExportCatalog) with the hand-maintained labels.json (external addresses), and exposes a directory
// grouped by category with market/vault hierarchy.
import type { Address, Category, DirectoryGroup, Label } from "@/model";
import { actor, getCatalog, shorten, targetInfo } from "@/lib/catalog";
import labelsRaw from "@/metadata/labels.json";

interface ExtLabel {
  label: string;
  category: string;
  tags?: string[];
  note?: string;
}
const EXTERNAL = labelsRaw as unknown as Record<string, Record<string, ExtLabel>>;

function ext(chainId: number, addr: string): ExtLabel | undefined {
  return EXTERNAL[String(chainId)]?.[addr.toLowerCase()];
}

const asCategory = (c: string): Category => c as Category;

export function resolveLabel(chainId: number, address: string): Label {
  const addr = address.toLowerCase() as Address;

  const t = targetInfo(chainId, addr);
  if (t) {
    return {
      address: addr,
      name: t.name,
      category: asCategory(t.category),
      subtype: t.type,
      parent: t.parent || undefined,
      tags: [],
      isExternal: false,
      known: true,
    };
  }
  const a = actor(chainId, addr);
  if (a) {
    return {
      address: addr,
      name: a.name,
      category: asCategory(a.category),
      tags: [],
      pendingDeployment: a.pendingDeployment,
      isExternal: false,
      known: true,
    };
  }
  const e = ext(chainId, addr);
  if (e) {
    return {
      address: addr,
      name: e.label,
      category: asCategory(e.category),
      tags: e.tags ?? [],
      isExternal: true,
      known: true,
    };
  }
  return { address: addr, name: shorten(addr), category: "external", tags: [], isExternal: true, known: false };
}

const CATEGORY_TITLE: Record<string, string> = {
  factory: "Control plane",
  multisig: "Multisigs",
  market: "Markets",
  vault: "Vaults",
  strategy: "Strategies (Makina)",
  entrypoint: "Entry point",
  syncer: "Syncer",
  agent: "Agents",
  lp: "Liquidity providers",
  protocol: "External protocols",
  external: "External / unlabeled",
};
const CATEGORY_ORDER = [
  "factory",
  "multisig",
  "market",
  "vault",
  "strategy",
  "entrypoint",
  "syncer",
  "agent",
  "protocol",
  "lp",
  "external",
];

// All labeled addresses on a chain (catalog targets + actors + labels.json).
export function allLabels(chainId: number): Label[] {
  const cat = getCatalog(chainId);
  const out: Label[] = [];
  const seen = new Set<string>();
  const push = (l: Label) => {
    if (seen.has(l.address)) return;
    seen.add(l.address);
    out.push(l);
  };
  for (const t of cat?.targets ?? []) push(resolveLabel(chainId, t.address));
  for (const a of cat?.actors ?? []) push(resolveLabel(chainId, a.address));
  for (const addr of Object.keys(EXTERNAL[String(chainId)] ?? {})) push(resolveLabel(chainId, addr));
  return out;
}

// Directory grouped by category; market/vault categories nest children under their parent.
export function buildDirectory(chainId: number): DirectoryGroup[] {
  const labels = allLabels(chainId);
  const byCat = new Map<string, Label[]>();
  for (const l of labels) {
    if (!byCat.has(l.category)) byCat.set(l.category, []);
    byCat.get(l.category)!.push(l);
  }

  const groups: DirectoryGroup[] = [];
  for (const category of CATEGORY_ORDER) {
    const ls = byCat.get(category);
    if (!ls) continue;
    let entries;
    if (category === "market" || category === "vault" || category === "strategy") {
      // group by parent (market/vault name)
      const byParent = new Map<string, Label[]>();
      for (const l of ls) {
        const p = l.parent ?? l.name;
        if (!byParent.has(p)) byParent.set(p, []);
        byParent.get(p)!.push(l);
      }
      entries = [...byParent.entries()]
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([parent, children]) => ({
          label: { address: "0x" as Address, name: parent, category: asCategory(category), tags: [], isExternal: false, known: true },
          children: children.sort((a, b) => (a.subtype ?? "").localeCompare(b.subtype ?? "")),
        }));
    } else {
      entries = ls.sort((a, b) => a.name.localeCompare(b.name)).map((label) => ({ label }));
    }
    groups.push({ category: asCategory(category), title: CATEGORY_TITLE[category] ?? category, entries });
  }
  return groups;
}

export function searchLabels(chainId: number, q: string, limit = 12): Label[] {
  const needle = q.trim().toLowerCase();
  if (!needle) return [];
  return allLabels(chainId)
    .filter(
      (l) =>
        l.name.toLowerCase().includes(needle) ||
        l.address.includes(needle) ||
        (l.parent ?? "").toLowerCase().includes(needle) ||
        l.category.includes(needle),
    )
    .slice(0, limit);
}
