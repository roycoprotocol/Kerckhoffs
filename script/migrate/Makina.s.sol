// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Selectors } from "../../src/access/Selectors.sol";
import { MigrationBase } from "../../src/migration/MigrationBase.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IMakinaGovernable } from "makina-core/src/interfaces/IMakinaGovernable.sol";

/**
 * @title MigrateMakina
 * @notice Migrates the Makina/Caliber surface (Caliber setters) to AccessManager-routed
 *         authorization per `authorization/README.md` §2 Makina table.
 *
 * Per vault (`srRoyUSDC`, `roywstETH`), the script binds Caliber AND Machine setters
 * (everything currently gated by the on-chain `onlyRiskManagerTimelock` modifier) to two new
 * per-vault AM roles and grants those roles to WAY with the model's delays:
 *
 *   `<VAULT>_RISK_MANAGER`     (72h) — routine risk parameters + base token mgmt + Machine fee/cooldown setters
 *   `<VAULT>_TIMELOCK_MANAGER` (72h) — `setTimelockDuration` only (meta-timelock on the Caliber)
 *
 * The Caliber's on-chain `_allowedInstrRoot` timelock is left untouched (see README §2 notes).
 *
 * **Out-of-band prerequisite (Makina governance).** BOTH the `_riskManager` (slot 2) AND the
 * `_riskManagerTimelock` (slot 3) slots on each Machine must point at `ROYCO_FACTORY` for the
 * AM-side bindings to take effect. Both are required because the migration binds
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
 * The strategy contract (sits under the vault) is wired in `script/migrate/Vaults.s.sol`, since
 * the strategy lives under the concrete vault — Makina migration handles only Caliber + Machine.
 *
 * Output: `output/migrate/makina/{chainId}_caliber.json` (combined batch for both vaults).
 *
 * ── ONE-TIME USE ────────────────────────────────────────────────────────────────────────────
 * The batch grants/wires roles via FNDN's ADMIN_ROLE directly, so this must run BEFORE Dawn's
 * ADMIN_ROLE lockdown (order: Vaults → Makina → Dawn). `run()` (via MigrationBase) calls
 * `_assertPreMigrationAdminState` and reverts (`MigrationAlreadyApplied`) if the lockdown has
 * already happened. One-shot bootstrap for the current state — not a reusable tool.
 */
contract MigrateMakina is MigrationBase, Script {
    function _targetChains() internal pure override returns (uint256[] memory chains) {
        chains = new uint256[](1);
        chains[0] = MAINNET;
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

    function _outputPath(uint256 _chainId) internal pure override returns (string memory) {
        return string.concat("output/migrate/makina/", _toString(_chainId), "_caliber");
    }

    function _batchMeta(
        uint256 /*_chainId*/
    )
        internal
        pure
        override
        returns (string memory name, string memory description)
    {
        name = "Royco Makina/Caliber AccessManager wiring";
        description =
            "Bind Caliber + Machine setters to per-vault RISK_MANAGER (72h) and TIMELOCK_MANAGER (72h) roles. Grant both to WAY; cancellable via GUARDIAN_ROLE (FNDN/FNDN_VETO). The on-chain _allowedInstrRoot timelock is unchanged.";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BUILDER
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildBatch(uint256 _chainId) internal view override returns (SafeTransaction[] memory) {
        string[] memory vaults = vaultNames(_chainId);
        // Resolve the AM per chain (Base has its own factory). Mainnet-only today, but never
        // hardcode ROYCO_FACTORY here — that would silently target the wrong AM off mainnet.
        address factory = roycoFactory(_chainId);

        // Per vault: 2 labelRole + 3 setTargetFunctionRole + 2 setRoleGuardian + 2 grantRole = 9 txs
        SafeTransaction[] memory txs = new SafeTransaction[](9 * vaults.length);
        uint256 t;

        for (uint256 i = 0; i < vaults.length; i++) {
            (uint64 riskRole, uint64 tlRole, string memory riskLabel, string memory tlLabel) = _vaultRoleIds(vaults[i]);
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);

            txs[t++] = buildLabelRole(factory, riskRole, riskLabel);
            txs[t++] = buildLabelRole(factory, tlRole, tlLabel);

            // Caliber: risk-manager-gated setters + meta-timelock setter
            txs[t++] = buildSetTargetFunctionRole(factory, s.caliber, Selectors.caliberRiskManagerSelectors(), riskRole);
            bytes4[] memory tlSel = new bytes4[](1);
            tlSel[0] = ICaliber.setTimelockDuration.selector;
            txs[t++] = buildSetTargetFunctionRole(factory, s.caliber, tlSel, tlRole);

            // Machine: risk-manager-gated setters (all `onlyRiskManagerTimelock`)
            txs[t++] = buildSetTargetFunctionRole(factory, s.machine, Selectors.machineRiskManagerSelectors(), riskRole);

            // Guardian wiring — required so the guardian can cancel the 72h-delayed risk/timelock
            // manager ops. Without this, getRoleGuardian defaults to ADMIN_ROLE and only an admin
            // can cancel.
            txs[t++] = buildSetRoleGuardian(factory, riskRole, GUARDIAN_ROLE);
            txs[t++] = buildSetRoleGuardian(factory, tlRole, GUARDIAN_ROLE);

            // Held by WAY (parameter-update authority). FNDN / FNDN_VETO cancel via GUARDIAN_ROLE.
            txs[t++] = buildGrantRole(factory, riskRole, WAY, DELAY_MIN);
            txs[t++] = buildGrantRole(factory, tlRole, WAY, DELAY_MIN);
        }

        require(t == txs.length, "Makina tx count mismatch");
        return txs;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRE-SIMULATION (Makina-governance prerequisite, NOT in the emitted JSON)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Two simulation-only prerequisites that depend on Makina governance and so are NOT
    ///      included in the emitted Safe JSON:
    ///
    ///      1. **Re-point BOTH `_riskManager` (slot 2) and `_riskManagerTimelock` (slot 3) on each
    ///         Machine to `ROYCO_FACTORY`** so the on-chain `onlyRiskManager` / `onlyRiskManagerTimelock`
    ///         modifiers on both Machine and Caliber accept calls relayed via the Royco AM. Both slots
    ///         are needed: `onlyRiskManager` setters (`Machine.setShareLimit`,
    ///         `Caliber.scheduleAllowedInstrRootUpdate`) read slot 2; every other bound setter reads
    ///         slot 3. Caliber doesn't inherit `MakinaGovernable` — its modifiers delegate to the
    ///         Machine's slots (vendored
    ///         `royco-vault-makina-strategy/lib/makina-core/src/caliber/Caliber.sol:109-121`), so a
    ///         single Machine update per slot covers both contracts. Mocked via `vm.store`.
    ///      2. **Add FNDN as an `instrRootGuardian` on each Caliber** so FNDN can call
    ///         `cancelAllowedInstrRootUpdate` during the on-chain timelock window. This requires
    ///         `Caliber.addInstrRootGuardian(FNDN)`, which is `restricted` (Makina AM). Mocked
    ///         here via `vm.mockCall(caliber, isInstrRootGuardian(FNDN), true)`.
    ///
    ///      Both ops require Makina governance to actually execute. Tracking is a separate workstream.
    function _preSimulate(uint256 _chainId) internal override {
        console2.log("");
        console2.log(">>> Pre-simulating Makina governance prerequisites:");

        string[] memory vaults = vaultNames(_chainId);
        for (uint256 i = 0; i < vaults.length; i++) {
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);
            _writeMachineGovernableSlot(s.machine, _SLOT_RISK_MANAGER, roycoFactory(_chainId), string.concat(vaults[i], " machine.riskManager"));
            _writeMachineGovernableSlot(
                s.machine, _SLOT_RISK_MANAGER_TIMELOCK, roycoFactory(_chainId), string.concat(vaults[i], " machine.riskManagerTimelock")
            );
            _mockCaliberInstrRootGuardian(s.caliber, FNDN, string.concat(vaults[i], " caliber"));
        }
    }

    function _mockCaliberInstrRootGuardian(address _caliber, address _guardian, string memory _label) internal {
        vm.mockCall(_caliber, abi.encodeWithSignature("isInstrRootGuardian(address)", _guardian), abi.encode(true));
        require(ICaliber(_caliber).isInstrRootGuardian(_guardian), string.concat(_label, ": isInstrRootGuardian mock did not stick"));
        console2.log(string.concat("    [OK] ", _label, " FNDN recognised as instrRootGuardian (cancelAllowedInstrRootUpdate)"));
    }

    /// @dev MakinaGovernableStorage layout (vendored
    ///      `royco-vault-makina-strategy/lib/makina-core/src/utils/MakinaGovernable.sol:14-22`):
    ///      slot+0 _mechanic, +1 _securityCouncil, +2 _riskManager, +3 _riskManagerTimelock, ...
    ///      ERC-7201 base slot:
    ///      `keccak256(abi.encode(uint256(keccak256("makina.storage.MakinaGovernable")) - 1)) & ~bytes32(uint256(0xff))`
    ///      = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000
    bytes32 private constant _MAKINA_GOVERNABLE_STORAGE_BASE = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000;
    uint256 private constant _SLOT_RISK_MANAGER = 2;
    uint256 private constant _SLOT_RISK_MANAGER_TIMELOCK = 3;

    /// @dev Writes either the riskManager (offset 2) or riskManagerTimelock (offset 3) slot
    ///      and verifies the corresponding view returns the new value.
    function _writeMachineGovernableSlot(address _machine, uint256 _offset, address _newAddr, string memory _label) internal {
        bytes32 slot = bytes32(uint256(_MAKINA_GOVERNABLE_STORAGE_BASE) + _offset);
        vm.store(_machine, slot, bytes32(uint256(uint160(_newAddr))));
        address actual = _offset == _SLOT_RISK_MANAGER ? IMakinaGovernable(_machine).riskManager() : IMakinaGovernable(_machine).riskManagerTimelock();
        require(actual == _newAddr, string.concat(_label, ": store did not stick (storage layout drifted?)"));
        console2.log(string.concat("    [OK] ", _label, " -> ROYCO_FACTORY"));
    }

    function _vaultRoleIds(string memory _vault) internal pure returns (uint64 riskRole, uint64 tlRole, string memory riskLabel, string memory tlLabel) {
        if (_str_eq(_vault, "srRoyUSDC")) {
            return (SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER, "SRROYUSDC_RISK_MANAGER", "SRROYUSDC_TIMELOCK_MANAGER");
        } else if (_str_eq(_vault, "roywstETH")) {
            return (ROYWSTETH_RISK_MANAGER, ROYWSTETH_TIMELOCK_MANAGER, "ROYWSTETH_RISK_MANAGER", "ROYWSTETH_TIMELOCK_MANAGER");
        }
        revert("Unknown vault for Makina migration");
    }

    function _str_eq(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(bytes(_a)) == keccak256(bytes(_b));
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
