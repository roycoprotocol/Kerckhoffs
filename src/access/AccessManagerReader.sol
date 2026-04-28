// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

/**
 * @title AccessManagerReader
 * @notice Thin view wrappers around `IAccessManager` for the read-side of the dumper.
 *
 * AccessManager has no native enumeration, so callers must feed in a curated list of roles,
 * holders, targets, and selectors. This contract just packages the per-query reads.
 */
library AccessManagerReader {
    struct RoleConfig {
        uint64 adminRole;
        uint64 guardianRole;
        uint32 grantDelay;
    }

    struct MemberInfo {
        bool isMember;
        uint32 executionDelay;
    }

    struct TargetConfig {
        bool isClosed;
        uint32 adminDelay;
    }

    function getRoleConfig(IAccessManager _am, uint64 _role) internal view returns (RoleConfig memory cfg) {
        cfg.adminRole = _am.getRoleAdmin(_role);
        cfg.guardianRole = _am.getRoleGuardian(_role);
        cfg.grantDelay = _am.getRoleGrantDelay(_role);
    }

    function getMemberInfo(IAccessManager _am, uint64 _role, address _holder) internal view returns (MemberInfo memory info) {
        (info.isMember, info.executionDelay) = _am.hasRole(_role, _holder);
    }

    function getTargetConfig(IAccessManager _am, address _target) internal view returns (TargetConfig memory cfg) {
        cfg.isClosed = _am.isTargetClosed(_target);
        cfg.adminDelay = _am.getTargetAdminDelay(_target);
    }

    function getTargetFunctionRoleBatch(IAccessManager _am, address _target, bytes4[] memory _selectors) internal view returns (uint64[] memory roles) {
        roles = new uint64[](_selectors.length);
        for (uint256 i = 0; i < _selectors.length; i++) {
            roles[i] = _am.getTargetFunctionRole(_target, _selectors[i]);
        }
    }
}
