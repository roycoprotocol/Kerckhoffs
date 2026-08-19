// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Multisigs
 * @notice Per-party multisig addresses used by the security model. Same on every chain.
 *
 * - **FNDN** (Royco Foundation) — root owner: `ADMIN_ROLE` (72h, role management); rarely
 *   transacts. Also `ADMIN_UNPAUSER_ROLE`, `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`,
 *   `ADMIN_ORACLE_QUOTER_ROLE` (all Immediate; quoter co-held with WAY for emergency
 *   oracle re-pegs), `STRATEGY_UNPAUSER` / `STRATEGY_RESCUE`, `DEPLOYER_ROLE`. Co-holds
 *   `GUARDIAN_ROLE` with FNDN_VETO. Same address as the legacy `ROOT_MULTISIG`.
 * - **WAY** — every parameter-update role: `LP_ROLE_ADMIN_ROLE`, `SYNC_ROLE` (Immediate);
 *   `DEPLOYER_ROLE_ADMIN_ROLE`, `ADMIN_KERNEL_ROLE`, `ADMIN_ACCOUNTANT_ROLE`,
 *   `ADMIN_PROTOCOL_FEE_SETTER_ROLE`, `ADMIN_ORACLE_QUOTER_ROLE`,
 *   `VAULT_MANAGER` / `STRATEGY_MANAGER` / `HOOK_MANAGER`, per-vault `*_RISK_MANAGER` /
 *   `*_TIMELOCK_MANAGER` (all 72h); `ADMIN_ENTRY_POINT_ROLE` (24h); `ADMIN_UPGRADER_ROLE` (72h).
 *   Schedules all delayed ops;
 *   each is cancellable via `GUARDIAN_ROLE`. No longer holds pause (moved to WAY_PAUSE).
 *   Same address as the legacy `EXECUTOR_MULTISIG` / `WCE_MULTISIG`.
 * - **WAY_PAUSE** (1/4) — sole holder of `ADMIN_PAUSER_ROLE` and `STRATEGY_PAUSER`
 *   (Immediate). Dedicated fast-response pause multisig; can pause every protocol contract.
 * - **FNDN_VETO** (1/4) — co-holds `GUARDIAN_ROLE` with FNDN (Immediate).
 *   Dedicated fast-response veto multisig; can cancel any WAY-scheduled op.
 * - **DIAL** — operations role-holder for `STRATEGY_ALLOCATOR` (and natively for the vault's
 *   `ALLOCATOR` / `WITHDRAWAL_MANAGER`, which stay native and are not remapped).
 * - **AUTO** (Autonomous) — contracted service provider. Co-holds `LP_ROLE_ADMIN_ROLE` with WAY
 *   (Immediate) so it can grant/revoke `ST_LP_ROLE` / `JT_LP_ROLE` to LPs as an operational duty.
 *   Deployed on Mainnet / Avalanche / Arbitrum only (not Base). The Dawn migration intentionally
 *   does NOT revoke it — it is an expected holder, not stale state.
 */
abstract contract Multisigs is Factory {
    /// @dev FNDN multisig (root admin / executor)
    address internal constant FNDN = 0x7c405bbD131e42af506d14e752f2e59B19D49997;

    /// @dev WAY multisig (proposer). Same address as the legacy EXECUTOR/WCE multisig.
    address internal constant WAY = 0x84d37A25e46029CE161111420E07cEb78880119e;

    /// @dev DIAL multisig (strategy allocator).
    address internal constant DIAL = 0xe7E4FA51280eB212254458d62081587Acd2077eE;

    /// @dev AUTO (Autonomous) multisig — contracted service provider; co-holds LP_ROLE_ADMIN_ROLE
    ///      with WAY (Immediate). Same address on Mainnet / Avalanche / Arbitrum; NOT on Base.
    address internal constant AUTO = 0xb2B80EBcb7EE285806ddcB26E84a444032D1c244;

    // ─────────────────────────────────────────────────────────────────────────
    // Emergency fast-response multisigs (1/4 each)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev WAY_PAUSE multisig (1/4): sole holder of ADMIN_PAUSER_ROLE + STRATEGY_PAUSER.
    address internal constant WAY_PAUSE = 0xC7605B1891B449B0051d55D083B49D6b46D164bb;

    /// @dev FNDN_VETO multisig (1/4): co-holds GUARDIAN_ROLE with FNDN.
    address internal constant FNDN_VETO = 0xc5Df006FA0647EFF1A55CCF5749ce17772F4d8CB;

    /// @dev True once WAY_PAUSE / FNDN_VETO hold their real deployed addresses. The production
    ///      `run()` paths revert while this is false (see `_assertProductionMultisigs`); the test
    ///      `applyToFork` path does not call the guard.
    bool internal constant MULTISIGS_DEPLOYED = true;

    error MultisigsNotDeployed();

    /// @dev Safety gate: reverts production Safe-JSON generation unless the emergency multisigs
    ///      are marked deployed. Call first in every production `run()`; never in `applyToFork`.
    function _assertProductionMultisigs() internal pure {
        if (!MULTISIGS_DEPLOYED) revert MultisigsNotDeployed();
    }
}
