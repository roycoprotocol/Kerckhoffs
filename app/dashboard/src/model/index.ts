// View-models (main.md §6): live on-chain state (subgraph) + catalog name resolution + Makina RPC.
// State is presented AS-IS — there is no reference model or drift comparison.

export type Address = `0x${string}`;
export type RoleId = string; // uint64 decimal string

// Which AccessManager an item belongs to: the Dawn RoycoFactory or the Day RoycoAccessManager.
// Role ids collide across the two AMs, so every role-scoped lookup carries an AmKind.
export type AmKind = "dawn" | "day";

export interface HolderView {
  address: Address;
  actor: string | null;
  executionDelaySeconds: number;
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
  am: AmKind;
  id: RoleId;
  name: string;
  config: RoleConfig;
  holders: HolderView[];
  capabilities: CapabilityView[];
  history: RoleEventView[];
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
}

export interface AccountView {
  address: Address;
  actor: string | null;
  roles: { role: RoleView; executionDelaySeconds: number }[];
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
  manager?: AmKind; // controlling AM, where statically known (catalog target hint)
  kernel?: Address; // for market components: the market's kernel (detail-page link target)
  tags: string[];
  pendingDeployment?: boolean;
  isExternal: boolean; // not in the registries/catalog
  known: boolean; // has a real label (not just a shortened address)
}

// ── Day markets (subgraph Market entities) & vaults ───────────────────────────

export interface MarketView {
  kernel: Address;
  name: string; // kernel label if known, else shortened kernel address
  deployer: Address;
  template: Address;
  timestamp: number;
  txHash: string;
  components: { componentType: string; address: Address; name: string }[];
}

export type ControllingAm = AmKind | "migrating" | "unknown";

export interface VaultView {
  name: string; // parent name: srRoyUSDC, roywstETH
  kind: "concrete" | "makina";
  controlling: ControllingAm;
  contracts: Label[];
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
