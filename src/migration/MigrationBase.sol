// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { console2 } from "forge-std/console2.sol";

import { AccessManagerDumper } from "../access/AccessManagerDumper.sol";
import { SafeSimulator } from "../safe/SafeSimulator.sol";

/**
 * @title MigrationBase
 * @notice Standard per-chain migration flow used by every surface (Dawn, Vaults, Makina).
 *
 * For each chain in `_targetChains()`:
 *   1. Fork the chain.
 *   2. Pre-state dump (via `AccessManagerDumper.dumpAccessManager`).
 *   3. `_buildBatch(chainId)` (abstract) — builds the ordered Safe transaction list.
 *   4. `_replayBatch(_safeFor(chainId), txs)` simulates the batch on the fork.
 *   5. Warp past any grace period.
 *   6. `_assertTargetState(chainId)` (abstract) — spot-check the resulting AM state.
 *   7. Post-state dump.
 *   8. `writeSafeTransactionJson(...)` — persist the batch as a Safe Transaction Builder JSON.
 *
 * Inherits the registry, AM dumper, and Safe simulator so leaf scripts compose against a single
 * base.
 */
abstract contract MigrationBase is AccessManagerDumper, SafeSimulator {
    /// @dev Default grace-period warp after the batch executes. Mirrors
    ///      `lib/royco-dawn/script/update/access/ApplySecurityMigration.s.sol:248` (1 day + 1s)
    ///      so that any "delay reduction" grace period elapses before assertions run.
    uint256 internal constant _MIGRATION_WARP_SECONDS = 1 days + 1;

    // ═══════════════════════════════════════════════════════════════════════════
    // ABSTRACT HOOKS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns the chain IDs this migration runs against.
    function _targetChains() internal view virtual returns (uint256[] memory);

    /// @notice The Safe (executor) that will sign+submit the produced JSON. Pranked during simulation.
    function _safeFor(uint256 chainId) internal view virtual returns (address);

    /// @notice Builds the ordered Safe transaction batch for `chainId`.
    function _buildBatch(uint256 chainId) internal virtual returns (SafeTransaction[] memory);

    /// @notice Returns the output JSON path (relative to project root, no extension).
    function _outputPath(uint256 chainId) internal view virtual returns (string memory);

    /// @notice Returns (name, description) for the Safe Transaction Builder metadata.
    function _batchMeta(uint256 chainId) internal view virtual returns (string memory name, string memory description);

    /// @notice Optional simulation-only hook that runs BEFORE the Safe batch is replayed.
    ///         Use this to mock external prerequisites (e.g. governance changes outside our
    ///         control) without including them in the emitted JSON. Default: no-op.
    function _preSimulate(
        uint256 /* chainId */
    )
        internal
        virtual { }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENTRY POINT
    // ═══════════════════════════════════════════════════════════════════════════

    function run() external virtual {
        _assertProductionMultisigs();
        uint256[] memory chains = _targetChains();
        for (uint256 i = 0; i < chains.length; i++) {
            _processChain(chains[i]);
        }
    }

    function _processChain(uint256 _chainId) internal {
        vm.createSelectFork(_getRpcUrl(_chainId));

        console2.log("");
        console2.log("################################################################################");
        console2.log("Migration | chain:", _chainName(_chainId), _chainId);
        console2.log("################################################################################");

        // ── Pre-state ────────────────────────────────────────────────────────
        console2.log("");
        console2.log(">>> Pre-state");
        dumpAccessManager(_chainId);

        // ── Build batch ──────────────────────────────────────────────────────
        SafeTransaction[] memory txs = _buildBatch(_chainId);
        console2.log("");
        console2.log(">>> Built batch with", txs.length, "transactions");

        // ── Pre-simulate (out-of-band prerequisites) ────────────────────────
        _preSimulate(_chainId);

        // ── Simulate ─────────────────────────────────────────────────────────
        console2.log("");
        console2.log(">>> Simulating");
        _replayBatch(_safeFor(_chainId), txs);
        vm.warp(vm.getBlockTimestamp() + _MIGRATION_WARP_SECONDS);

        // ── Post-state ───────────────────────────────────────────────────────
        console2.log("");
        console2.log(">>> Post-state");
        dumpAccessManager(_chainId);

        // ── Write JSON ───────────────────────────────────────────────────────
        (string memory name, string memory desc) = _batchMeta(_chainId);
        string memory path = string.concat(_outputPath(_chainId), ".json");
        writeSafeTransactionJson(txs, path, name, desc);

        console2.log("");
        console2.log("  Output:", path);
        console2.log("  Done.");
    }

    /// @notice Test-only entry point: applies the migration to a forked chain without writing
    ///         JSON or dumping state. Tests forking multiple migrations chain together via this.
    function applyToFork(uint256 _chainId) public {
        if (block.chainid != _chainId) {
            vm.createSelectFork(_getRpcUrl(_chainId));
        }
        SafeTransaction[] memory txs = _buildBatch(_chainId);
        _preSimulate(_chainId);
        _replayBatch(_safeFor(_chainId), txs);
        vm.warp(vm.getBlockTimestamp() + _MIGRATION_WARP_SECONDS);
    }
}
