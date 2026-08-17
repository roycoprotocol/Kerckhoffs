// Typed subgraph fetchers (ACTUAL side). Plain fetch so Next ISR revalidation works in Server
// Components. Endpoint per chain from chains.ts (local graph-node in dev, Goldsky in prod).
//
// One subgraph per chain indexes BOTH AccessManagers (Dawn + Day); every AM-scoped fetcher takes
// `am` — the lowercased manager address (from catalog managers[]) — and filters/keys with it.
// Entity ids in the subgraph are manager-prefixed ("{am}-{roleId}", "{am}-{target}", …); fetchers
// compose those ids and select the bare `roleId`/`address` fields so nothing downstream ever
// parses a composite id.
import { chainById } from "@/config/chains";

const REVALIDATE = 60; // seconds

export class NoSubgraphError extends Error {
  constructor(public chainId: number) {
    super(`No SUBGRAPH_URL configured for chain ${chainId}`);
  }
}

export function hasSubgraph(chainId: number): boolean {
  return !!chainById(chainId)?.subgraphUrl;
}

async function sg<T>(chainId: number, query: string, variables: Record<string, unknown> = {}): Promise<T> {
  const url = chainById(chainId)?.subgraphUrl;
  if (!url) throw new NoSubgraphError(chainId);
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
    next: { revalidate: REVALIDATE },
  });
  if (!res.ok) throw new Error(`subgraph ${chainId} HTTP ${res.status}`);
  const json = (await res.json()) as { data?: T; errors?: { message: string }[] };
  if (json.errors?.length) throw new Error(`subgraph ${chainId}: ${json.errors.map((e) => e.message).join("; ")}`);
  return json.data as T;
}

// ── raw response shapes (mirror app/subgraph/schema.graphql) ──────────────────

export interface SgMember {
  account: { id: string };
  executionDelay: string;
  active: boolean;
  grantedAt: string | null;
}
export interface SgFunction {
  id: string;
  selector: string;
  role: { roleId: string };
  target: { address: string };
}
export interface SgRole {
  id: string; // composite "{am}-{roleId}" — display/keying only, never parsed
  roleId: string; // bare uint64 decimal
  onChainLabel: string | null;
  adminRole: string;
  guardianRole: string;
  grantDelay: string;
  members: SgMember[];
  functions: SgFunction[];
}
export interface SgRoleEvent {
  kind: string;
  account: { id: string } | null;
  oldValue: string | null;
  newValue: string | null;
  timestamp: string;
  txHash: string;
}
export interface SgOperation {
  id: string;
  operationId: string;
  nonce: string;
  caller: string;
  target: string;
  data: string;
  schedule: string;
  status: "Scheduled" | "Executed" | "Canceled";
  scheduledAt: string;
}
export interface SgMeta {
  block: { number: number };
  hasIndexingErrors: boolean;
}

const ROLE_FIELDS = `
  id roleId onChainLabel adminRole guardianRole grantDelay
  members(first: 500, where: { active: true }) { account { id } executionDelay active grantedAt }
  functions(first: 500) { id selector role { roleId } target { address } }`;

export function fetchMeta(chainId: number) {
  return sg<{ _meta: SgMeta | null }>(chainId, `{ _meta { block { number } hasIndexingErrors } }`).then((d) => d._meta);
}

export function fetchAllRoles(chainId: number, am: string) {
  return sg<{ roles: SgRole[] }>(
    chainId,
    `query Roles($am: String!) { roles(first: 1000, orderBy: roleId, where: { manager: $am }) { ${ROLE_FIELDS} } }`,
    { am: am.toLowerCase() },
  ).then((d) => d.roles);
}

export function fetchRole(chainId: number, am: string, roleId: string) {
  const id = `${am.toLowerCase()}-${roleId}`;
  return sg<{ role: SgRole | null; roleEvents: SgRoleEvent[] }>(
    chainId,
    `query Role($id: ID!, $rid: String!) {
      role(id: $id) { ${ROLE_FIELDS} }
      roleEvents(first: 300, orderBy: timestamp, orderDirection: desc, where: { role: $rid }) {
        kind account { id } oldValue newValue timestamp txHash
      }
    }`,
    { id, rid: id },
  );
}

export function fetchAllTargetFunctions(chainId: number, am: string) {
  return sg<{ targetFunctions: SgFunction[] }>(
    chainId,
    `query Functions($am: String!) {
      targetFunctions(first: 1000, where: { manager: $am }) { id selector role { roleId } target { address } }
    }`,
    { am: am.toLowerCase() },
  ).then((d) => d.targetFunctions);
}

export function fetchPendingOperations(chainId: number, am: string) {
  return sg<{ operations: SgOperation[] }>(
    chainId,
    `query Operations($am: String!) {
      operations(first: 200, where: { manager: $am, status: Scheduled }, orderBy: scheduledAt, orderDirection: desc) {
        id operationId nonce caller target data schedule status scheduledAt
    } }`,
    { am: am.toLowerCase() },
  ).then((d) => d.operations);
}

// One operation with full provenance for the detail page.
export interface SgOpDetail extends SgOperation {
  executedAt: string | null;
  canceledAt: string | null;
  scheduleTx: string;
  executeTx: string | null;
  cancelTx: string | null;
  manager: { id: string; kind: string };
}
export function fetchOperation(chainId: number, id: string) {
  return sg<{ operation: SgOpDetail | null }>(
    chainId,
    `query Operation($id: ID!) {
      operation(id: $id) {
        id operationId nonce caller target data schedule status scheduledAt
        executedAt canceledAt scheduleTx executeTx cancelTx manager { id kind }
      }
    }`,
    { id },
  ).then((d) => d.operation);
}

export interface SgTarget {
  id: string;
  address: string;
  closed: boolean;
  adminDelay: string;
  everConfigured: boolean;
  functions: { selector: string; role: { roleId: string } }[];
}
export function fetchTarget(chainId: number, am: string, address: string) {
  return sg<{ targetContract: SgTarget | null }>(
    chainId,
    `query Target($id: ID!) {
      targetContract(id: $id) {
        id address closed adminDelay everConfigured functions(first: 500) { selector role { roleId } }
      }
    }`,
    { id: `${am.toLowerCase()}-${address.toLowerCase()}` },
  ).then((d) => d.targetContract);
}

// All target addresses registered on a manager — used to derive which AM controls a vault.
export function fetchManagedTargetAddresses(chainId: number, am: string) {
  return sg<{ targetContracts: { address: string }[] }>(
    chainId,
    `query ManagedTargets($am: String!) {
      targetContracts(first: 1000, where: { manager: $am }) { address }
    }`,
    { am: am.toLowerCase() },
  ).then((d) => new Set(d.targetContracts.map((t) => t.address.toLowerCase())));
}

export interface SgAccountRole {
  role: { roleId: string; manager: { id: string; kind: string } };
  executionDelay: string;
  active: boolean;
}
export interface SgAccount {
  id: string;
  roles: SgAccountRole[];
}
export function fetchAccount(chainId: number, address: string) {
  return sg<{ account: SgAccount | null }>(
    chainId,
    `query Account($id: ID!) {
      account(id: $id) {
        id roles(where: { active: true }) { role { roleId manager { id kind } } executionDelay active }
      }
    }`,
    { id: address.toLowerCase() },
  ).then((d) => d.account);
}

// ── Markets (dynamic enumeration: Dawn MarketDeployed + Day MarketDeploymentCompleted) ────

export interface SgMarket {
  id: string;
  kind: "dawn" | "day";
  factory: string;
  template: string | null;
  deployer: string | null;
  seniorTranche: string;
  juniorTranche: string;
  liquidityProviderTranche: string;
  kernel: string;
  accountant: string;
  ydm: string;
  lptYdm: string;
  seniorTrancheName: string | null;
  seniorTrancheSymbol: string | null;
  timestamp: string;
  txHash: string;
}
export function fetchMarkets(chainId: number, kind: "dawn" | "day") {
  return sg<{ markets: SgMarket[] }>(
    chainId,
    `query Markets($kind: String!) {
      markets(first: 500, orderBy: timestamp, orderDirection: desc, where: { kind: $kind }) {
        id kind factory template deployer seniorTranche juniorTranche liquidityProviderTranche kernel accountant ydm lptYdm
        seniorTrancheName seniorTrancheSymbol timestamp txHash
    } }`,
    { kind },
  ).then((d) => d.markets);
}

// ── Overview page: full operation history + latest config-change timestamp ────

export interface SgOpFull extends SgOperation {
  executedAt: string | null;
  manager: { id: string };
}
export function fetchAllOperations(chainId: number) {
  return sg<{ operations: SgOpFull[] }>(
    chainId,
    `{ operations(first: 1000, orderBy: scheduledAt, orderDirection: desc) {
        id operationId nonce caller target data schedule status scheduledAt executedAt manager { id }
    } }`,
  ).then((d) => d.operations);
}

export function fetchLatestConfigChange(chainId: number, ams: string[]) {
  return sg<{ roleEvents: { timestamp: string }[] }>(
    chainId,
    `query Latest($ams: [String!]!) {
      roleEvents(first: 1, orderBy: timestamp, orderDirection: desc, where: { manager_in: $ams }) { timestamp }
    }`,
    { ams: ams.map((a) => a.toLowerCase()) },
  ).then((d) => (d.roleEvents[0] ? Number(d.roleEvents[0].timestamp) : null));
}
