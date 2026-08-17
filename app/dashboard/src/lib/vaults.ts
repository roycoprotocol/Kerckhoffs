// Vault views for the Vaults tab: Concrete vaults + their Makina stacks, each annotated with the
// AccessManager that currently controls it. Control is derived from the subgraph: whichever
// manager has the vault's contracts registered as targets. During the Dawn -> Day migration a
// vault's targets may be registered on both AMs — surfaced as "migrating".
import type { AmKind, ControllingAm, Label, VaultView } from "@/model";
import { managerFor } from "@/lib/catalog";
import { allLabels, groupByParent } from "@/lib/labels";
import { fetchManagedTargetAddresses, hasSubgraph } from "@/lib/subgraph";

function controlling(addresses: string[], dawn: Set<string> | null, day: Set<string> | null): ControllingAm {
  const inDawn = dawn ? addresses.some((a) => dawn.has(a)) : false;
  const inDay = day ? addresses.some((a) => day.has(a)) : false;
  if (inDawn && inDay) return "migrating";
  if (inDawn) return "dawn";
  if (inDay) return "day";
  return "unknown";
}

async function managedTargets(chainId: number, kind: AmKind): Promise<Set<string> | null> {
  const mgr = managerFor(chainId, kind);
  if (!mgr || !hasSubgraph(chainId)) return null;
  try {
    return await fetchManagedTargetAddresses(chainId, mgr.address);
  } catch {
    return null;
  }
}

export async function buildVaultViews(chainId: number): Promise<VaultView[]> {
  const labels = allLabels(chainId);
  const vaultLabels = labels.filter((l) => l.category === "vault" && l.parent);
  const strategyLabels = labels.filter((l) => l.category === "strategy" && l.parent);
  if (vaultLabels.length === 0 && strategyLabels.length === 0) return [];

  const [dawnTargets, dayTargets] = await Promise.all([
    managedTargets(chainId, "dawn"),
    managedTargets(chainId, "day"),
  ]);

  const view = (name: string, kind: VaultView["kind"], contracts: Label[]): VaultView => ({
    name,
    kind,
    controlling: controlling(
      contracts.map((c) => c.address.toLowerCase()),
      dawnTargets,
      dayTargets,
    ),
    contracts,
  });

  const out: VaultView[] = [];
  for (const { parent, children } of groupByParent(vaultLabels)) {
    out.push(view(parent, "concrete", children));
  }
  for (const { parent, children } of groupByParent(strategyLabels)) {
    out.push(view(parent, "makina", children));
  }
  return out.sort((a, b) => a.name.localeCompare(b.name) || a.kind.localeCompare(b.kind));
}
