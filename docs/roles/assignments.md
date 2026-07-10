# Roles registry

Single inventory of every role / governance slot across every contract Royco controls or depends on. Source of truth for the design model is the migration scripts (`script/migrate/*.s.sol`); this doc enumerates the surface.

Three categories:

1. **AccessManager roles** — held in `RoycoFactory` (the OZ `AccessManager` instance). Single control plane for everything Royco manages.
2. **Native role-like state on contracts** — `AccessControl` roles, `Ownable` owners, ad-hoc role slots — held on the contract itself. After migration most of these are granted to the AccessManager and revoked from prior holders, so authority routes through #1.
3. **Out-of-band Makina governance slots** — address slots on Caliber / Machine that Royco depends on but cannot configure from this repo (changes require Makina governance).

Every table uses the same column structure: **Role | Admin / Setter | Guardian / Vetoable by | Holder | Delay | Description**. `—` means not applicable.

---

## Multisigs

| Multisig | Address | Purpose |
|---|---|---|
| **FNDN** (Royco Foundation) | `0x7c405bbD131e42af506d14e752f2e59B19D49997` | Root owner (`ADMIN_ROLE` @ 72h). Does not routinely transact; steps in only for role management, unpause, and fee collection. Co-holds guardian/cancel authority with FNDN_VETO. Same on every chain. |
| **WAY** | `0x84d37A25e46029CE161111420E07cEb78880119e` | Parameter-update authority. Schedules all delayed parameter ops (72h). No longer holds pause (moved to WAY_PAUSE). Same on every chain. |
| **DIAL** | `0xe7E4FA51280eB212254458d62081587Acd2077eE` | Strategy allocator (operations). |
| **WAY_PAUSE** (1/4) | `0xC7605B1891B449B0051d55D083B49D6b46D164bb` | Dedicated fast-response pause multisig. Sole holder of `ADMIN_PAUSER_ROLE` and `STRATEGY_PAUSER`; can pause every protocol contract at 0 delay. |
| **FNDN_VETO** (1/4) | `0xc5Df006FA0647EFF1A55CCF5749ce17772F4d8CB` | Dedicated fast-response veto multisig. Co-holds `GUARDIAN_ROLE` with FNDN; can cancel any WAY-scheduled op at 0 delay. |

Source: `src/registry/Multisigs.sol`.

---

## 1. AccessManager roles (RoycoFactory)

`RoycoFactory` = `0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C` (CREATE2; same on Mainnet / Avalanche / Arbitrum). Base has its own factory at `0x568c9709DaA2f7B7cc66AbC3E41DA0f0A339551A` — resolve via `Factory.roycoFactory(chainId)`. Role IDs are `uint64(keccak256(abi.encode(<tag>)))`. Defined in `src/registry/Roles.sol`.

### Built-ins

| Role | Admin / Setter | Guardian / Vetoable by | Holder | Delay | Description |
|---|---|---|---|---|---|
| `ADMIN_ROLE` (id 0) | self | self | FNDN | 72h | OZ AM root admin. Hardcoded gate for `setRoleAdmin`, `setRoleGuardian`, `setGrantDelay`, `setTargetAdminDelay`, `setTargetClosed`, `setTargetFunctionRole`, `updateAuthority`, `labelRole`. Default admin of every other role (gates `grantRole`/`revokeRole`). FNDN-only; not cancellable by any other party. |
| `PUBLIC_ROLE` (id `type(uint64).max`) | — | — | every address (auto) | — | Open role. Bound to the EntryPoint LP selectors (`requestDeposit`, `executeDeposit(s)`, `cancelDepositRequest(s)`, `requestRedemption`, `executeRedemption(s)`, `cancelRedemptionRequest(s)`) **and to `deposit` on every senior/junior tranche** — deposits are open to anyone. Tranche `redeem` remains gated by `ST_LP_ROLE` / `JT_LP_ROLE`. |

### Royco-defined roles

| Role | Admin / Setter | Guardian / Vetoable by | Holder | Delay | Description |
|---|---|---|---|---|---|
| **Pause / upgrade** | | | | | |
| `ADMIN_PAUSER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY_PAUSE | Immediate | Pause every protocol contract. Immediate so incident response isn't blocked. Held by the dedicated 1/4 WAY_PAUSE multisig. |
| `ADMIN_UNPAUSER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate | Unpause every protocol contract. Split from pause so only FNDN can clear an attacker-triggered pause. |
| `ADMIN_UPGRADER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | UUPS implementation upgrades. |
| **LP / accounting** | | | | | |
| `ST_LP_ROLE` | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | EntryPoint, LPs | Immediate | Senior tranche `redeem` (deposits are open — `deposit` is bound to `PUBLIC_ROLE`). |
| `JT_LP_ROLE` | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | EntryPoint, LPs | Immediate | Junior tranche `redeem` (deposits are open — `deposit` is bound to `PUBLIC_ROLE`). |
| `BURNER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | EntryPoint | Immediate | Yield-forfeiture (`burn`/`burnFrom` on tranches) during redemption. |
| `LP_ROLE_ADMIN_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | Immediate | Grants/revokes `ST_LP_ROLE` / `JT_LP_ROLE` to LPs. |
| `SYNC_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | Immediate | Triggers accounting sync on the kernel. |
| **Config admins** | | | | | |
| `ADMIN_KERNEL_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | Kernel admin: `setProtocolFeeRecipient`, `setSeniorTrancheSelfLiquidationBonus`. |
| `ADMIN_ACCOUNTANT_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | Accountant params: YDM, coverage, beta, LLTV, dust tolerances, fixed-term. |
| `ADMIN_PROTOCOL_FEE_SETTER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | Protocol fee % on senior / junior tranche yields. |
| `ADMIN_ORACLE_QUOTER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY, FNDN | 72h (WAY) / Immediate (FNDN) | Oracle / quoter settings: `setConversionRate`, `setChainlinkOracle`. WAY does routine quoter changes under 72h delay (FNDN-cancellable); FNDN can act immediately for emergency oracle re-pegs (e.g. depeg / Chainlink feed swap during incident response). |
| **Entry point** | | | | | |
| `ADMIN_ENTRY_POINT_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | `modifyTrancheConfigs`. |
| `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate | `collectProtocolFees`. |
| **Deployment / guardian / transfer agent** | | | | | |
| `DEPLOYER_ROLE` | `DEPLOYER_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate | Deploys new Royco markets via factory. |
| `DEPLOYER_ROLE_ADMIN_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | Grants/revokes `DEPLOYER_ROLE`. |
| `GUARDIAN_ROLE` | `ADMIN_ROLE` | `ADMIN_ROLE` | FNDN, FNDN_VETO | Immediate | Cancels delayed operations on every operational role. Co-held: FNDN (root, rarely steps in) + FNDN_VETO (dedicated 1/4 fast-veto multisig). |
| `TRANSFER_AGENT_ROLE` | `ADMIN_ROLE` | `ADMIN_ROLE` | Securitize | TBD | Tranche seizure / kernel blacklist. Outside the standard delay tiers. |
| **Concrete vaults** (Mainnet only, per concrete role) | | | | | |
| `VAULT_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | `updateManagementFee`, `updatePerformanceFee`, `setDepositLimits`, `setWithdrawLimits` on the concrete vault. |
| `STRATEGY_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | `addStrategy`, `removeStrategy`, `toggleStrategyStatus` on the concrete vault. |
| `HOOK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | `setHooks` on the concrete vault. |
| **Makina strategy adapter** (Mainnet only, per-vault) | | | | | |
| `STRATEGY_PAUSER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY_PAUSE | Immediate | Pause the strategy. Held by the dedicated 1/4 WAY_PAUSE multisig. |
| `STRATEGY_UNPAUSER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate | Unpause the strategy. |
| `STRATEGY_RESCUE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | 72h | Rescue stuck tokens from the strategy. |
| `STRATEGY_ALLOCATOR` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | DIAL | Immediate | `allocateFunds`, `deallocateFunds`. |
| **Makina/Caliber** (Mainnet only, per-vault) | | | | | |
| `SRROYUSDC_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | srRoyUSDC Caliber + Machine `onlyRiskManagerTimelock` setters (see §3 selector tables). |
| `SRROYUSDC_TIMELOCK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | srRoyUSDC Caliber `setTimelockDuration` only (the meta-timelock on `_allowedInstrRoot`'s on-chain delay). |
| `ROYWSTETH_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | roywstETH Caliber + Machine `onlyRiskManagerTimelock` setters. |
| `ROYWSTETH_TIMELOCK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | WAY | 72h | roywstETH Caliber `setTimelockDuration` only. |

---

## 2. Native role-like state on contracts

### Concrete vaults (`srRoyUSDC`, `roywstETH`)

| Native concrete role | AM role mapping | Effective holder | Effective delay | Effective guardian | Notes |
|---|---|---|---|---|---|
| `VAULT_MANAGER` | AM `VAULT_MANAGER` (see §1) | WAY | 72h | FNDN / FNDN_VETO (`GUARDIAN_ROLE`) | Primary vault management. |
| `STRATEGY_MANAGER` | AM `STRATEGY_MANAGER` | WAY | 72h | FNDN / FNDN_VETO (`GUARDIAN_ROLE`) | `addStrategy` / `removeStrategy` / `toggleStrategyStatus`. |
| `HOOK_MANAGER` | AM `HOOK_MANAGER` | WAY | 72h | FNDN / FNDN_VETO (`GUARDIAN_ROLE`) | `setHooks`. |
| `ALLOCATOR` | — (not mapped) | DIAL (native) | Immediate | — | Stays native; not gated by Royco AM. |
| `WITHDRAWAL_MANAGER` | — (not mapped) | DIAL (native) | Immediate | — | Stays native; not gated by Royco AM. |
| `VAULT_MANAGER_ADMIN` | AM `ADMIN_ROLE` (default; `vault.grantRole`/`revokeRole` not specifically bound) | FNDN | 72h | FNDN (self) | Adding/removing native role members on the vault. Falls through to `ADMIN_ROLE` so a new VAULT_MANAGER holder requires a 72h FNDN op — intentionally slow, intentionally non-cancellable by anyone but FNDN. |
| `STRATEGY_MANAGER_ADMIN` | AM `ADMIN_ROLE` (default) | FNDN | 72h | FNDN (self) | Same path. |
| `HOOK_MANAGER_ADMIN` | AM `ADMIN_ROLE` (default) | FNDN | 72h | FNDN (self) | Same path. |
| `ALLOCATOR_ADMIN` | AM `ADMIN_ROLE` (default) | FNDN | 72h | FNDN (self) | Admin slot held by AM (so no native admin can re-grant); primary role stays native. |
| `WITHDRAWAL_MANAGER_ADMIN` | AM `ADMIN_ROLE` (default) | FNDN | 72h | FNDN (self) | Same. |

---

## 3. Makina governance slots (Caliber / Machine)

Per `lib/makina-core/src/interfaces/IMakinaGovernable.sol` — **address slots, not AM roles**, set by Makina governance. Royco depends on the holders below but cannot configure them from this repo.

| Makina slot | AM role mapping | Effective holder | Effective delay | Effective guardian | Notes |
|---|---|---|---|---|---|
| `Machine.riskManager` (gates `Machine.onlyRiskManager` + `Caliber.onlyRiskManager`) | AM `<VAULT>_RISK_MANAGER` (see §1) | WAY | 72h | FNDN / FNDN_VETO (`GUARDIAN_ROLE`) | Re-pointed to RoycoFactory by Makina governance. Caliber's `onlyRiskManager` modifier delegates to this same Machine slot, so a single re-point covers both surfaces. |
| `Machine.riskManagerTimelock` (gates `Machine.onlyRiskManagerTimelock` + `Caliber.onlyRiskManagerTimelock`) | AM `<VAULT>_RISK_MANAGER` + `<VAULT>_TIMELOCK_MANAGER` (see §1) | WAY | 72h | FNDN / FNDN_VETO (`GUARDIAN_ROLE`) | Re-pointed to RoycoFactory by Makina governance. Caliber's modifier delegates to this Machine slot, so a single re-point covers both surfaces. |
| `Caliber.instrRootGuardian` (set, multi-member) | — (direct on-chain check) | FNDN | Immediate (during pending window) | — | Member added via Makina governance so FNDN can call `Caliber.cancelAllowedInstrRootUpdate` (Caliber.sol:539) during the on-chain `_allowedInstrRoot` timelock window. Not routed through Royco AM. |

### Selector-to-role bindings

Every `onlyRiskManager` / `onlyRiskManagerTimelock` setter on Caliber + Machine, with the AM role it's bound to. Applied per-vault by `MigrateMakina._buildBatch`; selector lists in `src/access/Selectors.sol :: caliberRiskManagerSelectors()` / `machineRiskManagerSelectors()`.

#### Caliber

| Selector | Original modifier | Bound AM role |
|---|---|---|
| `scheduleAllowedInstrRootUpdate(bytes32)` | `onlyRiskManager` | `<VAULT>_RISK_MANAGER` |
| `addBaseToken` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `removeBaseToken` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setPositionStaleThreshold` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxPositionIncreaseLossBps` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxPositionDecreaseLossBps` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxSwapLossBps` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setCooldownDuration` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setTimelockDuration` | `onlyRiskManagerTimelock` | `<VAULT>_TIMELOCK_MANAGER` |

#### Machine

| Selector | Original modifier | Bound AM role |
|---|---|---|
| `setShareLimit` | `onlyRiskManager` | `<VAULT>_RISK_MANAGER` |
| `setCaliberStaleThreshold` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxFixedFeeAccrualRate` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxPerfFeeAccrualRate` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setFeeMintCooldown` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxSharePriceChangeRate` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setOutTransferEnabled` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |
| `setMaxBridgeLossBps` | `onlyRiskManagerTimelock` | `<VAULT>_RISK_MANAGER` |

---

## 4. Out-of-scope authorities

Authorities Royco doesn't control today and aren't part of any migration here.

| Authority | Where | Holder | What it gates | Notes |
|---|---|---|---|---|
| ConcreteFactory `Ownable` owner | `lib/concrete-earn-v2-bug-bounty/src/factory/ConcreteFactory.sol:41` | Concrete | `approveImplementation`, `blockImplementation`, `registerVault`, `_authorizeUpgrade` (UUPS), `updateManagementFeeRecipient` / `updatePerformanceFeeRecipient` | Outside Royco's authority surface. |
| Vault whitelist hook contract owner | per-vault hook contract | Concrete / vault deployer | Whitelist additions / removals | Out of scope; only the vault's `HOOK_MANAGER` is migrated. |
| Securitize transfer agent | held via `TRANSFER_AGENT_ROLE` on AM | Securitize | Transfer-restriction logic per Securitize's compliance model | AM-tracked but doesn't fit Royco's delay tiers. |

---

## Quick lookup

- Full AM dump: `forge script script/Dump.s.sol --sig "run()"` or `dump(uint256 chainId)`.
- Native vault role enumeration: `script/migrate/Vaults.s.sol :: _buildPhase1Native` reads `getRoleMember*` at run time; produced JSON shows current vs. desired holders.
- Caliber/Machine governance slots: read directly via `IMakinaGovernable.{mechanic,securityCouncil,riskManager,riskManagerTimelock}` and `ICaliber.isInstrRootGuardian(address)`.
