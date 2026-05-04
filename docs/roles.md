# Roles registry

Single inventory of every role across every contract Royco controls — AccessManager roles, native `AccessControl` roles, on-chain governance slots, and `Ownable` owners. Source of truth for the authorization model is `authorization/README.md`; this doc enumerates the surface.

Three categories:

1. **AccessManager roles** — held in `RoycoFactory` (the OZ `AccessManager` instance). Single control plane for everything Royco can move under itself.
2. **Native role-like state on contracts** — `AccessControl` roles, `Ownable` owners, ad-hoc role slots — held on the contract itself. After migration, most of these are granted to the AccessManager and revoked from prior holders, so authority routes through #1.
3. **Out-of-scope authorities** — Makina governance, Securitize transfer agent, ConcreteFactory owner. Royco does not control these.

---

## Multisigs

| Name | Address | Purpose |
|---|---|---|
| **FNDN** (Royco Foundation) | `0x7c405bbD131e42af506d14e752f2e59B19D49997` | Root admin / executor. Holds privileged roles. Same on every chain. |
| **WAY** | `0x84d37A25e46029CE161111420E07cEb78880119e` | Proposer + guardian. Holds `GUARDIAN_ROLE`. Co-holds Immediate ops (pause, sync, LP-admin). Same on every chain. |
| **DIAL** | `0xe7E4FA51280eB212254458d62081587Acd2077eE` | Strategy allocator (operations). |

Source: `src/registry/Multisigs.sol`.

---

## 1. AccessManager roles (RoycoFactory)

`RoycoFactory` = `0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C` (CREATE2; same on every chain).

Role IDs are `uint64(keccak256(abi.encode(<tag>)))`. Defined in `src/registry/Roles.sol`. After Dawn migration, every operational role's admin is `ADMIN_MANAGER` (not `ADMIN_ROLE`) and the cancel-path storage for the 10 AM admin selectors resolves to `ADMIN_MANAGER` → `GUARDIAN_ROLE` (WAY can cancel).

### Built-ins

| Role | ID | Description |
|---|---|---|
| `ADMIN_ROLE` | `0` | OZ AM root admin. Hardcoded gate for `setRoleAdmin`, `setRoleGuardian`, `setGrantDelay`, `setTargetAdminDelay`, `setTargetClosed`, `setTargetFunctionRole`, `updateAuthority`, `labelRole`. |
| `PUBLIC_ROLE` | `type(uint64).max` | Auto-member for every address. Used to leave selectors unrestricted at the AM layer. |

### Royco-defined roles

| Role | Admin | Guardian | Holder(s) | Exec delay | Notes |
|---|---|---|---|---|---|
| `ADMIN_ROLE` | self | `ADMIN_MANAGER` (cancel-gate via storage write) | FNDN | Critical (48h) | Closes the meta-timelock — every admin op WAY-cancellable. |
| `ADMIN_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | Admin of every operational role; cancel-gate target for all 10 AM admin selectors. |
| **Dawn — pause/upgrade** | | | | | |
| `ADMIN_PAUSER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate | Pause all protocol contracts. |
| `ADMIN_UNPAUSER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Standard (24h) | Unpause split from pause so an attacker can't rush an unpause. |
| `ADMIN_UPGRADER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | UUPS impl upgrades. |
| **Dawn — LP / accounting** | | | | | |
| `ST_LP_ROLE` | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | EntryPoint, LPs | Immediate | Senior tranche LP ops. |
| `JT_LP_ROLE` | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | EntryPoint, LPs | Immediate | Junior tranche LP ops. |
| `BURNER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | EntryPoint | Immediate | Yield-forfeit on redemption. |
| `LP_ROLE_ADMIN_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate | Grants/revokes LP roles. |
| `SYNC_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate | Triggers accounting sync on kernel. |
| **Dawn — config admins** | | | | | |
| `ADMIN_KERNEL_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) | Kernel config (fee recipient, redemption delay). |
| `ADMIN_ACCOUNTANT_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) | YDM, coverage, beta, LLTV. |
| `ADMIN_PROTOCOL_FEE_SETTER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) | Protocol fee % on ST/JT yields. |
| `ADMIN_ORACLE_QUOTER_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | Oracle/quoter settings. |
| **Dawn — entry point** | | | | | |
| `ADMIN_ENTRY_POINT_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | `modifyTrancheConfigs`. |
| `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Immediate | `collectProtocolFees`. |
| **Dawn — deployment / guardian / transfer agent** | | | | | |
| `DEPLOYER_ROLE` | `DEPLOYER_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate | Deploys new Royco markets via factory. |
| `DEPLOYER_ROLE_ADMIN_ROLE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Immediate | Grants/revokes `DEPLOYER_ROLE`. |
| `GUARDIAN_ROLE` | `ADMIN_MANAGER` | `ADMIN_ROLE` | WAY | Immediate | Cancels delayed operations. |
| `TRANSFER_AGENT_ROLE` | `ADMIN_MANAGER` | `ADMIN_ROLE` | Securitize | TBD | Outside the Critical/Standard/Immediate tiers — flagged for separate treatment. |
| **Vaults (Mainnet only)** — vault management functions bind directly to `ADMIN_MANAGER`; no per-vault management roles. | | | | | |
| `STRATEGY_PAUSER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate | Pause strategy. Kept distinct from `ADMIN_MANAGER` because WAY co-holds. |
| `STRATEGY_UNPAUSER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Standard (24h) | Unpause strategy. Kept distinct: 24h delay differs from `ADMIN_MANAGER`'s 48h. |
| `STRATEGY_RESCUE` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | 30d | AM delay matches the strategy's non-upgradable on-chain 30d rescue timelock; the two run in series. |
| `STRATEGY_ALLOCATOR` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | DIAL | Immediate | `allocateFunds`, `deallocateFunds`. Kept distinct: DIAL holder. |
| **Makina/Caliber (per-vault, Mainnet only)** | | | | | |
| `SRROYUSDC_RISK_MANAGER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | srRoyUSDC Caliber + Machine risk-manager setters. |
| `SRROYUSDC_TIMELOCK_MANAGER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | srRoyUSDC Caliber `setTimelockDuration` only. |
| `ROYWSTETH_RISK_MANAGER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | roywstETH Caliber + Machine risk-manager setters. |
| `ROYWSTETH_TIMELOCK_MANAGER` | `ADMIN_MANAGER` | `GUARDIAN_ROLE` | FNDN | Critical (48h) | roywstETH Caliber `setTimelockDuration` only. |

### AM-self admin selectors (cancel-gate wiring)

`setTargetFunctionRole(RoycoFactory, [these], ADMIN_MANAGER)` is set so `cancel()` resolves the guardian via `getRoleGuardian(ADMIN_MANAGER) = GUARDIAN_ROLE`. Call-gate is unchanged (OZ AM hardcodes `ADMIN_ROLE` for these).

`labelRole`, `setRoleAdmin`, `setRoleGuardian`, `setGrantDelay`, `setTargetAdminDelay`, `setTargetClosed`, `setTargetFunctionRole`, `updateAuthority`, `grantRole`, `revokeRole` — see `src/access/Selectors.sol :: accessManagerAdminSelectors()`.

---

## 2. Native role-like state on contracts

### Concrete vaults (`srRoyUSDC`, `roywstETH`)

OpenZeppelin `AccessControl`. After `script/migrate/Vaults.s.sol` phase 1, all migrated roles are granted to the AccessManager (`RoycoFactory`) and revoked from prior holders.

| Role | Hash tag | Migrated to AM? | AM target role | Notes |
|---|---|---|---|---|
| `VAULT_MANAGER` | `keccak256("VAULT_MANAGER")` | ✅ | (selectors → `ADMIN_MANAGER`) | Vault selectors bind directly to `ADMIN_MANAGER` (FNDN @ 48h, WAY-cancellable). No per-vault AM role. |
| `STRATEGY_MANAGER` | `keccak256("STRATEGY_MANAGER")` | ✅ | (selectors → `ADMIN_MANAGER`) | Same — bind to `ADMIN_MANAGER`. |
| `HOOK_MANAGER` | `keccak256("HOOK_MANAGER")` | ✅ | (selectors → `ADMIN_MANAGER`) | Same — bind to `ADMIN_MANAGER`. |
| `VAULT_MANAGER_ADMIN` | `keccak256("VAULT_MANAGER_ADMIN")` | ✅ (admin slot) | n/a | All `*_ADMIN` slots collapse onto the AM; otherwise an admin holder could re-grant the primary role and bypass the AM gate. The AM-side actions that exercise these admin slots — `vault.grantRole` / `vault.revokeRole` — are bound to `ADMIN_MANAGER` so calls run at FNDN @ 48h and are WAY-cancellable. |
| `STRATEGY_MANAGER_ADMIN` | `keccak256("STRATEGY_MANAGER_ADMIN")` | ✅ (admin slot) | n/a | Same path. |
| `HOOK_MANAGER_ADMIN` | `keccak256("HOOK_MANAGER_ADMIN")` | ✅ (admin slot) | n/a | Same path. |
| `ALLOCATOR` | `keccak256("ALLOCATOR")` | ❌ stays native | n/a | Immediate ops, held by DIAL natively. |
| `WITHDRAWAL_MANAGER` | `keccak256("WITHDRAWAL_MANAGER")` | ❌ stays native | n/a | Immediate ops, held natively. |
| `ALLOCATOR_ADMIN` | `keccak256("ALLOCATOR_ADMIN")` | ✅ (admin slot only) | n/a | Primary role stays native, admin slot collapses to AM; admin actions go through `vault.grantRole` / `vault.revokeRole` (`ADMIN_MANAGER`-bound). |
| `WITHDRAWAL_MANAGER_ADMIN` | `keccak256("WITHDRAWAL_MANAGER_ADMIN")` | ✅ (admin slot only) | n/a | Same path. |

Source: `lib/concrete-earn-v2-bug-bounty/src/lib/Roles.sol` (mirrored in `src/access/Selectors.sol :: native*()`).

The whitelist hook contract's ownership is **out of scope** for this migration — only the vault's `HOOK_MANAGER` (which gates `setHooks` on the vault) is migrated.

### Royco Makina strategy contract

`AccessManaged` against the RoycoFactory — no native AccessControl roles. Selectors gated entirely via AM (`STRATEGY_PAUSER` / `STRATEGY_UNPAUSER` / `STRATEGY_RESCUE` / `STRATEGY_ALLOCATOR` per `script/migrate/Vaults.s.sol`).

The **rescue path itself has a 30d on-chain timelock** baked into the strategy — non-upgradable, the actual gate that protects depositors. The AM-side `STRATEGY_RESCUE` role sits on top with 0 additional delay; `GUARDIAN_ROLE` can still cancel during the 30d window.

### Caliber / Machine (Makina core)

Per `lib/makina-core/src/interfaces/IMakinaGovernable.sol` — these are address slots, not roles, but they gate authority just like roles do. Each vault has its own Machine; Caliber inherits authority from its Machine via the `onlyRiskManagerTimelock` modifier.

| Slot | Setter | Authority needed | Royco's plan |
|---|---|---|---|
| `mechanic` | `setMechanic` | Makina AM | Out of scope; Makina governance. |
| `securityCouncil` | `setSecurityCouncil` | Makina AM | Out of scope; Makina governance. |
| `riskManager` | `setRiskManager` | Makina AM | Out of scope; Makina governance. |
| `riskManagerTimelock` | `setRiskManagerTimelock` | Makina AM | Re-pointed to `RoycoFactory` so AM-relayed calls satisfy `onlyRiskManagerTimelock` on both Caliber and Machine. **Out-of-band Makina governance step.** |
| `recoveryMode` | `setRecoveryMode` | per-Machine policy | Out of scope. |
| `restrictedAccountingMode` | `setRestrictedAccountingMode` | per-Machine policy | Out of scope. |
| `accountingAgent` (set) | `addAccountingAgent` / `removeAccountingAgent` | per-Machine policy | Out of scope. |

Caliber additionally has its own guardian set:

| Role | Setter | Function | Royco's plan |
|---|---|---|---|
| `instrRootGuardian` (set) | `addInstrRootGuardian` / `removeInstrRootGuardian` | Can call `cancelAllowedInstrRootUpdate` during the on-chain `_allowedInstrRoot` timelock window. | **Add WAY** so it can veto allowed-instruction root updates. Requires Makina governance to execute. |

The on-chain `_allowedInstrRoot` timelock (Caliber.sol:524 / 539) stays **on-chain, untouched**. Royco's AM does not gate `scheduleAllowedInstrRootUpdate` / `cancelAllowedInstrRootUpdate`.

### Royco Dawn (kernel / accountant / tranches / syncer / entry point)

`royco-dawn` is AM-native — every privileged selector on every dawn contract is gated by `RoycoFactory` (the AM). No native AccessControl roles to migrate. Per-target dump via `forge script script/Dump.s.sol`.

#### Markets — pausable selectors

For every market on a chain (kernel, accountant, senior tranche, junior tranche) plus the per-chain syncer plus the entry point: the `pause()` selector is bound to `ADMIN_PAUSER_ROLE`, the `unpause()` selector is bound to `ADMIN_UNPAUSER_ROLE`. The split (Immediate pause, 24h unpause) means an attacker who triggered a pause can't rush an unpause to clear their own block. See `MigrateDawn._diffUnpauseRebind` and `_pausableTargets`.

#### Entry Point — selector bindings & self-grants

The Royco Entry Point handles asynchronous deposit / redemption flows on top of the tranches. One per chain (Ethereum / Avalanche / Arbitrum) — same address on every chain via CREATE3: `0x63dA1229be88Fb4D20210147954a1a3e05f2581B`. The migration mirrors the role config originally applied by `lib/royco-dawn/script/independent/DeployEntryPoint.s.sol:128-173`.

**Selector → role bindings on the entry point target:**

| Function | Role | Effective Delay | Why |
|---|---|---|---|
| `requestDeposit`, `executeDeposit`, `executeDeposits`, `cancelDepositRequest`, `cancelDepositRequests`, `requestRedemption`, `executeRedemption`, `executeRedemptions`, `cancelRedemptionRequest`, `cancelRedemptionRequests` | `PUBLIC_ROLE` | Immediate | LP ops — open at AM; tranches still gate on `ST_LP_ROLE` / `JT_LP_ROLE` |
| `modifyTrancheConfigs` | `ADMIN_ENTRY_POINT_ROLE` | Critical 48h (FNDN) | Per-tranche entry-point params |
| `collectProtocolFees` | `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | Immediate (FNDN) | Fee collection |
| `pause` | `ADMIN_PAUSER_ROLE` | Immediate (FNDN, WAY) | Protocol-wide pause |
| `unpause` | `ADMIN_UNPAUSER_ROLE` | Standard 24h (FNDN) | Protocol-wide unpause — can't rush an unpause to clear an attacker's pause |
| `upgradeToAndCall` | `ADMIN_UPGRADER_ROLE` | Critical 48h (FNDN) | UUPS impl upgrade |

**Self-grants on the entry point contract** — the entry point itself holds these so it can call into the tranches when relaying user ops:

| Role | Holder | Delay |
|---|---|---|
| `ST_LP_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |
| `JT_LP_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |
| `BURNER_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |

`ST_LP_ROLE` / `JT_LP_ROLE` let the entry point call `deposit` / `redeem` on the senior / junior tranche; `BURNER_ROLE` is required for the yield-forfeiture path on redemption.

---

## 3. Out-of-scope authorities

These exist and matter, but Royco doesn't control them today and they're not part of the migration.

| Authority | Where | Holder | What it gates | Notes |
|---|---|---|---|---|
| ConcreteFactory `Ownable` owner | `lib/concrete-earn-v2-bug-bounty/src/factory/ConcreteFactory.sol:41` | Concrete | `approveImplementation`, `blockImplementation`, `registerVault`, `_authorizeUpgrade` (UUPS), `updateManagementFeeRecipient` / `updatePerformanceFeeRecipient` | Outside Royco's authority surface. |
| Vault whitelist hook contract owner | per-vault hook contract | Concrete / vault deployer | Whitelist additions/removals | Out of scope; only the vault's `HOOK_MANAGER` (gates `setHooks` on the vault) is migrated. |
| Makina core AM | Makina governance contract | Makina | `setRiskManagerTimelock`, `setMechanic`, `setSecurityCouncil`, `setRiskManager`, `addInstrRootGuardian`, etc. on every Caliber and Machine | Required for two prerequisites (re-pointing `riskManagerTimelock` to RoycoFactory; adding WAY as `instrRootGuardian`) — tracked as a separate workstream. |
| Securitize transfer agent | held via `TRANSFER_AGENT_ROLE` on AM | Securitize | Transfer-restriction logic per Securitize's compliance model | AM-tracked but doesn't fit Royco's delay tiers. |

---
