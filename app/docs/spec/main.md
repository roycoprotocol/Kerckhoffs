# Royco Access-Control Dashboard + Subgraph — Main Specification

Onchain security command center for Royco's access-control surface: a **Goldsky-hosted subgraph per
chain** that indexes the access-control events, plus a **Next.js dashboard** that merges the
subgraph (live + historical on-chain truth) with a **generated canonical catalog** (the expected
model) and a few **live RPC reads** (Makina address-slots). Everything lives under `app/`.

Companion doc: [`subgraph.md`](./subgraph.md) — the executable build/deploy/test plan for the
subgraph component.

## Context

Today the "who can do what" picture of the Royco protocol lives in three human-maintained markdown
files (`docs/roles/{assignments,auth,diagram}.md`) plus a console-only Foundry dumper
(`src/access/AccessManagerDumper.sol`). There is no machine-readable, live view of on-chain
access-control state and no history of grants/revocations — OZ `AccessManager` has no on-chain
enumeration, so the dumper reads a point-in-time snapshot by iterating hardcoded lists.

Confirmed scope: cover OZ AccessManager (RoycoFactory, `uint64` roles) + native OZ AccessControl on
Concrete vaults (`bytes32` roles) + Makina governance slots; hosted on Goldsky; first-class
features = timelock-op tracking, role→function capability map, market enumeration from factory events, multi-chain diff. (Drift detection against a reference model was removed 2026-08 — the dashboard presents on-chain state as-is; the hand-authored expectations files remain under app/metadata/ as documentation only.)

This document specifies the **flows, shared data structures, and models**.

---

## 1. The single conceptual model

There is **one** domain model, projected into three representations. Define it once; every layer
conforms.

```
                       ┌──────────────────────────┐
                       │  Conceptual domain model  │
                       │  (§1 entities below)      │
                       └──────────────────────────┘
                    /              |               \
      GraphQL schema      Canonical catalog     Frontend view-models
      (§4, ACTUAL)        JSON (§5, EXPECTED)    (§6, MERGED = ACTUAL⊕EXPECTED)
      from on-chain       from Solidity+docs     drift = diff(ACTUAL, EXPECTED)
      events              via forge script
```

### Core entities (chain-scoped unless noted)

| Entity | Identity | Meaning |
|---|---|---|
| **Chain** | `chainId` | One of {1, 43114, 42161, 8453}. Every chain has the Dawn AccessManager (the RoycoFactory); all but Avalanche additionally have the Royco Day AccessManager. |
| **Manager** | `address` (lowercased AM address) | An AccessManager: `kind` ("dawn" \| "day"), `expiration`, `minSetback`, `address`. One row per AM per chain. |
| **Actor** | `address` | A known principal (FNDN, WAY, WAY_PAUSE, FNDN_VETO, DIAL, EntryPoint, Securitize). Catalog-only labels; joined to on-chain `Account`. |
| **Role** | `(manager, roleId)` | An AM role. Config: `adminRole`, `guardianRole`, `grantDelay`, optional on-chain `label`. Role ids collide across the Dawn and Day AMs (same keccak tags), so every role is manager-scoped. |
| **RoleMember** | `(manager, roleId, account)` | A current holder: `executionDelay`, `active`, grant/revoke timestamps. |
| **RoleEvent** | `(txHash, logIndex)` | Immutable historical record of any role state change (carries `manager`). The timeline. |
| **TargetContract** | `(manager, address)` | A contract gated by an AM: `closed`, `adminDelay`, its functions. The same contract may be gated by both AMs mid-migration. |
| **TargetFunction** | `(manager, target, selector)` | A `(target, selector)` → `roleId` binding: the capability edge. |
| **Operation** | `(manager, operationId, nonce)` | A scheduled timelocked op: `caller`, `target`, `data`, `schedule`, lifecycle status. |
| **Market** | `kernel` (address) | A Royco Day market: the 5 proxies + YDMs deployed atomically through the Day factory (`MarketDeploymentCompleted`). Dynamic enumeration — never a static registry. |
| **Account** | `address` | Any address that has ever held a role; derived roll-up of its memberships. |
| **NativeRole** | `(vault, roleHash)` | A native OZ AccessControl role on a Concrete vault (`bytes32`). |
| **NativeRoleMember** | `(vault, roleHash, account)` | Holder of a native role. |
| **NativeRoleEvent** | `(txHash, logIndex)` | History for native roles. |
| **MakinaSlot** | `(vault, slotName)` | Off-subgraph: `riskManager` / `riskManagerTimelock` / `instrRootGuardian` address(es), read live via RPC. |

### Identity & keying conventions (used everywhere — subgraph IDs, catalog keys, frontend maps)

- `chainId`: number.
- `address`: **lowercased** `0x` + 40 hex. All addresses normalized on ingest (subgraph
  `Bytes.toHexString().toLowerCase()`; frontend `getAddress()` only for display).
- `roleId`: uint64 rendered as a **decimal string** (GraphQL IDs are strings; avoids BigInt/JS
  precision loss). Catalog also carries the `0x…` hex form and the keccak `tag` for cross-checking.
- `selector`: `0x` + 8 hex (`bytes4`).
- `manager`: the lowercased AM address. Every AM-scoped id below is prefixed with it — the Dawn
  and Day AMs derive role ids from the same keccak tag strings, so unprefixed ids would silently
  merge the two AMs.
- `Role.id = "{manager}-{roleId}"` (plus a bare `roleId` field — consumers never parse composite ids).
- `RoleMember.id = "{manager}-{roleId}-{account}"`.
- `RoleEvent.id / NativeRoleEvent.id = "{txHash}-{logIndex}"` (globally unique, ordering-stable).
- `TargetContract.id = "{manager}-{address}"`; `TargetFunction.id = "{manager}-{target}-{selector}"`.
- `Operation.id = "{manager}-{operationId}-{nonce}"` (`operationId = hashOperation(caller,target,data)`
  is hashed without the AM address, hence the prefix).
- `NativeRole.id = "{vault}-{roleHash}"`; `NativeRoleMember.id = "{vault}-{roleHash}-{account}"`.
- `Market.id = kernel` (lowercased); `MarketComponent.id = "{kernel}-{componentType}"` (never the
  component address — YDM singletons are shared across markets).
- Cross-chain identity: the frontend keys on `(chainId, AmKind, roleId)`. Roles are the **same
  numeric id across chains** (keccak of the same tag), which is exactly what makes the multi-chain
  diff a simple group-by `roleId` — one matrix per AM kind.

---

## 2. Name resolution model (the uint64 → human bridge)

The single most load-bearing design fact: **the chain speaks in opaque `uint64` role ids and raw
`bytes4` selectors.** On-chain `RoleLabel`/`labelRole` is very likely never emitted (the migration
scripts don't call it). So:

- The **subgraph stores raw ids** and, if a `RoleLabel` event ever appears, records `onChainLabel`.
- The **catalog is the authoritative name source**, computed from Solidity: for every role tag in
  `src/registry/Roles.sol`, `roleId = uint64(uint256(keccak256(abi.encode(tag))))`. The exporter
  emits `{ id, hexId, tag, name }`. The two built-ins are literals: `ADMIN_ROLE = 0`,
  `PUBLIC_ROLE = 2^64-1`.
- **Selectors → function names**: computed from the imported protocol interfaces (the same ones
  `src/access/Selectors.sol` and `AccessManagerDumper` already import) → `{ selector, functionName,
  contractType }`.
- **Addresses → labels**: from `src/registry/{Multisigs,Markets,Vaults,Strategies,EntryPoints}.sol`.

Frontend builds three lookup maps from the catalog at load: `roleName(roleId)`,
`fnName(target|type, selector)`, `actorName(address)`. **No raw id/hash/calldata is ever rendered
unlabeled**; an id absent from the catalog renders as `Unknown role {id}` and is itself a drift
signal ("a role exists on-chain that the canonical model doesn't know about").

---

## 3. Flows

### 3.1 Catalog generation flow (build-time, Solidity → JSON)

`forge script script/ExportCatalog.s.sol --sig "run()"` — inherits `AccessManagerDumper` (which
already inherits every registry). Per chain in `{1, 43114, 42161, 8453}`:

1. `vm.createSelectFork(rpc)` (needed because market sub-addresses are derived from the kernel at
   runtime — `Markets.getMarketAddresses`, `Markets.sol:130-138`).
2. Build `roles[]` from `_allRoles()` (`AccessManagerDumper.sol:304-377`) → `{id, hexId, tag,
   name, delayTier}`; join the **expectations** map (holders/admin/guardian/delay) and
   **descriptions** from the machine-readable companion (§5.2).
3. Build `actors[]` from `Multisigs.sol` (flag `WAY_PAUSE`/`FNDN_VETO` `pendingDeployment=true` —
   they're `0xDEAD000x` sentinels, `Multisigs.sol:45-54`).
4. Build `targets[]` by walking every registry (kernels+derived accountant/tranches, syncer,
   entrypoint, vaults, strategies, calibers, machines) → `{address, name, type, chainId}`.
5. Build `capabilities[]` by walking the same (target, selector) pairs the dumper iterates
   (`Selectors.sol` groups + the single selectors in `AccessManagerDumper._dump*Targets`) plus the
   `auth.md` bindings → `{roleId, target, selector, functionName}`.
6. `vm.writeJson` → `app/metadata/catalog.<chainId>.json` (mirror the serialize pattern in
   `SafeBatchUtils.sol:121-155`; note: write under `app/metadata/`, NOT gitignored `output/`).

Output is deterministic and committed; it is the EXPECTED side of drift.

### 3.2 Subgraph indexing flows (on-chain events → entities)

One handler per event. All handlers are idempotent w.r.t. re-org (store-upsert by deterministic id)
and always append an immutable `RoleEvent`. Pseudocode for the load-bearing ones:

**`handleRoleGranted(roleId, account, delay, since, newMember)`** — note the dual semantics of
`since`/`newMember` (`IAccessManager.sol:37-39`): `newMember=true` ⇒ brand-new membership starting
at `since`; `newMember=false` ⇒ an execution-delay change taking effect at `since`.
```
role = Role.loadOrCreate(roleId)                 // create with defaults if first sighting
m = RoleMember.loadOrCreate(roleId, account)
m.active = true
m.executionDelay = delay
if newMember: m.grantedAt = block.timestamp; m.grantTx = tx.hash
else:         m.pendingDelayEffective = since    // delay update scheduled/effective at `since`
m.save()
RoleEvent.append(kind = newMember ? Granted : ExecutionDelayChanged,
                 role, account, newValue = delay, since, block, tx)
Account.loadOrCreate(account)                     // for the accounts view
```

**`handleRoleRevoked(roleId, account)`** → `m.active=false; m.revokedAt=ts; m.executionDelay=0`;
append `RoleEvent(Revoked)`. (Keep the row for history; `active=false` filters current holders.)

**`handleRoleAdminChanged` / `handleRoleGuardianChanged` / `handleRoleGrantDelayChanged`** → set the
Role field, append a `RoleEvent` carrying old→new. (Load old value before overwrite for the diff.)

**`handleTargetFunctionRoleUpdated(target, selector, roleId)`** — remember `selector` is **NOT
indexed** (it's in data): upsert `TargetFunction("{target}-{selector}")` with `role=roleId`,
`updatedAt`, `tx`; ensure `TargetContract(target)` exists. `roleId == 0` (ADMIN_ROLE) means "falls
back to admin"; `roleId == 2^64-1` (PUBLIC_ROLE) means "open".

**`handleTargetAdminDelayUpdated` / `handleTargetClosed`** → set `TargetContract` fields.

**Operation lifecycle** (powers the pending-timelock view):
```
handleOperationScheduled(id,nonce,schedule,caller,target,data):
    op = Operation.create(id); op.nonce=nonce; op.caller; op.target; op.data
    op.schedule = schedule            // unix ts when it becomes executable
    op.status = "Scheduled"; op.scheduledAt = ts; op.scheduleTx = tx; op.save()
handleOperationExecuted(id,nonce): op=load(id); op.status="Executed"; op.executedAt=ts; op.executeTx=tx
handleOperationCanceled(id,nonce): op=load(id); op.status="Canceled"; op.canceledAt=ts; op.cancelTx=tx
```
A "pending" op = `status == Scheduled`. `expired` is derived in the frontend from
`Manager.expiration` (`scheduledAt + delay + expiration < now`). The op's `data` is decoded
client-side against the AM ABI to show the human action (e.g. `grantRole(GUARDIAN_ROLE, 0x…)`).

**Native AccessControl** (Concrete vaults, per-vault data source):
`handleNativeRoleGranted(role, account, sender)` / `Revoked` / `AdminChanged(role, prev, new)` →
`NativeRole` / `NativeRoleMember` / `NativeRoleEvent`, keyed by `(vault, roleHash)`. `sender` is
captured (native AC exposes who granted; AM does not).

### 3.3 Frontend data-loading flow (per request)

For the active `chainId`:
1. Load `catalog.<chainId>.json` (static import / fetch) → EXPECTED + name maps.
2. Fire GraphQL queries against that chain's Goldsky endpoint → ACTUAL (roles, members, functions,
   ops, native roles).
3. viem multicall the Makina slots for each vault (`IMakinaGovernable.riskManager()`,
   `riskManagerTimelock()`, `ICaliber.isInstrRootGuardian(FNDN)`) → live slot values.
4. Merge into view-models (§6); compute drift (§3.4).

Multi-chain views (index, multi-chain diff) fan out steps 1–3 across all four chains and group by
`roleId`.

### 3.4 Drift-detection algorithm (ACTUAL vs EXPECTED)

Per role, per chain, produce `Drift[]`:
```
for role in catalog.roles:
  actual = subgraph.role(role.id)               // may be null → "never configured on-chain"
  checks:
    - adminRole:     actual.adminRole   != role.expected.adminRole
    - guardianRole:  actual.guardianRole!= role.expected.guardianRole
    - grantDelay:    actual.grantDelay  != role.expected.grantDelay
    - holders set:   symmetricDiff(activeMembers(actual), role.expected.holders)
                        → unexpectedHolder / missingHolder
    - per-holder executionDelay < role.expected.delay (below canonical floor) → severity HIGH
  for each capability in catalog where capability.roleId == role.id:
    - binding = subgraph.targetFunction(target, selector)
    - binding.role != role.id  → mis-bound / unbound selector
for role in subgraph but NOT in catalog:  → "unknown role present on-chain" (HIGH)
for targetFunction in subgraph but NOT in catalog capabilities: → "unexpected binding" (HIGH)
```
Severity: unexpected holder / unknown role / delay-below-floor / unexpected binding = **HIGH**;
missing holder / label mismatch = **MEDIUM**; cosmetic = **LOW**. The `forge test` drift guard (CI)
runs the same comparison server-side via `AccessManagerReader` and fails the build on any HIGH.

### 3.5 Multi-chain diff flow

Group all four chains' `RoleView`s by `roleId`; for each role render a matrix `role × chain` with
cells = `{holders, grantDelay, adminRole, guardianRole}`. Highlight any column that differs from the
modal value across chains (per-chain inconsistency), skipping chains where the role is legitimately
absent (e.g. vault/Makina roles are Mainnet-only; Base has factory only).

---

## 4. Subgraph schema (ACTUAL projection) — `app/subgraph/schema.graphql`

```graphql
type Manager @entity {
  id: ID!                 # chainId
  address: Bytes!
  expiration: BigInt!
  minSetback: BigInt!
}

type Role @entity {
  id: ID!                 # roleId, decimal string
  onChainLabel: String
  adminRole: BigInt!      # default 0 (ADMIN_ROLE) until RoleAdminChanged
  guardianRole: BigInt!
  grantDelay: BigInt!
  members: [RoleMember!]! @derivedFrom(field: "role")
  functions: [TargetFunction!]! @derivedFrom(field: "role")
  events: [RoleEvent!]! @derivedFrom(field: "role")
}

type RoleMember @entity {
  id: ID!                 # "{roleId}-{account}"
  role: Role!
  account: Account!
  executionDelay: BigInt!
  active: Boolean!
  grantedAt: BigInt
  revokedAt: BigInt
  pendingDelayEffective: BigInt
  grantTx: Bytes
}

type RoleEvent @entity(immutable: true) {
  id: ID!                 # "{txHash}-{logIndex}"
  role: Role!
  account: Account
  kind: RoleEventKind!
  oldValue: String
  newValue: String
  effectiveAt: BigInt     # `since` for grant/delay events
  blockNumber: BigInt!
  timestamp: BigInt!
  txHash: Bytes!
}
enum RoleEventKind { Granted Revoked ExecutionDelayChanged AdminChanged GuardianChanged GrantDelayChanged Labeled }

type TargetContract @entity {
  id: ID!                 # address
  address: Bytes!
  closed: Boolean!
  adminDelay: BigInt!
  functions: [TargetFunction!]! @derivedFrom(field: "target")
}

type TargetFunction @entity {
  id: ID!                 # "{target}-{selector}"
  target: TargetContract!
  selector: Bytes!
  role: Role!
  updatedAt: BigInt!
  txHash: Bytes!
}

type Operation @entity {
  id: ID!                 # operationId (bytes32)
  nonce: BigInt!
  caller: Bytes!
  target: Bytes!
  data: Bytes!
  schedule: BigInt!       # executable-at
  status: OperationStatus!
  scheduledAt: BigInt!
  executedAt: BigInt
  canceledAt: BigInt
  scheduleTx: Bytes!
  executeTx: Bytes
  cancelTx: Bytes
}
enum OperationStatus { Scheduled Executed Canceled }

type Account @entity {
  id: ID!                 # address
  roles: [RoleMember!]! @derivedFrom(field: "account")
  nativeRoles: [NativeRoleMember!]! @derivedFrom(field: "account")
}

type NativeRole @entity {
  id: ID!                 # "{vault}-{roleHash}"
  vault: Bytes!
  roleHash: Bytes!
  adminRoleHash: Bytes!
  members: [NativeRoleMember!]! @derivedFrom(field: "nativeRole")
}
type NativeRoleMember @entity {
  id: ID!                 # "{vault}-{roleHash}-{account}"
  nativeRole: NativeRole!
  account: Account!
  active: Boolean!
  grantedAt: BigInt
  revokedAt: BigInt
}
type NativeRoleEvent @entity(immutable: true) {
  id: ID! nativeRole: NativeRole! account: Bytes! sender: Bytes!
  kind: String! blockNumber: BigInt! timestamp: BigInt! txHash: Bytes!
}
```

---

## 5. Canonical catalog (EXPECTED projection)

### 5.1 `app/metadata/catalog.<chainId>.json` (generated by §3.1)
```jsonc
{
  "chainId": 1,
  "generatedAtBlock": 20123456,
  "manager": { "address": "0x7cc6…253c", "expiration": 604800, "minSetback": 432000 },
  "roles": [{
    "id": "3149…812", "hexId": "0x2bc4420d29f38eba", "tag": "ROYCO_GUARDIAN_ROLE",
    "name": "GUARDIAN_ROLE", "delayTier": "IMMEDIATE",
    "expected": { "adminRole": "0", "guardianRole": "0", "grantDelay": 0,
                  "holders": [{ "address": "0x7c40…9997", "actor": "FNDN", "executionDelay": 0 },
                              { "address": "0x…dead0002", "actor": "FNDN_VETO", "executionDelay": 0, "pendingDeployment": true }] },
    "description": "Cancels delayed operations on every operational role. Co-held by FNDN + FNDN_VETO."
  }],
  "actors": [{ "address": "0x84d3…119e", "name": "WAY", "kind": "multisig" }],
  "targets": [{ "address": "0x0ae0…d3c6", "name": "sNUSD.kernel", "type": "kernel" }],
  "capabilities": [{ "roleId": "…", "target": "0x…", "selector": "0x8456cb59",
                     "functionName": "pause", "contractType": "kernel" }],
  "makinaSlots": [{ "vault": "srRoyUSDC", "caliber": "0x…", "machine": "0x…",
                    "expected": { "riskManager": "0x7cc6…253c", "riskManagerTimelock": "0x7cc6…253c" } }]
}
```

### 5.2 `app/metadata/roles.descriptions.json` (hand-maintained, mirrors `assignments.md`)
Keyed by role `tag` → `{ description, expectedHolders[], expectedDelay, expectedAdmin,
expectedGuardian }`. Becomes the 4th member of the README "update-together" doc set. The exporter
joins it into `catalog.roles[].expected`/`.description`; a `forge test` asserts it stays consistent
with `Roles.sol` (every tag present, no orphans).

---

## 6. Frontend shared types (MERGED projection) — `app/dashboard/src/model/`

Single TS source of truth consumed by every view; produced by merging catalog (EXPECTED) + subgraph
(ACTUAL) + Makina RPC reads.

```ts
type Address = `0x${string}`;
type RoleId = string;            // uint64 decimal string
type Severity = "HIGH" | "MEDIUM" | "LOW";

interface Drift { field: string; expected: string; actual: string; severity: Severity; note?: string }

interface HolderView {
  address: Address; actor?: string;   // resolved name
  executionDelay: number; expected: boolean; pendingDeployment?: boolean;
  grantedAt?: number; revokedAt?: number;
}

interface CapabilityView { target: Address; targetName: string; selector: string; fnName: string; contractType: string }

interface RoleView {
  chainId: number; id: RoleId; name: string; tag: string; description: string;
  config: { adminRole: RoleId; adminRoleName: string; guardianRole: RoleId; guardianRoleName: string; grantDelay: number };
  expectedConfig: RoleView["config"];
  holders: HolderView[];             // current (active) members, expected-joined
  capabilities: CapabilityView[];    // functions this role gates
  history: RoleEventView[];          // timeline, newest-first
  drift: Drift[];                    // empty = in sync
  presentOnChain: boolean;           // false = catalog-known but never configured
}

interface RoleEventView { kind: string; account?: Address; actorName?: string; oldValue?: string; newValue?: string; timestamp: number; txHash: string }

interface OperationView {
  id: string; caller: Address; callerName?: string; target: Address; targetName?: string;
  action: string;                    // decoded, e.g. "grantRole(GUARDIAN_ROLE, 0x…)"
  schedule: number; status: "Scheduled" | "Executed" | "Canceled";
  executableNow: boolean; expired: boolean; guardianCancellable: boolean;
}

interface MakinaSlotView { vault: string; slot: "riskManager" | "riskManagerTimelock"; actual: Address; expected: Address; drift?: Drift }

interface ChainRoleMatrixCell { chainId: number; present: boolean; holders: HolderView[]; grantDelay: number; adminRoleName: string; guardianRoleName: string; divergent: boolean }
```

View → type mapping: Roles index (`RoleView[]` summary) · Role detail (`RoleView` full) · Accounts
(`AccountView` = address + `RoleView[]` it appears in) · Function map (`CapabilityView[]` grouped by
target) · Pending ops (`OperationView[]` filtered to `Scheduled`) · Drift (all `RoleView.drift` +
`MakinaSlotView.drift` flattened, sorted by severity) · Multi-chain diff (`ChainRoleMatrixCell[][]`).

---

## 7. Edge cases & invariants (must be handled explicitly)

- **`RoleGranted.since` dual meaning** (`newMember` true vs false) — §3.2; getting this wrong
  corrupts both membership start and execution-delay history.
- **`TargetFunctionRoleUpdated.selector` is non-indexed** — read from event `data`, not topics.
- **`ADMIN_ROLE = 0` fallback**: any selector with no explicit binding is effectively ADMIN_ROLE;
  the catalog must synthesize these "default" capabilities so the function map isn't misleadingly
  empty (auth.md convention line 10).
- **`PUBLIC_ROLE = 2^64-1`**: render as "open to all"; never treat as a normal holder set.
- **Sentinel multisigs**: `WAY_PAUSE`/`FNDN_VETO` = `0xDEAD0001/2` until deployed
  (`MULTISIGS_DEPLOYED=false`); show as "pending deployment", and suppress the corresponding
  "missing holder" drift as INFO rather than HIGH until real addresses land.
- **Makina slots** carry no reliable events and Royco can't set them → RPC-read only; snapshot with a
  `blockNumber` for freshness; drift compares actual slot vs `expected` = RoycoFactory address.
- **Base**: separate factory address (`roycoFactory(8453)`), factory-only (no vaults/Makina/syncer);
  no `BASE_RPC_URL` secret in CI today (`.github/workflows/test.yml:39-43`).
- **Role discovery vs. enumeration**: "all roles" = catalog set ∪ event-observed set; a role in one
  but not the other is itself a signal (unknown-on-chain = HIGH drift; catalog-only =
  `presentOnChain:false`).
- **Re-orgs / replays**: all upserts keyed by deterministic ids; `RoleEvent`/`NativeRoleEvent`
  immutable and keyed by `txHash-logIndex`.

---

## 8. Critical files

**Reuse (read):** `src/registry/*.sol`; `src/access/AccessManagerDumper.sol` (`_allRoles()`, target
iteration), `AccessManagerReader.sol` (struct shapes = entity shapes), `Selectors.sol`;
`docs/roles/{assignments,auth}.md`; `lib/openzeppelin-contracts/.../IAccessManager.sol`;
`src/safe/SafeBatchUtils.sol:121-155` (JSON serialize pattern).

**New:** `script/ExportCatalog.s.sol`; `app/metadata/{catalog.<chainId>.json, roles.descriptions.json}`;
`app/subgraph/{subgraph.template.yaml, schema.graphql, config/*.json, abis/*, src/{accessManager,accessControl}.ts, package.json}`;
`app/dashboard/**` (Next.js, `src/model/`, `src/lib/{graphql,catalog,makina,drift}.ts`, views);
optional `test/CatalogDrift.t.sol` (CI guard).

---

## 9. Verification

1. **Catalog:** `forge script script/ExportCatalog.s.sol --sig "run()"` → `app/metadata/catalog.1.json`;
   assert 31 roles (2 built-in + 29 Royco), GUARDIAN_ROLE hex id `0x2bc4420d29f38eba`, vault
   capabilities resolve to real selectors.
2. **Subgraph:** `graph codegen && graph build` clean; `goldsky subgraph deploy` one chain, wait for
   sync, query GUARDIAN_ROLE members == {FNDN, FNDN_VETO} (`assignments.md:65`); cross-check against
   `forge script script/Dump.s.sol --sig "dump(uint256)" 1`.
3. **History:** replay a known migration tx from `output/migrate/dawn/1_*.json`; confirm the matching
   grant/revoke `RoleEvent`s with correct block/timestamp.
4. **Frontend e2e:** `cd app/dashboard && npm run dev`; every view loads; chain switch works; Drift is
   empty on a fully-migrated chain and lights HIGH when the catalog is perturbed; Pending Ops reflects
   an open scheduled op; Multi-chain diff flags a deliberately divergent delay.
5. **Drift guard:** `forge test --match-contract CatalogDrift` green against forked mainnet.
