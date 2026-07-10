# Roles → capabilities

Every privileged selector each role can call, exhaustively. Companion to [`assignments.md`](./assignments.md) (which says *who* holds each role) — this doc says *what* each role can do.

Conventions:
- "per market" = once per market on each chain (kernel, accountant, senior tranche, junior tranche).
- "per vault" = once per concrete vault on Mainnet (`srRoyUSDC`, `roywstETH`).
- "AM" = `RoycoFactory` (the OpenZeppelin AccessManager).
- Functions on the AM itself (e.g. `setRoleAdmin`) are listed under `ADMIN_ROLE`.
- Selectors not bound to a specific role default to `ADMIN_ROLE` (FNDN @ 72h).

---

## Built-ins

### `ADMIN_ROLE` (id 0)

Hardcoded in OZ AM (`AccessManager._getAdminRestrictions`). Required to call:

| Target | Selector | Notes |
|---|---|---|
| AM (RoycoFactory) | `labelRole` | Re-label any role. |
| AM | `setRoleAdmin` | Change which role gates `grantRole`/`revokeRole` for a given role. |
| AM | `setRoleGuardian` | Change which role can `cancel` a delayed op. |
| AM | `setGrantDelay` | Change the grant delay (separate from execution delay) on a role. |
| AM | `setTargetAdminDelay` | Change the admin-side delay for `setTargetFunctionRole` / `setTargetClosed` / `updateAuthority` against a specific target. |
| AM | `setTargetClosed` | Disable all AM gating for a target (closes it). |
| AM | `setTargetFunctionRole` | Bind a (target, selector) pair to a specific role. |
| AM | `updateAuthority` | Change a target's `IAuthority`. |
| AM | `grantRole(R, …)` | If `getRoleAdmin(R) == ADMIN_ROLE` (i.e. every role except `ST_LP_ROLE` / `JT_LP_ROLE` / `DEPLOYER_ROLE`). |
| AM | `revokeRole(R, …)` | Same coverage as `grantRole`. |
| AM (via `restricted`) | `upgradeToAndCall` (UUPS) | RoycoFactory itself is UUPS — gated by ADMIN_ROLE per the OZ AM defaults. |
| Concrete vault (per vault) | `grantRole`, `revokeRole` | Native AccessControl `grantRole`/`revokeRole` not bound to a more specific role; falls through to AM `ADMIN_ROLE`. |

### `PUBLIC_ROLE` (`type(uint64).max`)

| Target | Selector | Notes |
|---|---|---|
| EntryPoint | `requestDeposit`, `executeDeposit`, `executeDeposits`, `cancelDepositRequest`, `cancelDepositRequests`, `requestRedemption`, `executeRedemption`, `executeRedemptions`, `cancelRedemptionRequest`, `cancelRedemptionRequests` | LP user-facing flow. Tranche `deposit` is open (`PUBLIC_ROLE`); tranche `redeem` is gated at the tranche layer (`ST_LP_ROLE` / `JT_LP_ROLE`). |
| Tranches (per market) | `deposit` (senior + junior) | Deposits are open to anyone — `deposit` on every senior/junior tranche is bound to `PUBLIC_ROLE`. |

---

## Pause / upgrade

### `ADMIN_PAUSER_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `pause` |
| Accountant (per market) | `pause` |
| Senior tranche (per market) | `pause` |
| Junior tranche (per market) | `pause` |
| Syncer (per chain) | `pause` |
| EntryPoint | `pause` |

### `ADMIN_UNPAUSER_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `unpause` |
| Accountant (per market) | `unpause` |
| Senior tranche (per market) | `unpause` |
| Junior tranche (per market) | `unpause` |
| Syncer (per chain) | `unpause` |
| EntryPoint | `unpause` |

### `ADMIN_UPGRADER_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `upgradeToAndCall` (UUPS) |
| Accountant (per market) | `upgradeToAndCall` (UUPS) |
| Senior tranche (per market) | `upgradeToAndCall` (UUPS) |
| Junior tranche (per market) | `upgradeToAndCall` (UUPS) |
| Syncer (per chain) | `upgradeToAndCall` (UUPS) |
| EntryPoint | `upgradeToAndCall` (UUPS) |

---

## LP / accounting

Note: `deposit` on every tranche is bound to `PUBLIC_ROLE` (deposits are open to anyone); only
`redeem` is gated per-tranche by `ST_LP_ROLE` / `JT_LP_ROLE`.

### `ST_LP_ROLE`

| Target | Selector |
|---|---|
| Senior tranche (per market) | `redeem` |

### `JT_LP_ROLE`

| Target | Selector |
|---|---|
| Junior tranche (per market) | `redeem` |

### `BURNER_ROLE`

| Target | Selector |
|---|---|
| Senior tranche (per market) | `burn` |
| Senior tranche (per market) | `burnFrom` |
| Junior tranche (per market) | `burn` |
| Junior tranche (per market) | `burnFrom` |

### `LP_ROLE_ADMIN_ROLE`

| Target | Selector | Notes |
|---|---|---|
| AM | `grantRole(ST_LP_ROLE, …)` | `getRoleAdmin(ST_LP_ROLE) == LP_ROLE_ADMIN_ROLE`. |
| AM | `grantRole(JT_LP_ROLE, …)` | `getRoleAdmin(JT_LP_ROLE) == LP_ROLE_ADMIN_ROLE`. |
| AM | `revokeRole(ST_LP_ROLE, …)` / `revokeRole(JT_LP_ROLE, …)` | Same. |

### `SYNC_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `syncTrancheAccounting` |
| Syncer (per chain) | `executeBatchAccountingSync` |
| Syncer (per chain) | `executeBatchAccountingSyncFor` |
| Syncer (per chain) | `addMarketKernels` |
| Syncer (per chain) | `removeMarketKernels` |

---

## Config admins

### `ADMIN_KERNEL_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `setProtocolFeeRecipient` |
| Kernel (per market) | `setSeniorTrancheSelfLiquidationBonus` |

### `ADMIN_ACCOUNTANT_ROLE`

| Target | Selector |
|---|---|
| Accountant (per market) | `setYDM` |
| Accountant (per market) | `setCoverage` |
| Accountant (per market) | `setBeta` |
| Accountant (per market) | `setLiquidationUtilization` |
| Accountant (per market) | `setFixedTermDuration` |
| Accountant (per market) | `setSeniorTrancheDustTolerance` |
| Accountant (per market) | `setJuniorTrancheDustTolerance` |
| Accountant (per market) | `setCoverageConfiguration` |

### `ADMIN_PROTOCOL_FEE_SETTER_ROLE`

| Target | Selector |
|---|---|
| Accountant (per market) | `setSeniorTrancheProtocolFee` |
| Accountant (per market) | `setJuniorTrancheProtocolFee` |
| Accountant (per market) | `setYieldShareProtocolFee` |

### `ADMIN_ORACLE_QUOTER_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `setConversionRate` |
| Kernel (per market) | `setChainlinkOracle` |

---

## Entry point

### `ADMIN_ENTRY_POINT_ROLE`

| Target | Selector |
|---|---|
| EntryPoint | `modifyTrancheConfigs` |

### `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`

| Target | Selector |
|---|---|
| EntryPoint | `collectProtocolFees` |

---

## Deployment / guardian / transfer agent

### `DEPLOYER_ROLE`

| Target | Selector |
|---|---|
| AM (RoycoFactory) | `deployMarket` |

### `DEPLOYER_ROLE_ADMIN_ROLE`

| Target | Selector | Notes |
|---|---|---|
| AM | `grantRole(DEPLOYER_ROLE, …)` | `getRoleAdmin(DEPLOYER_ROLE) == DEPLOYER_ROLE_ADMIN_ROLE`. |
| AM | `revokeRole(DEPLOYER_ROLE, …)` | Same. |

### `GUARDIAN_ROLE`

| Target | Selector | Notes |
|---|---|---|
| AM | `cancel(caller, target, data)` | Can cancel any scheduled op whose `getRoleGuardian(getTargetFunctionRole(target, selector)) == GUARDIAN_ROLE`. In practice: every WAY-scheduled op. Co-held by FNDN (root) and FNDN_VETO (dedicated 1/4 fast-veto multisig). |

### `TRANSFER_AGENT_ROLE`

| Target | Selector |
|---|---|
| Kernel (per market) | `blacklistAccounts` |
| Kernel (per market) | `unblacklistAccounts` |
| Kernel (per market) | `setBlacklistStatus` |
| Senior tranche (per market) | `seizeShares` |
| Senior tranche (per market) | `seizeAndRedeemShares` |
| Junior tranche (per market) | `seizeShares` |
| Junior tranche (per market) | `seizeAndRedeemShares` |

---

## Concrete vaults (Mainnet only)

### `VAULT_MANAGER`

| Target | Selector |
|---|---|
| Concrete vault (per vault) | `updateManagementFee` |
| Concrete vault (per vault) | `updatePerformanceFee` |
| Concrete vault (per vault) | `setDepositLimits` |
| Concrete vault (per vault) | `setWithdrawLimits` |

### `STRATEGY_MANAGER`

| Target | Selector |
|---|---|
| Concrete vault (per vault) | `addStrategy` |
| Concrete vault (per vault) | `removeStrategy` |
| Concrete vault (per vault) | `toggleStrategyStatus` |

### `HOOK_MANAGER`

| Target | Selector |
|---|---|
| Concrete vault (per vault) | `setHooks` |

---

## Makina strategy adapter (Mainnet only, per-vault)

### `STRATEGY_PAUSER`

| Target | Selector |
|---|---|
| Strategy adapter (per vault) | `pause` |

### `STRATEGY_UNPAUSER`

| Target | Selector |
|---|---|
| Strategy adapter (per vault) | `unpause` |

### `STRATEGY_RESCUE`

| Target | Selector |
|---|---|
| Strategy adapter (per vault) | `rescueToken` |

### `STRATEGY_ALLOCATOR`

| Target | Selector |
|---|---|
| Strategy adapter (per vault) | `allocateFunds` |
| Strategy adapter (per vault) | `deallocateFunds` |

---

## Makina/Caliber (Mainnet only, per-vault)

### `<VAULT>_RISK_MANAGER`

| Target | Selector | Original modifier |
|---|---|---|
| Caliber (per vault) | `scheduleAllowedInstrRootUpdate(bytes32)` | `onlyRiskManager` |
| Caliber (per vault) | `addBaseToken` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `removeBaseToken` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `setPositionStaleThreshold` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `setMaxPositionIncreaseLossBps` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `setMaxPositionDecreaseLossBps` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `setMaxSwapLossBps` | `onlyRiskManagerTimelock` |
| Caliber (per vault) | `setCooldownDuration` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setShareLimit` | `onlyRiskManager` |
| Machine (per vault) | `setCaliberStaleThreshold` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setMaxFixedFeeAccrualRate` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setMaxPerfFeeAccrualRate` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setFeeMintCooldown` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setMaxSharePriceChangeRate` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setOutTransferEnabled` | `onlyRiskManagerTimelock` |
| Machine (per vault) | `setMaxBridgeLossBps` | `onlyRiskManagerTimelock` |

### `<VAULT>_TIMELOCK_MANAGER`

| Target | Selector | Original modifier |
|---|---|---|
| Caliber (per vault) | `setTimelockDuration` | `onlyRiskManagerTimelock` |

---

## Out-of-band Makina governance (not Royco-AM-routed)

### `Caliber.instrRootGuardian` set member

| Target | Selector |
|---|---|
| Caliber (per vault) | `cancelAllowedInstrRootUpdate` |

Held directly on the Caliber (added via `Caliber.addInstrRootGuardian` by Makina governance, not by Royco). FNDN added so it can veto a pending allowed-instruction-root update during the on-chain `_allowedInstrRoot` timelock window.

---

## Native concrete vault roles (held by AM after migration)

For completeness — these are native AccessControl roles on the vault contract. After Phase 1 of the Vaults migration, only `RoycoFactory` (AM) holds them. Effective authority routes through the AM roles above (`VAULT_MANAGER` / `STRATEGY_MANAGER` / `HOOK_MANAGER`).

| Native role | Gates (on the vault) | Effective AM role |
|---|---|---|
| `VAULT_MANAGER` | `updateManagementFee`, `updatePerformanceFee`, `setDepositLimits`, `setWithdrawLimits` | AM `VAULT_MANAGER` |
| `STRATEGY_MANAGER` | `addStrategy`, `removeStrategy`, `toggleStrategyStatus` | AM `STRATEGY_MANAGER` |
| `HOOK_MANAGER` | `setHooks` | AM `HOOK_MANAGER` |
| `VAULT_MANAGER_ADMIN` | `vault.grantRole(VAULT_MANAGER, …)`, `vault.revokeRole(VAULT_MANAGER, …)` | AM `ADMIN_ROLE` (default) |
| `STRATEGY_MANAGER_ADMIN` | `vault.grantRole(STRATEGY_MANAGER, …)`, `vault.revokeRole(STRATEGY_MANAGER, …)` | AM `ADMIN_ROLE` (default) |
| `HOOK_MANAGER_ADMIN` | `vault.grantRole(HOOK_MANAGER, …)`, `vault.revokeRole(HOOK_MANAGER, …)` | AM `ADMIN_ROLE` (default) |
| `ALLOCATOR` | Allocate/withdraw operational paths on the vault | — (held natively by DIAL, not AM) |
| `WITHDRAWAL_MANAGER` | Withdrawal operational paths on the vault | — (held natively by DIAL, not AM) |
| `ALLOCATOR_ADMIN` | `vault.grantRole(ALLOCATOR, …)`, `vault.revokeRole(ALLOCATOR, …)` | AM `ADMIN_ROLE` (default) |
| `WITHDRAWAL_MANAGER_ADMIN` | `vault.grantRole(WITHDRAWAL_MANAGER, …)`, `vault.revokeRole(WITHDRAWAL_MANAGER, …)` | AM `ADMIN_ROLE` (default) |
