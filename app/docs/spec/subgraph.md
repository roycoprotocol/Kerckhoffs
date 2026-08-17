# Subgraph: build, deploy to Goldsky, test

The executable plan for Component 1 of the access-control dashboard. Reads alongside
[`main.md`](./main.md) — this doc references its sections (§3.2 handlers, §4 schema, §1 keying).

## 10.1 Goal & shape

Four Goldsky subgraph deployments — `royco-access-mainnet`, `-avalanche`, `-arbitrum`, `-base` —
from **one** templated codebase, indexing the events in main.md §3.2 into the schema in main.md §4.
Mainnet/Avalanche/Arbitrum share the CREATE2 factory `0x7cC6…253C`; Base uses `0x568c…551A`. Only
Mainnet adds the Concrete-vault AccessControl data sources.

## 10.2 Scaffold (`app/subgraph/`)

```
app/subgraph/
  package.json
  subgraph.template.yaml          # mustache-templated manifest
  config/
    1.json  43114.json  42161.json  8453.json   # {network, factory, startBlock, vaults[]}
  schema.graphql                  # main.md §4
  abis/
    AccessManager.json            # extracted from forge `out/`
    AccessControl.json
  src/
    accessManager.ts
    accessControl.ts
    helpers.ts                    # id builders, loadOrCreate, constants
  tests/                          # matchstick-as
    accessManager.test.ts
    accessControl.test.ts
    operations.test.ts
  scripts/
    render.mjs                    # mustache(template, config/<chain>.json) -> subgraph.yaml
    extract-abis.mjs              # pull abi arrays out of ../../out/*.json
```

`package.json` deps: `@graphprotocol/graph-cli`, `@graphprotocol/graph-ts`, `matchstick-as`,
`mustache`, `@goldskycom/cli` (or the `goldsky` binary via curl in CI). Scripts:
`render:<chain>`, `codegen`, `build`, `test` (matchstick), `deploy:<chain>`.

`config/<chainId>.json` example:
```json
{ "network": "mainnet", "factory": "0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C",
  "factoryStartBlock": 20000000,
  "dayManager": { "address": "0x87aED46566cb28c8375cfcC9971090882A0fB12e", "startBlock": 25734830 },
  "dayFactory": { "address": "0xaaAaaaaa01Af9426C2eB6FeBc61DcD7C302cc45F", "startBlock": 25734830 },
  "vaults": [ { "name": "srRoyUSDC", "address": "0x…", "startBlock": 20100000 },
              { "name": "roywstETH", "address": "0x…", "startBlock": 20100000 } ] }
```
`dayManager` / `dayFactory` are present on every chain since the 2026-08-17 Avalanche Day
deployment; the mustache sections still render to nothing if a future chain omits them. An
optional `graft: {base, block}` (local graph-node only — stripped by `NO_GRAFT=1` for hosted
deploys) grafts a new deployment onto an existing one to avoid full resyncs. Goldsky network names: `mainnet`, `avalanche`, `arbitrum-one`,
`base`. Start blocks = deployment blocks (resolve via explorer or `cast code`/first-tx lookup) so
first sync is bounded — **not** block 0.

## 10.3 ABIs

`scripts/extract-abis.mjs` reads the compiled artifacts under repo `out/` (Foundry builds
`IAccessManager`, the vault's `AccessControl`, and the thin Day mirrors in `src/interfaces/day/`)
and writes just the `abi` array to `abis/AccessManager.json` / `abis/AccessControl.json` /
`abis/RoycoAccessManager.json` (Day AM: OZ superset + `TargetConfiguredAtGenesis`) /
`abis/DayFactory.json` (`MarketDeploymentCompleted` with named `DeploymentResult` tuple
components — required for codegen accessors). Keeps the subgraph ABI in lockstep with the audited
Solidity rather than hand-copying. Run after `forge build`.

## 10.4 Manifest (`subgraph.template.yaml`)

- `dataSources[0]`: `AccessManager` (Dawn) at `{{factory}}`, `startBlock {{factoryStartBlock}}`,
  all 12 event handlers (main.md §3.2), data-source `context` `kind: "dawn"`.
- `{{#dayManager}}` → `DayAccessManager` data source: same 12 handlers (mapping module
  `src/dayAccessManager.ts` re-exports them) plus `TargetConfiguredAtGenesis`, context `kind: "day"`.
- `{{#dayFactory}}` → `DayFactory` data source: `MarketDeploymentCompleted` → `src/dayFactory.ts`
  (`Market` / `MarketComponent` entities).
- `{{#vaults}}` loop → one `AccessControl` data source per vault (Mainnet only; the array is empty
  for the other chains so the loop emits nothing).
- `Manager` rows have no dedicated event — lazily create them in every AM handler, keyed by
  `event.address`, via a bound contract call (`AccessManager.bind(address).try_expiration()` /
  `try_minSetback()`), cached. `kind` comes from the data-source context (default "dawn" for
  contextless matchstick events).
- Day-only mapping modules live in `src/dayAccessManager.ts` / `src/dayFactory.ts` so the
  Avalanche render (no Day data sources → no generated Day types) still compiles.

## 10.5 Mappings (AssemblyScript)

Implement handlers exactly per main.md §3.2 pseudocode. `helpers.ts` centralizes:
- id builders (`roleMemberId`, `eventId(event)`, `targetFnId`, `nativeRoleId`…) matching main.md §1;
- `loadOrCreateRole/Member/Target/Account`;
- constants `ADMIN_ROLE = 0`, `PUBLIC_ROLE = u64.MAX`.

Two correctness traps to encode as comments + tests:
1. `RoleGranted`: branch on `newMember` — true ⇒ membership start; false ⇒ execution-delay change
   effective at `since` (do **not** reset `grantedAt`).
2. `TargetFunctionRoleUpdated`: `selector` is a **data** param, not a topic — read `event.params.selector`.

## 10.6 Build

`npm run render:mainnet && npm run codegen && npm run build` must be clean. `codegen` regenerates
`generated/` types from schema + ABIs; `build` compiles mappings to WASM. Repeat per chain (the
rendered `subgraph.yaml` differs only in network/address/startBlock/vaults).

## 10.7 Local unit tests — Matchstick (fast, no network)

`npm run test` runs `matchstick-as` specs. Cover every handler and the edge cases:

| Test | Asserts |
|---|---|
| grant new member | `RoleMember.active=true`, `executionDelay`, `grantedAt` set, one `RoleEvent(Granted)` |
| execution-delay change (`newMember=false`) | delay updated, `grantedAt` **unchanged**, `RoleEvent(ExecutionDelayChanged)` |
| revoke | `active=false`, `revokedAt` set, member row retained, `RoleEvent(Revoked)` |
| admin/guardian/grantDelay changed | Role field set + `RoleEvent` with old→new |
| target function bound | `TargetFunction` upserted with correct `role`; re-bind updates in place |
| target closed / adminDelay | `TargetContract` flags set |
| op scheduled→executed | `Operation.status` transitions, tx hashes recorded |
| op scheduled→canceled | status `Canceled`, `canceledAt` set |
| native grant/revoke | `NativeRoleMember` state + `sender` captured |
| idempotency | replaying same event id doesn't duplicate `RoleEvent` |

Matchstick runs in CI (no RPC needed) — this is the primary correctness gate.

## 10.8 Deploy to Goldsky

1. Auth: `goldsky login` locally, or `GOLDSKY_API_KEY` secret in CI.
2. Per chain: render manifest → `goldsky subgraph deploy royco-access-<chain>/<semver> --path app/subgraph`.
3. Goldsky returns a GraphQL query URL per deployment; record them in `app/dashboard` env config
   (`NEXT_PUBLIC_SUBGRAPH_URL_<chainId>`).
4. Tag/version on each schema or mapping change; use `goldsky subgraph tag` to move a stable alias
   (e.g. `…/prod`) so the frontend points at an alias, not a pinned version.
5. Monitor sync via Goldsky dashboard / `goldsky subgraph list`; confirm `synced: true` and head
   block ≈ chain head before trusting queries.

## 10.9 Integration tests — against the live indexer (golden comparison)

A `app/subgraph/tests/integration/` node suite (vitest) that runs **after** deploy+sync and
validates ACTUAL(subgraph) == ACTUAL(RPC), reusing the canonical catalog as the oracle:

1. **Holders golden:** for each catalog role, query subgraph active members; independently read the
   same via `cast`/viem against the AM (`hasRole`) — assert equal. Anchor case: GUARDIAN_ROLE ==
   {FNDN, FNDN_VETO} (`docs/roles/assignments.md:65`).
2. **Config golden:** subgraph `grantDelay`/`adminRole`/`guardianRole` == on-chain getters ==
   catalog `expected` (three-way check; any mismatch is either an indexing bug or real drift — the
   test message distinguishes).
3. **Capability golden:** subgraph `TargetFunction` bindings == catalog `capabilities`.
4. **History:** pick a known migration tx from `output/migrate/dawn/1_*.json`, decode its
   grant/revoke calls, assert corresponding `RoleEvent`s exist with matching block/timestamp.
5. **Operations:** if any op is currently `Scheduled` on-chain, assert it appears with correct
   `schedule` and status.

Cross-tool oracle: `forge script script/Dump.s.sol --sig "dump(uint256)" <chain>` is the
human-readable second source to eyeball against the subgraph during bring-up.

## 10.10 CI & guardrails

- CI job `subgraph`: `forge build` → `extract-abis` → `render` (all chains, matrix) → `codegen` →
  `build` → `matchstick test`. No RPC, no deploy — pure correctness. Fails PR on any red.
- Deploy is a **manual/gated** workflow (needs `GOLDSKY_API_KEY`), not on every push.
- Integration suite runs post-deploy (or nightly against `…/prod`) with RPC secrets, so indexing
  drift from a chain re-org or a missed event surfaces without a code change.

## 10.11 Milestones (order of work)

1. Scaffold `app/subgraph/`, `package.json`, `extract-abis`, `render` scripts; commit `config/*.json`.
2. `schema.graphql` (main.md §4) + `codegen` green.
3. `helpers.ts` + `accessManager.ts` (AM handlers) → build green.
4. Matchstick suite for AM handlers green (§10.7).
5. `accessControl.ts` (native vault) + its Matchstick tests.
6. Deploy `royco-access-mainnet` to Goldsky; run integration golden suite (§10.9); fix until green.
7. Deploy Avalanche, Arbitrum, Base (factory-only); spot-check each.
8. Wire Goldsky query URLs into `app/dashboard` config; add CI `subgraph` job + gated deploy workflow.
