// Multi-chain diff (main.md §3.5): group the same role across chains, flag per-chain divergence.
import { CHAINS } from "@/config/chains";
import { shorten } from "@/lib/catalog";
import { buildRoleViews } from "@/lib/merge";
import { hasSubgraph } from "@/lib/subgraph";
import type { ChainRoleRow, RoleView } from "@/model";

export async function buildChainMatrix(): Promise<{ rows: ChainRoleRow[]; chains: typeof CHAINS }> {
  const perChain = await Promise.all(
    CHAINS.map(async (c) => {
      if (!hasSubgraph(c.chainId)) return { chain: c, views: [] as RoleView[] };
      try {
        return { chain: c, views: await buildRoleViews(c.chainId) };
      } catch {
        return { chain: c, views: [] as RoleView[] };
      }
    }),
  );

  const rows = new Map<string, ChainRoleRow>();
  for (const { views } of perChain) {
    for (const v of views) {
      if (!rows.has(v.id)) rows.set(v.id, { id: v.id, name: v.name, cells: [] });
    }
  }

  for (const row of rows.values()) {
    for (const { chain, views } of perChain) {
      const v = views.find((x) => x.id === row.id);
      row.cells.push({
        chainId: chain.chainId,
        slug: chain.slug,
        chainName: chain.name,
        present: !!v && v.presentOnChain,
        holderLabels: v ? v.holders.map((h) => h.actor ?? shorten(h.address)) : [],
        grantDelaySeconds: v?.config.grantDelaySeconds ?? 0,
        guardianRoleName: v?.config.guardianRoleName ?? "",
        divergent: false,
      });
    }
    markDivergence(row);
  }

  return { rows: [...rows.values()].sort((a, b) => a.name.localeCompare(b.name)), chains: CHAINS };
}

function sig(c: ChainRoleRow["cells"][number]): string {
  return `${[...c.holderLabels].sort().join(",")}|${c.guardianRoleName}|${c.grantDelaySeconds}`;
}

function markDivergence(row: ChainRoleRow): void {
  const present = row.cells.filter((c) => c.present);
  if (present.length < 2) return;
  const counts = new Map<string, number>();
  for (const c of present) counts.set(sig(c), (counts.get(sig(c)) ?? 0) + 1);
  let modal = "";
  let best = -1;
  for (const [s, n] of counts) if (n > best) ((best = n), (modal = s));
  for (const c of present) if (sig(c) !== modal) c.divergent = true;
}
