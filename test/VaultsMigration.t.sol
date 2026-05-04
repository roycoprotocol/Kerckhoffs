// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";

import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { IConcreteVault, MigrateVaults } from "../script/migrate/Vaults.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/**
 * @title VaultsMigrationTest
 * @notice Verifies the Vaults migration leaves the AccessManager + concrete vault native state
 *         in the canonical post-state, and that vault management + strategy roles behave as
 *         designed (execution / delay enforcement / cancellability).
 *
 * Setup chain: Dawn migration first (so ADMIN_MANAGER exists), then Vaults migration per vault.
 *
 * Vault management functions (`updateManagementFee`, `updatePerformanceFee`, `setDeposit/WithdrawLimits`,
 * `addStrategy`, `removeStrategy`, `toggleStrategyStatus`, `setHooks`) are bound directly to
 * `ADMIN_MANAGER` — there are no per-vault management roles. So vault-level role behavior is
 * already exercised by `DawnMigrationTest::test_AdminManagerRole_Behavior`. This file focuses on:
 *   - **Native vault state**: AM holds every native AccessControl role on each vault.
 *   - **Vault selector bindings**: management selectors -> ADMIN_MANAGER, including
 *     `vault.grantRole` / `vault.revokeRole` for the cancel-path.
 *   - **Strategy roles**: per-strategy STRATEGY_PAUSER / UNPAUSER / RESCUE / ALLOCATOR.
 */
contract VaultsMigrationTest is RoleBehaviorBase, MigrateVaults {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        // Apply Vaults FIRST — phase-2 AM calls run via FNDN's ADMIN_ROLE which is still
        // Immediate (0 delay) at this point. Dawn migration is the lockdown step that raises
        // ADMIN_ROLE to Critical 48h, so it must run AFTER Vaults / Makina.
        applyToFork(MAINNET);
        new MigrateDawn().applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE ASSERTIONS — per vault
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PostState_srRoyUSDC_NativeRolesOnAM() public view {
        _assertNativeRolesOnAM(SRROYUSDC);
    }

    function test_PostState_srRoyUSDC_VaultSelectorBindings() public view {
        _assertVaultSelectorBindings(SRROYUSDC);
    }

    function test_PostState_srRoyUSDC_StrategySelectorBindings() public view {
        _assertStrategySelectorBindings(SRROYUSDC);
    }

    function test_PostState_srRoyUSDC_StrategyRoleConfig() public view {
        _assertStrategyRoleConfig(SRROYUSDC);
    }

    function test_PostState_roywstETH_NativeRolesOnAM() public view {
        _assertNativeRolesOnAM(ROYWSTETH);
    }

    function test_PostState_roywstETH_VaultSelectorBindings() public view {
        _assertVaultSelectorBindings(ROYWSTETH);
    }

    function test_PostState_roywstETH_StrategySelectorBindings() public view {
        _assertStrategySelectorBindings(ROYWSTETH);
    }

    function test_PostState_roywstETH_StrategyRoleConfig() public view {
        _assertStrategyRoleConfig(ROYWSTETH);
    }

    function _assertNativeRolesOnAM(string memory _vaultName) internal view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        IConcreteVault vault = IConcreteVault(v.vault);
        bytes32[] memory native = _nativeRoles();
        for (uint256 i = 0; i < native.length; i++) {
            require(vault.hasRole(native[i], ROYCO_FACTORY), string.concat(_vaultName, ": AM is not a native role member"));
        }
    }

    function _assertVaultSelectorBindings(string memory _vaultName) internal view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        bytes4[] memory mgrSel = Selectors.vaultManagerSelectors();
        for (uint256 i = 0; i < mgrSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, mgrSel[i]) == ADMIN_MANAGER, "vault management selector not bound to ADMIN_MANAGER");
        }
        bytes4[] memory stratSel = Selectors.strategyManagerSelectors();
        for (uint256 i = 0; i < stratSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, stratSel[i]) == ADMIN_MANAGER, "strategy management selector not bound to ADMIN_MANAGER");
        }
        bytes4[] memory hookSel = Selectors.hookManagerSelectors();
        for (uint256 i = 0; i < hookSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, hookSel[i]) == ADMIN_MANAGER, "hook management selector not bound to ADMIN_MANAGER");
        }
        // Native AccessControl admin functions on the vault.
        require(am.getTargetFunctionRole(v.vault, IConcreteVault.grantRole.selector) == ADMIN_MANAGER, "vault.grantRole not bound to ADMIN_MANAGER");
        require(am.getTargetFunctionRole(v.vault, IConcreteVault.revokeRole.selector) == ADMIN_MANAGER, "vault.revokeRole not bound to ADMIN_MANAGER");
    }

    function _assertStrategySelectorBindings(string memory _vaultName) internal view {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        require(am.getTargetFunctionRole(s.strategy, IRoycoAuth.pause.selector) == STRATEGY_PAUSER, "Strategy pause role mismatch");
        require(am.getTargetFunctionRole(s.strategy, IRoycoAuth.unpause.selector) == STRATEGY_UNPAUSER, "Strategy unpause role mismatch");
        require(am.getTargetFunctionRole(s.strategy, IStrategyTemplate.rescueToken.selector) == STRATEGY_RESCUE, "Strategy rescueToken role mismatch");
        bytes4[] memory allocSel = Selectors.strategyAllocatorSelectors();
        for (uint256 i = 0; i < allocSel.length; i++) {
            require(am.getTargetFunctionRole(s.strategy, allocSel[i]) == STRATEGY_ALLOCATOR, "Strategy allocator selector mismatch");
        }
    }

    /// @dev Phase 1 not only grants AM the native roles but also revokes them from prior
    ///      non-AM holders so the AM is the unique admin pathway. Verify both halves.
    function test_PostState_srRoyUSDC_NoNonAMNativeHolders() public view {
        _assertOnlyAMHoldsNativeRoles(SRROYUSDC);
    }

    function test_PostState_roywstETH_NoNonAMNativeHolders() public view {
        _assertOnlyAMHoldsNativeRoles(ROYWSTETH);
    }

    function _assertOnlyAMHoldsNativeRoles(string memory _vaultName) internal view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        IConcreteVault vault = IConcreteVault(v.vault);
        bytes32[] memory native = _nativeRoles();
        for (uint256 i = 0; i < native.length; i++) {
            uint256 count = vault.getRoleMemberCount(native[i]);
            for (uint256 j = 0; j < count; j++) {
                address holder = vault.getRoleMember(native[i], j);
                require(holder == ROYCO_FACTORY, "non-AM holder still has native role");
            }
        }
    }

    function test_PostState_Phase2_FixedShape() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, SRROYUSDC);
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        // Phase 2 builder is non-diff (re-emits the full set every time). Verify it produces
        // the documented fixed shape: 4 vault binds + 4 strategy labels + 4 strategy binds +
        // 2 setRoleGuardian + 5 grants = 19. (Re-executing post-Dawn-lockdown isn't realistic
        // since FNDN's ADMIN_ROLE is now 48h; that's the expected operational shape.)
        SafeTransaction[] memory phase2 = _buildPhase2AM(v.vault, s.strategy, SRROYUSDC);
        require(phase2.length == 19, "Vaults phase 2 should be exactly 19 txs");
    }

    function _assertStrategyRoleConfig(string memory _vaultName) internal view {
        _assertMembership(STRATEGY_PAUSER, FNDN, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_PAUSER @ FNDN"));
        _assertMembership(STRATEGY_PAUSER, WAY, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_PAUSER @ WAY"));
        _assertMembership(STRATEGY_UNPAUSER, FNDN, DELAY_STANDARD, string.concat(_vaultName, " STRATEGY_UNPAUSER @ FNDN"));
        _assertMembership(STRATEGY_RESCUE, FNDN, DELAY_RESCUE, string.concat(_vaultName, " STRATEGY_RESCUE @ FNDN"));
        require(am.getRoleGuardian(STRATEGY_UNPAUSER) == GUARDIAN_ROLE, "STRATEGY_UNPAUSER guardian mismatch");
        require(am.getRoleGuardian(STRATEGY_RESCUE) == GUARDIAN_ROLE, "STRATEGY_RESCUE guardian mismatch");
        _assertMembership(STRATEGY_ALLOCATOR, DIAL, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_ALLOCATOR @ DIAL"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — vault-management (collapsed onto ADMIN_MANAGER)
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // These exercise the same role (ADMIN_MANAGER, FNDN @ 48h) as
    // `DawnMigrationTest::test_AdminManagerRole_Behavior`, but against vault-side selectors
    // — verifying the binding actually routes through the role's gating + cancel-path.

    function test_VaultManagement_srRoyUSDC_DelayedAndCancellable() public {
        _assertVaultManagementBehavior(SRROYUSDC);
    }

    function test_VaultManagement_roywstETH_DelayedAndCancellable() public {
        _assertVaultManagementBehavior(ROYWSTETH);
    }

    function _assertVaultManagementBehavior(string memory _vaultName) internal {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        // Pick one vault management selector; behavior is identical for the others (all bound to ADMIN_MANAGER).
        bytes4[] memory sel = Selectors.vaultManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(_vaultName, " vault management -> ADMIN_MANAGER"), ADMIN_MANAGER, FNDN, DELAY_CRITICAL, v.vault, data, WAY);
    }

    // Native vault role admin (vault.grantRole / vault.revokeRole) — bound to ADMIN_MANAGER.
    function test_VaultGrantRole_srRoyUSDC_DelayedAndCancellable() public {
        _assertVaultGrantRoleBehavior(SRROYUSDC);
    }

    function test_VaultGrantRole_roywstETH_DelayedAndCancellable() public {
        _assertVaultGrantRoleBehavior(ROYWSTETH);
    }

    function _assertVaultGrantRoleBehavior(string memory _vaultName) internal {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(IConcreteVault.grantRole, (Selectors.nativeVaultManager(), address(0xCAFE)));
        _assertDelayedRoleBehavior(string.concat(_vaultName, " vault.grantRole -> ADMIN_MANAGER"), ADMIN_MANAGER, FNDN, DELAY_CRITICAL, v.vault, data, WAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — strategy roles
    // ═══════════════════════════════════════════════════════════════════════════

    function test_StrategyPauserRole_srRoyUSDC_FNDN_Immediate() public {
        _assertStrategyPauserImmediate(SRROYUSDC, FNDN);
    }

    function test_StrategyPauserRole_srRoyUSDC_WAY_Immediate() public {
        _assertStrategyPauserImmediate(SRROYUSDC, WAY);
    }

    function test_StrategyPauserRole_roywstETH_FNDN_Immediate() public {
        _assertStrategyPauserImmediate(ROYWSTETH, FNDN);
    }

    function test_StrategyPauserRole_roywstETH_WAY_Immediate() public {
        _assertStrategyPauserImmediate(ROYWSTETH, WAY);
    }

    function _assertStrategyPauserImmediate(string memory _vaultName, address _holder) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(IRoycoAuth.pause, ());
        _assertImmediateRoleBehavior(string.concat(_vaultName, " STRATEGY_PAUSER"), STRATEGY_PAUSER, _holder, s.strategy, data);
    }

    function test_StrategyUnpauserRole_srRoyUSDC_DelayedAndCancellable() public {
        _assertStrategyUnpauserDelayed(SRROYUSDC);
    }

    function test_StrategyUnpauserRole_roywstETH_DelayedAndCancellable() public {
        _assertStrategyUnpauserDelayed(ROYWSTETH);
    }

    function _assertStrategyUnpauserDelayed(string memory _vaultName) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(IRoycoAuth.unpause, ());
        _assertDelayedRoleBehavior(string.concat(_vaultName, " STRATEGY_UNPAUSER"), STRATEGY_UNPAUSER, FNDN, DELAY_STANDARD, s.strategy, data, WAY);
    }

    function test_StrategyRescueRole_srRoyUSDC_DelayedAndCancellable() public {
        _assertStrategyRescueDelayed(SRROYUSDC);
    }

    function test_StrategyRescueRole_roywstETH_DelayedAndCancellable() public {
        _assertStrategyRescueDelayed(ROYWSTETH);
    }

    function _assertStrategyRescueDelayed(string memory _vaultName) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(IStrategyTemplate.rescueToken, (address(0xDEAD), uint256(0)));
        _assertDelayedRoleBehavior(string.concat(_vaultName, " STRATEGY_RESCUE"), STRATEGY_RESCUE, FNDN, DELAY_RESCUE, s.strategy, data, WAY);
    }

    function test_StrategyAllocatorRole_srRoyUSDC_DIAL_Immediate() public {
        _assertStrategyAllocatorImmediate(SRROYUSDC);
    }

    function test_StrategyAllocatorRole_roywstETH_DIAL_Immediate() public {
        _assertStrategyAllocatorImmediate(ROYWSTETH);
    }

    function _assertStrategyAllocatorImmediate(string memory _vaultName) internal {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        bytes memory data = abi.encodeCall(IStrategyTemplate.allocateFunds, (""));
        _assertImmediateRoleBehavior(string.concat(_vaultName, " STRATEGY_ALLOCATOR @ DIAL"), STRATEGY_ALLOCATOR, DIAL, s.strategy, data);
    }
}
