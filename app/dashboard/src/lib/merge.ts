// MERGE (main.md §3.3): join subgraph ACTUAL state with catalog name resolution -> RoleView[].
// State is presented as-is: only roles that exist on-chain, no reference model.
// All role views are AM-scoped: the same role id exists independently on the Dawn and Day AMs.
import type { Address, AmKind, HolderView, RoleView } from "@/model";
import { actor, actorName, managerFor, roleName, selectorName, shorten, targetInfo } from "@/lib/catalog";
import {
  fetchAllRoles,
  fetchRole,
  type SgMember,
  type SgRole,
  type SgRoleEvent,
} from "@/lib/subgraph";

function holderView(chainId: number, m: SgMember): HolderView {
  const address = m.account.id.toLowerCase() as Address;
  const a = actor(chainId, address);
  return {
    address,
    actor: a?.name ?? null,
    executionDelaySeconds: Number(m.executionDelay),
    pendingDeployment: a?.pendingDeployment,
    grantedAt: m.grantedAt ? Number(m.grantedAt) : null,
  };
}

export function toRoleView(chainId: number, am: AmKind, r: SgRole, history: SgRoleEvent[] = []): RoleView {
  const name = roleName(chainId, am, r.roleId);

  const holders = r.members
    .map((m) => holderView(chainId, m))
    .sort((a, b) => (a.actor ?? "z").localeCompare(b.actor ?? "z"));

  const config = {
    adminRole: r.adminRole,
    adminRoleName: roleName(chainId, am, r.adminRole),
    guardianRole: r.guardianRole,
    guardianRoleName: roleName(chainId, am, r.guardianRole),
    grantDelaySeconds: Number(r.grantDelay),
  };

  const capabilities = r.functions
    .map((f) => {
      const ti = targetInfo(chainId, f.target.address);
      return {
        target: f.target.address.toLowerCase() as Address,
        targetName: ti?.name ?? shorten(f.target.address),
        targetType: ti?.type ?? "unknown",
        selector: f.selector,
        fnName: selectorName(f.selector),
      };
    })
    .sort((a, b) => a.targetName.localeCompare(b.targetName) || a.fnName.localeCompare(b.fnName));

  const historyViews = history.map((e) => ({
    kind: e.kind,
    account: (e.account ? (e.account.id.toLowerCase() as Address) : null) as Address | null,
    actorName: e.account ? actorName(chainId, e.account.id) : null,
    oldValue: e.oldValue,
    newValue: e.newValue,
    timestamp: Number(e.timestamp),
    txHash: e.txHash,
  }));

  return { chainId, am, id: r.roleId, name, config, holders, capabilities, history: historyViews };
}

function sortRoles(views: RoleView[]): RoleView[] {
  return views.sort((a, b) => {
    if (a.holders.length !== b.holders.length) return b.holders.length - a.holders.length;
    return a.name.localeCompare(b.name);
  });
}

export async function buildRoleViews(chainId: number, am: AmKind): Promise<RoleView[]> {
  const mgr = managerFor(chainId, am);
  if (!mgr) return [];
  const roles = await fetchAllRoles(chainId, mgr.address);
  return sortRoles(roles.map((r) => toRoleView(chainId, am, r)));
}

export async function buildRoleView(chainId: number, am: AmKind, id: string): Promise<RoleView | null> {
  const mgr = managerFor(chainId, am);
  if (!mgr) return null;
  const { role, roleEvents } = await fetchRole(chainId, mgr.address, id);
  return role ? toRoleView(chainId, am, role, roleEvents) : null;
}
