// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Multisigs
 * @notice Per-party multisig addresses used by the security model. Same on every chain.
 *
 * - **FNDN** (Royco Foundation) — root owner: `ADMIN_ROLE` (7d, role management); rarely
 *   transacts. Also `ADMIN_UNPAUSER_ROLE`, `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`,
 *   `ADMIN_ORACLE_QUOTER_ROLE` (all Immediate; quoter co-held with WAY for emergency
 *   oracle re-pegs), `STRATEGY_UNPAUSER` / `STRATEGY_RESCUE`, `DEPLOYER_ROLE`. Co-holds
 *   `GUARDIAN_ROLE` with FNDN_VETO. Same address as the legacy `ROOT_MULTISIG`.
 * - **WAY** — every parameter-update role: `LP_ROLE_ADMIN_ROLE`, `SYNC_ROLE` (Immediate);
 *   `DEPLOYER_ROLE_ADMIN_ROLE`, `ADMIN_KERNEL_ROLE`, `ADMIN_ACCOUNTANT_ROLE`,
 *   `ADMIN_PROTOCOL_FEE_SETTER_ROLE`, `ADMIN_ORACLE_QUOTER_ROLE`, `ADMIN_ENTRY_POINT_ROLE`,
 *   `VAULT_MANAGER` / `STRATEGY_MANAGER` / `HOOK_MANAGER`, per-vault `*_RISK_MANAGER` /
 *   `*_TIMELOCK_MANAGER` (all 60h); `ADMIN_UPGRADER_ROLE` (7d). Schedules all delayed ops;
 *   each is cancellable via `GUARDIAN_ROLE`. No longer holds pause (moved to WAY_PAUSE).
 *   Same address as the legacy `EXECUTOR_MULTISIG` / `WCE_MULTISIG`.
 * - **WAY_PAUSE** (undeployed, 1/4) — sole holder of `ADMIN_PAUSER_ROLE` and `STRATEGY_PAUSER`
 *   (Immediate). Dedicated fast-response pause multisig; can pause every protocol contract.
 * - **FNDN_VETO** (undeployed, 1/4) — co-holds `GUARDIAN_ROLE` with FNDN (Immediate).
 *   Dedicated fast-response veto multisig; can cancel any WAY-scheduled op.
 * - **DIAL** — operations role-holder for `STRATEGY_ALLOCATOR` (and natively for the vault's
 *   `ALLOCATOR` / `WITHDRAWAL_MANAGER`, which stay native and are not remapped).
 */
abstract contract Multisigs is Factory {
    /// @dev FNDN multisig (root admin / executor)
    address internal constant FNDN = 0x7c405bbD131e42af506d14e752f2e59B19D49997;

    /// @dev WAY multisig (proposer). Same address as the legacy EXECUTOR/WCE multisig.
    address internal constant WAY = 0x84d37A25e46029CE161111420E07cEb78880119e;

    /// @dev DIAL multisig (strategy allocator).
    address internal constant DIAL = 0xe7E4FA51280eB212254458d62081587Acd2077eE;

    // ─────────────────────────────────────────────────────────────────────────
    // Emergency fast-response multisigs (1/4 each) — UNDEPLOYED PLACEHOLDERS
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev WAY_PAUSE multisig (1/4): sole holder of ADMIN_PAUSER_ROLE + STRATEGY_PAUSER.
    ///      Deliberately-fake sentinel. TODO(deploy): set real address + flip MULTISIGS_DEPLOYED.
    address internal constant WAY_PAUSE = address(uint160(0xDEAD0001));

    /// @dev FNDN_VETO multisig (1/4): co-holds GUARDIAN_ROLE with FNDN.
    ///      Deliberately-fake sentinel. TODO(deploy): set real address + flip MULTISIGS_DEPLOYED.
    address internal constant FNDN_VETO = address(uint160(0xDEAD0002));

    /// @dev Flip to true once WAY_PAUSE / FNDN_VETO hold their real deployed addresses. The
    ///      production `run()` paths revert while this is false (see `_assertProductionMultisigs`);
    ///      the test `applyToFork` path does not call the guard, so tests run with placeholders.
    bool internal constant MULTISIGS_DEPLOYED = false;

    error MultisigsNotDeployed();

    /// @dev Guard against generating real Safe JSON while the emergency multisigs are still
    ///      placeholders. Call first in every production `run()`; never in `applyToFork`.
    function _assertProductionMultisigs() internal pure {
        if (!MULTISIGS_DEPLOYED) revert MultisigsNotDeployed();
    }
}
