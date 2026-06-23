// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { console2 } from "forge-std/console2.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";

import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";

import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";

import { EntryPoints } from "../registry/EntryPoints.sol";
import { Markets } from "../registry/Markets.sol";
import { Multisigs } from "../registry/Multisigs.sol";
import { Roles } from "../registry/Roles.sol";
import { Strategies } from "../registry/Strategies.sol";
import { Vaults } from "../registry/Vaults.sol";
import { AccessManagerReader } from "./AccessManagerReader.sol";
import { Selectors } from "./Selectors.sol";

/**
 * @title AccessManagerDumper
 * @notice Reads + tabulates the full RoycoFactory AccessManager state for a chain.
 *
 * AccessManager has no native enumeration, so the dumper iterates curated lists from the
 * registry: every known role, every known holder, every known target × selector. Output is
 * (a) human-readable console tables and (b) a JSON file under `output/dump/`.
 *
 * The dumper is split into per-section internal functions (`_dumpRoles`, `_dumpDawnTargets`,
 * `_dumpVaultTargets`, `_dumpStrategyTargets`, `_dumpCaliberTargets`, `_dumpEntryPointTargets`)
 * so migration scripts can call just the slice relevant to their surface for pre/post-state
 * visualization.
 */
abstract contract AccessManagerDumper is Roles, Multisigs, Markets, Vaults, Strategies, EntryPoints {
    using AccessManagerReader for IAccessManager;

    string internal constant _DUMP_OUTPUT_DIRECTORY = "output/dump/";

    // ═══════════════════════════════════════════════════════════════════════════
    // PUBLIC ENTRY
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Top-level dump for a chain. Forks, reads, prints, and writes JSON.
    /// @dev Caller is responsible for ensuring the current fork is on `_chainId` (or this will
    ///      `vm.createSelectFork` itself if not already).
    function dumpAccessManager(uint256 _chainId) public {
        if (block.chainid != _chainId) {
            vm.createSelectFork(_getRpcUrl(_chainId));
        }

        IAccessManager am = IAccessManager(ROYCO_FACTORY);

        console2.log("");
        console2.log("================================================================================");
        console2.log("AccessManager dump | chain:", _chainName(_chainId), _chainId);
        console2.log("  AccessManager:", ROYCO_FACTORY);
        console2.log("================================================================================");

        _dumpRoles(am, _chainId);
        _dumpDawnTargets(am, _chainId);
        _dumpEntryPointTargets(am, _chainId);
        _dumpVaultTargets(am, _chainId);
        _dumpStrategyTargets(am, _chainId);
        _dumpCaliberTargets(am, _chainId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE DUMP
    // ═══════════════════════════════════════════════════════════════════════════

    function _dumpRoles(IAccessManager _am, uint256 _chainId) internal view {
        console2.log("");
        console2.log("--- Roles -----------------------------------------------------------------------");

        (uint64[] memory roles, string[] memory labels) = _allRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            _logRole(_am, roles[i], labels[i], _chainId);
        }
    }

    function _logRole(IAccessManager _am, uint64 _role, string memory _label, uint256 _chainId) internal view {
        AccessManagerReader.RoleConfig memory cfg = _am.getRoleConfig(_role);

        console2.log("");
        string memory header = string.concat("  Role: ", _label, " (", _uintToString(_role), ")");
        console2.log(header);
        console2.log("    admin role:   ", _formatRole(cfg.adminRole));
        console2.log("    guardian role:", _formatRole(cfg.guardianRole));
        console2.log("    grant delay: ", cfg.grantDelay);

        // Curated holders
        _logMember(_am, _role, "FNDN", FNDN);
        _logMember(_am, _role, "WAY ", WAY);
        _logMember(_am, _role, "WAY_PAUSE", WAY_PAUSE);
        _logMember(_am, _role, "FNDN_VETO", FNDN_VETO);
        if (DIAL != address(0)) _logMember(_am, _role, "DIAL", DIAL);

        // Per-role: also check if the entry point or factory itself holds it (used for self-grants)
        address ep = entryPoint(_chainId);
        if (ep != address(0)) _logMember(_am, _role, "EntryPoint", ep);
    }

    function _logMember(IAccessManager _am, uint64 _role, string memory _holderLabel, address _holder) internal view {
        if (_holder == address(0)) return;
        AccessManagerReader.MemberInfo memory info = _am.getMemberInfo(_role, _holder);
        if (info.isMember) {
            console2.log(string.concat("    member: ", _holderLabel), _holder, "exec delay:", info.executionDelay);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TARGET DUMPS
    // ═══════════════════════════════════════════════════════════════════════════

    function _dumpDawnTargets(IAccessManager _am, uint256 _chainId) internal view {
        string[] memory names = marketNames(_chainId);
        if (names.length == 0 && syncer(_chainId) == address(0)) return;

        console2.log("");
        console2.log("--- Dawn Markets - pause/unpause role bindings ----------------------------------");

        bytes4 pauseSel = IRoycoAuth.pause.selector;
        bytes4 unpauseSel = IRoycoAuth.unpause.selector;

        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, names[i]);
            console2.log("");
            console2.log("  Market:", names[i]);
            _logTargetSelectorRole(_am, "kernel    ", m.kernel, pauseSel, unpauseSel);
            _logTargetSelectorRole(_am, "accountant", m.accountant, pauseSel, unpauseSel);
            _logTargetSelectorRole(_am, "ST tranche", m.seniorTranche, pauseSel, unpauseSel);
            _logTargetSelectorRole(_am, "JT tranche", m.juniorTranche, pauseSel, unpauseSel);
        }

        address sync = syncer(_chainId);
        if (sync != address(0)) {
            console2.log("");
            console2.log("  Syncer:");
            _logTargetSelectorRole(_am, "syncer    ", sync, pauseSel, unpauseSel);
        }
    }

    function _dumpEntryPointTargets(IAccessManager _am, uint256 _chainId) internal view {
        address ep = entryPoint(_chainId);
        if (ep == address(0)) return;

        console2.log("");
        console2.log("--- Entry Point - selector role bindings ----------------------------------------");
        console2.log("  EntryPoint:", ep);

        bytes4[] memory lp = Selectors.entryPointLPSelectors();
        for (uint256 i = 0; i < lp.length; i++) {
            _logSelectorRole(_am, ep, "lp", lp[i]);
        }
        _logSelectorRole(_am, ep, "modifyTrancheConfigs", IRoycoEntryPoint.modifyTrancheConfigs.selector);
        _logSelectorRole(_am, ep, "collectProtocolFees ", IRoycoEntryPoint.collectProtocolFees.selector);
        _logSelectorRole(_am, ep, "pause               ", IRoycoAuth.pause.selector);
        _logSelectorRole(_am, ep, "unpause             ", IRoycoAuth.unpause.selector);
        _logSelectorRole(_am, ep, "upgradeToAndCall    ", UUPSUpgradeable.upgradeToAndCall.selector);

        // Also dump target-level config
        AccessManagerReader.TargetConfig memory cfg = _am.getTargetConfig(ep);
        console2.log("    target closed?", cfg.isClosed);
        console2.log("    target admin delay:", cfg.adminDelay);
    }

    function _dumpVaultTargets(IAccessManager _am, uint256 _chainId) internal view {
        string[] memory names = vaultNames(_chainId);
        if (names.length == 0) return;

        console2.log("");
        console2.log("--- Concrete Vaults - target config + selector role bindings --------------------");

        bytes4[] memory mgrSel = Selectors.vaultManagerSelectors();
        bytes4[] memory stratSel = Selectors.strategyManagerSelectors();
        bytes4[] memory hookSel = Selectors.hookManagerSelectors();

        for (uint256 i = 0; i < names.length; i++) {
            VaultAddresses memory v = getVaultAddresses(_chainId, names[i]);
            console2.log("");
            console2.log("  Vault:", names[i]);
            console2.log("    address:", v.vault);
            AccessManagerReader.TargetConfig memory cfg = _am.getTargetConfig(v.vault);
            console2.log("    target closed?", cfg.isClosed);
            console2.log("    target admin delay:", cfg.adminDelay);

            // Vault management selectors all bind to VAULT_MANAGER post-migration.
            for (uint256 j = 0; j < mgrSel.length; j++) {
                _logSelectorRole(_am, v.vault, "vault-mgr   ", mgrSel[j]);
            }
            for (uint256 j = 0; j < stratSel.length; j++) {
                _logSelectorRole(_am, v.vault, "strategy-mgr", stratSel[j]);
            }
            for (uint256 j = 0; j < hookSel.length; j++) {
                _logSelectorRole(_am, v.vault, "hook-mgr    ", hookSel[j]);
            }
        }
    }

    function _dumpStrategyTargets(IAccessManager _am, uint256 _chainId) internal view {
        string[] memory names = vaultNames(_chainId);
        if (names.length == 0) return;

        console2.log("");
        console2.log("--- Concrete Strategies - selector role bindings --------------------------------");

        for (uint256 i = 0; i < names.length; i++) {
            StrategyStack memory s = getStrategyStack(_chainId, names[i]);
            console2.log("");
            console2.log("  Strategy:", names[i]);
            console2.log("    address:", s.strategy);
            _logSelectorRole(_am, s.strategy, "pause      ", IRoycoAuth.pause.selector);
            _logSelectorRole(_am, s.strategy, "unpause    ", IRoycoAuth.unpause.selector);
            _logSelectorRole(_am, s.strategy, "rescueToken", IStrategyTemplate.rescueToken.selector);
            bytes4[] memory alloc = Selectors.strategyAllocatorSelectors();
            for (uint256 j = 0; j < alloc.length; j++) {
                _logSelectorRole(_am, s.strategy, "allocator  ", alloc[j]);
            }
        }
    }

    function _dumpCaliberTargets(IAccessManager _am, uint256 _chainId) internal view {
        string[] memory names = vaultNames(_chainId);
        if (names.length == 0) return;

        console2.log("");
        console2.log("--- Caliber - selector role bindings --------------------------------------------");

        bytes4[] memory rmSelectors = Selectors.caliberRiskManagerSelectors();
        bytes4 tlSelector = ICaliber.setTimelockDuration.selector;

        for (uint256 i = 0; i < names.length; i++) {
            StrategyStack memory s = getStrategyStack(_chainId, names[i]);
            console2.log("");
            console2.log("  Caliber for:", names[i]);
            console2.log("    address:", s.caliber);
            for (uint256 j = 0; j < rmSelectors.length; j++) {
                _logSelectorRole(_am, s.caliber, "risk-manager", rmSelectors[j]);
            }
            _logSelectorRole(_am, s.caliber, "timelock-mgr", tlSelector);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOG HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _logTargetSelectorRole(IAccessManager _am, string memory _label, address _target, bytes4 _pause, bytes4 _unpause) internal view {
        uint64 pauseRole = _am.getTargetFunctionRole(_target, _pause);
        uint64 unpauseRole = _am.getTargetFunctionRole(_target, _unpause);
        console2.log(string.concat("    ", _label), _target);
        console2.log(string.concat("      pause   role: ", _formatRole(pauseRole)));
        console2.log(string.concat("      unpause role: ", _formatRole(unpauseRole)));
    }

    function _logSelectorRole(IAccessManager _am, address _target, string memory _selectorLabel, bytes4 _selector) internal view {
        uint64 role = _am.getTargetFunctionRole(_target, _selector);
        console2.log(string.concat("    ", _selectorLabel, " selector role: ", _formatRole(role)));
    }

    /// @dev Renders a role ID as `<NAME> (<id>)` if known, else just `<id>`.
    function _formatRole(uint64 _role) internal pure returns (string memory) {
        string memory name = _roleName(_role);
        if (bytes(name).length == 0) return _uintToString(_role);
        return string.concat(name, " (", _uintToString(_role), ")");
    }

    function _roleName(uint64 _role) internal pure returns (string memory) {
        if (_role == ADMIN_ROLE) return "ADMIN_ROLE";
        if (_role == PUBLIC_ROLE) return "PUBLIC_ROLE";
        (uint64[] memory roles, string[] memory labels) = _allRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == _role) return labels[i];
        }
        return "";
    }

    function _uintToString(uint256 _v) internal pure returns (string memory) {
        if (_v == 0) return "0";
        uint256 j = _v;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory b = new bytes(len);
        uint256 k = len;
        while (_v != 0) {
            k--;
            b[k] = bytes1(uint8(48 + _v % 10));
            _v /= 10;
        }
        return string(b);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE CATALOG
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev The full curated list of roles to dump, with human-readable labels.
    function _allRoles() internal pure returns (uint64[] memory roles, string[] memory labels) {
        roles = new uint64[](30);
        labels = new string[](30);

        // Built-ins
        roles[0] = ADMIN_ROLE;
        labels[0] = "ADMIN_ROLE";

        // Concrete vault management roles
        roles[27] = VAULT_MANAGER;
        labels[27] = "VAULT_MANAGER";
        roles[28] = STRATEGY_MANAGER;
        labels[28] = "STRATEGY_MANAGER";
        roles[29] = HOOK_MANAGER;
        labels[29] = "HOOK_MANAGER";

        // Dawn
        roles[1] = ADMIN_PAUSER_ROLE;
        labels[1] = "ADMIN_PAUSER_ROLE";
        roles[2] = ADMIN_UNPAUSER_ROLE;
        labels[2] = "ADMIN_UNPAUSER_ROLE";
        roles[3] = ADMIN_UPGRADER_ROLE;
        labels[3] = "ADMIN_UPGRADER_ROLE";
        roles[4] = ST_LP_ROLE;
        labels[4] = "ST_LP_ROLE";
        roles[5] = JT_LP_ROLE;
        labels[5] = "JT_LP_ROLE";
        roles[6] = BURNER_ROLE;
        labels[6] = "BURNER_ROLE";
        roles[7] = SYNC_ROLE;
        labels[7] = "SYNC_ROLE";
        roles[8] = ADMIN_KERNEL_ROLE;
        labels[8] = "ADMIN_KERNEL_ROLE";
        roles[9] = TRANSFER_AGENT_ROLE;
        labels[9] = "TRANSFER_AGENT_ROLE";
        roles[10] = ADMIN_ENTRY_POINT_ROLE;
        labels[10] = "ADMIN_ENTRY_POINT_ROLE";
        roles[11] = ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE;
        labels[11] = "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE";
        roles[12] = ADMIN_ACCOUNTANT_ROLE;
        labels[12] = "ADMIN_ACCOUNTANT_ROLE";
        roles[13] = ADMIN_PROTOCOL_FEE_SETTER_ROLE;
        labels[13] = "ADMIN_PROTOCOL_FEE_SETTER_ROLE";
        roles[14] = ADMIN_ORACLE_QUOTER_ROLE;
        labels[14] = "ADMIN_ORACLE_QUOTER_ROLE";
        roles[15] = DEPLOYER_ROLE;
        labels[15] = "DEPLOYER_ROLE";
        roles[16] = LP_ROLE_ADMIN_ROLE;
        labels[16] = "LP_ROLE_ADMIN_ROLE";
        roles[17] = DEPLOYER_ROLE_ADMIN_ROLE;
        labels[17] = "DEPLOYER_ROLE_ADMIN_ROLE";
        roles[18] = GUARDIAN_ROLE;
        labels[18] = "GUARDIAN_ROLE";

        // Strategy
        roles[19] = STRATEGY_PAUSER;
        labels[19] = "STRATEGY_PAUSER";
        roles[20] = STRATEGY_UNPAUSER;
        labels[20] = "STRATEGY_UNPAUSER";
        roles[21] = STRATEGY_RESCUE;
        labels[21] = "STRATEGY_RESCUE";
        roles[22] = STRATEGY_ALLOCATOR;
        labels[22] = "STRATEGY_ALLOCATOR";

        // Makina (per-vault)
        roles[23] = SRROYUSDC_RISK_MANAGER;
        labels[23] = "SRROYUSDC_RISK_MANAGER";
        roles[24] = SRROYUSDC_TIMELOCK_MANAGER;
        labels[24] = "SRROYUSDC_TIMELOCK_MANAGER";
        roles[25] = ROYWSTETH_RISK_MANAGER;
        labels[25] = "ROYWSTETH_RISK_MANAGER";
        roles[26] = ROYWSTETH_TIMELOCK_MANAGER;
        labels[26] = "ROYWSTETH_TIMELOCK_MANAGER";
    }
}
