// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CaliberWiring } from "../../src/migration/CaliberWiring.sol";
import { MigrationBase } from "../../src/migration/MigrationBase.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title MigrateMakina
 * @notice Migrates the Makina/Caliber surface (Caliber setters) to AccessManager-routed
 *         authorization per `authorization/README.md` §2 Makina table.
 *
 * Makina is hub-and-spoke, so this runs on multiple chains:
 *   - **Hub (mainnet)** — both vaults (`srRoyUSDC`, `roywstETH`); each Caliber's endpoint is a
 *     Machine. Binds Caliber setters + the Machine's risk-manager setters.
 *   - **Spokes (Arbitrum, Base)** — only `srRoyUSDC` (its Caliber is deployed at the same address;
 *     roywstETH has no spoke Caliber). The Caliber's endpoint is a local `CaliberMailbox` (no
 *     Machine); binds Caliber setters + the CaliberMailbox's risk-manager setters.
 *
 * Per (chain, vault-with-Caliber), everything currently gated by `onlyRiskManager[Timelock]` is
 * bound to two per-vault AM roles, granted to WAY with the model's delays:
 *
 *   `<VAULT>_RISK_MANAGER`     (72h) — routine risk parameters + base token mgmt + endpoint setters
 *   `<VAULT>_TIMELOCK_MANAGER` (72h) — `setTimelockDuration` only (meta-timelock on the Caliber)
 *
 * The Caliber's on-chain `_allowedInstrRoot` timelock is left untouched (see README §2 notes).
 *
 * **Out-of-band prerequisite (Makina governance).** BOTH the `_riskManager` (slot 2) AND the
 * `_riskManagerTimelock` (slot 3) slots on each Caliber endpoint (the Machine on the hub, the
 * CaliberMailbox on a spoke) must point at that chain's RoycoFactory for the AM-side bindings to
 * take effect. Both are required because the migration binds
 * `onlyRiskManager`-gated setters too: `Machine.setShareLimit` and `Caliber.scheduleAllowedInstrRootUpdate`
 * resolve against `_riskManager` (slot 2), while every other bound setter resolves against
 * `_riskManagerTimelock` (slot 3). Re-pointing only slot 3 would leave `setShareLimit` /
 * `scheduleAllowedInstrRootUpdate` gated by the OLD riskManager (WAY couldn't call them; the prior
 * authority would retain them). `setRiskManager(...)` / `setRiskManagerTimelock(...)` are
 * `restricted` — gated by the *Makina* AM, not Royco's — and Royco does not currently hold
 * permission to call them. The migration script does NOT include these calls in the emitted Safe
 * JSON. They ARE included in the local fork simulation (via `_preSimulate` writing both slots) so
 * that we can verify the post-state assuming Makina governance executes the change. Tracking this
 * with Makina is a separate workstream.
 *
 * The strategy contract (sits under the concrete vault) is wired in `script/migrate/Vaults.s.sol`;
 * Makina migration handles only the Caliber + its endpoint.
 *
 * Output: `output/migrate/makina/{chainId}_caliber_{vault}.json` — one batch per (chain, vault).
 *
 * ── ONE-TIME USE ────────────────────────────────────────────────────────────────────────────
 * The batch grants/wires roles via FNDN's ADMIN_ROLE directly, so this must run BEFORE Dawn's
 * ADMIN_ROLE lockdown (order: Vaults → Makina → Dawn). `run()` (via MigrationBase) calls
 * `_assertPreMigrationAdminState` and reverts (`MigrationAlreadyApplied`) if the lockdown has
 * already happened. One-shot bootstrap for the current state — not a reusable tool.
 */
contract MigrateMakina is CaliberWiring, MigrationBase, Script {
    /// @dev When set, `_buildBatch` emits ONLY this vault's 9 txs and `_outputPath` writes a
    ///      per-vault file. `run()` sets it per vault so each vault gets its own signable JSON
    ///      (the two vaults are independent: disjoint roles, targets and holders). Left empty by
    ///      the `applyToFork` test path, which builds the combined batch.
    string private _currentVault;

    /// @dev Mainnet (hub) has both vaults' calibers; the spokes have only srRoyUSDC's caliber
    ///      (roywstETH is hub-only). Per-chain vault sets come from `strategyVaultNames`.
    function _targetChains() internal pure override returns (uint256[] memory chains) {
        chains = new uint256[](3);
        chains[0] = MAINNET;
        chains[1] = ARBITRUM;
        chains[2] = BASE;
    }

    /// @notice Emits ONE Safe batch per (chain, vault-with-caliber):
    ///         `output/migrate/makina/{chainId}_caliber_{vault}.json`.
    function run() external override {
        _assertProductionMultisigs();
        uint256[] memory chains = _targetChains();
        for (uint256 i = 0; i < chains.length; i++) {
            string[] memory vaults = strategyVaultNames(chains[i]);
            for (uint256 j = 0; j < vaults.length; j++) {
                _currentVault = vaults[j];
                _processChain(chains[i]);
            }
        }
    }

    function _safeFor(
        uint256 /*_chainId*/
    )
        internal
        pure
        override
        returns (address)
    {
        return FNDN;
    }

    function _outputPath(uint256 _chainId) internal view override returns (string memory) {
        if (bytes(_currentVault).length > 0) {
            return string.concat("output/migrate/makina/", _toString(_chainId), "_caliber_", _currentVault);
        }
        return string.concat("output/migrate/makina/", _toString(_chainId), "_caliber");
    }

    function _batchMeta(
        uint256 /*_chainId*/
    )
        internal
        view
        override
        returns (string memory name, string memory description)
    {
        string memory scope = bytes(_currentVault).length > 0 ? string.concat(" - ", _currentVault) : "";
        name = string.concat("Royco Makina/Caliber AccessManager wiring", scope);
        description = string.concat(
            "Bind Caliber + Machine setters to per-vault RISK_MANAGER (72h) and TIMELOCK_MANAGER (72h) roles. Grant both to WAY; cancellable via GUARDIAN_ROLE (FNDN/FNDN_VETO). The on-chain _allowedInstrRoot timelock is unchanged.",
            bytes(_currentVault).length > 0 ? string.concat(" Scope: ", _currentVault, " only.") : ""
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BUILDER
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildBatch(uint256 _chainId) internal view override returns (SafeTransaction[] memory) {
        // Scoped to one vault when `run()` set it; otherwise every caliber on the chain (the
        // applyToFork test path).
        string[] memory vaults;
        if (bytes(_currentVault).length > 0) {
            vaults = new string[](1);
            vaults[0] = _currentVault;
        } else {
            vaults = strategyVaultNames(_chainId);
        }

        // Each vault's 9-tx batch is built by the shared `CaliberWiring` mixin (single source of
        // truth with the consolidated srRoyUSDC generator). Concatenate them in registry order.
        SafeTransaction[][] memory perVault = new SafeTransaction[][](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            perVault[i] = _buildCaliberForVault(_chainId, vaults[i]);
        }
        return mergeBatches(perVault);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRE-SIMULATION (Makina-governance prerequisite, NOT in the emitted JSON)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Runs the shared per-vault Makina-governance prerequisites (both governable slots ->
    ///      RoycoFactory + FNDN mocked as instrRootGuardian) for every caliber on the chain. The
    ///      mechanics + full rationale live in `CaliberWiring._preSimulateCaliberForVault`; these
    ///      are simulation-only and NOT part of the emitted JSON.
    function _preSimulate(uint256 _chainId) internal override {
        console2.log("");
        console2.log(">>> Pre-simulating Makina governance prerequisites:");

        string[] memory vaults = strategyVaultNames(_chainId);
        for (uint256 i = 0; i < vaults.length; i++) {
            _preSimulateCaliberForVault(_chainId, vaults[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE ASSERTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    // Assertions moved to `test/MakinaMigration.t.sol`.

    // ═══════════════════════════════════════════════════════════════════════════
    // STRING UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    function _toString(uint256 _v) private pure returns (string memory s) {
        if (_v == 0) return "0";
        uint256 j = _v;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory b = new bytes(len);
        uint256 k = len;
        while (_v != 0) {
            k--;
            b[k] = bytes1(uint8(48 + _v % 10));
            _v /= 10;
        }
        s = string(b);
    }
}
