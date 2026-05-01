// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Script } from "forge-std/Script.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";

import { Selectors } from "../../src/access/Selectors.sol";
import { MigrationBase } from "../../src/migration/MigrationBase.sol";

/**
 * @title MigrateDawn
 * @notice Migrates the Royco Dawn surface (markets + entry point) to the canonical security
 *         model defined in `authorization/README.md`.
 *
 * **Diff-based.** Each step reads on-chain state and emits a Safe transaction ONLY when the
 * current configuration differs from the desired configuration. Re-running the script after a
 * partial application produces a smaller batch (or no batch at all). The post-state assertion
 * always validates the FULL desired configuration regardless of which entries the batch
 * actually touched.
 *
 * The desired configuration, in order:
 *
 *   1. **FNDN role grants** with Immediate / Standard / Critical delays per the security model
 *      (plus `GUARDIAN_ROLE` to WAY). Order matters: any `*_ADMIN_ROLE` grant whose delay we
 *      raise to Standard must come AFTER any role gated by it (e.g. `DEPLOYER_ROLE` before
 *      `DEPLOYER_ROLE_ADMIN_ROLE`).
 *
 *   2. **Entry point role configuration** (mirrors
 *      `lib/royco-dawn/script/independent/DeployEntryPoint.s.sol:buildFactoryConfigTransactions:128-173`):
 *        - LP selectors → `PUBLIC_ROLE`
 *        - `modifyTrancheConfigs` → `ADMIN_ENTRY_POINT_ROLE`
 *        - `collectProtocolFees` → `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`
 *        - `pause` / `unpause` / `upgradeToAndCall` → `ADMIN_PAUSER_ROLE` / `ADMIN_UNPAUSER_ROLE` / `ADMIN_UPGRADER_ROLE`
 *        - Grant `ADMIN_ENTRY_POINT_ROLE` to FNDN (Critical 48h)
 *        - Grant `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` to FNDN (Immediate)
 *        - Self-grant `ST_LP_ROLE` / `JT_LP_ROLE` / `BURNER_ROLE` to the entry point itself
 *
 *   3. **`ADMIN_UNPAUSER_ROLE` wiring** for the protocol-wide unpause split:
 *        - `setRoleGuardian(ADMIN_UNPAUSER_ROLE, GUARDIAN_ROLE)`
 *        - For every pausable target (kernel/accountant/ST/JT per market + syncer + entry point),
 *          re-bind the `unpause()` selector from `ADMIN_PAUSER_ROLE` → `ADMIN_UNPAUSER_ROLE`.
 *
 *   4. **Root (7d) execution delay on `ADMIN_ROLE`** (LAST). After this every role-0-gated
 *      call requires schedule + 7d + execute.
 *
 * Output: `output/migrate/dawn/{chainId}_apply_security_migration.json` (one per chain).
 */
contract MigrateDawn is MigrationBase, Script {
    /// @dev Upper bound on diff'd batch size (current full migration is ~32 txs on the lighter chains, ~60 on mainnet).
    uint256 internal constant _MAX_BATCH_SIZE = 128;

    // ═══════════════════════════════════════════════════════════════════════════
    // CHAIN SELECTION
    // ═══════════════════════════════════════════════════════════════════════════

    function _targetChains() internal pure override returns (uint256[] memory chains) {
        chains = new uint256[](3);
        chains[0] = MAINNET;
        chains[1] = AVALANCHE;
        chains[2] = ARBITRUM;
    }

    function _safeFor(
        uint256 /*_chainId*/
    )
        internal
        pure
        override
        returns (address)
    {
        return FNDN;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BUILDER (diff-based)
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildBatch(uint256 _chainId) internal view override returns (SafeTransaction[] memory) {
        IAccessManager am = IAccessManager(ROYCO_FACTORY);
        SafeTransaction[] memory buf = new SafeTransaction[](_MAX_BATCH_SIZE);
        uint256 n;

        n = _diffFNDNRoleGrants(buf, n, am);
        n = _diffEntryPointConfig(buf, n, am, _chainId);
        n = _diffUnpauseRebind(buf, n, am, _chainId);
        n = _diffAdminRoleCriticalDelay(buf, n, am);

        return _trim(buf, n);
    }

    // ── Step 1 ────────────────────────────────────────────────────────────────

    /// @dev Order matters here: `DEPLOYER_ROLE` is gated by `DEPLOYER_ROLE_ADMIN_ROLE`. If we
    ///      ever push `DEPLOYER_ROLE_ADMIN_ROLE` to Standard delay before granting `DEPLOYER_ROLE`,
    ///      the latter grant would need schedule+execute. So when both are pending, immediate-tier
    ///      grants run first. Already-correct grants are skipped.
    /// @dev Several roles are co-held by FNDN and WAY at the same delay so WAY can also
    ///      schedule/execute the corresponding ops. The complete dual-holder set:
    ///        Immediate:    ADMIN_PAUSER_ROLE, LP_ROLE_ADMIN_ROLE, SYNC_ROLE
    ///        Critical 48h: ADMIN_KERNEL_ROLE, ADMIN_ACCOUNTANT_ROLE, ADMIN_PROTOCOL_FEE_SETTER_ROLE
    ///      WAY also holds GUARDIAN_ROLE solo (Immediate) — that grant is here too.
    function _diffFNDNRoleGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Immediate (0) — granted first so their delay-zero ordering is irrelevant for the rest
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE);
        // Standard (24h)
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE_ADMIN_ROLE, FNDN, DELAY_STANDARD);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_UNPAUSER_ROLE, FNDN, DELAY_STANDARD);
        // Critical (48h)
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ORACLE_QUOTER_ROLE, FNDN, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_KERNEL_ROLE, FNDN, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ACCOUNTANT_ROLE, FNDN, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, FNDN, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_UPGRADER_ROLE, FNDN, DELAY_CRITICAL);
        // Root (7d) for ADMIN_ROLE is set last in step 4
        return _n;
    }

    // ── Step 2 ────────────────────────────────────────────────────────────────

    function _diffEntryPointConfig(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
        address ep = entryPoint(_chainId);
        if (ep == address(0)) return _n;

        // Selector bindings (only emit calls for the (target, role) pairs that have at least one selector mismatched)
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, Selectors.entryPointLPSelectors(), PUBLIC_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoEntryPoint.modifyTrancheConfigs.selector), ADMIN_ENTRY_POINT_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoEntryPoint.collectProtocolFees.selector), ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoAuth.pause.selector), ADMIN_PAUSER_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoAuth.unpause.selector), ADMIN_UNPAUSER_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(UUPSUpgradeable.upgradeToAndCall.selector), ADMIN_UPGRADER_ROLE);

        // Grants
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ENTRY_POINT_ROLE, FNDN, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, DELAY_IMMEDIATE);
        // Entry-point self-grants — required so the entry point can call deposit/redeem on tranches
        // and forfeit yield via the burner role.
        _n = _maybeGrantRole(_buf, _n, _am, ST_LP_ROLE, ep, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, JT_LP_ROLE, ep, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, BURNER_ROLE, ep, DELAY_IMMEDIATE);
        return _n;
    }

    // ── Step 3 ────────────────────────────────────────────────────────────────

    function _diffUnpauseRebind(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
        // setRoleGuardian only if not already pointing at GUARDIAN_ROLE
        if (_am.getRoleGuardian(ADMIN_UNPAUSER_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_UNPAUSER_ROLE, GUARDIAN_ROLE);
        }

        bytes4[] memory unpauseSel = _one(IRoycoAuth.unpause.selector);
        address[] memory targets = _pausableTargets(_chainId);
        for (uint256 j = 0; j < targets.length; j++) {
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, targets[j], unpauseSel, ADMIN_UNPAUSER_ROLE);
        }
        return _n;
    }

    /// @dev kernel/accountant/ST/JT for each market on the chain + syncer + entry point.
    function _pausableTargets(uint256 _chainId) internal view returns (address[] memory targets) {
        string[] memory names = marketNames(_chainId);
        uint256 count = 4 * names.length;
        if (syncer(_chainId) != address(0)) count += 1;
        if (entryPoint(_chainId) != address(0)) count += 1;

        targets = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, names[i]);
            targets[idx++] = m.kernel;
            targets[idx++] = m.accountant;
            targets[idx++] = m.seniorTranche;
            targets[idx++] = m.juniorTranche;
        }
        if (syncer(_chainId) != address(0)) targets[idx++] = syncer(_chainId);
        if (entryPoint(_chainId) != address(0)) targets[idx++] = entryPoint(_chainId);
    }

    // ── Step 4 ────────────────────────────────────────────────────────────────

    /// @dev grantRole(ADMIN_ROLE, FNDN, ROOT 7d) — LAST. Closes the timelock-the-timelock gap.
    function _diffAdminRoleCriticalDelay(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        return _maybeGrantRole(_buf, _n, _am, ADMIN_ROLE, FNDN, DELAY_ROOT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DIFF HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Append a `grantRole` only if `_holder`'s membership/delay differs from desired.
    function _maybeGrantRole(
        SafeTransaction[] memory _buf,
        uint256 _n,
        IAccessManager _am,
        uint64 _role,
        address _holder,
        uint32 _desiredDelay
    )
        internal
        view
        returns (uint256)
    {
        (bool isMember, uint32 currentDelay) = _am.hasRole(_role, _holder);
        if (isMember && currentDelay == _desiredDelay) return _n;
        _buf[_n++] = buildGrantRole(ROYCO_FACTORY, _role, _holder, _desiredDelay);
        return _n;
    }

    /// @dev Append a single `setTargetFunctionRole` containing only the selectors whose current
    ///      role doesn't match `_desiredRole`. If all selectors already match, no tx is emitted.
    function _maybeSetTargetFunctionRole(
        SafeTransaction[] memory _buf,
        uint256 _n,
        IAccessManager _am,
        address _target,
        bytes4[] memory _selectors,
        uint64 _desiredRole
    )
        internal
        view
        returns (uint256)
    {
        // First pass: count selectors needing update
        uint256 missingCount;
        for (uint256 i = 0; i < _selectors.length; i++) {
            if (_am.getTargetFunctionRole(_target, _selectors[i]) != _desiredRole) missingCount++;
        }
        if (missingCount == 0) return _n;

        // Second pass: collect them
        bytes4[] memory missing = new bytes4[](missingCount);
        uint256 m;
        for (uint256 i = 0; i < _selectors.length; i++) {
            if (_am.getTargetFunctionRole(_target, _selectors[i]) != _desiredRole) {
                missing[m++] = _selectors[i];
            }
        }

        _buf[_n++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _target, missing, _desiredRole);
        return _n;
    }

    /// @dev Trim the over-allocated buffer to its actual size.
    function _trim(SafeTransaction[] memory _buf, uint256 _n) internal pure returns (SafeTransaction[] memory out) {
        out = new SafeTransaction[](_n);
        for (uint256 i = 0; i < _n; i++) {
            out[i] = _buf[i];
        }
    }

    /// @dev Tiny helper: wrap a single selector in a `bytes4[1]`.
    function _one(bytes4 _sel) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = _sel;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-STATE ASSERTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Validates the FULL desired configuration regardless of which entries the diff'd
    ///      batch actually touched. After the simulation the post-state dump is also printed
    ///      via `MigrationBase._processChain`, so an operator can manually inspect the
    ///      resulting tables alongside these asserts.
    function _assertTargetState(uint256 _chainId) internal view override {
        IAccessManager am = IAccessManager(ROYCO_FACTORY);

        // FNDN role delays
        _assertRoleDelay(am, ADMIN_KERNEL_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_ACCOUNTANT_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_PROTOCOL_FEE_SETTER_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_ORACLE_QUOTER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ORACLE_QUOTER_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_UPGRADER_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_UPGRADER_ROLE @ FNDN");
        _assertRoleDelay(am, DEPLOYER_ROLE_ADMIN_ROLE, FNDN, DELAY_STANDARD, "DEPLOYER_ROLE_ADMIN_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_UNPAUSER_ROLE, FNDN, DELAY_STANDARD, "ADMIN_UNPAUSER_ROLE @ FNDN");
        _assertRoleDelay(am, ADMIN_PAUSER_ROLE, FNDN, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ FNDN");
        _assertRoleDelay(am, LP_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE, "LP_ROLE_ADMIN_ROLE @ FNDN");
        _assertRoleDelay(am, SYNC_ROLE, FNDN, DELAY_IMMEDIATE, "SYNC_ROLE @ FNDN");
        _assertRoleDelay(am, DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE, "DEPLOYER_ROLE @ FNDN");
        // WAY co-holders (matching delays)
        _assertRoleDelay(am, GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE, "GUARDIAN_ROLE @ WAY");
        _assertRoleDelay(am, ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE, "ADMIN_PAUSER_ROLE @ WAY");
        _assertRoleDelay(am, LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE, "LP_ROLE_ADMIN_ROLE @ WAY");
        _assertRoleDelay(am, SYNC_ROLE, WAY, DELAY_IMMEDIATE, "SYNC_ROLE @ WAY");
        _assertRoleDelay(am, ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL, "ADMIN_KERNEL_ROLE @ WAY");
        _assertRoleDelay(am, ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL, "ADMIN_ACCOUNTANT_ROLE @ WAY");
        _assertRoleDelay(am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL, "ADMIN_PROTOCOL_FEE_SETTER_ROLE @ WAY");

        // Entry point
        address ep = entryPoint(_chainId);
        if (ep != address(0)) {
            _assertRoleDelay(am, ADMIN_ENTRY_POINT_ROLE, FNDN, DELAY_CRITICAL, "ADMIN_ENTRY_POINT_ROLE @ FNDN");
            _assertRoleDelay(am, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, DELAY_IMMEDIATE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE");
            _assertRoleDelay(am, ST_LP_ROLE, ep, DELAY_IMMEDIATE, "ST_LP_ROLE @ entryPoint");
            _assertRoleDelay(am, JT_LP_ROLE, ep, DELAY_IMMEDIATE, "JT_LP_ROLE @ entryPoint");
            _assertRoleDelay(am, BURNER_ROLE, ep, DELAY_IMMEDIATE, "BURNER_ROLE @ entryPoint");

            require(
                am.getTargetFunctionRole(ep, IRoycoEntryPoint.modifyTrancheConfigs.selector) == ADMIN_ENTRY_POINT_ROLE, "EP modifyTrancheConfigs role mismatch"
            );
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

        // Unpause re-bind on every pausable target
        require(am.getRoleGuardian(ADMIN_UNPAUSER_ROLE) == GUARDIAN_ROLE, "ADMIN_UNPAUSER_ROLE guardian mismatch");
        address[] memory targets = _pausableTargets(_chainId);
        for (uint256 i = 0; i < targets.length; i++) {
            require(am.getTargetFunctionRole(targets[i], IRoycoAuth.unpause.selector) == ADMIN_UNPAUSER_ROLE, "unpause role mismatch");
        }

        // ADMIN_ROLE on Root (7d) delay — closes timelock-the-timelock
        _assertRoleDelay(am, ADMIN_ROLE, FNDN, DELAY_ROOT, "ADMIN_ROLE");
    }

    function _assertRoleDelay(IAccessManager _am, uint64 _role, address _holder, uint32 _expectedDelay, string memory _label) internal view {
        (bool isMember, uint32 delay) = _am.hasRole(_role, _holder);
        require(isMember, string.concat(_label, ": holder is not a member"));
        require(delay == _expectedDelay, string.concat(_label, ": delay mismatch"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════════════════════════════════

    function _outputPath(uint256 _chainId) internal pure override returns (string memory) {
        return string.concat("output/migrate/dawn/", vm_toString(_chainId), "_apply_security_migration");
    }

    function _batchMeta(
        uint256 /*_chainId*/
    )
        internal
        pure
        override
        returns (string memory name, string memory description)
    {
        name = "Royco security migration (Dawn surface)";
        description =
            "Diff-based: only emits role grants / setTargetFunctionRole / setRoleGuardian / etc. for entries that don't already match the desired configuration in `authorization/README.md`. Applying this batch leaves the AccessManager in the canonical post-migration state.";
    }

    /// @dev Local helper to keep `_outputPath` `pure`.
    function vm_toString(uint256 _v) private pure returns (string memory s) {
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
        s = string(b);
    }
}
