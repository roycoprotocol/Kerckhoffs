// Loads the generated catalog and exposes name-resolution lookups (role names, actor/target
// labels). Static JSON imports so everything is bundled (works on Vercel with no fs/cwd concerns).
//
// Catalog v2: each chain carries a `managers[]` array — the Dawn RoycoFactory plus, on chains
// where Royco Day is deployed, the Day RoycoAccessManager. Role ids collide across the two AMs
// (same keccak tag derivation), so every role lookup is keyed by (chainId, AmKind).
import type { Address, AmKind, RoleId } from "@/model";

import catalog1 from "@/metadata/catalog.1.json";
import catalog43114 from "@/metadata/catalog.43114.json";
import catalog42161 from "@/metadata/catalog.42161.json";
import catalog8453 from "@/metadata/catalog.8453.json";
import selectorsRaw from "@/metadata/selectors.json";
import verifiedRaw from "@/metadata/verified-markets.json";

export interface CatalogRole {
  id: string;
  name: string;
}
export interface CatalogActor {
  address: string;
  name: string;
  category: string;
  pendingDeployment: boolean;
}
export interface CatalogTarget {
  address: string;
  name: string;
  type: string;
  category: string;
  parent: string;
}
export interface CatalogMakina {
  vault: string;
  caliber: string;
  machine: string;
  expectedRiskManager: string;
  expectedRiskManagerTimelock: string;
}
export interface CatalogManager {
  kind: AmKind;
  address: string;
  name: string;
  expiration: number;
  minSetback: number;
  roles: CatalogRole[];
  actors: CatalogActor[];
  targets: CatalogTarget[];
}
export interface Catalog {
  chainId: number;
  chainName: string;
  generatedAtBlock: number;
  /** @deprecated alias of managers[kind=dawn].address — use managersFor() */
  factory: string;
  /** @deprecated alias of managers[kind=dawn].expiration */
  expiration: number;
  /** @deprecated alias of managers[kind=dawn].minSetback */
  minSetback: number;
  managers: CatalogManager[];
  makinaSlots: CatalogMakina[];
}

const CATALOGS: Record<number, Catalog> = {
  1: catalog1 as unknown as Catalog,
  43114: catalog43114 as unknown as Catalog,
  42161: catalog42161 as unknown as Catalog,
  8453: catalog8453 as unknown as Catalog,
};

const SELECTORS = selectorsRaw as Record<string, { name: string; signature: string }>;

// ── managers ──────────────────────────────────────────────────────────────────

export function getCatalog(chainId: number): Catalog | undefined {
  return CATALOGS[chainId];
}

export function managersFor(chainId: number): CatalogManager[] {
  return CATALOGS[chainId]?.managers ?? [];
}

export function managerFor(chainId: number, kind: AmKind): CatalogManager | undefined {
  return managersFor(chainId).find((m) => m.kind === kind);
}

export function amKindsFor(chainId: number): AmKind[] {
  return managersFor(chainId).map((m) => m.kind);
}

export function managerKindByAddress(chainId: number, address: string): AmKind | undefined {
  const a = address.toLowerCase();
  return managersFor(chainId).find((m) => m.address.toLowerCase() === a)?.kind;
}

// The CURRENT factory for an AM kind — Dawn's factory IS the Dawn AM; Day's factory is the
// catalog day target named "dayFactory". Markets from retired factories (pre-production Day
// deployment) remain in grafted subgraph stores and are filtered against this address.
export function factoryFor(chainId: number, kind: AmKind): string | undefined {
  const mgr = managerFor(chainId, kind);
  if (!mgr) return undefined;
  if (kind === "dawn") return mgr.address.toLowerCase();
  return mgr.targets.find((t) => t.name === "dayFactory")?.address.toLowerCase();
}

export function amLabel(kind: AmKind): string {
  return kind === "dawn" ? "Dawn AM" : "Day AM";
}

export function parseAmKind(s: string): AmKind | null {
  return s === "dawn" || s === "day" ? s : null;
}

// ── memoized lookup maps ──────────────────────────────────────────────────────

// Per-(chain, manager) role names; per-chain merged actor/target maps for labeling. Targets keep
// the manager kind they came from so labels can show the controlling AM where statically known.
interface ManagerMaps {
  roleNameById: Map<string, string>;
}
interface ChainMaps {
  byKind: Map<AmKind, ManagerMaps>;
  actorByAddress: Map<string, CatalogActor>;
  targetByAddress: Map<string, CatalogTarget & { manager: AmKind }>;
}
const _maps = new Map<number, ChainMaps>();

function maps(chainId: number): ChainMaps {
  let m = _maps.get(chainId);
  if (m) return m;
  const managers = managersFor(chainId);
  const byKind = new Map<AmKind, ManagerMaps>();
  const actorByAddress = new Map<string, CatalogActor>();
  const targetByAddress = new Map<string, CatalogTarget & { manager: AmKind }>();
  for (const mgr of managers) {
    byKind.set(mgr.kind, {
      roleNameById: new Map(mgr.roles.map((r) => [r.id, r.name])),
    });
    // First writer wins (dawn is listed first): shared actors keep their dawn entry, and a target
    // known to both managers keeps its dawn categorization.
    for (const a of mgr.actors) {
      const k = a.address.toLowerCase();
      if (!actorByAddress.has(k)) actorByAddress.set(k, a);
    }
    for (const t of mgr.targets) {
      const k = t.address.toLowerCase();
      if (!targetByAddress.has(k)) targetByAddress.set(k, { ...t, manager: mgr.kind });
    }
  }
  m = { byKind, actorByAddress, targetByAddress };
  _maps.set(chainId, m);
  return m;
}

function managerMaps(chainId: number, am: AmKind): ManagerMaps | undefined {
  return maps(chainId).byKind.get(am);
}

// ── roles ─────────────────────────────────────────────────────────────────────

export function roleName(chainId: number, am: AmKind, id: RoleId): string {
  if (id === "0") return "ADMIN_ROLE";
  return managerMaps(chainId, am)?.roleNameById.get(id) ?? `role_${id}`;
}
export function isKnownRole(chainId: number, am: AmKind, id: RoleId): boolean {
  return id === "0" || (managerMaps(chainId, am)?.roleNameById.has(id) ?? false);
}
export function rolesFor(chainId: number, am: AmKind): CatalogRole[] {
  return managerFor(chainId, am)?.roles ?? [];
}

// ── actors / targets (chain-scoped: addresses are shared across managers) ─────

// Display aliases for multisig actor tags — the catalog keeps the canonical on-chain-facing
// names (metadata keys, docs); the UI shows these short forms.
const ACTOR_DISPLAY: Record<string, string> = {
  WAY: "OPS",
  FNDN_VETO: "VETO",
  WAY_PAUSE: "PAUSE",
  AUTO: "SP",
};
export function actorDisplayName(name: string): string {
  // Alias if mapped; otherwise split camelCase (DayEntryPoint → Day Entry Point) — actor names
  // are never function names, so the no-camelCase display rule applies.
  return ACTOR_DISPLAY[name] ?? name.replace(/([a-z0-9])([A-Z])/g, "$1 $2");
}

export function actorName(chainId: number, address: string): string | null {
  const n = maps(chainId).actorByAddress.get(address.toLowerCase())?.name;
  return n ? actorDisplayName(n) : null;
}
export function actor(chainId: number, address: string): CatalogActor | undefined {
  return maps(chainId).actorByAddress.get(address.toLowerCase());
}

export function targetInfo(chainId: number, address: string): (CatalogTarget & { manager: AmKind }) | undefined {
  return maps(chainId).targetByAddress.get(address.toLowerCase());
}
export function targetName(chainId: number, address: string): string {
  return targetInfo(chainId, address)?.name ?? shorten(address);
}

// Kernel address of a catalog market, by its parent (market) name — lets a component chip link
// to the market's detail page.
export function kernelForParent(chainId: number, parent: string): string | undefined {
  for (const mgr of managersFor(chainId)) {
    const k = mgr.targets.find((t) => t.parent === parent && t.type === "kernel");
    if (k) return k.address.toLowerCase();
  }
  return undefined;
}

// ── verified markets (hand-maintained allowlist of kernel addresses) ──────────

const VERIFIED = verifiedRaw as Record<string, string[]>;

export function isVerifiedMarket(chainId: number, kernel: string): boolean {
  return (VERIFIED[String(chainId)] ?? []).includes(kernel.toLowerCase());
}

export function selectorName(selector: string): string {
  return SELECTORS[selector.toLowerCase()]?.name ?? selector;
}
export function selectorSignature(selector: string): string | undefined {
  return SELECTORS[selector.toLowerCase()]?.signature;
}

export function shorten(addr: string): string {
  return addr.length > 12 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr;
}
