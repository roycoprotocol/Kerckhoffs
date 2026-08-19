// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";

import { MakinaAssertions } from "./_MakinaAssertions.sol";

/// @dev Base spoke: srRoyUSDC's Caliber (same address as mainnet) with a CaliberMailbox endpoint.
///      Base uses its own factory (`ROYCO_FACTORY_BASE`); the wiring resolves it via
///      `roycoFactory(BASE)`. Dawn is already live on Base with the lockdown deferred.
contract MakinaMigrationBaseTest is MakinaAssertions {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(BASE));
        applyToFork(BASE);
        am = IAccessManager(roycoFactory(BASE));
    }

    function test_PostState_srRoyUSDC_SpokeWiring() public view {
        _assertMakinaWiring(BASE, SRROYUSDC, SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_PostState_FixedShape() public view {
        SafeTransaction[] memory rerun = _buildBatch(BASE);
        require(rerun.length == 9 * strategyVaultNames(BASE).length, "9 txs per spoke caliber");
    }

    function test_SpokeCaliber_RiskManager_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(BASE, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("BASE srRoyUSDC RISK_MANAGER @ WAY (caliber)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_MIN, s.caliber, data, FNDN);
    }
}
