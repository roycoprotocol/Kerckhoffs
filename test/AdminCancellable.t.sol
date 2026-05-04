// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Test } from "forge-std/Test.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";

/**
 * @title AdminCancellableTest
 * @notice Verifies that after the Dawn migration, every AccessManager admin operation FNDN
 *         schedules can be cancelled by WAY (the GUARDIAN_ROLE holder).
 *
 * The cancel surface comes from two mechanisms wired in `MigrateDawn._diffAdminManager`:
 *
 *   - `setRoleAdmin(R, ADMIN_MANAGER)` for every operational role makes `grantRole` and
 *     `revokeRole` route through ADMIN_MANAGER for both the call-gate (FNDN @ 48h) and
 *     the cancel-gate (`getRoleGuardian(ADMIN_MANAGER) = GUARDIAN_ROLE = WAY`).
 *
 *   - `setTargetFunctionRole(AM, [10 admin selectors], ADMIN_MANAGER)` writes the cancel-path
 *     storage for every AM-self admin function. The OZ AM call-gate hardcodes ADMIN_ROLE for
 *     these (so FNDN still calls them via ADMIN_ROLE @ 48h), but `cancel()` reads the same
 *     `getTargetFunctionRole(target, selector)` storage to look up the guardian — so WAY's
 *     GUARDIAN_ROLE membership is what authorises cancellation.
 *
 * Each test schedules a representative admin op via FNDN, asserts the operation is queued,
 * then has WAY call `cancel()` and verifies the schedule is cleared.
 */
contract AdminCancellableTest is Test, MigrateDawn {
    IAccessManager internal am;

    /// @dev Apply the Dawn migration on a mainnet fork so we test against the real
    ///      post-migration AM state. We bypass `MigrationBase._processChain` to avoid the
    ///      JSON write + console dumps; the migration logic itself is identical.
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        am = IAccessManager(ROYCO_FACTORY);

        SafeTransaction[] memory txs = _buildBatch(MAINNET);
        _replayBatch(FNDN, txs);
        vm.warp(block.timestamp + 1 days + 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // grantRole / revokeRole — call-gate via getRoleAdmin → ADMIN_MANAGER
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GrantRoleIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xA11CE), 0));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_RevokeRoleIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.revokeRole, (ADMIN_PAUSER_ROLE, FNDN));
        _scheduleByFNDN_cancelByWAY(data);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AM-self admin functions — call-gate hardcoded to ADMIN_ROLE, cancel via storage write
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetRoleAdminIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.setRoleAdmin, (ADMIN_PAUSER_ROLE, ADMIN_ROLE));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_SetRoleGuardianIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.setRoleGuardian, (ADMIN_PAUSER_ROLE, ADMIN_ROLE));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_SetGrantDelayIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.setGrantDelay, (ADMIN_PAUSER_ROLE, 1 hours));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_SetTargetAdminDelayIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.setTargetAdminDelay, (entryPoint(MAINNET), 1 hours));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_SetTargetClosedIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.setTargetClosed, (entryPoint(MAINNET), true));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_SetTargetFunctionRoleIsCancellableByGuardian() public {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = bytes4(0xdeadbeef);
        bytes memory data = abi.encodeCall(IAccessManager.setTargetFunctionRole, (entryPoint(MAINNET), sel, ADMIN_PAUSER_ROLE));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_LabelRoleIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.labelRole, (ADMIN_PAUSER_ROLE, "relabeled"));
        _scheduleByFNDN_cancelByWAY(data);
    }

    function test_UpdateAuthorityIsCancellableByGuardian() public {
        bytes memory data = abi.encodeCall(IAccessManager.updateAuthority, (entryPoint(MAINNET), address(0xBEEF)));
        _scheduleByFNDN_cancelByWAY(data);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Negative checks — confirm the cancel actually requires GUARDIAN_ROLE
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RandomAccountCannotCancel() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xA11CE), 0));
        bytes32 opId = _schedule(data);
        require(_scheduledTimepoint(opId) != 0, "op should be scheduled");

        address rando = address(0xCAFE);
        vm.prank(rando);
        vm.expectRevert();
        am.cancel(FNDN, address(am), data);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Schedule `data` (sent to AM as target) by FNDN, then cancel via WAY.
    function _scheduleByFNDN_cancelByWAY(bytes memory data) internal {
        bytes32 opId = _schedule(data);
        require(_scheduledTimepoint(opId) != 0, "op should be scheduled before cancel");

        vm.prank(WAY);
        am.cancel(FNDN, address(am), data);

        require(_scheduledTimepoint(opId) == 0, "op should be cleared after cancel");
    }

    /// @dev FNDN schedules `data` against the AM. Returns the operation ID.
    function _schedule(bytes memory data) internal returns (bytes32) {
        vm.prank(FNDN);
        am.schedule(address(am), data, uint48(block.timestamp + 2 days));
        return am.hashOperation(FNDN, address(am), data);
    }

    function _scheduledTimepoint(bytes32 opId) internal view returns (uint48) {
        return am.getSchedule(opId);
    }
}
