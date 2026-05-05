// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Test } from "forge-std/Test.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";

/**
 * @title AdminNotCancellableTest
 * @notice Inverse of the previous "cancel-gate hack" test. Under the new WAY-centric model,
 *         FNDN's `ADMIN_ROLE`-gated ops (grantRole, setRoleAdmin, setTargetFunctionRole, etc.)
 *         run at 7d delay and are **intentionally NOT cancellable by anyone but FNDN itself**.
 *         No `setTargetFunctionRole(AM, [admin selectors], ...)` writes are made; default cancel
 *         guardian for those selectors is `getRoleGuardian(ADMIN_ROLE) = ADMIN_ROLE` → only
 *         FNDN can cancel.
 *
 *         Verifies for each AM admin selector: WAY cannot cancel a scheduled FNDN op, but
 *         FNDN can self-cancel.
 */
contract AdminNotCancellableTest is Test, MigrateDawn {
    IAccessManager internal am;

    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET);
        am = IAccessManager(ROYCO_FACTORY);
    }

    function test_GrantRole_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (ADMIN_PAUSER_ROLE, address(0xA11CE), 0));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_RevokeRole_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.revokeRole, (ADMIN_PAUSER_ROLE, FNDN));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_SetRoleAdmin_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.setRoleAdmin, (ADMIN_PAUSER_ROLE, ADMIN_ROLE));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_SetRoleGuardian_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.setRoleGuardian, (ADMIN_PAUSER_ROLE, ADMIN_ROLE));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_SetGrantDelay_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.setGrantDelay, (ADMIN_PAUSER_ROLE, 1 hours));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_SetTargetFunctionRole_NotCancellableByWAY() public {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = bytes4(0xdeadbeef);
        bytes memory data = abi.encodeCall(IAccessManager.setTargetFunctionRole, (entryPoint(MAINNET), sel, ADMIN_PAUSER_ROLE));
        _assertOnlyFNDNCanCancel(data);
    }

    function test_LabelRole_NotCancellableByWAY() public {
        bytes memory data = abi.encodeCall(IAccessManager.labelRole, (ADMIN_PAUSER_ROLE, "test"));
        _assertOnlyFNDNCanCancel(data);
    }

    /// @dev FNDN schedules `data` against the AM. WAY's cancel attempt reverts; FNDN's
    ///      self-cancel succeeds and clears the schedule.
    function _assertOnlyFNDNCanCancel(bytes memory data) internal {
        bytes32 opId = am.hashOperation(FNDN, address(am), data);
        vm.prank(FNDN);
        am.schedule(address(am), data, uint48(block.timestamp + 7 days));
        require(am.getSchedule(opId) != 0, "schedule did not queue");

        // WAY cannot cancel.
        vm.prank(WAY);
        vm.expectRevert();
        am.cancel(FNDN, address(am), data);

        // Random EOA cannot cancel.
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        am.cancel(FNDN, address(am), data);

        // FNDN self-cancel succeeds.
        vm.prank(FNDN);
        am.cancel(FNDN, address(am), data);
        require(am.getSchedule(opId) == 0, "FNDN self-cancel failed to clear");
    }
}
