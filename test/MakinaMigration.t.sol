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
 * @notice Per-vault Caliber/Machine roles held by WAY @ Critical 48h, FNDN-cancellable.
 *
 * Setup chain: Makina FIRST (FNDN's ADMIN_ROLE still Immediate to drive phase-2 calls), then
 * Dawn (lockdown). Both per-vault `RISK_MANAGER` and `TIMELOCK_MANAGER` roles bind every
 * `onlyRiskManagerTimelock` selector on Caliber + Machine.
 */
contract MakinaMigrationTest is RoleBehaviorBase, MigrateMakina {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET);
        new MigrateDawn().applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
    }

    function test_PostState_srRoyUSDC_RiskManagerWiring() public view {
        _assertCaliberMachineWiring(SRROYUSDC, SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_PostState_roywstETH_RiskManagerWiring() public view {
        _assertCaliberMachineWiring(ROYWSTETH, ROYWSTETH_RISK_MANAGER, ROYWSTETH_TIMELOCK_MANAGER);
    }

    function test_PostState_FixedShape() public view {
        SafeTransaction[] memory rerun = _buildBatch(MAINNET);
        require(rerun.length == 9 * vaultNames(MAINNET).length, "Makina migration should emit 9 txs per vault");
    }

    function _assertCaliberMachineWiring(string memory _vaultName, uint64 _riskRole, uint64 _tlRole) internal view {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);

        // Holder is WAY (parameter-update authority); FNDN-cancellable via GUARDIAN_ROLE.
        _assertMembership(_riskRole, WAY, DELAY_CRITICAL, string.concat(_vaultName, "_RISK_MANAGER @ WAY"));
        _assertMembership(_tlRole, WAY, DELAY_CRITICAL, string.concat(_vaultName, "_TIMELOCK_MANAGER @ WAY"));
        require(am.getRoleGuardian(_riskRole) == GUARDIAN_ROLE, "RISK_MANAGER guardian mismatch");
        require(am.getRoleGuardian(_tlRole) == GUARDIAN_ROLE, "TIMELOCK_MANAGER guardian mismatch");

        // Caliber: 8 risk-manager-gated setters (incl. scheduleAllowedInstrRootUpdate).
        bytes4[] memory rmSel = Selectors.caliberRiskManagerSelectors();
        for (uint256 j = 0; j < rmSel.length; j++) {
            require(am.getTargetFunctionRole(s.caliber, rmSel[j]) == _riskRole, "Caliber risk-manager selector mismatch");
        }
        // Caliber: setTimelockDuration → tlRole
        require(am.getTargetFunctionRole(s.caliber, ICaliber.setTimelockDuration.selector) == _tlRole, "Caliber timelock-manager selector mismatch");

        // Machine: 7 risk-manager-gated setters
        bytes4[] memory machineSel = Selectors.machineRiskManagerSelectors();
        for (uint256 j = 0; j < machineSel.length; j++) {
            require(am.getTargetFunctionRole(s.machine, machineSel[j]) == _riskRole, "Machine risk-manager selector mismatch");
        }

        // Pre-simulated Makina governance steps: BOTH riskManager AND riskManagerTimelock
        // must point at ROYCO_FACTORY so onlyRiskManager + onlyRiskManagerTimelock both gate
        // through the AM.
        require(IMakinaGovernable(s.machine).riskManager() == ROYCO_FACTORY, "Machine riskManager not ROYCO_FACTORY");
        require(IMakinaGovernable(s.machine).riskManagerTimelock() == ROYCO_FACTORY, "Machine riskManagerTimelock not ROYCO_FACTORY");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Behavior — WAY @ 48h, FNDN-cancellable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SrRoyUSDC_RiskManager_Caliber_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("srRoyUSDC RISK_MANAGER @ WAY (caliber)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_CRITICAL, s.caliber, data, FNDN);
    }

    function test_RoywstETH_RiskManager_Caliber_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("roywstETH RISK_MANAGER @ WAY (caliber)", ROYWSTETH_RISK_MANAGER, WAY, DELAY_CRITICAL, s.caliber, data, FNDN);
    }

    function test_SrRoyUSDC_RiskManager_Machine_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeWithSignature("setCaliberStaleThreshold(uint256)", uint256(0));
        _assertDelayedRoleBehavior("srRoyUSDC RISK_MANAGER @ WAY (machine)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_CRITICAL, s.machine, data, FNDN);
    }

    function test_RoywstETH_RiskManager_Machine_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeWithSignature("setCaliberStaleThreshold(uint256)", uint256(0));
        _assertDelayedRoleBehavior("roywstETH RISK_MANAGER @ WAY (machine)", ROYWSTETH_RISK_MANAGER, WAY, DELAY_CRITICAL, s.machine, data, FNDN);
    }

    function test_SrRoyUSDC_TimelockManager_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setTimelockDuration, (uint256(0)));
        _assertDelayedRoleBehavior("srRoyUSDC TIMELOCK_MANAGER @ WAY", SRROYUSDC_TIMELOCK_MANAGER, WAY, DELAY_CRITICAL, s.caliber, data, FNDN);
    }

    function test_RoywstETH_TimelockManager_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(ICaliber.setTimelockDuration, (uint256(0)));
        _assertDelayedRoleBehavior("roywstETH TIMELOCK_MANAGER @ WAY", ROYWSTETH_TIMELOCK_MANAGER, WAY, DELAY_CRITICAL, s.caliber, data, FNDN);
    }
}
