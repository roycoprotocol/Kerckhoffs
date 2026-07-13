// MERGED view-models (main.md §6): ACTUAL (subgraph) ⊕ EXPECTED (catalog) + Makina RPC.

export type Address = `0x${string}`;
export type RoleId = string; // uint64 decimal string
export type Severity = "HIGH" | "MEDIUM" | "LOW";

export interface Drift {
  field: string;
  expected: string;
  actual: string;
  severity: Severity;
  note?: string;
}

export interface HolderView {
  address: Address;
  actor: string | null;
  executionDelaySeconds: number;
  expected: boolean; // present in the canonical expected-holder set
  pendingDeployment?: boolean;
  grantedAt?: number | null;
}

export interface CapabilityView {
  target: Address;
  targetName: string;
  targetType: string;
  selector: string;
  fnName: string;
}

export interface RoleEventView {
  kind: string;
  account?: Address | null;
  actorName?: string | null;
  oldValue?: string | null;
  newValue?: string | null;
  timestamp: number;
  txHash: string;
}

export interface RoleConfig {
  adminRole: RoleId;
  adminRoleName: string;
  guardianRole: RoleId;
  guardianRoleName: string;
  grantDelaySeconds: number;
}

export interface RoleView {
  chainId: number;
  id: RoleId;
  name: string;
  description: string;
  config: RoleConfig;
  expectedConfig?: Partial<RoleConfig>;
  holders: HolderView[];
  capabilities: CapabilityView[];
  history: RoleEventView[];
  drift: Drift[];
  presentOnChain: boolean; // false = catalog-known but never configured on-chain
}

export interface OperationView {
  id: string;
  operationId: string;
  nonce: number;
  caller: Address;
  callerName: string | null;
  target: Address;
  targetName: string | null;
  data: string;
  scheduleSeconds: number;
  status: "Scheduled" | "Executed" | "Canceled";
  executableNow: boolean;
  expired: boolean;
}

export interface MakinaSlotView {
  vault: string;
  slot: "riskManager" | "riskManagerTimelock";
  actual: Address | null;
  expected: Address;
  drift?: Drift;
}

export interface AccountView {
  address: Address;
  actor: string | null;
  roles: { role: RoleView; executionDelaySeconds: number }[];
}

export interface ChainRoleCell {
  chainId: number;
  slug: string;
  chainName: string;
  present: boolean;
  holderLabels: string[];
  grantDelaySeconds: number;
  guardianRoleName: string;
  divergent: boolean;
}
export interface ChainRoleRow {
  id: RoleId;
  name: string;
  cells: ChainRoleCell[];
}

// ── Address labeling / categorization ─────────────────────────────────────────

export type Category =
  | "multisig"
  | "market"
  | "vault"
  | "strategy"
  | "entrypoint"
  | "syncer"
  | "factory"
  | "agent"
  | "lp"
  | "protocol"
  | "external";

export interface Label {
  address: Address;
  name: string; // human name (or shortened address if unknown)
  category: Category;
  subtype?: string; // fine-grained: kernel|accountant|seniorTranche|juniorTranche|caliber|machine…
  parent?: string; // market or vault name, for hierarchy
  tags: string[];
  pendingDeployment?: boolean;
  isExternal: boolean; // not in the registries/catalog
  known: boolean; // has a real label (not just a shortened address)
}

// A directory entry, optionally with hierarchical children (market → contracts).
export interface DirectoryEntry {
  label: Label;
  children?: Label[];
}
export interface DirectoryGroup {
  category: Category;
  title: string;
  entries: DirectoryEntry[];
}
