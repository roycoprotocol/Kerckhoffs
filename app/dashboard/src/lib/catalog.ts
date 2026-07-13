// Loads the generated canonical catalog (EXPECTED side) and exposes name-resolution + expectation
// lookups. Static JSON imports so everything is bundled (works on Vercel with no fs/cwd concerns).
import type { Address, RoleId } from "@/model";

import catalog1 from "@/metadata/catalog.1.json";
import catalog43114 from "@/metadata/catalog.43114.json";
import catalog42161 from "@/metadata/catalog.42161.json";
import catalog8453 from "@/metadata/catalog.8453.json";
import descriptionsRaw from "@/metadata/roles.descriptions.json";
import selectorsRaw from "@/metadata/selectors.json";

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
export interface Catalog {
  chainId: number;
  chainName: string;
  factory: string;
  generatedAtBlock: number;
  expiration: number;
  minSetback: number;
  roles: CatalogRole[];
  actors: CatalogActor[];
  targets: CatalogTarget[];
  makinaSlots: CatalogMakina[];
}

export interface ExpectedHolder {
  actor: string;
  executionDelaySeconds: number;
}
export interface RoleExpectation {
  description: string;
  grantDelaySeconds: number;
  admin: string;
  guardian: string;
  holders: ExpectedHolder[];
}

const CATALOGS: Record<number, Catalog> = {
  1: catalog1 as Catalog,
  43114: catalog43114 as Catalog,
  42161: catalog42161 as Catalog,
  8453: catalog8453 as Catalog,
};

const DESCRIPTIONS = descriptionsRaw as Record<string, RoleExpectation | string>;
const SELECTORS = selectorsRaw as Record<string, { name: string; signature: string }>;

// Per-chain memoized lookup maps.
interface ChainMaps {
  roleNameById: Map<string, string>;
  actorByAddress: Map<string, CatalogActor>;
  targetByAddress: Map<string, CatalogTarget>;
}
const _maps = new Map<number, ChainMaps>();

function maps(chainId: number): ChainMaps {
  let m = _maps.get(chainId);
  if (m) return m;
  const cat = CATALOGS[chainId];
  m = {
    roleNameById: new Map((cat?.roles ?? []).map((r) => [r.id, r.name])),
    actorByAddress: new Map((cat?.actors ?? []).map((a) => [a.address.toLowerCase(), a])),
    targetByAddress: new Map((cat?.targets ?? []).map((t) => [t.address.toLowerCase(), t])),
  };
  _maps.set(chainId, m);
  return m;
}

export function getCatalog(chainId: number): Catalog | undefined {
  return CATALOGS[chainId];
}

export function roleName(chainId: number, id: RoleId): string {
  if (id === "0") return "ADMIN_ROLE";
  return maps(chainId).roleNameById.get(id) ?? `role_${id}`;
}
export function isKnownRole(chainId: number, id: RoleId): boolean {
  return id === "0" || maps(chainId).roleNameById.has(id);
}

export function actorName(chainId: number, address: string): string | null {
  return maps(chainId).actorByAddress.get(address.toLowerCase())?.name ?? null;
}
export function actor(chainId: number, address: string): CatalogActor | undefined {
  return maps(chainId).actorByAddress.get(address.toLowerCase());
}

export function targetInfo(chainId: number, address: string): CatalogTarget | undefined {
  return maps(chainId).targetByAddress.get(address.toLowerCase());
}
export function targetName(chainId: number, address: string): string {
  return targetInfo(chainId, address)?.name ?? shorten(address);
}

export function selectorName(selector: string): string {
  return SELECTORS[selector.toLowerCase()]?.name ?? selector;
}

export function expectation(roleName: string): RoleExpectation | undefined {
  const e = DESCRIPTIONS[roleName];
  return typeof e === "object" ? e : undefined;
}

// Resolve an actor NAME to its address on a chain (for expected-holder comparison).
export function actorAddress(chainId: number, name: string): string | undefined {
  return CATALOGS[chainId]?.actors.find((a) => a.name === name)?.address.toLowerCase();
}

export function shorten(addr: string): string {
  return addr.length > 12 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr;
}
