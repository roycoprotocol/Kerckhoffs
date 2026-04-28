// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";

import { IBridgeController } from "makina-core/src/interfaces/IBridgeController.sol";
import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";

import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";

import { ConcreteV2RolesLib } from "concrete-earn/src/lib/Roles.sol";

import { IConcreteStandardVaultImpl } from "concrete-earn/src/interface/IConcreteStandardVaultImpl.sol";

/// @dev Minimal local interface for the Machine setters we bind via AM. Avoids importing
///      IMachine directly (which transitively pulls in the wormhole SDK).
interface IMachineRiskManagerTimelock {
    function setCaliberStaleThreshold(uint256 newCaliberStaleThreshold) external;
    function setMaxFixedFeeAccrualRate(uint256 newMaxAccrualRate) external;
    function setMaxPerfFeeAccrualRate(uint256 newMaxAccrualRate) external;
    function setFeeMintCooldown(uint256 newFeeMintCooldown) external;
    function setMaxSharePriceChangeRate(uint256 newMaxSharePriceChangeRate) external;
}

/**
 * @notice Selector list helpers for selectors that come in groups (LP ops, Caliber/Machine
 *         risk-manager setters, vault role-gated functions, strategy allocators) plus native
 *         AccessControl role hashes for the concrete vaults. For single selectors, callers
 *         should use `Interface.method.selector` directly at the call site rather than going
 *         through a wrapper here.
 */
library Selectors {
    // ═══════════════════════════════════════════════════════════════════════════
    // ENTRY POINT — derived from IRoycoEntryPoint
    // ═══════════════════════════════════════════════════════════════════════════

    function entryPointLPSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](10);
        s[0] = IRoycoEntryPoint.requestDeposit.selector;
        s[1] = IRoycoEntryPoint.executeDeposit.selector;
        s[2] = IRoycoEntryPoint.executeDeposits.selector;
        s[3] = IRoycoEntryPoint.cancelDepositRequest.selector;
        s[4] = IRoycoEntryPoint.cancelDepositRequests.selector;
        s[5] = IRoycoEntryPoint.requestRedemption.selector;
        s[6] = IRoycoEntryPoint.executeRedemption.selector;
        s[7] = IRoycoEntryPoint.executeRedemptions.selector;
        s[8] = IRoycoEntryPoint.cancelRedemptionRequest.selector;
        s[9] = IRoycoEntryPoint.cancelRedemptionRequests.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALIBER — derived from ICaliber (makina-core)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Risk-manager-restricted setters: routine risk parameters + base token mgmt.
    function caliberRiskManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = ICaliber.setPositionStaleThreshold.selector;
        s[1] = ICaliber.setMaxPositionIncreaseLossBps.selector;
        s[2] = ICaliber.setMaxPositionDecreaseLossBps.selector;
        s[3] = ICaliber.setMaxSwapLossBps.selector;
        s[4] = ICaliber.setCooldownDuration.selector;
        s[5] = ICaliber.addBaseToken.selector;
        s[6] = ICaliber.removeBaseToken.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MACHINE — onlyRiskManagerTimelock setters (Caliber's hub-side counterpart)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev All Machine setters gated by `onlyRiskManagerTimelock`. Map to `<VAULT>_RISK_MANAGER`.
    function machineRiskManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = IMachineRiskManagerTimelock.setCaliberStaleThreshold.selector;
        s[1] = IMachineRiskManagerTimelock.setMaxFixedFeeAccrualRate.selector;
        s[2] = IMachineRiskManagerTimelock.setMaxPerfFeeAccrualRate.selector;
        s[3] = IMachineRiskManagerTimelock.setFeeMintCooldown.selector;
        s[4] = IMachineRiskManagerTimelock.setMaxSharePriceChangeRate.selector;
        s[5] = IBridgeController.setOutTransferEnabled.selector;
        s[6] = IBridgeController.setMaxBridgeLossBps.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROYCO MAKINA STRATEGY allocator selectors (IStrategyTemplate)
    // ═══════════════════════════════════════════════════════════════════════════

    function strategyAllocatorSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = IStrategyTemplate.allocateFunds.selector;
        s[1] = IStrategyTemplate.deallocateFunds.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCRETE VAULTS — role-gated function selectors per native role
    // ═══════════════════════════════════════════════════════════════════════════

    function vaultManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = IConcreteStandardVaultImpl.updateManagementFee.selector;
        s[1] = IConcreteStandardVaultImpl.updatePerformanceFee.selector;
        s[2] = IConcreteStandardVaultImpl.setDepositLimits.selector;
        s[3] = IConcreteStandardVaultImpl.setWithdrawLimits.selector;
    }

    function strategyManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = IConcreteStandardVaultImpl.addStrategy.selector;
        s[1] = IConcreteStandardVaultImpl.removeStrategy.selector;
        s[2] = IConcreteStandardVaultImpl.toggleStrategyStatus.selector;
    }

    function hookManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = IConcreteStandardVaultImpl.setHooks.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCRETE VAULTS — native AccessControl role hashes (from concrete-earn Roles.sol)
    // ═══════════════════════════════════════════════════════════════════════════

    function nativeVaultManager() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.VAULT_MANAGER;
    }

    function nativeStrategyManager() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.STRATEGY_MANAGER;
    }

    function nativeHookManager() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.HOOK_MANAGER;
    }

    function nativeVaultManagerAdmin() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.VAULT_MANAGER_ADMIN;
    }

    function nativeStrategyManagerAdmin() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.STRATEGY_MANAGER_ADMIN;
    }

    function nativeHookManagerAdmin() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.HOOK_MANAGER_ADMIN;
    }

    function nativeAllocatorAdmin() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.ALLOCATOR_ADMIN;
    }

    function nativeWithdrawalManagerAdmin() internal pure returns (bytes32) {
        return ConcreteV2RolesLib.WITHDRAWAL_MANAGER_ADMIN;
    }
}
