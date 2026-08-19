// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CaliberWiring } from "../../src/migration/CaliberWiring.sol";
import { IConcreteVault, MigrateVaults } from "./Vaults.s.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title MigrateSrRoyUSDC
 * @notice Consolidated, one-batch-per-chain migration for the `srRoyUSDC` vault. Produces exactly
 *         ONE signable Safe batch per chain the vault touches, so an operator imports a single file
 *         per chain instead of stitching the vault + Makina batches together by hand.
 *
 * Reuses the audited builders verbatim — the vault phase-1/phase-2 logic from `MigrateVaults` and
 * the Caliber logic from the shared `CaliberWiring` mixin — so every transaction here is
 * byte-identical to what the standalone `Vaults` / `Makina` scripts emit; this script only changes
 * how they are grouped and simulated (single-executor), not their content.
 *
 * Per chain:
 *   - **Hub (mainnet)** — `output/migrate/srRoyUSDC/1.json`:
 *       phase-1 native vault role migration (grant the AM every native AccessControl role, revoke
 *       the current holders) + phase-2 AM-side vault/strategy wiring + Caliber/Machine AM wiring.
 *       All three are executed by FNDN: FNDN is the sole admin of the vault's native roles
 *       (verified on-chain), and holds the AM `ADMIN_ROLE` at 0 delay, so a single Safe batch is
 *       valid. The whole batch is replayed as ONE FNDN execution in simulation — a strictly
 *       stronger check than the standalone `Vaults` script, which simulates phase-1 with a resolved
 *       native caller and never proves FNDN can run the merged batch end-to-end.
 *   - **Spokes (Arbitrum, Base)** — `output/migrate/srRoyUSDC/{42161,8453}.json`:
 *       Caliber + CaliberMailbox AM wiring only (no concrete vault or Machine on a spoke).
 *
 * The Makina-governance prerequisite (re-point both governable slots on the endpoint to
 * RoycoFactory) is simulated via `_preSimulateCaliberForVault` but, as in the standalone Makina
 * script, is deliberately NOT part of the emitted JSON — Royco cannot execute it; Makina governance
 * must. Tracked as a separate workstream.
 *
 * ── ONE-TIME USE ────────────────────────────────────────────────────────────────────────────
 * Every batch calls FNDN's ADMIN_ROLE-gated functions directly, so this must run BEFORE Dawn's
 * ADMIN_ROLE lockdown (order: Vaults/Makina/srRoyUSDC → Dawn). `_assertPreMigrationAdminState`
 * reverts (`MigrationAlreadyApplied`) if the lockdown already happened. One-shot bootstrap for the
 * current on-chain state — not a reusable tool. Run order relative to the roywstETH batches is
 * immaterial (disjoint roles, targets and holders).
 *
 * Usage:
 *   forge script script/migrate/SrRoyUSDC.s.sol            # all 3 chains
 *   forge script script/migrate/SrRoyUSDC.s.sol --sig "runChains(uint256[])" "[1]"
 */
contract MigrateSrRoyUSDC is MigrateVaults, CaliberWiring {
    string private constant _VAULT = "srRoyUSDC";

    /// @dev srRoyUSDC touches the hub (mainnet) and both spokes; roywstETH is hub-only and not
    ///      handled here.
    function _srRoyUSDCChains() internal pure returns (uint256[] memory chains) {
        chains = new uint256[](3);
        chains[0] = MAINNET;
        chains[1] = ARBITRUM;
        chains[2] = BASE;
    }

    /// @notice Generate + simulate + write one consolidated batch for every chain srRoyUSDC touches.
    function run() external override {
        _assertProductionMultisigs();
        uint256[] memory chains = _srRoyUSDCChains();
        for (uint256 i = 0; i < chains.length; i++) {
            _processChainConsolidated(chains[i]);
        }
    }

    /// @notice Generate for a caller-specified SUBSET of srRoyUSDC's chains (same guards as `run`).
    ///         Usage: `forge script ... --sig "runChains(uint256[])" "[1,8453]"`.
    function runChains(uint256[] calldata _chains) external {
        _assertProductionMultisigs();
        for (uint256 i = 0; i < _chains.length; i++) {
            _processChainConsolidated(_chains[i]);
        }
    }

    function _processChainConsolidated(uint256 _chainId) internal {
        vm.createSelectFork(_getRpcUrl(_chainId));

        // One-time-use guard: refuse to (re)generate a direct-call batch once ADMIN_ROLE is locked.
        _assertPreMigrationAdminState(_chainId);

        bool isHub = _chainId == MAINNET;

        console2.log("");
        console2.log("################################################################################");
        console2.log("srRoyUSDC migration | chain:", _chainName(_chainId), _chainId);
        console2.log("################################################################################");

        console2.log("");
        console2.log(">>> Pre-state");
        dumpAccessManager(_chainId);

        // ── Build the consolidated batch ──────────────────────────────────────
        SafeTransaction[] memory caliber = _buildCaliberForVault(_chainId, _VAULT);
        SafeTransaction[] memory batch;
        SafeTransaction[] memory phase1; // populated on the hub only, for the staged sanity sim

        if (isHub) {
            VaultAddresses memory v = getVaultAddresses(_chainId, _VAULT);
            StrategyStack memory s = getStrategyStack(_chainId, _VAULT);

            // Fail-closed linchpin: the whole batch is a SINGLE FNDN execution only because FNDN is
            // the sole admin of every native role phase-1 migrates. The merged replay below would
            // also revert on a violation, but assert it up front so the failure names the exact
            // broken invariant instead of surfacing as an opaque replay revert.
            _assertFNDNAdminsNativeRoles(v.vault);

            phase1 = _buildPhase1Native(_chainId, v.vault);
            SafeTransaction[] memory phase2 = _buildPhase2AM(_chainId, v.vault, s.strategy, _VAULT);

            SafeTransaction[][] memory parts = new SafeTransaction[][](3);
            parts[0] = phase1;
            parts[1] = phase2;
            parts[2] = caliber;
            batch = mergeBatches(parts);
        } else {
            batch = caliber;
        }
        console2.log("");
        console2.log(">>> Built consolidated batch with", batch.length, "transactions");

        // ── Makina-governance prerequisite (simulation-only; NOT emitted) ─────
        _preSimulateCaliberForVault(_chainId, _VAULT);

        // ── Simulate the ENTIRE batch as a single FNDN execution ──────────────
        // This is the claim behind "one batch per chain": FNDN is the sole admin of the vault's
        // native roles (verified on-chain) AND holds the AM ADMIN_ROLE at 0 delay, so it can run
        // phase-1 (native grant/revoke) in the same Safe batch as the AM-side phase-2 + caliber txs.
        // If that were ever false the replay would revert here and no JSON would be written.
        console2.log("");
        console2.log(">>> Simulating the consolidated batch as a single FNDN execution");
        _replayBatch(FNDN, batch);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);

        console2.log("");
        console2.log(">>> Post-state");
        dumpAccessManager(_chainId);

        // ── Write ONE JSON for this chain ─────────────────────────────────────
        string memory path = string.concat("output/migrate/srRoyUSDC/", vm.toString(_chainId), ".json");
        writeAuditableSafeTransactionJson(batch, _chainId, path, _batchName(_chainId, isHub), _batchDesc(isHub));

        console2.log("");
        console2.log("  Output:", path);
        console2.log("  Done.");

        // Silence unused-var warning on spokes (phase1 is hub-only).
        phase1;
    }

    /// @dev Enforces the invariant that makes the consolidated single-FNDN batch valid: FNDN must
    ///      be the sole/effective admin of every native role phase-1 migrates, so it can run the
    ///      native grant/revoke txs in the same Safe batch as the AM-side txs.
    function _assertFNDNAdminsNativeRoles(address _vault) internal view {
        IConcreteVault vault = IConcreteVault(_vault);
        bytes32[] memory roles = _nativeRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            require(
                vault.hasRole(vault.getRoleAdmin(roles[i]), FNDN),
                "srRoyUSDC hub: FNDN does not admin a native role being migrated; single-FNDN batch is invalid"
            );
        }
    }

    function _batchName(uint256 _chainId, bool _isHub) internal view returns (string memory) {
        return string.concat("Royco srRoyUSDC migration - ", _chainName(_chainId), _isHub ? " (hub: vault + caliber)" : " (spoke: caliber)");
    }

    /// @dev Operator-critical caveats shared by every srRoyUSDC batch. Kept in the signer-facing
    ///      meta.description so they travel into the Safe UI at signing time.
    ///        - Makina prerequisite + its CONSEQUENCE: the batch only configures the Royco AM; the
    ///          Caliber/endpoint still read `riskManager()`/`riskManagerTimelock()` directly, and
    ///          those slots currently point at FNDN. Until Makina governance re-points BOTH slots to
    ///          RoycoFactory, WAY's new roles are INERT and FNDN retains immediate, un-delayed,
    ///          un-vetoable risk-manager control — so the risk-manager migration is NOT complete on
    ///          execution. (The fork sim mocks these slots via vm.store; on-chain they are not yet
    ///          changed.) After Makina acts, verify `riskManager()==RoycoFactory` on the endpoint.
    ///        - One-time-use + order: these are direct ADMIN_ROLE calls, valid only while FNDN's AM
    ///          ADMIN_ROLE delay is 0. Import order is Vaults/Makina/srRoyUSDC BEFORE the Dawn
    ///          lockdown; after lockdown every tx here reverts. Import + execute as ONE atomic batch.
    string internal constant _CAVEATS =
        " PREREQUISITE (out-of-band, Makina governance): this batch only configures the Royco AccessManager; the Caliber/endpoint read riskManager()/riskManagerTimelock() directly and those slots currently point at FNDN. Until Makina re-points BOTH slots to RoycoFactory, WAY's risk/timelock roles are INERT and FNDN keeps immediate, un-delayed, un-vetoable risk-manager control - do NOT treat the risk-manager migration as complete on execution; afterward verify riskManager()==RoycoFactory on the endpoint. ONE-TIME USE: direct ADMIN_ROLE calls, valid only while FNDN's AM ADMIN_ROLE delay is 0 - import Vaults/Makina/srRoyUSDC BEFORE the Dawn lockdown (after it, every tx reverts); import and execute as ONE atomic batch.";

    function _batchDesc(bool _isHub) internal pure returns (string memory) {
        if (_isHub) {
            return string.concat(
                "Consolidated srRoyUSDC hub migration in one FNDN batch: (1) phase-1 native vault role migration - grant the AccessManager every native AccessControl role + revoke current holders; (2) phase-2 AM-side vault + strategy wiring - label roles, setTargetFunctionRole, grants with 72h/immediate delays, guardians; (3) Caliber + Machine AM wiring - risk-manager/timelock setters bound to per-vault RISK_MANAGER/TIMELOCK_MANAGER (72h), granted to WAY, guardian GUARDIAN_ROLE. FNDN admins the vault's native roles, so a single Safe batch is valid.",
                _CAVEATS
            );
        }
        return string.concat(
            "srRoyUSDC spoke Caliber AM wiring in one FNDN batch: bind Caliber + CaliberMailbox risk-manager setters to SRROYUSDC_RISK_MANAGER (72h) and Caliber.setTimelockDuration to SRROYUSDC_TIMELOCK_MANAGER (72h); grant both to WAY; guardian GUARDIAN_ROLE (FNDN/FNDN_VETO cancel). The on-chain _allowedInstrRoot timelock is unchanged.",
            _CAVEATS
        );
    }
}
