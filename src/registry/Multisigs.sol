// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Multisigs
 * @notice Per-party multisig addresses used by the security model. Same on every chain.
 *
 * - **FNDN** (Royco Foundation) — `ADMIN_ROLE` (7d, role management), `GUARDIAN_ROLE` (cancel
 *   authority), `ADMIN_UNPAUSER_ROLE` and `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` (Immediate),
 *   `STRATEGY_UNPAUSER` / `STRATEGY_RESCUE`, `DEPLOYER_ROLE`. Same address as the legacy
 *   `ROOT_MULTISIG`.
 * - **WAY** — every parameter-update role: `ADMIN_PAUSER_ROLE`, `LP_ROLE_ADMIN_ROLE`, `SYNC_ROLE`
 *   (Immediate); `ADMIN_ORACLE_QUOTER_ROLE`, `DEPLOYER_ROLE_ADMIN_ROLE` (24h);
 *   `ADMIN_KERNEL_ROLE`, `ADMIN_ACCOUNTANT_ROLE`, `ADMIN_PROTOCOL_FEE_SETTER_ROLE`,
 *   `ADMIN_ENTRY_POINT_ROLE`, `VAULT_MANAGER` / `STRATEGY_MANAGER` / `HOOK_MANAGER`, per-vault
 *   `*_RISK_MANAGER` / `*_TIMELOCK_MANAGER` (48h); `ADMIN_UPGRADER_ROLE` (7d). Every delayed
 *   WAY op is FNDN-cancellable via `GUARDIAN_ROLE`. Same address as the legacy
 *   `EXECUTOR_MULTISIG` / `WCE_MULTISIG`.
 * - **DIAL** — operations role-holder for `STRATEGY_ALLOCATOR` (and natively for the vault's
 *   `ALLOCATOR` / `WITHDRAWAL_MANAGER`, which stay native and are not remapped).
 */
abstract contract Multisigs is Factory {
    /// @dev FNDN multisig (root admin / executor)
    address internal constant FNDN = 0x7c405bbD131e42af506d14e752f2e59B19D49997;

    /// @dev WAY multisig (proposer + guardian). Same address as the legacy EXECUTOR/WCE multisig.
    address internal constant WAY = 0x84d37A25e46029CE161111420E07cEb78880119e;

    /// @dev DIAL multisig (strategy allocator).
    address internal constant DIAL = 0xe7E4FA51280eB212254458d62081587Acd2077eE;
}
