// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IMakinaGovernable } from "makina-core/src/interfaces/IMakinaGovernable.sol";

import { MigrateMakina } from "../script/migrate/Makina.s.sol";
import { Selectors } from "../src/access/Selectors.sol";
import { RoleBehaviorBase } from "./_RoleBehaviorBase.sol";

/**
 * @title MakinaAssertions
 * @notice Shared, chain-generic post-state checks for the Makina migration. Works for the hub
 *         (mainnet: endpoint = Machine) and the spokes (Arbitrum/Base: endpoint = CaliberMailbox),
 *         selecting the endpoint's risk-manager selector set from `s.spoke`.
 */
abstract contract MakinaAssertions is RoleBehaviorBase, MigrateMakina {
    function _assertMakinaWiring(uint256 _chainId, string memory _vaultName, uint64 _riskRole, uint64 _tlRole) internal view {
        StrategyStack memory s = getStrategyStack(_chainId, _vaultName);
        address factory = roycoFactory(_chainId);

        // Roles held by WAY @ 72h, cancellable via GUARDIAN_ROLE.
        _assertMembership(_riskRole, WAY, DELAY_MIN, string.concat(_vaultName, "_RISK_MANAGER @ WAY"));
        _assertMembership(_tlRole, WAY, DELAY_MIN, string.concat(_vaultName, "_TIMELOCK_MANAGER @ WAY"));
        require(am.getRoleGuardian(_riskRole) == GUARDIAN_ROLE, "RISK_MANAGER guardian mismatch");
        require(am.getRoleGuardian(_tlRole) == GUARDIAN_ROLE, "TIMELOCK_MANAGER guardian mismatch");

        // Caliber: risk-manager setters → RISK_MANAGER; setTimelockDuration → TIMELOCK_MANAGER.
        bytes4[] memory rmSel = Selectors.caliberRiskManagerSelectors();
        for (uint256 j = 0; j < rmSel.length; j++) {
            require(am.getTargetFunctionRole(s.caliber, rmSel[j]) == _riskRole, "Caliber risk-manager selector mismatch");
        }
        require(am.getTargetFunctionRole(s.caliber, ICaliber.setTimelockDuration.selector) == _tlRole, "Caliber timelock-manager selector mismatch");

        // Endpoint: Machine (hub) or CaliberMailbox (spoke) risk-manager setters → RISK_MANAGER.
        bytes4[] memory epSel = s.spoke ? Selectors.mailboxRiskManagerSelectors() : Selectors.machineRiskManagerSelectors();
        for (uint256 j = 0; j < epSel.length; j++) {
            require(am.getTargetFunctionRole(s.endpoint, epSel[j]) == _riskRole, "Endpoint risk-manager selector mismatch");
        }

        // Pre-simulated Makina-governance re-point: BOTH riskManager and riskManagerTimelock on the
        // endpoint point at the chain's RoycoFactory so onlyRiskManager[Timelock] gate through the AM.
        require(IMakinaGovernable(s.endpoint).riskManager() == factory, "endpoint riskManager not RoycoFactory");
        require(IMakinaGovernable(s.endpoint).riskManagerTimelock() == factory, "endpoint riskManagerTimelock not RoycoFactory");
    }
}
