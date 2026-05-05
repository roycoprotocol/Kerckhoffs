// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { IRoycoAccountant } from "royco-dawn/src/interfaces/IRoycoAccountant.sol";
import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";
import { IRoycoFactory } from "royco-dawn/src/interfaces/IRoycoFactory.sol";
import { IRoycoKernel } from "royco-dawn/src/interfaces/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/**
 * @title DawnMigrationTest
 * @notice Mainnet-fork tests for the WAY-centric Dawn migration. Verifies post-state for both
 *         WAY (parameter-update holder) and FNDN (cancellation + role-management holder), and
 *         exercises every role's behavior triplet (execute / delay-enforced / cancellable).
 */
contract DawnMigrationTest is RoleBehaviorBase, MigrateDawn {
    address internal ep;

    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
        ep = entryPoint(MAINNET);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE ASSERTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PostState_FNDN_RoleDelays() public view {
        // FNDN holds: ADMIN_ROLE @ 7d (role management), GUARDIAN_ROLE @ Immediate (cancel),
        //             ADMIN_UNPAUSER_ROLE @ Immediate, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE @ Immediate,
        //             DEPLOYER_ROLE @ Immediate (market deployment).
        _assertMembership(ADMIN_ROLE, FNDN, DELAY_ROOT, "ADMIN_ROLE @ FNDN");
        _assertMembership(GUARDIAN_ROLE, FNDN, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ FNDN");
        _assertMembership(ADMIN_UNPAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_UNPAUSER_ROLE @ FNDN");
        _assertMembership(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, DELAY_IMMEDIATE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE @ FNDN");
        _assertMembership(DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE @ FNDN");
    }

    function test_PostState_WAY_RoleDelays() public view {
        // WAY holds every parameter-update role plus ADMIN_PAUSER_ROLE, LP_ROLE_ADMIN_ROLE,
        // SYNC_ROLE, and ADMIN_UPGRADER_ROLE. FNDN is NOT a co-holder of any operational role.
        _assertMembership(ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ WAY");
        _assertMembership(LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE, "LP_ROLE_ADMIN_ROLE @ WAY");
        _assertMembership(SYNC_ROLE, WAY, DELAY_IMMEDIATE, "SYNC_ROLE @ WAY");
        _assertMembership(ADMIN_ORACLE_QUOTER_ROLE, WAY, DELAY_STANDARD, "ADMIN_ORACLE_QUOTER_ROLE @ WAY");
        _assertMembership(DEPLOYER_ROLE_ADMIN_ROLE, WAY, DELAY_STANDARD, "DEPLOYER_ROLE_ADMIN_ROLE @ WAY");
        _assertMembership(ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ WAY");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ WAY");
        _assertMembership(ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL, "ADMIN_PROTOCOL_FEE_SETTER_ROLE @ WAY");
        _assertMembership(ADMIN_ENTRY_POINT_ROLE, WAY, DELAY_CRITICAL, "ADMIN_ENTRY_POINT_ROLE @ WAY");
        _assertMembership(ADMIN_UPGRADER_ROLE, WAY, DELAY_ROOT, "ADMIN_UPGRADER_ROLE @ WAY");
    }

    function test_PostState_StaleHolders_Revoked() public view {
        // FNDN should NOT hold WAY-only roles after migration.
        uint64[] memory waOnly = _wayOnlyRoles();
        for (uint256 i = 0; i < waOnly.length; i++) {
            (bool isMember,) = am.hasRole(waOnly[i], FNDN);
            require(!isMember, "FNDN still holds a WAY-only role");
        }
        // WAY should NOT hold GUARDIAN_ROLE.
        (bool wayHasGuardian,) = am.hasRole(GUARDIAN_ROLE, WAY);
        require(!wayHasGuardian, "WAY still holds GUARDIAN_ROLE");
    }

    function test_PostState_EntryPoint_Wiring() public view {
        _assertMembership(ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
        _assertMembership(JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
        _assertMembership(BURNER_ROLE, ep, DELAY_IMMEDIATE, "BURNER_ROLE @ entryPoint");

        require(am.getRoleGuardian(BURNER_ROLE) == GUARDIAN_ROLE, "BURNER_ROLE guardian mismatch");
        require(am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE) == GUARDIAN_ROLE, "ADMIN_ENTRY_POINT_ROLE guardian mismatch");
        require(am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE) == GUARDIAN_ROLE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE guardian mismatch");

        require(am.getTargetFunctionRole(ep, IRoycoEntryPoint.modifyTrancheConfigs.selector) == ADMIN_ENTRY_POINT_ROLE, "EP modifyTrancheConfigs role mismatch");
        require(
            am.getTargetFunctionRole(ep, IRoycoEntryPoint.collectProtocolFees.selector) == ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE,
            "EP collectProtocolFees role mismatch"
        );
        require(am.getTargetFunctionRole(ep, IRoycoAuth.pause.selector) == ADMIN_PAUSER_ROLE, "EP pause role mismatch");
        require(am.getTargetFunctionRole(ep, IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "EP unpause role mismatch");
        require(am.getTargetFunctionRole(ep, UUPSUpgradeable.upgradeToAndCall.selector) == ADMIN_UPGRADER_ROLE, "EP upgrade role mismatch");

        bytes4[] memory lp = Selectors.entryPointLPSelectors();
        for (uint256 i = 0; i < lp.length; i++) {
            require(am.getTargetFunctionRole(ep, lp[i]) == PUBLIC_ROLE, "EP LP selector role mismatch");
        }
    }

    function test_PostState_UnpauseRebind() public view {
        require(am.getRoleGuardian(ADMIN_UNPAUSER_ROLE) == GUARDIAN_ROLE, "ADMIN_UNPAUSER_ROLE guardian mismatch");
        address[] memory targets = _pausableTargets(MAINNET);
        for (uint256 i = 0; i < targets.length; i++) {
            require(am.getTargetFunctionRole(targets[i], IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "unpause role mismatch");
        }
    }

    function test_PostState_TrancheBindings_Consistent() public view {
        string[] memory names = marketNames(MAINNET);
        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(MAINNET, names[i]);
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burnFrom.selector) == BURNER_ROLE, "ST burnFrom not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "JT burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burnFrom.selector) == BURNER_ROLE, "JT burnFrom not BURNER_ROLE");
            require(
                am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.seizeShares.selector) == TRANSFER_AGENT_ROLE, "ST seize not TRANSFER_AGENT_ROLE"
            );
            require(
                am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.seizeShares.selector) == TRANSFER_AGENT_ROLE, "JT seize not TRANSFER_AGENT_ROLE"
            );
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.deposit.selector) == ST_LP_ROLE, "ST deposit not ST_LP_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.deposit.selector) == JT_LP_ROLE, "JT deposit not JT_LP_ROLE");
        }
    }

    function test_PostState_Idempotency() public {
        SafeTransaction[] memory rerun = _buildBatch(MAINNET);
        require(rerun.length == 0, "re-applying migration should produce 0 txs (diff converged)");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — Immediate roles
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AdminPauserRole_Behavior_WAY() public {
        _assertImmediateRoleBehavior("ADMIN_PAUSER_ROLE @ WAY", ADMIN_PAUSER_ROLE, WAY, ep, abi.encodeCall(IRoycoAuth.pause, ()));
    }

    function test_AdminUnpauserRole_Behavior_FNDN() public {
        _assertImmediateRoleBehavior("ADMIN_UNPAUSER_ROLE @ FNDN", ADMIN_UNPAUSER_ROLE, FNDN, ep, abi.encodeCall(IRoycoAuth.unpause, ()));
    }

    function test_AdminEntryPointClaimFeeRole_Behavior_FNDN() public {
        bytes memory data = abi.encodeCall(IRoycoEntryPoint.collectProtocolFees, (new address[](0), new uint256[](0), FNDN));
        _assertImmediateRoleBehavior("ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE @ FNDN", ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, ep, data);
    }

    function test_SyncRole_Behavior_WAY() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        _assertImmediateRoleBehavior("SYNC_ROLE @ WAY", SYNC_ROLE, WAY, kernel, abi.encodeCall(IRoycoKernel.syncTrancheAccounting, ()));
    }

    function test_LpRoleAdminRole_Behavior_WAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ST_LP_ROLE, address(0xB0B), 0));
        _assertImmediateRoleBehavior("LP_ROLE_ADMIN_ROLE @ WAY", LP_ROLE_ADMIN_ROLE, WAY, ROYCO_FACTORY, data);
    }

    function test_DeployerRole_Behavior_FNDN() public view {
        _assertMembership(DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE @ FNDN");
        (bool immediate, uint32 delay) = am.canCall(FNDN, ROYCO_FACTORY, IRoycoFactory.deployMarket.selector);
        require(immediate, "DEPLOYER_ROLE: canCall not immediate");
        require(delay == 0, "DEPLOYER_ROLE: canCall delay non-zero");
    }

    function test_GuardianRole_Behavior_FNDN() public view {
        _assertMembership(GUARDIAN_ROLE, FNDN, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ FNDN");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — Delayed roles (held by WAY, cancellable by FNDN)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AdminUpgraderRole_Behavior_WAY() public {
        bytes memory data = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(0xBEEF), ""));
        _assertDelayedRoleBehavior("ADMIN_UPGRADER_ROLE @ WAY", ADMIN_UPGRADER_ROLE, WAY, DELAY_ROOT, ep, data, FNDN);
    }

    function test_AdminEntryPointRole_Behavior_WAY() public {
        bytes memory data = abi.encodeCall(IRoycoEntryPoint.modifyTrancheConfigs, (new address[](0), new IRoycoEntryPoint.TrancheConfig[](0)));
        _assertDelayedRoleBehavior("ADMIN_ENTRY_POINT_ROLE @ WAY", ADMIN_ENTRY_POINT_ROLE, WAY, DELAY_CRITICAL, ep, data, FNDN);
    }

    function test_AdminKernelRole_Behavior_WAY() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        bytes memory data = abi.encodeCall(IRoycoKernel.setProtocolFeeRecipient, (FNDN));
        _assertDelayedRoleBehavior("ADMIN_KERNEL_ROLE @ WAY", ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, kernel, data, FNDN);
    }

    function test_AdminAccountantRole_Behavior_WAY() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setBeta, (uint96(0)));
        _assertDelayedRoleBehavior("ADMIN_ACCOUNTANT_ROLE @ WAY", ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, accountant, data, FNDN);
    }

    function test_AdminProtocolFeeSetterRole_Behavior_WAY() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setSeniorTrancheProtocolFee, (uint64(0)));
        _assertDelayedRoleBehavior("ADMIN_PROTOCOL_FEE_SETTER_ROLE @ WAY", ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL, accountant, data, FNDN);
    }

    function test_AdminOracleQuoterRole_Behavior_WAY() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        bytes memory data = abi.encodeWithSignature("setConversionRate(uint256,bool)", uint256(1e18), false);
        _assertDelayedRoleBehavior("ADMIN_ORACLE_QUOTER_ROLE @ WAY", ADMIN_ORACLE_QUOTER_ROLE, WAY, DELAY_STANDARD, kernel, data, FNDN);
    }

    function test_DeployerRoleAdminRole_Behavior_WAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (DEPLOYER_ROLE, address(0xCAFE), 0));
        _assertDelayedRoleBehavior("DEPLOYER_ROLE_ADMIN_ROLE @ WAY", DEPLOYER_ROLE_ADMIN_ROLE, WAY, DELAY_STANDARD, ROYCO_FACTORY, data, FNDN);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — ADMIN_ROLE (FNDN, 7d, intentionally non-cancellable by others)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AdminRole_DelayedAndExecutable_FNDN() public {
        // FNDN can grant a role via ADMIN_ROLE @ 7d. No one but FNDN can cancel.
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xDEAD), 0));
        bytes32 opId = am.hashOperation(FNDN, address(am), data);

        vm.prank(FNDN);
        am.schedule(address(am), data, 0);
        require(am.getSchedule(opId) > 0, "schedule did not queue");

        // Cannot bypass delay
        vm.prank(FNDN);
        vm.expectRevert();
        am.execute(address(am), data);

        // WAY cannot cancel (default cancel guardian for AM-self admin selectors = ADMIN_ROLE,
        // and we deliberately did NOT do the cancel-gate hack).
        vm.prank(WAY);
        vm.expectRevert();
        am.cancel(FNDN, address(am), data);

        // Random EOA cannot cancel
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        am.cancel(FNDN, address(am), data);

        // FNDN can self-cancel
        vm.prank(FNDN);
        am.cancel(FNDN, address(am), data);
        require(am.getSchedule(opId) == 0, "FNDN self-cancel failed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — entry point self-grants (membership only)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_StLpRole_Behavior() public view {
        address senior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).seniorTranche;
        _assertMembership(ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, senior, IRoycoVaultTranche.deposit.selector);
        require(immediate, "ST_LP_ROLE: canCall not immediate");
        require(delay == 0, "ST_LP_ROLE: delay non-zero");
    }

    function test_JtLpRole_Behavior() public view {
        address junior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).juniorTranche;
        _assertMembership(JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, junior, IRoycoVaultTranche.deposit.selector);
        require(immediate, "JT_LP_ROLE: canCall not immediate");
        require(delay == 0, "JT_LP_ROLE: delay non-zero");
    }

    function test_BurnerRole_Behavior() public view {
        _assertMembership(BURNER_ROLE, ep, DELAY_IMMEDIATE, "BURNER_ROLE @ entryPoint");
        require(am.getRoleGuardian(BURNER_ROLE) == GUARDIAN_ROLE, "BURNER_ROLE guardian mismatch");
        address senior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).seniorTranche;
        require(am.getTargetFunctionRole(senior, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NEGATIVE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Negative_FNDNCannotPause() public {
        // FNDN no longer holds ADMIN_PAUSER_ROLE under the new model.
        (bool isMember,) = am.hasRole(ADMIN_PAUSER_ROLE, FNDN);
        require(!isMember, "FNDN should not hold ADMIN_PAUSER_ROLE");
        bytes memory data = abi.encodeCall(IRoycoAuth.pause, ());
        vm.prank(FNDN);
        vm.expectRevert();
        am.execute(ep, data);
    }

    function test_Negative_WAYCannotUnpause() public {
        // WAY does NOT hold ADMIN_UNPAUSER_ROLE — only FNDN unpauses.
        (bool isMember,) = am.hasRole(ADMIN_UNPAUSER_ROLE, WAY);
        require(!isMember, "WAY should not hold ADMIN_UNPAUSER_ROLE");
    }

    function test_Negative_WAYCannotGrantRoles() public {
        // Only FNDN holds ADMIN_ROLE; WAY can't call grantRole on operational roles.
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xA11CE), 0));
        vm.prank(WAY);
        vm.expectRevert();
        am.schedule(address(am), data, 0);
    }

    function test_Negative_RandomAccountCannotCancel() public {
        bytes memory data = abi.encodeCall(IRoycoAuth.unpause, ());
        // Schedule via WAY's ADMIN_UPGRADER_ROLE on entry point as a stand-in for any delayed op.
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(0xBEEF), ""));
        vm.prank(WAY);
        am.schedule(ep, upgradeData, 0);
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        am.cancel(WAY, ep, upgradeData);
        // Suppress unused warning
        data;
    }
}
