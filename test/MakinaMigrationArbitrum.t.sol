// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";

import { MakinaAssertions } from "./_MakinaAssertions.sol";

/// @dev Arbitrum spoke: srRoyUSDC's Caliber (same address as mainnet) with a CaliberMailbox
///      endpoint (no local Machine). Dawn is already live on Arbitrum with the ADMIN_ROLE lockdown
///      deferred, so FNDN can drive this batch directly.
contract MakinaMigrationArbitrumTest is MakinaAssertions {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(ARBITRUM));
        applyToFork(ARBITRUM);
        am = IAccessManager(roycoFactory(ARBITRUM));
    }

    function test_PostState_srRoyUSDC_SpokeWiring() public view {
        _assertMakinaWiring(ARBITRUM, SRROYUSDC, SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER);
    }

    function test_PostState_FixedShape() public view {
        SafeTransaction[] memory rerun = _buildBatch(ARBITRUM);
        require(rerun.length == 9 * strategyVaultNames(ARBITRUM).length, "9 txs per spoke caliber");
    }

    function test_SpokeCaliber_RiskManager_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(ARBITRUM, SRROYUSDC);
        bytes memory data = abi.encodeCall(ICaliber.setMaxSwapLossBps, (uint256(0)));
        _assertDelayedRoleBehavior("ARB srRoyUSDC RISK_MANAGER @ WAY (caliber)", SRROYUSDC_RISK_MANAGER, WAY, DELAY_MIN, s.caliber, data, FNDN);
    }
}
