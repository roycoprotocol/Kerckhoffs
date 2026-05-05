// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

contract DawnMigrationAvalancheTest is RoleBehaviorBase, MigrateDawn {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(AVALANCHE));
        applyToFork(AVALANCHE);
        am = IAccessManager(ROYCO_FACTORY);
    }

    function test_PostState_FNDN_RoleDelays() public view {
        _assertMembership(ADMIN_ROLE, FNDN, DELAY_ROOT, "ADMIN_ROLE @ FNDN");
        _assertMembership(GUARDIAN_ROLE, FNDN, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ FNDN");
        _assertMembership(ADMIN_UNPAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_UNPAUSER_ROLE @ FNDN");
    }

    function test_PostState_WAY_RoleDelays() public view {
        _assertMembership(ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ WAY");
        _assertMembership(ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ WAY");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ WAY");
        _assertMembership(ADMIN_UPGRADER_ROLE, WAY, DELAY_ROOT, "ADMIN_UPGRADER_ROLE @ WAY");
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
