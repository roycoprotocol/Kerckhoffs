// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/// @dev Base (chain id 8453) — note the factory here is `ROYCO_FACTORY_BASE`, not the
///      CREATE2 address used on the other chains, so the entry-point / LP wiring is exactly
///      what's most worth asserting here.
contract DawnMigrationBaseTest is RoleBehaviorBase, MigrateDawn {
    address internal ep;

    function setUp() public {
        vm.createSelectFork(_getRpcUrl(BASE));
        applyToFork(BASE);
        am = IAccessManager(roycoFactory(BASE));
        ep = entryPoint(BASE);
    }

    function test_PostState_FNDN_RoleDelays() public view {
        _assertMembership(ADMIN_ROLE, FNDN, DELAY_ROOT, "ADMIN_ROLE @ FNDN");
        _assertMembership(GUARDIAN_ROLE, FNDN, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ FNDN");
        _assertMembership(GUARDIAN_ROLE, FNDN_VETO, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ FNDN_VETO");
        _assertMembership(ADMIN_UNPAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_UNPAUSER_ROLE @ FNDN");
    }

    function test_PostState_WAY_RoleDelays() public view {
        _assertMembership(ADMIN_PAUSER_ROLE, WAY_PAUSE, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ WAY_PAUSE");
        _assertMembership(ADMIN_KERNEL_ROLE, WAY, DELAY_MIN, "ADMIN_KERNEL_ROLE @ WAY");
        _assertMembership(ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_MIN, "ADMIN_ACCOUNTANT_ROLE @ WAY");
        _assertMembership(ADMIN_UPGRADER_ROLE, WAY, DELAY_ROOT, "ADMIN_UPGRADER_ROLE @ WAY");
    }

    function test_PostState_GuardianWiring() public view {
        // Every delayed WAY role must be cancellable via GUARDIAN_ROLE on the Base factory too.
        _assertGuardianWiring(am);
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

    function test_PostState_TrancheBindings_Consistent() public view {
        string[] memory names = marketNames(BASE);
        require(names.length > 0, "no Base markets registered");
        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(BASE, names[i]);
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "ST burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.burn.selector) == BURNER_ROLE, "JT burn not BURNER_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "ST unpause not ADMIN_UNPAUSER");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "JT unpause not ADMIN_UNPAUSER");
            // Deposits are open (PUBLIC_ROLE); redemptions stay gated per-tranche.
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.deposit.selector) == PUBLIC_ROLE, "ST deposit not PUBLIC_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.deposit.selector) == PUBLIC_ROLE, "JT deposit not PUBLIC_ROLE");
            require(am.getTargetFunctionRole(m.seniorTranche, IRoycoVaultTranche.redeem.selector) == ST_LP_ROLE, "ST redeem not ST_LP_ROLE");
            require(am.getTargetFunctionRole(m.juniorTranche, IRoycoVaultTranche.redeem.selector) == JT_LP_ROLE, "JT redeem not JT_LP_ROLE");
        }
    }

    /// @dev ST_LP_ROLE now gates redemption (deposits are public); the EntryPoint holds it.
    function test_StLpRole_Behavior() public view {
        MarketAddresses memory m = getMarketAddresses(BASE, marketNames(BASE)[0]);
        _assertMembership(ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, m.seniorTranche, IRoycoVaultTranche.redeem.selector);
        require(immediate, "ST_LP_ROLE: canCall not immediate");
        require(delay == 0, "ST_LP_ROLE: delay non-zero");
    }

    function test_JtLpRole_Behavior() public view {
        MarketAddresses memory m = getMarketAddresses(BASE, marketNames(BASE)[0]);
        _assertMembership(JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
        (bool immediate, uint32 delay) = am.canCall(ep, m.juniorTranche, IRoycoVaultTranche.redeem.selector);
        require(immediate, "JT_LP_ROLE: canCall not immediate");
        require(delay == 0, "JT_LP_ROLE: delay non-zero");
    }

    function test_PublicDeposit_AnyoneCanDeposit() public view {
        MarketAddresses memory m = getMarketAddresses(BASE, marketNames(BASE)[0]);
        address rando = address(0xD3AD);
        (bool st, uint32 stD) = am.canCall(rando, m.seniorTranche, IRoycoVaultTranche.deposit.selector);
        (bool jt, uint32 jtD) = am.canCall(rando, m.juniorTranche, IRoycoVaultTranche.deposit.selector);
        require(st && stD == 0, "ST deposit not public");
        require(jt && jtD == 0, "JT deposit not public");
    }

    function test_PostState_Idempotency() public {
        SafeTransaction[] memory rerun = _buildBatch(BASE);
        require(rerun.length == 0, "re-applying migration on Base should produce 0 txs");
    }
}
