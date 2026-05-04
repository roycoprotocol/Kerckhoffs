// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/**
 * @title DawnMigrationAvalancheTest
 * @notice Cross-chain smoke test: Dawn migration applies clean on Avalanche and post-state
 *         matches the canonical configuration. Avalanche has only one market (savUSD).
 *
 * Deliberately a focused subset of the Mainnet suite — full role behavior coverage lives in
 * `DawnMigrationTest`; this file confirms the migration logic is chain-agnostic.
 */
contract DawnMigrationAvalancheTest is RoleBehaviorBase, MigrateDawn {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(AVALANCHE));
        applyToFork(AVALANCHE);
        am = IAccessManager(ROYCO_FACTORY);
    }

    function test_PostState_FNDN_RoleDelays() public view {
        _assertMembership(ADMIN_KERNEL_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ FNDN");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ FNDN");
        _assertMembership(ADMIN_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ROLE @ FNDN");
        _assertMembership(ADMIN_MANAGER, FNDN, DELAY_CRITICAL, "ADMIN_MANAGER @ FNDN");
        _assertMembership(ADMIN_PAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ FNDN");
        _assertMembership(GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ WAY");
    }

    function test_PostState_AdminManager_Wiring() public view {
        require(am.getRoleGuardian(ADMIN_MANAGER) == GUARDIAN_ROLE, "ADMIN_MANAGER guardian mismatch");
        uint64[] memory mgrRoles = _adminManagerRoles();
        for (uint256 i = 0; i < mgrRoles.length; i++) {
            require(am.getRoleAdmin(mgrRoles[i]) == ADMIN_MANAGER, "operational role admin not ADMIN_MANAGER");
        }
        bytes4[] memory adminSel = Selectors.accessManagerAdminSelectors();
        for (uint256 i = 0; i < adminSel.length; i++) {
            require(am.getTargetFunctionRole(ROYCO_FACTORY, adminSel[i]) == ADMIN_MANAGER, "AM admin selector cancel-gate mismatch");
        }
    }

    function test_PostState_TrancheBindings_Consistent() public view {
        string[] memory names = marketNames(AVALANCHE);
        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(AVALANCHE, names[i]);
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "JT burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "ST unpause not ADMIN_UNPAUSER");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "JT unpause not ADMIN_UNPAUSER");
        }
    }

    function test_PostState_Idempotency() public {
        SafeTransaction[] memory rerun = _buildBatch(AVALANCHE);
        require(rerun.length == 0, "re-applying migration on AVAX should produce 0 txs");
    }
}
