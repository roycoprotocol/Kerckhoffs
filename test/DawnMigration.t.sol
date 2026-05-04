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
 * @notice Verifies the Royco Dawn migration leaves the AccessManager in the canonical post-state
 *         and that every Dawn role behaves as designed (execution / delay enforcement /
 *         cancellability) on a Mainnet fork.
 *
 * Layout:
 *   - `setUp()` — fork + apply Dawn migration.
 *   - `test_PostState_*` — moved from `MigrateDawn._assertTargetState`. Spot-checks the full
 *     desired AM configuration (role grants, delays, selector bindings, guardian wiring).
 *   - `test_<Role>_RoleBehavior` — per role, invokes the three-property check from
 *     `RoleBehaviorBase`.
 *
 * Each test runs in its own snapshot; sequential ops (schedule → fail-immediate-execute →
 * warp + execute → re-schedule → cancel) inside one test exercise the role's full lifecycle.
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
    // POST-STATE ASSERTIONS (moved from MigrateDawn._assertTargetState)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PostState_FNDN_RoleDelays() public view {
        _assertMembership(ADMIN_KERNEL_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ FNDN");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ FNDN");
        _assertMembership(ADMIN_PROTOCOL_FEE_SETTER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_PROTOCOL_FEE_SETTER_ROLE @ FNDN");
        _assertMembership(ADMIN_ORACLE_QUOTER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ORACLE_QUOTER_ROLE @ FNDN");
        _assertMembership(ADMIN_UPGRADER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_UPGRADER_ROLE @ FNDN");
        _assertMembership(DEPLOYER_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE_ADMIN_ROLE @ FNDN");
        _assertMembership(ADMIN_UNPAUSER_ROLE, FNDN, DELAY_STANDARD, "ADMIN_UNPAUSER_ROLE @ FNDN");
        _assertMembership(ADMIN_PAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ FNDN");
        _assertMembership(LP_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE, "LP_ROLE_ADMIN_ROLE @ FNDN");
        _assertMembership(SYNC_ROLE, FNDN, DELAY_IMMEDIATE, "SYNC_ROLE @ FNDN");
        _assertMembership(DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE @ FNDN");
    }

    function test_PostState_WAY_RoleDelays() public view {
        _assertMembership(GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ WAY");
        _assertMembership(ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ WAY");
        _assertMembership(LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE, "LP_ROLE_ADMIN_ROLE @ WAY");
        _assertMembership(SYNC_ROLE, WAY, DELAY_IMMEDIATE, "SYNC_ROLE @ WAY");
        _assertMembership(ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ WAY");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ WAY");
        _assertMembership(ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL, "ADMIN_PROTOCOL_FEE_SETTER_ROLE @ WAY");
    }

    function test_PostState_EntryPoint_Wiring() public view {
        _assertMembership(ADMIN_ENTRY_POINT_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ENTRY_POINT_ROLE @ FNDN");
        _assertMembership(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, DELAY_IMMEDIATE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE @ FNDN");
        _assertMembership(ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
        _assertMembership(JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
        _assertMembership(BURNER_ROLE, ep, DELAY_IMMEDIATE, "BURNER_ROLE @ entryPoint");

        require(am.getRoleGuardian(BURNER_ROLE) == GUARDIAN_ROLE, "BURNER_ROLE guardian mismatch");

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

    /// @dev Every tranche on every market should carry the canonical role bindings (BURNER_ROLE,
    ///      TRANSFER_AGENT_ROLE, LP roles, pause, upgrade) — the migration's `_diffTrancheBindings`
    ///      step backfills any missing binding so role coverage is uniform across the surface.
    function test_PostState_TrancheBindings_Consistent() public view {
        string[] memory names = marketNames(MAINNET);
        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(MAINNET, names[i]);
            // BURNER_ROLE
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burnFrom.selector) == BURNER_ROLE, "ST burnFrom not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "JT burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burnFrom.selector) == BURNER_ROLE, "JT burnFrom not BURNER_ROLE");
            // TRANSFER_AGENT_ROLE
            require(
                am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.seizeShares.selector) == TRANSFER_AGENT_ROLE, "ST seize not TRANSFER_AGENT_ROLE"
            );
            require(
                am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.seizeAndRedeemShares.selector) == TRANSFER_AGENT_ROLE,
                "ST seizeAndRedeem not TRANSFER_AGENT_ROLE"
            );
            require(
                am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.seizeShares.selector) == TRANSFER_AGENT_ROLE, "JT seize not TRANSFER_AGENT_ROLE"
            );
            require(
                am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.seizeAndRedeemShares.selector) == TRANSFER_AGENT_ROLE,
                "JT seizeAndRedeem not TRANSFER_AGENT_ROLE"
            );
            // LP roles
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.deposit.selector) == ST_LP_ROLE, "ST deposit not ST_LP_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.redeem.selector) == ST_LP_ROLE, "ST redeem not ST_LP_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.deposit.selector) == JT_LP_ROLE, "JT deposit not JT_LP_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.redeem.selector) == JT_LP_ROLE, "JT redeem not JT_LP_ROLE");
            // pause / upgrade
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoAuth.pause.selector) == ADMIN_PAUSER_ROLE, "ST pause not ADMIN_PAUSER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoAuth.pause.selector) == ADMIN_PAUSER_ROLE, "JT pause not ADMIN_PAUSER_ROLE");
            require(
                am.getTargetFunctionRole(m.seniorTranche, UUPSUpgradeable.upgradeToAndCall.selector) == ADMIN_UPGRADER_ROLE,
                "ST upgrade not ADMIN_UPGRADER_ROLE"
            );
            require(
                am.getTargetFunctionRole(m.juniorTranche, UUPSUpgradeable.upgradeToAndCall.selector) == ADMIN_UPGRADER_ROLE,
                "JT upgrade not ADMIN_UPGRADER_ROLE"
            );
        }
    }

    function test_PostState_AdminManager_Wiring() public view {
        require(am.getRoleGuardian(ADMIN_MANAGER) == GUARDIAN_ROLE, "ADMIN_MANAGER guardian mismatch");
        _assertMembership(ADMIN_MANAGER, FNDN, DELAY_CRITICAL, "ADMIN_MANAGER @ FNDN");

        uint64[] memory mgrRoles = _adminManagerRoles();
        for (uint256 i = 0; i < mgrRoles.length; i++) {
            require(am.getRoleAdmin(mgrRoles[i]) == ADMIN_MANAGER, "operational role admin not ADMIN_MANAGER");
        }
        bytes4[] memory adminSel = Selectors.accessManagerAdminSelectors();
        for (uint256 i = 0; i < adminSel.length; i++) {
            require(am.getTargetFunctionRole(ROYCO_FACTORY, adminSel[i]) == ADMIN_MANAGER, "AM admin selector cancel-gate mismatch");
        }
    }

    function test_PostState_AdminRole_Delay() public view {
        _assertMembership(ADMIN_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ROLE @ FNDN");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — Immediate roles
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Properties: membership + canCall(true, 0) + execution succeeds.
    // No delay enforcement / cancellation possible (Immediate, no scheduling).

    function test_AdminPauserRole_Behavior_FNDN() public {
        _assertImmediateRoleBehavior("ADMIN_PAUSER_ROLE @ FNDN", ADMIN_PAUSER_ROLE, FNDN, ep, abi.encodeCall(IRoycoAuth.pause, ()));
    }

    function test_AdminPauserRole_Behavior_WAY() public {
        _assertImmediateRoleBehavior("ADMIN_PAUSER_ROLE @ WAY", ADMIN_PAUSER_ROLE, WAY, ep, abi.encodeCall(IRoycoAuth.pause, ()));
    }

    function test_AdminEntryPointClaimFeeRole_Behavior() public {
        bytes memory data = abi.encodeCall(IRoycoEntryPoint.collectProtocolFees, (new address[](0), new uint256[](0), FNDN));
        _assertImmediateRoleBehavior("ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE @ FNDN", ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, ep, data);
    }

    function test_SyncRole_Behavior_FNDN() public {
        // SYNC_ROLE gates kernel.syncTrancheAccounting — pick the first market's kernel as target.
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        _assertImmediateRoleBehavior("SYNC_ROLE @ FNDN", SYNC_ROLE, FNDN, kernel, abi.encodeCall(IRoycoKernel.syncTrancheAccounting, ()));
    }

    function test_SyncRole_Behavior_WAY() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        _assertImmediateRoleBehavior("SYNC_ROLE @ WAY", SYNC_ROLE, WAY, kernel, abi.encodeCall(IRoycoKernel.syncTrancheAccounting, ()));
    }

    function test_LpRoleAdminRole_Behavior_FNDN() public {
        // LP_ROLE_ADMIN_ROLE is the admin of ST_LP_ROLE / JT_LP_ROLE — exercising = grantRole on AM.
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ST_LP_ROLE, address(0xA11CE), 0));
        _assertImmediateRoleBehavior("LP_ROLE_ADMIN_ROLE @ FNDN", LP_ROLE_ADMIN_ROLE, FNDN, ROYCO_FACTORY, data);
    }

    function test_LpRoleAdminRole_Behavior_WAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ST_LP_ROLE, address(0xB0B), 0));
        _assertImmediateRoleBehavior("LP_ROLE_ADMIN_ROLE @ WAY", LP_ROLE_ADMIN_ROLE, WAY, ROYCO_FACTORY, data);
    }

    function test_DeployerRoleAdminRole_Behavior() public {
        // DEPLOYER_ROLE_ADMIN_ROLE is the admin of DEPLOYER_ROLE — exercising = grantRole on AM.
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (DEPLOYER_ROLE, address(0xCAFE), 0));
        _assertImmediateRoleBehavior("DEPLOYER_ROLE_ADMIN_ROLE @ FNDN", DEPLOYER_ROLE_ADMIN_ROLE, FNDN, ROYCO_FACTORY, data);
    }

    function test_DeployerRole_Behavior() public {
        // DEPLOYER_ROLE gates RoycoFactory.deployMarket — verify membership + canCall.
        // We don't actually invoke deployMarket since the params are non-trivial; just verify the AM gate.
        _assertMembership(DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE @ FNDN");
        (bool immediate, uint32 delay) = am.canCall(FNDN, ROYCO_FACTORY, IRoycoFactory.deployMarket.selector);
        require(immediate, "DEPLOYER_ROLE: canCall not immediate");
        require(delay == 0, "DEPLOYER_ROLE: canCall delay non-zero");
    }

    function test_GuardianRole_Behavior() public {
        // GUARDIAN_ROLE gates `cancel` (not via setTargetFunctionRole, but via the guardian lookup
        // baked into AM.cancel). Membership is the operative check; cancel mechanics are exercised
        // by every other delayed-role test in this suite.
        _assertMembership(GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ WAY");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — Delayed roles
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Properties: membership + canCall(false, delay) + schedule + cannot-bypass + execute-after-warp + cancel.

    function test_AdminUnpauserRole_Behavior() public {
        bytes memory data = abi.encodeCall(IRoycoAuth.unpause, ());
        _assertDelayedRoleBehavior("ADMIN_UNPAUSER_ROLE @ FNDN", ADMIN_UNPAUSER_ROLE, FNDN, DELAY_STANDARD, ep, data, WAY);
    }

    function test_AdminUpgraderRole_Behavior() public {
        bytes memory data = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(0xBEEF), ""));
        _assertDelayedRoleBehavior("ADMIN_UPGRADER_ROLE @ FNDN", ADMIN_UPGRADER_ROLE, FNDN, DELAY_CRITICAL, ep, data, WAY);
    }

    function test_AdminEntryPointRole_Behavior() public {
        bytes memory data = abi.encodeCall(IRoycoEntryPoint.modifyTrancheConfigs, (new address[](0), new IRoycoEntryPoint.TrancheConfig[](0)));
        _assertDelayedRoleBehavior("ADMIN_ENTRY_POINT_ROLE @ FNDN", ADMIN_ENTRY_POINT_ROLE, FNDN, DELAY_CRITICAL, ep, data, WAY);
    }

    function test_AdminKernelRole_Behavior_FNDN() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        bytes memory data = abi.encodeCall(IRoycoKernel.setProtocolFeeRecipient, (FNDN));
        _assertDelayedRoleBehavior("ADMIN_KERNEL_ROLE @ FNDN", ADMIN_KERNEL_ROLE, FNDN, DELAY_CRITICAL, kernel, data, WAY);
    }

    function test_AdminKernelRole_Behavior_WAY() public {
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        bytes memory data = abi.encodeCall(IRoycoKernel.setProtocolFeeRecipient, (WAY));
        _assertDelayedRoleBehavior("ADMIN_KERNEL_ROLE @ WAY", ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, kernel, data, FNDN);
    }

    function test_AdminAccountantRole_Behavior_FNDN() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setBeta, (uint96(0)));
        _assertDelayedRoleBehavior("ADMIN_ACCOUNTANT_ROLE @ FNDN", ADMIN_ACCOUNTANT_ROLE, FNDN, DELAY_CRITICAL, accountant, data, WAY);
    }

    function test_AdminAccountantRole_Behavior_WAY() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setBeta, (uint96(1)));
        _assertDelayedRoleBehavior("ADMIN_ACCOUNTANT_ROLE @ WAY", ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, accountant, data, FNDN);
    }

    function test_AdminProtocolFeeSetterRole_Behavior_FNDN() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setSeniorTrancheProtocolFee, (uint64(0)));
        _assertDelayedRoleBehavior("ADMIN_PROTOCOL_FEE_SETTER_ROLE @ FNDN", ADMIN_PROTOCOL_FEE_SETTER_ROLE, FNDN, DELAY_CRITICAL, accountant, data, WAY);
    }

    function test_AdminProtocolFeeSetterRole_Behavior_WAY() public {
        address accountant = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).accountant;
        bytes memory data = abi.encodeCall(IRoycoAccountant.setSeniorTrancheProtocolFee, (uint64(1)));
        _assertDelayedRoleBehavior("ADMIN_PROTOCOL_FEE_SETTER_ROLE @ WAY", ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL, accountant, data, FNDN);
    }

    function test_AdminOracleQuoterRole_Behavior() public {
        // setConversionRate(uint256, bool) is on the kernel (it inherits the quoter).
        address kernel = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).kernel;
        bytes memory data = abi.encodeWithSignature("setConversionRate(uint256,bool)", uint256(1e18), false);
        _assertDelayedRoleBehavior("ADMIN_ORACLE_QUOTER_ROLE @ FNDN", ADMIN_ORACLE_QUOTER_ROLE, FNDN, DELAY_CRITICAL, kernel, data, WAY);
    }

    function test_AdminManagerRole_Behavior() public {
        // ADMIN_MANAGER is admin of every operational role — exercising = grantRole on AM.
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xDEAD), 0));
        _assertDelayedRoleBehavior("ADMIN_MANAGER @ FNDN", ADMIN_MANAGER, FNDN, DELAY_CRITICAL, ROYCO_FACTORY, data, WAY);
    }

    function test_AdminRole_Behavior() public {
        // ADMIN_ROLE call-gate is hardcoded in OZ AM for admin selectors. Cancel-gate is wired
        // through ADMIN_MANAGER (via storage write), so WAY is the cancel authority.
        bytes memory data = abi.encodeCall(IAccessManager.labelRole, (ADMIN_PAUSER_ROLE, "test"));
        _assertDelayedRoleBehavior("ADMIN_ROLE @ FNDN", ADMIN_ROLE, FNDN, DELAY_CRITICAL, ROYCO_FACTORY, data, WAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — Roles where holder is the EntryPoint contract (self-grants)
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // ST_LP_ROLE / JT_LP_ROLE / BURNER_ROLE are held by the entry point itself so it can
    // relay user ops into the senior/junior tranches. Holder is the entry point contract
    // (not FNDN/WAY), and these are Immediate. Test = membership + canCall(true, 0).

    function test_StLpRole_Behavior() public {
        address senior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).seniorTranche;
        // ST_LP_ROLE gates deposit on the senior tranche; entry point holds it.
        _assertMembership(ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, senior, IRoycoVaultTranche.deposit.selector);
        require(immediate, "ST_LP_ROLE: canCall not immediate");
        require(delay == 0, "ST_LP_ROLE: delay non-zero");
    }

    function test_JtLpRole_Behavior() public {
        address junior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).juniorTranche;
        _assertMembership(JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, junior, IRoycoVaultTranche.deposit.selector);
        require(immediate, "JT_LP_ROLE: canCall not immediate");
        require(delay == 0, "JT_LP_ROLE: delay non-zero");
    }

    function test_BurnerRole_Behavior() public view {
        // BURNER_ROLE is held by the entry point so it can burn shares for yield forfeiture.
        // Migration's `_diffTrancheBindings` guarantees burn/burnFrom is bound on every tranche.
        _assertMembership(BURNER_ROLE, ep, DELAY_IMMEDIATE, "BURNER_ROLE @ entryPoint");
        require(am.getRoleGuardian(BURNER_ROLE) == GUARDIAN_ROLE, "BURNER_ROLE guardian mismatch");
        require(am.getRoleAdmin(BURNER_ROLE) == ADMIN_MANAGER, "BURNER_ROLE admin mismatch");

        // Spot-check the binding actually routes to BURNER_ROLE on the first market's senior tranche.
        address senior = getMarketAddresses(MAINNET, marketNames(MAINNET)[0]).seniorTranche;
        require(am.getTargetFunctionRole(senior, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
        require(am.getTargetFunctionRole(senior, IRoycoVaultTranche.burnFrom.selector) == BURNER_ROLE, "ST burnFrom not BURNER_ROLE");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE BEHAVIOR — TRANSFER_AGENT_ROLE
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Held by Securitize. Outside the standard delay tiers. Test what's testable: there's
    // no on-chain holder yet — so just verify the role-gating wiring on the kernel/tranche
    // is in place, and any (non-existent) holder doesn't pass canCall.

    function test_TransferAgentRole_Wiring() public view {
        // No assertion on a specific holder — Securitize hasn't been granted the role on-chain.
        // What we can verify: the role exists as a role ID, getRoleAdmin returns ADMIN_MANAGER
        // (after Dawn migration's setRoleAdmin sweep).
        require(am.getRoleAdmin(TRANSFER_AGENT_ROLE) == ADMIN_MANAGER, "TRANSFER_AGENT_ROLE admin not ADMIN_MANAGER");
    }
}
