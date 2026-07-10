// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";

/// @notice Verifies the one-time-use guard (`_assertPreMigrationAdminState`): it passes against
///         the current pre-migration mainnet state and reverts once Dawn's ADMIN_ROLE lockdown
///         has been applied. This is the enforcement that stops the migration scripts from
///         (re)generating a direct-call batch against an already-locked-down system.
contract OneTimeUseGuardTest is Test, MigrateDawn {
    function test_Guard_PassesOnPreMigrationState() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        // Pre-migration: FNDN's ADMIN_ROLE delay is still 0, so the guard passes (no revert).
        _assertPreMigrationAdminState(MAINNET);
    }

    function test_Guard_RevertsAfterLockdown() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
        applyToFork(MAINNET); // runs Dawn, flipping FNDN's ADMIN_ROLE to DELAY_ROOT (72h)

        vm.expectRevert(abi.encodeWithSelector(MigrationAlreadyApplied.selector, MAINNET, DELAY_ROOT));
        this.exposed_assertPreMigrationAdminState(MAINNET);
    }

    /// @dev External wrapper so `vm.expectRevert` targets a call boundary.
    function exposed_assertPreMigrationAdminState(uint256 _chainId) external view {
        _assertPreMigrationAdminState(_chainId);
    }
}
