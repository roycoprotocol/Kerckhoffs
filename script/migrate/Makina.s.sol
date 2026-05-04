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
 * per-vault AM roles and grants those roles to FNDN with the model's delays:
 *
 *   `<VAULT>_RISK_MANAGER`     (Critical 48h) — routine risk parameters + base token mgmt + Machine fee/cooldown setters
 *   `<VAULT>_TIMELOCK_MANAGER` (Critical 48h) — `setTimelockDuration` only (meta-timelock on the Caliber)
 *
 * The Caliber's on-chain `_allowedInstrRoot` timelock is left untouched (see README §2 notes).
 *
 * **Out-of-band prerequisite (Makina governance).** The on-chain `_riskManagerTimelock` slot on
 * each Caliber and Machine must point at `ROYCO_FACTORY` for the AM-side bindings to take effect.
 * `setRiskManagerTimelock(...)` is `restricted` — gated by the *Makina* AM, not Royco's — and
 * Royco does not currently hold permission to call it. The migration script does NOT include
 * this call in the emitted Safe JSON. It IS included in the local fork simulation (via
 * `_preSimulate` pranking the contract's `authority()`) so that we can verify the post-state
 * assuming Makina governance executes the change. Tracking this with Makina is a separate
 * workstream.
 *
 * The strategy contract (sits under the vault) is wired in `script/migrate/Vaults.s.sol`, since
 * the strategy lives under the concrete vault — Makina migration handles only Caliber + Machine.
 *
 * Output: `output/migrate/makina/{chainId}_caliber.json` (combined batch for both vaults).
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
            "Bind Caliber + Machine setters to per-vault RISK_MANAGER (Critical 48h) and TIMELOCK_MANAGER (Critical 48h) roles. Grant both to FNDN. The on-chain _allowedInstrRoot timelock is unchanged.";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BUILDER
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildBatch(uint256 _chainId) internal view override returns (SafeTransaction[] memory) {
        string[] memory vaults = vaultNames(_chainId);

        // Per vault: 2 labelRole + 3 setTargetFunctionRole + 2 setRoleGuardian + 2 grantRole = 9 txs
        SafeTransaction[] memory txs = new SafeTransaction[](9 * vaults.length);
        uint256 t;

        for (uint256 i = 0; i < vaults.length; i++) {
            (uint64 riskRole, uint64 tlRole, string memory riskLabel, string memory tlLabel) = _vaultRoleIds(vaults[i]);
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);

            txs[t++] = buildLabelRole(ROYCO_FACTORY, riskRole, riskLabel);
            txs[t++] = buildLabelRole(ROYCO_FACTORY, tlRole, tlLabel);

            // Caliber: risk-manager-gated setters + meta-timelock setter
            txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, s.caliber, Selectors.caliberRiskManagerSelectors(), riskRole);
            bytes4[] memory tlSel = new bytes4[](1);
            tlSel[0] = ICaliber.setTimelockDuration.selector;
            txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, s.caliber, tlSel, tlRole);

            // Machine: risk-manager-gated setters (all `onlyRiskManagerTimelock`)
            txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, s.machine, Selectors.machineRiskManagerSelectors(), riskRole);

            // Guardian wiring — required for WAY to cancel the 48h-delayed risk/timelock manager ops.
            // Without this, getRoleGuardian defaults to ADMIN_ROLE and only an admin can cancel.
            txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, riskRole, GUARDIAN_ROLE);
            txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, tlRole, GUARDIAN_ROLE);

            txs[t++] = buildGrantRole(ROYCO_FACTORY, riskRole, FNDN, DELAY_CRITICAL);
            txs[t++] = buildGrantRole(ROYCO_FACTORY, tlRole, FNDN, DELAY_CRITICAL);
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
    ///      1. **Re-point `_riskManagerTimelock` on each Machine to `ROYCO_FACTORY`** so the
    ///         on-chain `onlyRiskManagerTimelock` modifier on both Machine and Caliber accepts
    ///         calls relayed via the Royco AM. Caliber doesn't inherit `MakinaGovernable` — its
    ///         modifier delegates to the Machine's slot (`Caliber.sol:115-119`), so a single
    ///         Machine update covers both. Mocked via `vm.store`.
    ///      2. **Add WAY as an `instrRootGuardian` on each Caliber** so WAY can call
    ///         `cancelAllowedInstrRootUpdate` during the on-chain timelock window. This requires
    ///         `Caliber.addInstrRootGuardian(WAY)`, which is `restricted` (Makina AM). Mocked
    ///         here via `vm.mockCall(caliber, isInstrRootGuardian(WAY), true)`.
    ///
    ///      Both ops require Makina governance to actually execute. Tracking is a separate workstream.
    function _preSimulate(uint256 _chainId) internal override {
        console2.log("");
        console2.log(">>> Pre-simulating Makina governance prerequisites:");

        string[] memory vaults = vaultNames(_chainId);
        for (uint256 i = 0; i < vaults.length; i++) {
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);
            _writeMachineRiskManagerTimelock(s.machine, ROYCO_FACTORY, string.concat(vaults[i], " machine"));
            _mockCaliberInstrRootGuardian(s.caliber, WAY, string.concat(vaults[i], " caliber"));
        }
    }

    function _mockCaliberInstrRootGuardian(address _caliber, address _guardian, string memory _label) internal {
        vm.mockCall(_caliber, abi.encodeWithSignature("isInstrRootGuardian(address)", _guardian), abi.encode(true));
        require(ICaliber(_caliber).isInstrRootGuardian(_guardian), string.concat(_label, ": isInstrRootGuardian mock did not stick"));
        console2.log(string.concat("    [OK] ", _label, " WAY recognised as instrRootGuardian (cancelAllowedInstrRootUpdate)"));
    }

    /// @dev MakinaGovernableStorage layout (`MakinaGovernable.sol:14-22`):
    ///      slot+0 _mechanic, +1 _securityCouncil, +2 _riskManager, +3 _riskManagerTimelock, ...
    ///      ERC-7201 base slot:
    ///      `keccak256(abi.encode(uint256(keccak256("makina.storage.MakinaGovernable")) - 1)) & ~bytes32(uint256(0xff))`
    ///      = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000
    bytes32 private constant _MAKINA_GOVERNABLE_STORAGE_BASE = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000;

    function _writeMachineRiskManagerTimelock(address _machine, address _newTimelock, string memory _label) internal {
        bytes32 slot = bytes32(uint256(_MAKINA_GOVERNABLE_STORAGE_BASE) + 3);
        vm.store(_machine, slot, bytes32(uint256(uint160(_newTimelock))));
        require(
            IMakinaGovernable(_machine).riskManagerTimelock() == _newTimelock,
            string.concat(_label, ": riskManagerTimelock store did not stick (storage layout drifted?)")
        );
        console2.log(string.concat("    [OK] ", _label, " riskManagerTimelock -> ROYCO_FACTORY"));
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
