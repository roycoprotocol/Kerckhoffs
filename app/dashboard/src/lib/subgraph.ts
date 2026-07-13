// Typed subgraph fetchers (ACTUAL side). Plain fetch so Next ISR revalidation works in Server
// Components. Endpoint per chain from chains.ts (local graph-node in dev, Goldsky in prod).
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
  role: { id: string };
  target: { id: string };
}
export interface SgRole {
  id: string;
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
  id onChainLabel adminRole guardianRole grantDelay
  members(first: 500, where: { active: true }) { account { id } executionDelay active grantedAt }
  functions(first: 500) { id selector role { id } target { id } }`;

export function fetchMeta(chainId: number) {
  return sg<{ _meta: SgMeta | null }>(chainId, `{ _meta { block { number } hasIndexingErrors } }`).then((d) => d._meta);
}

export function fetchAllRoles(chainId: number) {
  return sg<{ roles: SgRole[] }>(chainId, `{ roles(first: 1000, orderBy: id) { ${ROLE_FIELDS} } }`).then((d) => d.roles);
}

export function fetchRole(chainId: number, id: string) {
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

export function fetchAllTargetFunctions(chainId: number) {
  return sg<{ targetFunctions: SgFunction[] }>(
    chainId,
    `{ targetFunctions(first: 1000) { id selector role { id } target { id } } }`,
  ).then((d) => d.targetFunctions);
}

export function fetchPendingOperations(chainId: number) {
  return sg<{ operations: SgOperation[] }>(
    chainId,
    `{ operations(first: 200, where: { status: Scheduled }, orderBy: scheduledAt, orderDirection: desc) {
        id operationId nonce caller target data schedule status scheduledAt
    } }`,
  ).then((d) => d.operations);
}

export interface SgTarget {
  id: string;
  closed: boolean;
  adminDelay: string;
  functions: { selector: string; role: { id: string } }[];
}
export function fetchTarget(chainId: number, address: string) {
  return sg<{ targetContract: SgTarget | null }>(
    chainId,
    `query Target($id: ID!) {
      targetContract(id: $id) { id closed adminDelay functions(first: 500) { selector role { id } } }
    }`,
    { id: address.toLowerCase() },
  ).then((d) => d.targetContract);
}

export interface SgAccount {
  id: string;
  roles: { role: { id: string }; executionDelay: string; active: boolean }[];
}
export function fetchAccount(chainId: number, address: string) {
  return sg<{ account: SgAccount | null }>(
    chainId,
    `query Account($id: ID!) {
      account(id: $id) { id roles(where: { active: true }) { role { id } executionDelay active } }
    }`,
    { id: address.toLowerCase() },
  ).then((d) => d.account);
}
