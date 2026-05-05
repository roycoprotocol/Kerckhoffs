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
 * @notice Verifies the Vaults migration:
 *   - AM holds every native AccessControl role on each vault (Phase 1).
 *   - Every vault selector (management + native admin) routes through `VAULT_MANAGER` held
 *     by WAY @ Critical 48h, FNDN-cancellable.
 *   - Strategy roles: WAY pauses Immediate, FNDN unpauses Immediate, FNDN rescues @ 30d
 *     (FNDN-cancellable), DIAL allocates Immediate.
 *
 * Setup chain: Vaults FIRST (so FNDN's ADMIN_ROLE is still Immediate to drive phase-2 calls),
 * then Dawn (lockdown raises FNDN's ADMIN_ROLE to 7d).
 */
contract VaultsMigrationTest is RoleBehaviorBase, MigrateVaults {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET);
        new MigrateDawn().applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PostState_srRoyUSDC_NativeRolesOnAM() public view {
        _assertNativeRolesOnAM(SRROYUSDC);
    }

    function test_PostState_roywstETH_NativeRolesOnAM() public view {
        _assertNativeRolesOnAM(ROYWSTETH);
    }

    function test_PostState_srRoyUSDC_NoNonAMNativeHolders() public view {
        _assertOnlyAMHoldsNativeRoles(SRROYUSDC);
    }

    function test_PostState_roywstETH_NoNonAMNativeHolders() public view {
        _assertOnlyAMHoldsNativeRoles(ROYWSTETH);
    }

    function test_PostState_srRoyUSDC_VaultManagerWiring() public view {
        _assertVaultManagerWiring(SRROYUSDC);
    }

    function test_PostState_roywstETH_VaultManagerWiring() public view {
        _assertVaultManagerWiring(ROYWSTETH);
    }

    function test_PostState_srRoyUSDC_StrategyRoleConfig() public view {
        _assertStrategyRoleConfig(SRROYUSDC);
    }

    function test_PostState_roywstETH_StrategyRoleConfig() public view {
        _assertStrategyRoleConfig(ROYWSTETH);
    }

    function test_PostState_ConcreteVaultRoles_HoldersAndGuardians() public view {
        // Three per-concrete-role AM roles, each WAY @ 48h, FNDN-cancellable.
        _assertMembership(VAULT_MANAGER, WAY, DELAY_CRITICAL, "VAULT_MANAGER @ WAY");
        _assertMembership(STRATEGY_MANAGER, WAY, DELAY_CRITICAL, "STRATEGY_MANAGER @ WAY");
        _assertMembership(HOOK_MANAGER, WAY, DELAY_CRITICAL, "HOOK_MANAGER @ WAY");
        require(am.getRoleGuardian(VAULT_MANAGER) == GUARDIAN_ROLE, "VAULT_MANAGER guardian mismatch");
        require(am.getRoleGuardian(STRATEGY_MANAGER) == GUARDIAN_ROLE, "STRATEGY_MANAGER guardian mismatch");
        require(am.getRoleGuardian(HOOK_MANAGER) == GUARDIAN_ROLE, "HOOK_MANAGER guardian mismatch");
        // FNDN should NOT hold any of them.
        (bool a,) = am.hasRole(VAULT_MANAGER, FNDN);
        (bool b,) = am.hasRole(STRATEGY_MANAGER, FNDN);
        (bool c,) = am.hasRole(HOOK_MANAGER, FNDN);
        require(!a && !b && !c, "FNDN unexpectedly holds a vault management role");
    }

    function _assertNativeRolesOnAM(string memory _vaultName) internal view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        IConcreteVault vault = IConcreteVault(v.vault);
        bytes32[] memory native = _nativeRoles();
        for (uint256 i = 0; i < native.length; i++) {
            require(vault.hasRole(native[i], ROYCO_FACTORY), string.concat(_vaultName, ": AM is not a native role member"));
        }
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

    function _assertVaultManagerWiring(string memory _vaultName) internal view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, _vaultName);
        bytes4[] memory mgrSel = Selectors.vaultManagerSelectors();
        for (uint256 i = 0; i < mgrSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, mgrSel[i]) == VAULT_MANAGER, "vault management selector not bound to VAULT_MANAGER");
        }
        bytes4[] memory stratSel = Selectors.strategyManagerSelectors();
        for (uint256 i = 0; i < stratSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, stratSel[i]) == STRATEGY_MANAGER, "strategy management selector not bound to STRATEGY_MANAGER");
        }
        bytes4[] memory hookSel = Selectors.hookManagerSelectors();
        for (uint256 i = 0; i < hookSel.length; i++) {
            require(am.getTargetFunctionRole(v.vault, hookSel[i]) == HOOK_MANAGER, "hook management selector not bound to HOOK_MANAGER");
        }
        // vault.grantRole / vault.revokeRole are intentionally NOT bound to a specific role —
        // they fall through to the default (`ADMIN_ROLE`), so adding new holders to a native
        // vault role requires FNDN's 7d ADMIN_ROLE flow.
        require(am.getTargetFunctionRole(v.vault, IConcreteVault.grantRole.selector) == ADMIN_ROLE, "vault.grantRole should default to ADMIN_ROLE");
        require(am.getTargetFunctionRole(v.vault, IConcreteVault.revokeRole.selector) == ADMIN_ROLE, "vault.revokeRole should default to ADMIN_ROLE");
    }

    function _assertStrategyRoleConfig(string memory _vaultName) internal view {
        StrategyStack memory s = getStrategyStack(MAINNET, _vaultName);
        require(am.getTargetFunctionRole(s.strategy, IRoycoAuth.pause.selector) == STRATEGY_PAUSER, "Strategy pause role mismatch");
        require(am.getTargetFunctionRole(s.strategy, IRoycoAuth.unpause.selector) == STRATEGY_UNPAUSER, "Strategy unpause role mismatch");
        require(am.getTargetFunctionRole(s.strategy, IStrategyTemplate.rescueToken.selector) == STRATEGY_RESCUE, "Strategy rescueToken role mismatch");

        _assertMembership(STRATEGY_PAUSER, WAY, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_PAUSER @ WAY"));
        _assertMembership(STRATEGY_UNPAUSER, FNDN, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_UNPAUSER @ FNDN"));
        _assertMembership(STRATEGY_RESCUE, FNDN, DELAY_RESCUE, string.concat(_vaultName, " STRATEGY_RESCUE @ FNDN"));
        _assertMembership(STRATEGY_ALLOCATOR, DIAL, DELAY_IMMEDIATE, string.concat(_vaultName, " STRATEGY_ALLOCATOR @ DIAL"));
        require(am.getRoleGuardian(STRATEGY_RESCUE) == GUARDIAN_ROLE, "STRATEGY_RESCUE guardian mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VAULT_MANAGER behavior — WAY @ 48h, FNDN-cancellable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VaultManagement_srRoyUSDC_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, SRROYUSDC);
        bytes4[] memory sel = Selectors.vaultManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(SRROYUSDC, " VAULT_MANAGER"), VAULT_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    function test_VaultManagement_roywstETH_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, ROYWSTETH);
        bytes4[] memory sel = Selectors.vaultManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(ROYWSTETH, " VAULT_MANAGER"), VAULT_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    // vault.grantRole / vault.revokeRole default to ADMIN_ROLE (FNDN @ 7d). Verify a delayed
    // FNDN call works. (Cancellable only by FNDN itself, since AM admin selector cancel-gate
    // wasn't wired in the new model — see DawnMigrationTest::test_AdminRole_*.)
    function test_VaultGrantRole_srRoyUSDC_FNDNGated() public view {
        VaultAddresses memory v = getVaultAddresses(MAINNET, SRROYUSDC);
        (bool immediate, uint32 delay) = am.canCall(FNDN, v.vault, IConcreteVault.grantRole.selector);
        require(!immediate, "vault.grantRole should be delayed for FNDN (ADMIN_ROLE @ 7d)");
        require(delay == DELAY_ROOT, "vault.grantRole delay mismatch");
    }

    function test_StrategyManagement_srRoyUSDC_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, SRROYUSDC);
        bytes4[] memory sel = Selectors.strategyManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(SRROYUSDC, " STRATEGY_MANAGER"), STRATEGY_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    function test_HookManagement_srRoyUSDC_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, SRROYUSDC);
        bytes4[] memory sel = Selectors.hookManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(SRROYUSDC, " HOOK_MANAGER"), HOOK_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    function test_StrategyManagement_roywstETH_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, ROYWSTETH);
        bytes4[] memory sel = Selectors.strategyManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(ROYWSTETH, " STRATEGY_MANAGER"), STRATEGY_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    function test_HookManagement_roywstETH_DelayedAndCancellable() public {
        VaultAddresses memory v = getVaultAddresses(MAINNET, ROYWSTETH);
        bytes4[] memory sel = Selectors.hookManagerSelectors();
        bytes memory data = abi.encodeWithSelector(sel[0]);
        _assertDelayedRoleBehavior(string.concat(ROYWSTETH, " HOOK_MANAGER"), HOOK_MANAGER, WAY, DELAY_CRITICAL, v.vault, data, FNDN);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Strategy role behavior
    // ═══════════════════════════════════════════════════════════════════════════

    function test_StrategyPauserRole_srRoyUSDC_WAY_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(IRoycoAuth.pause, ());
        _assertImmediateRoleBehavior(string.concat(SRROYUSDC, " STRATEGY_PAUSER @ WAY"), STRATEGY_PAUSER, WAY, s.strategy, data);
    }

    function test_StrategyUnpauserRole_srRoyUSDC_FNDN_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(IRoycoAuth.unpause, ());
        _assertImmediateRoleBehavior(string.concat(SRROYUSDC, " STRATEGY_UNPAUSER @ FNDN"), STRATEGY_UNPAUSER, FNDN, s.strategy, data);
    }

    function test_StrategyRescueRole_srRoyUSDC_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(IStrategyTemplate.rescueToken, (address(0xDEAD), uint256(0)));
        _assertDelayedRoleBehavior(string.concat(SRROYUSDC, " STRATEGY_RESCUE @ FNDN"), STRATEGY_RESCUE, FNDN, DELAY_RESCUE, s.strategy, data, FNDN);
    }

    function test_StrategyAllocatorRole_srRoyUSDC_DIAL_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, SRROYUSDC);
        bytes memory data = abi.encodeCall(IStrategyTemplate.allocateFunds, (""));
        _assertImmediateRoleBehavior(string.concat(SRROYUSDC, " STRATEGY_ALLOCATOR @ DIAL"), STRATEGY_ALLOCATOR, DIAL, s.strategy, data);
    }

    function test_StrategyPauserRole_roywstETH_WAY_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(IRoycoAuth.pause, ());
        _assertImmediateRoleBehavior(string.concat(ROYWSTETH, " STRATEGY_PAUSER @ WAY"), STRATEGY_PAUSER, WAY, s.strategy, data);
    }

    function test_StrategyUnpauserRole_roywstETH_FNDN_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(IRoycoAuth.unpause, ());
        _assertImmediateRoleBehavior(string.concat(ROYWSTETH, " STRATEGY_UNPAUSER @ FNDN"), STRATEGY_UNPAUSER, FNDN, s.strategy, data);
    }

    function test_StrategyRescueRole_roywstETH_DelayedAndCancellable() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(IStrategyTemplate.rescueToken, (address(0xDEAD), uint256(0)));
        _assertDelayedRoleBehavior(string.concat(ROYWSTETH, " STRATEGY_RESCUE @ FNDN"), STRATEGY_RESCUE, FNDN, DELAY_RESCUE, s.strategy, data, FNDN);
    }

    function test_StrategyAllocatorRole_roywstETH_DIAL_Immediate() public {
        StrategyStack memory s = getStrategyStack(MAINNET, ROYWSTETH);
        bytes memory data = abi.encodeCall(IStrategyTemplate.allocateFunds, (""));
        _assertImmediateRoleBehavior(string.concat(ROYWSTETH, " STRATEGY_ALLOCATOR @ DIAL"), STRATEGY_ALLOCATOR, DIAL, s.strategy, data);
    }
}
