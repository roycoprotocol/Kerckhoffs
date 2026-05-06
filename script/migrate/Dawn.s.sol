// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Script } from "forge-std/Script.sol";

import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { Selectors } from "../../src/access/Selectors.sol";
import { MigrationBase } from "../../src/migration/MigrationBase.sol";

/**
 * @title MigrateDawn
 * @notice Migrates the Royco Dawn surface (markets + entry point) to the canonical security
 *         model. **WAY-centric**: WAY holds every parameter-update role (under specified
 *         delays) and `ADMIN_PAUSER_ROLE`. FNDN holds `ADMIN_ROLE` (Root 7d, role
 *         management), `GUARDIAN_ROLE` (cancellation), and `ADMIN_UNPAUSER_ROLE` (Immediate).
 *         Every WAY-scheduled op is FNDN-cancellable. FNDN's own ADMIN_ROLE-gated ops are
 *         intentionally non-cancellable by anyone but FNDN itself.
 *
 * **Diff-based.** Each step reads on-chain state and emits a Safe transaction ONLY when the
 * current configuration differs from the desired configuration.
 *
 * Order:
 *   1. WAY operational role grants (Immediate / 24h / 48h / 7d) + FNDN narrow grants
 *      (`ADMIN_UNPAUSER_ROLE`, `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`, `GUARDIAN_ROLE`).
 *   2. Revoke prior holders that the new model says shouldn't hold a role (e.g. FNDN losing
 *      operational roles to WAY).
 *   3. Entry point selector + role wiring.
 *   4. Tranche binding consistency backfill.
 *   5. Unpause re-bind (`unpause` selectors → `ADMIN_UNPAUSER_ROLE`, FNDN @ Immediate).
 *   6. Backfill `labelRole` for every Dawn role on first-run.
 *   7. ADMIN_ROLE delay flip to Root (7d) on FNDN — LAST.
 *
 * Output: `output/migrate/dawn/{chainId}_apply_security_migration.json` (one per chain).
 */
contract MigrateDawn is MigrationBase, Script {
    /// @dev Upper bound on diff'd batch size. Mainnet (7 markets × 2 tranches × ~8 selector
    ///      groups + entry-point + ADMIN_ROLE flip + WAY grants) tops out around ~150 tx.
    uint256 internal constant _MAX_BATCH_SIZE = 256;

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

        n = _diffWAYRoleGrants(buf, n, am);
        n = _diffFNDNRoleGrants(buf, n, am);
        n = _diffRevokeStaleHolders(buf, n, am);
        n = _diffEntryPointConfig(buf, n, am, _chainId);
        n = _diffTrancheBindings(buf, n, am, _chainId);
        n = _diffUnpauseRebind(buf, n, am, _chainId);
        n = _diffLabels(buf, n, am);
        n = _diffAdminRoleDelay(buf, n, am);

        return _trim(buf, n);
    }

    // ── Step 1: WAY operational role grants ───────────────────────────────────

    /// @dev WAY holds every parameter-update role (per spec) plus pause and upgrade.
    ///      All delayed WAY ops are FNDN-cancellable via `GUARDIAN_ROLE` (default guardian
    ///      `GUARDIAN_ROLE` was set at original Dawn deploy; we backfill it for any role
    ///      that's missing it as part of the unpause/entry-point wiring steps).
    function _diffWAYRoleGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Immediate
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, WAY, DELAY_IMMEDIATE);
        // Standard (24h)
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE_ADMIN_ROLE, WAY, DELAY_STANDARD);
        // Critical (48h)
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_KERNEL_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ORACLE_QUOTER_ROLE, WAY, DELAY_CRITICAL);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ENTRY_POINT_ROLE, WAY, DELAY_CRITICAL);
        // Root (7d)
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_UPGRADER_ROLE, WAY, DELAY_ROOT);
        return _n;
    }

    /// @dev FNDN holds the cancellation authority + the narrow Immediate-tier ops the
    ///      foundation explicitly retains: unpause, fee collection, deployer role, the
    ///      oracle/quoter role (co-held with WAY for emergency oracle re-pegs), and the
    ///      meta-grant authority (`ADMIN_ROLE`, set in step 7).
    function _diffFNDNRoleGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        _n = _maybeGrantRole(_buf, _n, _am, GUARDIAN_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_UNPAUSER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ORACLE_QUOTER_ROLE, FNDN, DELAY_IMMEDIATE);
        return _n;
    }

    // ── Step 2: revoke stale holders ──────────────────────────────────────────

    /// @dev The original Dawn deploy granted many operational roles to FNDN. The new model
    ///      gives those to WAY exclusively — revoke FNDN where it shouldn't be.
    function _diffRevokeStaleHolders(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Roles where FNDN should NOT be a holder under the new model (WAY-only).
        uint64[] memory waOnly = _wayOnlyRoles();
        for (uint256 i = 0; i < waOnly.length; i++) {
            (bool fndnIsMember,) = _am.hasRole(waOnly[i], FNDN);
            if (fndnIsMember) {
                _buf[_n++] = buildRevokeRole(ROYCO_FACTORY, waOnly[i], FNDN);
            }
        }
        // GUARDIAN_ROLE: WAY held it under the old model; new model has FNDN as guardian.
        (bool wayHasGuardian,) = _am.hasRole(GUARDIAN_ROLE, WAY);
        if (wayHasGuardian) {
            _buf[_n++] = buildRevokeRole(ROYCO_FACTORY, GUARDIAN_ROLE, WAY);
        }
        return _n;
    }

    /// @dev Roles where FNDN must NOT be a holder under the new model. ADMIN_ORACLE_QUOTER_ROLE
    ///      is intentionally omitted — it's co-held by FNDN @ Immediate (emergency oracle
    ///      re-peg) and WAY @ 48h (routine quoter changes).
    function _wayOnlyRoles() internal pure returns (uint64[] memory roles) {
        roles = new uint64[](9);
        roles[0] = ADMIN_PAUSER_ROLE;
        roles[1] = ADMIN_UPGRADER_ROLE;
        roles[2] = ADMIN_KERNEL_ROLE;
        roles[3] = ADMIN_ACCOUNTANT_ROLE;
        roles[4] = ADMIN_PROTOCOL_FEE_SETTER_ROLE;
        roles[5] = ADMIN_ENTRY_POINT_ROLE;
        roles[6] = DEPLOYER_ROLE_ADMIN_ROLE;
        roles[7] = LP_ROLE_ADMIN_ROLE;
        roles[8] = SYNC_ROLE;
    }

    // ── Step 3: entry point ───────────────────────────────────────────────────

    function _diffEntryPointConfig(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
        address ep = entryPoint(_chainId);
        if (ep == address(0)) return _n;

        // Selector bindings
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, Selectors.entryPointLPSelectors(), PUBLIC_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoEntryPoint.modifyTrancheConfigs.selector), ADMIN_ENTRY_POINT_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoEntryPoint.collectProtocolFees.selector), ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoAuth.pause.selector), ADMIN_PAUSER_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(IRoycoAuth.unpause.selector), ADMIN_UNPAUSER_ROLE);
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ep, _one(UUPSUpgradeable.upgradeToAndCall.selector), ADMIN_UPGRADER_ROLE);

        // Entry-point self-grants
        _n = _maybeGrantRole(_buf, _n, _am, ST_LP_ROLE, ep, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, JT_LP_ROLE, ep, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, BURNER_ROLE, ep, DELAY_IMMEDIATE);

        // Guardian wiring (entry-point roles weren't auto-guardianed by the original
        // DeployEntryPoint script — backfill so FNDN can cancel WAY-scheduled ops).
        if (_am.getRoleGuardian(BURNER_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, BURNER_ROLE, GUARDIAN_ROLE);
        }
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE, GUARDIAN_ROLE);
        }
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, GUARDIAN_ROLE);
        }
        return _n;
    }

    // ── Step 4: tranche bindings consistency ──────────────────────────────────

    /// @dev Backfill any tranche selector → role binding the original Dawn deploy missed
    ///      (notably `BURNER_ROLE` on older markets). Idempotent: 0 txs if all set.
    function _diffTrancheBindings(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
        string[] memory names = marketNames(_chainId);
        if (names.length == 0) return _n;

        bytes4[] memory burnSel = new bytes4[](2);
        burnSel[0] = IRoycoVaultTranche.burn.selector;
        burnSel[1] = IRoycoVaultTranche.burnFrom.selector;

        bytes4[] memory seizeSel = new bytes4[](2);
        seizeSel[0] = IRoycoVaultTranche.seizeShares.selector;
        seizeSel[1] = IRoycoVaultTranche.seizeAndRedeemShares.selector;

        bytes4[] memory lpSel = new bytes4[](2);
        lpSel[0] = IRoycoVaultTranche.deposit.selector;
        lpSel[1] = IRoycoVaultTranche.redeem.selector;

        bytes4[] memory pauseSel = _one(IRoycoAuth.pause.selector);
        bytes4[] memory upgradeSel = _one(UUPSUpgradeable.upgradeToAndCall.selector);

        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, names[i]);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, burnSel, BURNER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, burnSel, BURNER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, seizeSel, TRANSFER_AGENT_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, seizeSel, TRANSFER_AGENT_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, lpSel, ST_LP_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, lpSel, JT_LP_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
        }
        return _n;
    }

    // ── Step 5: unpause rebind ────────────────────────────────────────────────

    function _diffUnpauseRebind(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
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

    // ── Step 6: label backfill ────────────────────────────────────────────────

    /// @dev Original royco-dawn deploy doesn't `labelRole` any of its roles. Backfill on a
    ///      first-run gate (probe via `getRoleGuardian(ADMIN_UPGRADER_ROLE)` against the
    ///      expected GUARDIAN_ROLE — set during initial dawn deploy, so present on a
    ///      previously-deployed chain. We use a different probe: WAY hasRole(ADMIN_KERNEL_ROLE)
    ///      — true after the migration runs once, false before.)
    function _diffLabels(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        (bool labelsLikelySet,) = _am.hasRole(ADMIN_KERNEL_ROLE, WAY);
        if (labelsLikelySet) return _n;

        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_PAUSER_ROLE, "ADMIN_PAUSER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_UNPAUSER_ROLE, "ADMIN_UNPAUSER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_UPGRADER_ROLE, "ADMIN_UPGRADER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ST_LP_ROLE, "ST_LP_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, JT_LP_ROLE, "JT_LP_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, BURNER_ROLE, "BURNER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, SYNC_ROLE, "SYNC_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_KERNEL_ROLE, "ADMIN_KERNEL_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_ACCOUNTANT_ROLE, "ADMIN_ACCOUNTANT_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_PROTOCOL_FEE_SETTER_ROLE, "ADMIN_PROTOCOL_FEE_SETTER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_ORACLE_QUOTER_ROLE, "ADMIN_ORACLE_QUOTER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE, "ADMIN_ENTRY_POINT_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, DEPLOYER_ROLE, "DEPLOYER_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, LP_ROLE_ADMIN_ROLE, "LP_ROLE_ADMIN_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, DEPLOYER_ROLE_ADMIN_ROLE, "DEPLOYER_ROLE_ADMIN_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, GUARDIAN_ROLE, "GUARDIAN_ROLE");
        _buf[_n++] = buildLabelRole(ROYCO_FACTORY, TRANSFER_AGENT_ROLE, "TRANSFER_AGENT_ROLE");
        return _n;
    }

    // ── Step 7: ADMIN_ROLE delay (LAST) ───────────────────────────────────────

    /// @dev Set FNDN's `ADMIN_ROLE` execution delay to Root (7d). This is the last step
    ///      because every prior step relies on FNDN being able to call AM admin functions
    ///      immediately. After this, FNDN's admin ops (grantRole, setRoleAdmin,
    ///      setTargetFunctionRole, etc.) all run at 7d. Default cancel-gate keeps these
    ///      cancellable only by FNDN itself — not WAY — by design.
    function _diffAdminRoleDelay(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        return _maybeGrantRole(_buf, _n, _am, ADMIN_ROLE, FNDN, DELAY_ROOT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DIFF HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

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
        uint256 missingCount;
        for (uint256 i = 0; i < _selectors.length; i++) {
            if (_am.getTargetFunctionRole(_target, _selectors[i]) != _desiredRole) missingCount++;
        }
        if (missingCount == 0) return _n;

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

    function _trim(SafeTransaction[] memory _buf, uint256 _n) internal pure returns (SafeTransaction[] memory out) {
        out = new SafeTransaction[](_n);
        for (uint256 i = 0; i < _n; i++) {
            out[i] = _buf[i];
        }
    }

    function _one(bytes4 _sel) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = _sel;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════════════════════════════════

    function _outputPath(uint256 _chainId) internal pure override returns (string memory) {
        return string.concat("output/migrate/dawn/", _toString(_chainId), "_apply_security_migration");
    }

    function _batchMeta(
        uint256 /*_chainId*/
    )
        internal
        pure
        override
        returns (string memory name, string memory description)
    {
        name = "Royco security migration (Dawn surface, WAY-centric)";
        description =
            "Diff-based: WAY holds parameter-update + pause + upgrade roles; FNDN holds ADMIN_ROLE (7d), GUARDIAN_ROLE, ADMIN_UNPAUSER_ROLE, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE. Re-running against a fully-applied chain produces a 0-tx batch.";
    }

    function _toString(uint256 _v) private pure returns (string memory s) {
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
