// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Multisigs
 * @notice Per-party multisig addresses used by the security model. Same on every chain.
 *
 * - **FNDN** (Royco Foundation) — root admin / executor. Holds privileged roles across all
 *   surfaces. Same address as the legacy `ROOT_MULTISIG`.
 * - **WAY** — proposer + guardian. Holds `GUARDIAN_ROLE` (cancel/veto) and the immediate-delay
 *   variant of `ADMIN_ENTRY_POINT_ROLE`. Same address as the legacy `EXECUTOR_MULTISIG` /
 *   `WCE_MULTISIG`.
 * - **DIAL** — operations role-holder for the strategy `STRATEGY_ALLOCATOR` (and natively for
 *   the vault's `ALLOCATOR` / `WITHDRAWAL_MANAGER`, which stay native and are not remapped).
 */
abstract contract Multisigs is Factory {
    /// @dev FNDN multisig (root admin / executor)
    address internal constant FNDN = 0x7c405bbD131e42af506d14e752f2e59B19D49997;

    /// @dev WAY multisig (proposer + guardian). Same address as the legacy EXECUTOR/WCE multisig.
    address internal constant WAY = 0x84d37A25e46029CE161111420E07cEb78880119e;

    /// @dev DIAL multisig (strategy allocator).
    address internal constant DIAL = 0xe7E4FA51280eB212254458d62081587Acd2077eE;
}
