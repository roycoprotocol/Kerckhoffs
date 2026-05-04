// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IMakinaGovernable } from "makina-core/src/interfaces/IMakinaGovernable.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { MigrateMakina } from "../script/migrate/Makina.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/**
 * @title MakinaMigrationTest
 * @notice Verifies the Makina migration leaves the AccessManager in the canonical post-state and
 *         that per-vault Caliber/Machine roles behave as designed.
 *
 * Setup chain: Makina migration first (so its bindings are in place), then Dawn (lockdown step
 * raises ADMIN_ROLE to 48h). Dawn last matches operational ordering.
 *
 * Per-vault roles tested:
 *   - `<VAULT>_RISK_MANAGER` — Critical 48h, FNDN, guards Caliber + Machine risk-manager setters.
 *   - `<VAULT>_TIMELOCK_MANAGER` — Critical 48h, FNDN, guards `setTimelockDuration` on Caliber.
 */
contract MakinaMigrationTest is RoleBehaviorBase, MigrateMakina {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        // Apply Makina FIRST — phase-2 AM calls run via FNDN's ADMIN_ROLE Immediate. Dawn locks
        // down ADMIN_ROLE to Critical 48h and must run last.
        applyToFork(MAINNET);
        new MigrateDawn().applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE ASSERTIONS — per vault
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PostState_srRoyUSDC_RiskManagerWiring() public view {
        _assertCaliberMachineWiring(SRROYUSDC, SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_PostState_roywstETH_RiskManagerWiring() public view {
        _assertCaliberMachineWiring(ROYWSTETH, ROYWSTETH_RISK_MANAGER, ROYWSTETH_TIMELOCK_MANAGER);
    }

    /// @dev Makina migration is non-diff (re-emits the full set every time). Verify it produces
    ///      the documented fixed shape: 9 txs per vault.
    function test_PostState_FixedShape() public view {
        SafeTransaction[] memory rerun = _buildBatch(MAINNET);
        require(rerun.length == 9 * vaultNames(MAINNET).length, "Makina migration should emit 9 txs per vault");
    }

    function _assertCaliberMachineWiring(string memory _vaultName, uint64 _riskRole, uint64 _tlRole) internal view {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);

        // FNDN role delays
        _assertMembership(_riskRole, FNDN, DELAY_CRITICAL, string.concat(_vaultName, "_RISK_MANAGER @ FNDN"));
        _assertMembership(_tlRole, FNDN, DELAY_CRITICAL, string.concat(_vaultName, "_TIMELOCK_MANAGER @ FNDN"));

        // Caliber selector bindings — risk-manager setters
        bytes4[] memory rmSel = Selectors.caliberRiskManagerSelectors();
        for (uint256 j = 0; j < rmSel.length; j++) {
            require(am.getTargetFunctionRole(s.caliber, rmSel[j]) == _riskRole, "Caliber risk-manager selector mismatch");
        }
        // Caliber timelock-manager
        require(am.getTargetFunctionRole(s.caliber, ICaliber.setTimelockDuration.selector) == _tlRole, "Caliber timelock-manager selector mismatch");

        // Machine selector bindings — risk-manager setters
        bytes4[] memory machineSel = Selectors.machineRiskManagerSelectors();
        for (uint256 j = 0; j < machineSel.length; j++) {
            require(am.getTargetFunctionRole(s.machine, machineSel[j]) == _riskRole, "Machine risk-manager selector mismatch");
        }

        // Pre-simulated Makina governance step: Machine.riskManagerTimelock should be ROYCO_FACTORY.
        require(IMakinaGovernable(s.machine).riskManagerTimelock() == ROYCO_FACTORY, "Machine riskManagerTimelock not ROYCO_FACTORY");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — per vault Caliber/Machine roles
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SrRoyUSDC_RiskManager_Caliber_DelayedAndCancellable() public {
        _assertRiskManagerCaliberBehavior(SRROYUSDC, SRROYUSDC_RISK_MANAGER);
    }

    function test_RoywstETH_RiskManager_Caliber_DelayedAndCancellable() public {
        _assertRiskManagerCaliberBehavior(ROYWSTETH, ROYWSTETH_RISK_MANAGER);
    }

    function _assertRiskManagerCaliberBehavior(string memory _vaultName, uint64 _riskRole) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        // setMaxSwapLossBps is risk-manager-gated; behavior is identical for the other risk-manager selectors.
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint16(0)));
        _assertDelayedRoleBehavior(string.concat(_vaultName, "_RISK_MANAGER @ FNDN (caliber)"), _riskRole, FNDN, DELAY_CRITICAL, s.caliber, data, WAY);
    }

    function test_SrRoyUSDC_RiskManager_Machine_DelayedAndCancellable() public {
        _assertRiskManagerMachineBehavior(SRROYUSDC, SRROYUSDC_RISK_MANAGER);
    }

    function test_RoywstETH_RiskManager_Machine_DelayedAndCancellable() public {
        _assertRiskManagerMachineBehavior(ROYWSTETH, ROYWSTETH_RISK_MANAGER);
    }

    function _assertRiskManagerMachineBehavior(string memory _vaultName, uint64 _riskRole) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        // Machine.setCaliberStaleThreshold is risk-manager-gated; representative selector.
        bytes memory data = abi.encodeWithSignature("setCaliberStaleThreshold(uint256)", uint256(0));
        _assertDelayedRoleBehavior(string.concat(_vaultName, "_RISK_MANAGER @ FNDN (machine)"), _riskRole, FNDN, DELAY_CRITICAL, s.machine, data, WAY);
    }

    function test_SrRoyUSDC_TimelockManager_DelayedAndCancellable() public {
        _assertTimelockManagerBehavior(SRROYUSDC, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_RoywstETH_TimelockManager_DelayedAndCancellable() public {
        _assertTimelockManagerBehavior(ROYWSTETH, ROYWSTETH_TIMELOCK_MANAGER);
    }

    function _assertTimelockManagerBehavior(string memory _vaultName, uint64 _tlRole) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(ICaliber.setTimelockDuration, (uint128(0)));
        _assertDelayedRoleBehavior(string.concat(_vaultName, "_TIMELOCK_MANAGER @ FNDN"), _tlRole, FNDN, DELAY_CRITICAL, s.caliber, data, WAY);
    }
}
