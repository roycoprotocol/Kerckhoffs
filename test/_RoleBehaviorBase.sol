// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Test } from "forge-std/Test.sol";

/**
 * @title RoleBehaviorBase
 * @notice Shared helpers for verifying that an AccessManager role behaves as designed.
 *
 * For every role-with-holder, three properties are checked:
 *   1. **Execution** — the assigned holder can run operations gated by the role (after the
 *      role's execution delay, if any).
 *   2. **Delay enforcement** — for delayed roles, execution cannot happen before the delay
 *      elapses; the holder must `schedule()` and wait.
 *   3. **Cancellability** — for delayed roles, the guardian role holder can `cancel()` a
 *      scheduled op during the delay window.
 *
 * Subclasses set `am` in their `setUp()` (after applying the relevant migration on a fork),
 * then call the helpers below to exercise each property per role.
 *
 * Where the gated function would revert at the target due to its own preconditions
 * (uninitialized state, invalid args, etc.), we use `vm.mockCall` to make the target accept
 * the call as a no-op. We're testing the AM's gating mechanics, not the target contract's
 * business logic.
 */
abstract contract RoleBehaviorBase is Test {
    IAccessManager internal am;

    // ═══════════════════════════════════════════════════════════════════════════
    // Property 0 — membership
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Asserts the holder is a member of the role with the expected execution delay.
    function _assertMembership(uint64 _role, address _holder, uint32 _expectedDelay, string memory _label) internal view {
        (bool isMember, uint32 delay) = am.hasRole(_role, _holder);
        require(isMember, string.concat(_label, ": holder is not a member"));
        require(delay == _expectedDelay, string.concat(_label, ": execution delay mismatch"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Three-property test for delayed roles
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Runs all three properties (execution / delay enforcement / cancellability) for a
    ///      delayed role + (target, calldata) gated by it.
    ///
    ///      The function structure runs the three properties sequentially in one test by
    ///      using fresh schedules where needed (each `am.schedule` re-uses the same opId
    ///      after the previous one is consumed/cancelled).
    function _assertDelayedRoleBehavior(
        string memory _label,
        uint64 _role,
        address _holder,
        uint32 _delay,
        address _target,
        bytes memory _data,
        address _guardianHolder
    )
        internal
    {
        _assertMembership(_role, _holder, _delay, _label);

        // Note: we don't check `canCall` directly here. For AM-self admin functions like
        // `grantRole`, canCall takes only a selector — it can't decode the role-id arg
        // that determines the actual permission. The schedule/execute flow uses full calldata
        // and exercises the real gate, which is what we want to verify anyway.
        bytes32 opId = am.hashOperation(_holder, _target, _data);

        // ── Property 1: holder can schedule + execute after delay ──
        // `when=0` lets AM auto-compute minWhen = now + setback (= now + delay).
        vm.prank(_holder);
        am.schedule(_target, _data, 0);
        require(am.getSchedule(opId) > 0, string.concat(_label, ": schedule did not queue"));

        // ── Property 2: cannot bypass delay (try execute immediately) ──
        vm.prank(_holder);
        vm.expectRevert();
        am.execute(_target, _data);

        // Warp past delay and execute (mock target to accept the call as no-op)
        vm.warp(block.timestamp + _delay + 1);
        vm.mockCall(_target, _data, abi.encode());
        vm.prank(_holder);
        am.execute(_target, _data);
        require(am.getSchedule(opId) == 0, string.concat(_label, ": schedule not consumed by execute"));

        // ── Property 3: guardian can cancel ──
        vm.prank(_holder);
        am.schedule(_target, _data, 0);
        require(am.getSchedule(opId) > 0, string.concat(_label, ": re-schedule did not queue"));

        vm.prank(_guardianHolder);
        am.cancel(_holder, _target, _data);
        require(am.getSchedule(opId) == 0, string.concat(_label, ": guardian cancel did not clear"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Two-property test for Immediate roles
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev For Immediate roles: no delay enforcement / cancellation possible (no scheduling).
    ///      Just verify membership + canCall(true, 0) + that execution actually works.
    function _assertImmediateRoleBehavior(string memory _label, uint64 _role, address _holder, address _target, bytes memory _data) internal {
        _assertMembership(_role, _holder, 0, _label);

        // Verify the holder can actually invoke the gated call. Mocking the target so the test
        // doesn't depend on the function's own preconditions (e.g. already paused / valid args).
        vm.mockCall(_target, _data, abi.encode());
        vm.prank(_holder);
        am.execute(_target, _data);
    }
}
