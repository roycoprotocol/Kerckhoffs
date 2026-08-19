// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { IConcreteStandardVaultImpl } from "concrete-earn/src/interface/IConcreteStandardVaultImpl.sol";
import { ConcreteV2RolesLib } from "concrete-earn/src/lib/Roles.sol";
import { IBridgeController } from "makina-core/src/interfaces/IBridgeController.sol";
import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";

/// @dev Minimal local interface for the Machine setters we bind via AM. Avoids importing
///      IMachine directly (which transitively pulls in the wormhole SDK). Includes both
///      `onlyRiskManager` (`setShareLimit`) and `onlyRiskManagerTimelock` setters — both
///      gate through the same `Machine.riskManager*` slots and are AM-routed once those
///      slots point at `RoycoFactory`.
interface IMachineRiskManagerSetters {
    function setShareLimit(uint256 newShareLimit) external; // onlyRiskManager
    function setCaliberStaleThreshold(uint256 newCaliberStaleThreshold) external; // onlyRiskManagerTimelock
    function setMaxFixedFeeAccrualRate(uint256 newMaxAccrualRate) external; // onlyRiskManagerTimelock
    function setMaxPerfFeeAccrualRate(uint256 newMaxAccrualRate) external; // onlyRiskManagerTimelock
    function setFeeMintCooldown(uint256 newFeeMintCooldown) external; // onlyRiskManagerTimelock
    function setMaxSharePriceChangeRate(uint256 newMaxSharePriceChangeRate) external; // onlyRiskManagerTimelock
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
    // ACCESS MANAGER — admin selectors (gated by ADMIN_ROLE / role-admin in OZ AM)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Every admin selector on the AccessManager itself. Used as the cancel-gate target
    ///      list: `setTargetFunctionRole(AM, these, ADMIN_MANAGER)` makes WAY (guardian of
    ///      ADMIN_MANAGER) the cancel authority for every scheduled AM-self admin op. The
    ///      call-gate for these selectors stays as OZ AM hardcodes it (ADMIN_ROLE for most;
    ///      `getRoleAdmin(roleId)` for grant/revoke) — this only changes the cancel path,
    ///      which reads `getTargetFunctionRole(target, selector)` storage independently.
    function accessManagerAdminSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](10);
        s[0] = IAccessManager.labelRole.selector;
        s[1] = IAccessManager.setRoleAdmin.selector;
        s[2] = IAccessManager.setRoleGuardian.selector;
        s[3] = IAccessManager.setGrantDelay.selector;
        s[4] = IAccessManager.setTargetAdminDelay.selector;
        s[5] = IAccessManager.setTargetClosed.selector;
        s[6] = IAccessManager.setTargetFunctionRole.selector;
        s[7] = IAccessManager.updateAuthority.selector;
        s[8] = IAccessManager.grantRole.selector;
        s[9] = IAccessManager.revokeRole.selector;
    }

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

    /// @dev Risk-manager-restricted setters: routine risk parameters + base token mgmt + the
    ///      `scheduleAllowedInstrRootUpdate` entry point (gated by `onlyRiskManager` in Caliber;
    ///      becomes AM-routed once the Machine's `riskManager` slot is moved to ROYCO_FACTORY).
    function caliberRiskManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = ICaliber.setPositionStaleThreshold.selector;
        s[1] = ICaliber.setMaxPositionIncreaseLossBps.selector;
        s[2] = ICaliber.setMaxPositionDecreaseLossBps.selector;
        s[3] = ICaliber.setMaxSwapLossBps.selector;
        s[4] = ICaliber.setCooldownDuration.selector;
        s[5] = ICaliber.addBaseToken.selector;
        s[6] = ICaliber.removeBaseToken.selector;
        s[7] = ICaliber.scheduleAllowedInstrRootUpdate.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MACHINE — onlyRiskManagerTimelock setters (Caliber's hub-side counterpart)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev All Machine setters gated by `onlyRiskManager` or `onlyRiskManagerTimelock`. Map to
    ///      `<VAULT>_RISK_MANAGER` — both modifiers gate through the same `Machine.riskManager*`
    ///      slots, both re-pointed to RoycoFactory by the migration.
    function machineRiskManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = IMachineRiskManagerSetters.setShareLimit.selector;
        s[1] = IMachineRiskManagerSetters.setCaliberStaleThreshold.selector;
        s[2] = IMachineRiskManagerSetters.setMaxFixedFeeAccrualRate.selector;
        s[3] = IMachineRiskManagerSetters.setMaxPerfFeeAccrualRate.selector;
        s[4] = IMachineRiskManagerSetters.setFeeMintCooldown.selector;
        s[5] = IMachineRiskManagerSetters.setMaxSharePriceChangeRate.selector;
        s[6] = IBridgeController.setOutTransferEnabled.selector;
        s[7] = IBridgeController.setMaxBridgeLossBps.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALIBER MAILBOX — spoke endpoint's onlyRiskManagerTimelock setters
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev On a spoke chain the Caliber's `_hubMachineEndpoint` is a `CaliberMailbox` (no local
    ///      Machine). Its `onlyRiskManagerTimelock` setters — the spoke analogue of the Machine's
    ///      risk surface — map to `<VAULT>_RISK_MANAGER`. `resetBridgingState` is
    ///      `onlySecurityCouncil`, so it is intentionally excluded. `setCooldownDuration(uint256)`
    ///      shares the Caliber selector.
    function mailboxRiskManagerSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = ICaliber.setCooldownDuration.selector;
        s[1] = IBridgeController.setOutTransferEnabled.selector;
        s[2] = IBridgeController.setMaxBridgeLossBps.selector;
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
