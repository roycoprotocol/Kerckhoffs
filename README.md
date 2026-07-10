# Kerckhoffs

> *"A cryptosystem should be secure even if everything about the system, except the key, is public knowledge."* — Auguste Kerckhoffs, 1883

Onchain security command center for the Royco protocol. The name is a nod to the principle: every privileged operation in this repo is fully open — the role topology, the delays, the exact transactions the Safes will execute, the simulations that prove they do what we claim. Security comes from the multisig signatures and the timelocks, not from anything hidden here.

This repo is the canonical home for everything that touches privileged onchain operations across the stack:

- **Royco Dawn Markets** (per chain — Mainnet / Avalanche / Arbitrum)
- **Concrete vaults** (`srRoyUSDC`, `roywstETH`)
- **Makina / Caliber** strategies sitting under each vault
- **Royco Entry Point** (per chain)
- Anything else privileged that gets added later

It's a Foundry repo. Every privileged operation we run is generated as a Safe Transaction Builder JSON, simulated on a fork, and only then signed and executed by the appropriate multisig. No script in this repo broadcasts to mainnet directly.

## What's here

### `authorization/`
The spec. `authorization/README.md` defines the canonical role / delay / guardian model that everything else here implements. Read this first.

### `src/`
Reusable Solidity libraries and abstractions. Inherit from these when writing a new script — don't reach for `forge-std/Script` directly.

| Path | Purpose |
|---|---|
| `src/registry/` | Per-contract-type registries: `Roles`, `Multisigs`, `Factory`, `Markets`, `Vaults`, `Strategies`, `EntryPoints`. Single source of truth for addresses + role IDs. |
| `src/safe/SafeBatchUtils.sol` | Builders for `IAccessManager` Safe transactions (`buildGrantRole`, `buildSetTargetFunctionRole`, etc.) and Safe Transaction Builder JSON v1.0 output. |
| `src/safe/SafeSimulator.sol` | `_replayBatch(safe, txs)` — pranks a Safe address and replays a batch on a fork with revert decoding. |
| `src/access/Selectors.sol` | Curated selector lists derived from imported interfaces (LP ops, Caliber/Machine risk-manager setters, vault role-gated functions, etc.). Single selectors should use `Interface.method.selector` directly at the call site. |
| `src/access/AccessManagerReader.sol` | Thin view wrappers around `IAccessManager` for queries. |
| `src/access/AccessManagerDumper.sol` | Reads + tabulates the full RoycoFactory AccessManager state for a chain (roles, members, delays, target-function-role bindings, etc.). |
| `src/migration/MigrationBase.sol` | Standard per-chain migration flow: fork → pre-state dump → `_buildBatch` → `_preSimulate` → replay → assert → post-state dump → write JSON. Override the abstract hooks. |

### `script/`
Operational scripts.

| Script | What it does |
|---|---|
| `script/Dump.s.sol` | Tabulates the full AccessManager state for one or all chains. Importable: any other script can call `dump(uint256 chainId)` to print pre/post state. |
| `script/migrate/Dawn.s.sol` | Diff-based migration of the Dawn surface (markets + entry point) to the canonical role / delay model. |
| `script/migrate/Vaults.s.sol` | Migration of the concrete vaults (`srRoyUSDC`, `roywstETH`) — phase 1 native AccessControl + phase 2 AM-side wiring + a merged batch. |
| `script/migrate/Makina.s.sol` | AM-side wiring for Caliber + Machine setters (per-vault `RISK_MANAGER` and `TIMELOCK_MANAGER` roles). Pre-simulates the Makina-governance step (`Machine.setRiskManagerTimelock`) which we don't have permission to execute today. |

### `output/` (gitignored)
Where every script writes its artifacts. Subdirectories:
- `output/dump/` — point-in-time AM state JSONs (used for diffing across runs)
- `output/migrate/<surface>/` — Safe Transaction Builder batches ready to import into the Safe UI

## Operating model

Every privileged operation follows the same shape:

1. **Spec it** in `authorization/README.md` — the desired post-state.
2. **Build a Solidity script** under `script/` (inheriting `MigrationBase` for migrations, or just `AccessManagerDumper`/`SafeSimulator` for one-off operational scripts) that:
   - Reads on-chain state via the dumper / `AccessManagerReader`
   - Constructs the diff between current and desired state as `SafeTransaction[]`
   - Replays the batch on a fork with `_replayBatch`
   - Asserts the full desired state via `_assertTargetState`
   - Writes the batch to `output/.../<chainId>_<name>.json` via `writeSafeTransactionJson`
3. **Run it** locally — `forge script script/...` produces the JSON and runs the simulation in one go.
4. **Operator imports the JSON** into the Safe UI, signs, executes.

### Human-auditable output

Every emitted batch is self-describing, so signers and auditors never have to hand-decode
calldata. `SafeBatchDecoder` (`src/safe/SafeBatchDecoder.sol`) is the single decoder that drives
this, and `writeAuditableSafeTransactionJson` asserts every transaction round-trips (decoded args
re-encode to the exact `data`) before writing. Each emitted JSON therefore carries, per
transaction:

- `contractMethod` + `contractInputsValues` — the standard Safe Transaction Builder decoded
  fields, so the **Safe UI renders the method name and typed args at signing time** (not raw
  calldata). These stay canonical (role as a number, address as hex) because the Safe UI
  validates them by re-encoding to `data`.
- The raw `to` / `value` / `data` are untouched.

The **human labels** — role names, actor/contract names (`FNDN`, `WAY`, `sNUSD.ST`,
`RoycoFactory(AM)`), human delays (`72h`, `immediate`), a one-line effect per tx, plus a batch summary
(chain, tx count, `keccak256` batch hash) — live in `meta.description`, which the Safe UI shows
and which travels in the same file.

**Independently verify any batch** (works on already-generated files) with the standalone
decoder, which prints the fully-labeled table and asserts both the round-trip and that the file's
`contractInputsValues` match the values decoded from `data`:

```bash
forge script script/DecodeBatch.s.sol --sig "run(string)" -- output/migrate/dawn/1_apply_security_migration.json
```

For incident-response (pause / unpause / cancel), the same shape applies but the script will typically just emit a single tx and skip the diff.

### One-time use — the migration scripts are NOT reusable

The three migration scripts (`Dawn.s.sol`, `Vaults.s.sol`, `Makina.s.sol`) each emit a **flat, direct-call** Safe batch (`grantRole` / `setTargetFunctionRole` / `setRoleGuardian`, all `ADMIN_ROLE`-gated) that FNDN executes as ordinary Safe transactions. That is only valid while **FNDN's `ADMIN_ROLE` execution delay is still 0**. The Dawn migration's final step raises it to 72h (`DELAY_ROOT`), locking down role management. After that lockdown:

- Every `ADMIN_ROLE`-gated op must go through `schedule()` → wait 72h → `execute()`. A freshly generated direct-call batch would revert on import.
- The scripts **refuse to run** (`_assertPreMigrationAdminState` reverts with `MigrationAlreadyApplied`) so you cannot accidentally generate an invalid batch.

Consequences:

1. **Run order is fixed: `Vaults` → `Makina` → `Dawn`.** Dawn is last because it performs the lockdown. Vaults and Makina must be executed while FNDN can still call admin functions immediately.
2. **These scripts are for the current on-chain state only.** They are a one-shot bootstrap of the security model — not a standing tool. Do not re-run them and do not re-import a previously generated JSON.
3. **Onboarding a new market/vault/chain after lockdown is a different operation.** It must be authored as a `schedule`/`execute` flow (or a temporary FNDN delay reduction), not by re-running these scripts. See the per-script headers.

## Setup

```bash
git clone --recursive <this-repo>
cd royco/dawn/security
forge build
```

Submodules pulled into `lib/`:
- `forge-std`
- `royco-dawn` — Royco Dawn Markets contracts (read-only reference)
- `concrete-earn-v2-bug-bounty` — concrete vaults
- `royco-vault-makina-strategy` — Royco's Makina strategy adapter
- `openzeppelin-contracts`

**Makina Caliber + Machine** (`makina-core`) is **not** a direct submodule. The `makina-core/`
remapping resolves to the copy vendored under `royco-vault-makina-strategy/lib/makina-core/`
(see `remappings.txt`) — that nested copy is the single source of truth and the one that
compiles. Do not add a top-level `lib/makina-core`; a second, drifting copy is exactly what this
setup avoids. Any code/comment that cites a `makina-core` line number means that vendored copy.

Remappings live in `remappings.txt`.

### Environment variables

Set RPC URLs in `.env` (loaded by `set -a && source .env && set +a`):

```
MAINNET_RPC_URL=...
AVALANCHE_RPC_URL=...
ARBITRUM_RPC_URL=...
BASE_RPC_URL=...
```

No private keys are needed for any script in this repo — everything goes through Safe.

## Running things

```bash
# Dump full AM state for one or all chains
forge script script/Dump.s.sol --sig "run()"
forge script script/Dump.s.sol --sig "dump(uint256)" -- 1

# Generate + simulate the migration batches
forge script script/migrate/Dawn.s.sol     # → output/migrate/dawn/{1,43114,42161}_apply_security_migration.json
forge script script/migrate/Vaults.s.sol   # → output/migrate/vaults/{srRoyUSDC,roywstETH}_{phase1_native,phase2_am,merged}.json
forge script script/migrate/Makina.s.sol   # → output/migrate/makina/1_caliber.json
```

Each migrate script:
1. Forks the target chain
2. Dumps current state to console
3. Builds the diff
4. Replays the batch on the fork (this is where you catch revert reasons)
5. Asserts the full desired state matches
6. Dumps post-state to console
7. Writes the Safe JSON

If any step fails, the script reverts and no JSON is written.

## Adding a new script

For a new privileged operation:
1. Pick the right base — `MigrationBase` for full migrations, otherwise inherit `AccessManagerDumper, SafeSimulator, Script` directly.
2. Use `Selectors.*` for selector groups; use `Interface.method.selector` inline for one-off selectors. Never hand-hash function signatures.
3. Read on-chain state to drive the diff. Don't emit txs blindly.
4. Always assert the full desired state at the end, not just the deltas.

For a new privileged contract:
1. Add its addresses to the relevant registry in `src/registry/`.
2. Add its role IDs to `src/registry/Roles.sol`.
3. Add its selector groups to `src/access/Selectors.sol` (importing the interface, not hashing strings).
4. Extend `AccessManagerDumper._allRoles()` and the relevant `_dump<X>Targets` so its state shows up in dumps.

## Conventions

- **No keccak'd selectors.** Always derive from an imported interface — broken signatures should fail to compile here, not silently fail at runtime.
- **No private keys, no broadcasting.** Every state-changing call goes through a Safe; this repo just produces JSON.
- **Diff-based migrations.** Read current state, emit only what's needed, but assert the full target state regardless of what was emitted. Re-running a migration against a fully-applied chain should produce a 0-tx batch.
- **Simulation is mandatory.** A migration that doesn't simulate clean on a real-RPC fork doesn't ship.
- **Single AccessManager.** RoycoFactory (`0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C`, same on every chain) is the single control plane. Don't introduce a second AM.
