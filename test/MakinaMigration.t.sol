// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { MakinaAssertions } from "./_MakinaAssertions.sol";

/**
 * @title MakinaMigrationTest
 * @notice Mainnet (hub): per-vault Caliber + Machine roles held by WAY @ 72h, FNDN-cancellable.
 *         Both srRoyUSDC and roywstETH have a hub Caliber whose endpoint is a Machine.
 */
contract MakinaMigrationTest is MakinaAssertions {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET);
        new MigrateDawn().applyToFork(MAINNET); // Dawn is idempotent (already live) — keeps ordering explicit
        am = IAccessManager(roycoFactory(MAINNET));
    }

    function test_PostState_srRoyUSDC_RiskManagerWiring() public view {
        _assertMakinaWiring(MAINNET, SRROYUSDC, SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_PostState_roywstETH_RiskManagerWiring() public view {
        _assertMakinaWiring(MAINNET, ROYWSTETH, ROYWSTETH_RISK_MANAGER, ROYWSTETH_TIMELOCK_MANAGER);
    }

    function test_PostState_FixedShape() public view {
        SafeTransaction[] memory rerun = _buildBatch(MAINNET);
        require(rerun.length == 9 * strategyVaultNames(MAINNET).length, "Makina migration should emit 9 txs per caliber");
    }

    // ── Behavior — WAY @ 72h, FNDN-cancellable ────────────────────────────────

    function test_SrRoyUSDC_RiskManager_Caliber_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("srRoyUSDC RISK_MANAGER @ WAY (caliber)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_MIN, s.caliber, data, FNDN);
    }

    function test_RoywstETH_RiskManager_Caliber_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("roywstETH RISK_MANAGER @ WAY (caliber)", ROYWSTETH_RISK_MANAGER, WAY, DELAY_MIN, s.caliber, data, FNDN);
    }

    function test_SrRoyUSDC_RiskManager_Machine_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeWithSignature("setCaliberStaleThreshold(uint256)", uint256(0));
        _assertDelayedRoleBehavior("srRoyUSDC RISK_MANAGER @ WAY (machine)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_MIN, s.endpoint, data, FNDN);
    }

    function test_SrRoyUSDC_TimelockManager_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setTimelockDuration, (uint256(0)));
        _assertDelayedRoleBehavior("srRoyUSDC TIMELOCK_MANAGER @ WAY", SRROYUSDC_TIMELOCK_MANAGER, WAY, DELAY_MIN, s.caliber, data, FNDN);
    }
}
