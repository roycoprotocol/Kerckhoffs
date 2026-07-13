// MERGE (main.md §3.3): join subgraph ACTUAL + catalog EXPECTED -> RoleView[] (§6).
import type { Address, HolderView, RoleView } from "@/model";
import {
  actor,
  actorAddress,
  actorName,
  expectation,
  getCatalog,
  roleName,
  selectorName,
  shorten,
  targetInfo,
  type CatalogRole,
} from "@/lib/catalog";
import { computeRoleDrift, highestSeverity, severityRank } from "@/lib/drift";
import {
  fetchAllRoles,
  fetchRole,
  type SgMember,
  type SgRole,
  type SgRoleEvent,
} from "@/lib/subgraph";

function holderView(chainId: number, m: SgMember, expectedAddrs: Set<string>): HolderView {
  const address = m.account.id.toLowerCase() as Address;
  const a = actor(chainId, address);
  return {
    address,
    actor: a?.name ?? null,
    executionDelaySeconds: Number(m.executionDelay),
    expected: expectedAddrs.has(address),
    pendingDeployment: a?.pendingDeployment,
    grantedAt: m.grantedAt ? Number(m.grantedAt) : null,
  };
}

export function toRoleView(chainId: number, r: SgRole, history: SgRoleEvent[] = []): RoleView {
  const name = roleName(chainId, r.id);
  const exp = expectation(name);
  const expectedAddrs = new Set(
    (exp?.holders ?? []).map((h) => actorAddress(chainId, h.actor)).filter((x): x is string => !!x),
  );

  const holders = r.members
    .map((m) => holderView(chainId, m, expectedAddrs))
    .sort((a, b) => (a.actor ?? "z").localeCompare(b.actor ?? "z"));

  const config = {
    adminRole: r.adminRole,
    adminRoleName: roleName(chainId, r.adminRole),
    guardianRole: r.guardianRole,
    guardianRoleName: roleName(chainId, r.guardianRole),
    grantDelaySeconds: Number(r.grantDelay),
  };

  const capabilities = r.functions
    .map((f) => {
      const ti = targetInfo(chainId, f.target.id);
      return {
        target: f.target.id.toLowerCase() as Address,
        targetName: ti?.name ?? shorten(f.target.id),
        targetType: ti?.type ?? "unknown",
        selector: f.selector,
        fnName: selectorName(f.selector),
      };
    })
    .sort((a, b) => a.targetName.localeCompare(b.targetName) || a.fnName.localeCompare(b.fnName));

  const drift = computeRoleDrift({
    chainId,
    id: r.id,
    name,
    adminRoleName: config.adminRoleName,
    guardianRoleName: config.guardianRoleName,
    grantDelaySeconds: config.grantDelaySeconds,
    holders,
  });

  const historyViews = history.map((e) => ({
    kind: e.kind,
    account: (e.account ? (e.account.id.toLowerCase() as Address) : null) as Address | null,
    actorName: e.account ? actorName(chainId, e.account.id) : null,
    oldValue: e.oldValue,
    newValue: e.newValue,
    timestamp: Number(e.timestamp),
    txHash: e.txHash,
  }));

  return {
    chainId,
    id: r.id,
    name,
    description: exp?.description ?? "",
    config,
    expectedConfig: exp
      ? { adminRoleName: exp.admin, guardianRoleName: exp.guardian, grantDelaySeconds: exp.grantDelaySeconds }
      : undefined,
    holders,
    capabilities,
    history: historyViews,
    drift,
    presentOnChain: true,
  };
}

export function syntheticRoleView(chainId: number, cr: CatalogRole): RoleView {
  const exp = expectation(cr.name);
  return {
    chainId,
    id: cr.id,
    name: cr.name,
    description: exp?.description ?? "",
    config: {
      adminRole: "0",
      adminRoleName: "ADMIN_ROLE",
      guardianRole: "0",
      guardianRoleName: "ADMIN_ROLE",
      grantDelaySeconds: 0,
    },
    expectedConfig: exp
      ? { adminRoleName: exp.admin, guardianRoleName: exp.guardian, grantDelaySeconds: exp.grantDelaySeconds }
      : undefined,
    holders: [],
    capabilities: [],
    history: [],
    drift: [],
    presentOnChain: false,
  };
}

function sortRoles(views: RoleView[]): RoleView[] {
  return views.sort((a, b) => {
    const sa = highestSeverity(a.drift);
    const sb = highestSeverity(b.drift);
    if (sa !== sb) return (sa ? severityRank(sa) : 9) - (sb ? severityRank(sb) : 9);
    if (a.presentOnChain !== b.presentOnChain) return a.presentOnChain ? -1 : 1;
    if (a.holders.length !== b.holders.length) return b.holders.length - a.holders.length;
    return a.name.localeCompare(b.name);
  });
}

export async function buildRoleViews(chainId: number): Promise<RoleView[]> {
  const roles = await fetchAllRoles(chainId);
  const present = new Set(roles.map((r) => r.id));
  const views = roles.map((r) => toRoleView(chainId, r));
  for (const cr of getCatalog(chainId)?.roles ?? []) {
    if (!present.has(cr.id) && cr.name !== "PUBLIC_ROLE") views.push(syntheticRoleView(chainId, cr));
  }
  return sortRoles(views);
}

export async function buildRoleView(chainId: number, id: string): Promise<RoleView | null> {
  const { role, roleEvents } = await fetchRole(chainId, id);
  if (role) return toRoleView(chainId, role, roleEvents);
  const cr = getCatalog(chainId)?.roles.find((r) => r.id === id);
  return cr ? syntheticRoleView(chainId, cr) : null;
}
