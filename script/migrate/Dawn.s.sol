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
 *         model. **WAY-centric**: WAY holds every parameter-update role under a uniform 72h
 *         minimum delay. Pause is split out to the dedicated `WAY_PAUSE` multisig
 *         (`ADMIN_PAUSER_ROLE`, Immediate). FNDN holds `ADMIN_ROLE` (Root 72h, role
 *         management) and `ADMIN_UNPAUSER_ROLE` (Immediate); `GUARDIAN_ROLE` (cancellation)
 *         is co-held by FNDN and the dedicated `FNDN_VETO` multisig. Every WAY-scheduled op
 *         is cancellable by either guardian holder. FNDN's own ADMIN_ROLE-gated ops are
 *         intentionally non-cancellable by anyone but FNDN itself.
 *
 * **Diff-based.** Each step reads on-chain state and emits a Safe transaction ONLY when the
 * current configuration differs from the desired configuration.
 *
 * Order:
 *   1. WAY operational role grants (Immediate / 72h) + FNDN narrow grants
 *      (`ADMIN_UNPAUSER_ROLE`, `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`, `GUARDIAN_ROLE`).
 *   2. Emergency-multisig grants: `ADMIN_PAUSER_ROLE` → WAY_PAUSE, `GUARDIAN_ROLE` co-grant
 *      → FNDN_VETO (both Immediate).
 *   3. Revoke prior holders the new model says shouldn't hold a role (FNDN losing operational
 *      roles to WAY; WAY losing `GUARDIAN_ROLE` and `ADMIN_PAUSER_ROLE`).
 *   4. Entry point selector + role wiring.
 *   5. Tranche binding consistency backfill.
 *   6. Unpause re-bind (`unpause` selectors → `ADMIN_UNPAUSER_ROLE`, FNDN @ Immediate).
 *   7. Backfill `labelRole` for every Dawn role on first-run.
 *   8. ADMIN_ROLE delay flip to Root (72h) on FNDN — LAST.
 *
 * Output: `output/migrate/dawn/{chainId}_apply_security_migration.json` (one per chain).
 *
 * ── ONE-TIME USE ────────────────────────────────────────────────────────────────────────────
 * This script emits a flat, direct-call Safe batch valid ONLY while FNDN's ADMIN_ROLE execution
 * delay is 0. Step 8 raises it to 72h — after that, admin ops require schedule → wait 72h →
 * execute, so a regenerated batch would revert on import. `run()` calls
 * `_assertPreMigrationAdminState` and reverts (`MigrationAlreadyApplied`) once the lockdown has
 * happened. Dawn runs LAST (Vaults → Makina → Dawn); it is a one-shot bootstrap, not a reusable
 * tool. Post-lockdown market onboarding is a separate schedule/execute operation.
 */
contract MigrateDawn is MigrationBase, Script {
    /// @dev Upper bound on diff'd batch size. Mainnet (9 markets × 2 tranches × ~8 selector
    ///      groups + entry-point + ADMIN_ROLE flip + WAY grants) tops out around ~190 tx.
    uint256 internal constant _MAX_BATCH_SIZE = 256;

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLLOUT PHASING (deferred ADMIN_ROLE lockdown)
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // The ADMIN_ROLE delay flip (step 8) is the point of no return: once FNDN's ADMIN_ROLE
    // execution delay is 72h, every further admin op needs schedule → wait 72h → execute. For a
    // staged multi-chain rollout you usually apply steps 1–7 on each chain FIRST (keeping FNDN's
    // fast admin access), then flip the lockdown on every chain LAST. These flags select which
    // slice of the batch `_buildBatch` emits; they are set by the entry points below.
    bool private _deferAdminLockdown; // emit steps 1–7 only (skip the ADMIN_ROLE flip)
    bool private _onlyAdminLockdown; // emit ONLY the ADMIN_ROLE flip (the final lockdown)

    /// @notice Steps 1–7 for `_chains`, EXCLUDING the ADMIN_ROLE delay flip. Run this as each
    ///         chain goes live; apply the lockdown separately at the end via `runLockdown`.
    ///         Usage: `forge script ... --sig "runDeferLockdown(uint256[])" "[1,43114,8453]"`
    function runDeferLockdown(uint256[] calldata _chains) external {
        _deferAdminLockdown = true;
        _assertProductionMultisigs();
        for (uint256 i = 0; i < _chains.length; i++) {
            _processChain(_chains[i]);
        }
    }

    /// @notice ONLY the ADMIN_ROLE delay flip (72h lockdown) for `_chains` — the FINAL step, run
    ///         once every chain has had steps 1–7 applied. Writes a separate JSON
    ///         (`{chainId}_admin_role_lockdown.json`) so it never clobbers the main batch.
    ///         Usage: `forge script ... --sig "runLockdown(uint256[])" "[1,43114,42161,8453]"`
    function runLockdown(uint256[] calldata _chains) external {
        _onlyAdminLockdown = true;
        _assertProductionMultisigs();
        for (uint256 i = 0; i < _chains.length; i++) {
            _processChain(_chains[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHAIN SELECTION
    // ═══════════════════════════════════════════════════════════════════════════

    function _targetChains() internal pure override returns (uint256[] memory chains) {
        chains = new uint256[](4);
        chains[0] = MAINNET;
        chains[1] = AVALANCHE;
        chains[2] = ARBITRUM;
        chains[3] = BASE;
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
        // Base has its own factory; everywhere else this is the CREATE2 address(_am).
        IAccessManager am = IAccessManager(roycoFactory(_chainId));
        SafeTransaction[] memory buf = new SafeTransaction[](_MAX_BATCH_SIZE);
        uint256 n;

        // Lockdown-only phase (`runLockdown`): emit just the ADMIN_ROLE delay flip.
        if (_onlyAdminLockdown) {
            n = _diffAdminRoleDelay(buf, n, am);
            return _trim(buf, n);
        }

        n = _diffWAYRoleGrants(buf, n, am);
        n = _diffFNDNRoleGrants(buf, n, am);
        n = _diffEmergencyMultisigGrants(buf, n, am);
        n = _diffRevokeStaleHolders(buf, n, am);
        n = _diffEntryPointConfig(buf, n, am, _chainId);
        n = _diffTrancheBindings(buf, n, am, _chainId);
        n = _diffUnpauseRebind(buf, n, am, _chainId);
        n = _diffLabels(buf, n, am);
        // Step 8 (ADMIN_ROLE lockdown) is the point of no return — skip it when deferring.
        if (!_deferAdminLockdown) {
            n = _diffAdminRoleDelay(buf, n, am);
        }

        return _trim(buf, n);
    }

    // ── Step 1: WAY operational role grants ───────────────────────────────────

    /// @dev WAY holds every parameter-update role (per spec) plus upgrade. Pause is NOT here —
    ///      it moved to the dedicated WAY_PAUSE multisig (see `_diffEmergencyMultisigGrants`).
    ///      All delayed WAY ops are cancellable via `GUARDIAN_ROLE` (default guardian
    ///      `GUARDIAN_ROLE` was set at original Dawn deploy; we backfill it for any role
    ///      that's missing it as part of the unpause/entry-point wiring steps).
    function _diffWAYRoleGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Immediate
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, WAY, DELAY_IMMEDIATE);
        // Minimum delay (72h)
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE_ADMIN_ROLE, WAY, DELAY_MIN);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_KERNEL_ROLE, WAY, DELAY_MIN);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ACCOUNTANT_ROLE, WAY, DELAY_MIN);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PROTOCOL_FEE_SETTER_ROLE, WAY, DELAY_MIN);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ORACLE_QUOTER_ROLE, WAY, DELAY_MIN);
        // Short delay (24h)
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_ENTRY_POINT_ROLE, WAY, DELAY_SHORT);
        // Root (72h)
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

    // ── Step 2: emergency-multisig grants ─────────────────────────────────────

    /// @dev Dedicated fast-response multisigs (both 1/4, Immediate):
    ///        - WAY_PAUSE  → `ADMIN_PAUSER_ROLE` (sole pause authority; WAY revoked in step 3).
    ///        - FNDN_VETO  → `GUARDIAN_ROLE` (co-held with FNDN; cancels any WAY-scheduled op).
    ///      Both run before the step-8 ADMIN_ROLE delay flip so FNDN can grant immediately.
    function _diffEmergencyMultisigGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, WAY_PAUSE, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, GUARDIAN_ROLE, FNDN_VETO, DELAY_IMMEDIATE);
        return _n;
    }

    // ── Step 3: revoke stale holders ──────────────────────────────────────────

    /// @dev The original Dawn deploy granted many operational roles to FNDN. The new model
    ///      gives those to WAY exclusively — revoke FNDN where it shouldn't be. Also revoke
    ///      WAY from the roles it no longer holds under the new model: `GUARDIAN_ROLE` (now
    ///      FNDN/FNDN_VETO) and `ADMIN_PAUSER_ROLE` (now WAY_PAUSE).
    function _diffRevokeStaleHolders(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Roles where FNDN should NOT be a holder under the new model (WAY-only).
        uint64[] memory waOnly = _wayOnlyRoles();
        for (uint256 i = 0; i < waOnly.length; i++) {
            (bool fndnIsMember,) = _am.hasRole(waOnly[i], FNDN);
            if (fndnIsMember) {
                _buf[_n++] = buildRevokeRole(address(_am), waOnly[i], FNDN);
            }
        }
        // GUARDIAN_ROLE: WAY held it under the old model; new model has FNDN + FNDN_VETO.
        (bool wayHasGuardian,) = _am.hasRole(GUARDIAN_ROLE, WAY);
        if (wayHasGuardian) {
            _buf[_n++] = buildRevokeRole(address(_am), GUARDIAN_ROLE, WAY);
        }
        // ADMIN_PAUSER_ROLE: WAY held it under the old model; pause now lives on WAY_PAUSE.
        (bool wayHasPauser,) = _am.hasRole(ADMIN_PAUSER_ROLE, WAY);
        if (wayHasPauser) {
            _buf[_n++] = buildRevokeRole(address(_am), ADMIN_PAUSER_ROLE, WAY);
        }
        return _n;
    }

    /// @dev Roles where FNDN must NOT be a holder under the new model. ADMIN_ORACLE_QUOTER_ROLE
    ///      is intentionally omitted — it's co-held by FNDN @ Immediate (emergency oracle
    ///      re-peg) and WAY @ 72h (routine quoter changes). ADMIN_PAUSER_ROLE stays in the
    ///      list so FNDN is revoked from it too (pause is WAY_PAUSE-only; WAY revoked above).
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

    // ── Step 4: entry point ───────────────────────────────────────────────────

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
            _buf[_n++] = buildSetRoleGuardian(address(_am), BURNER_ROLE, GUARDIAN_ROLE);
        }
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(address(_am), ADMIN_ENTRY_POINT_ROLE, GUARDIAN_ROLE);
        }
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(address(_am), ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, GUARDIAN_ROLE);
        }
        return _n;
    }

    // ── Step 5: tranche bindings consistency ──────────────────────────────────

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

        // Deposits are OPEN to everyone → PUBLIC_ROLE on every tranche. Redemptions stay gated
        // per-tranche (ST_LP_ROLE / JT_LP_ROLE), still routed through the EntryPoint / LPs.
        bytes4[] memory depositSel = _one(IRoycoVaultTranche.deposit.selector);
        bytes4[] memory redeemSel = _one(IRoycoVaultTranche.redeem.selector);

        bytes4[] memory pauseSel = _one(IRoycoAuth.pause.selector);
        bytes4[] memory upgradeSel = _one(UUPSUpgradeable.upgradeToAndCall.selector);

        for (uint256 i = 0; i < names.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, names[i]);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, burnSel, BURNER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, burnSel, BURNER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, seizeSel, TRANSFER_AGENT_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, seizeSel, TRANSFER_AGENT_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, depositSel, PUBLIC_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, depositSel, PUBLIC_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, redeemSel, ST_LP_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, redeemSel, JT_LP_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
        }
        return _n;
    }

    // ── Step 6: unpause rebind ────────────────────────────────────────────────

    function _diffUnpauseRebind(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am, uint256 _chainId) internal view returns (uint256) {
        if (_am.getRoleGuardian(ADMIN_UNPAUSER_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(address(_am), ADMIN_UNPAUSER_ROLE, GUARDIAN_ROLE);
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

    // ── Step 7: label backfill ────────────────────────────────────────────────

    /// @dev Original royco-dawn deploy doesn't `labelRole` any of its roles. Backfill on a
    ///      first-run gate (probe via `getRoleGuardian(ADMIN_UPGRADER_ROLE)` against the
    ///      expected GUARDIAN_ROLE — set during initial dawn deploy, so present on a
    ///      previously-deployed chain. We use a different probe: WAY hasRole(ADMIN_KERNEL_ROLE)
    ///      — true after the migration runs once, false before.)
    function _diffLabels(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        (bool labelsLikelySet,) = _am.hasRole(ADMIN_KERNEL_ROLE, WAY);
        if (labelsLikelySet) return _n;

        _buf[_n++] = buildLabelRole(address(_am), ADMIN_PAUSER_ROLE, "ADMIN_PAUSER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_UNPAUSER_ROLE, "ADMIN_UNPAUSER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_UPGRADER_ROLE, "ADMIN_UPGRADER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ST_LP_ROLE, "ST_LP_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), JT_LP_ROLE, "JT_LP_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), BURNER_ROLE, "BURNER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), SYNC_ROLE, "SYNC_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_KERNEL_ROLE, "ADMIN_KERNEL_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_ACCOUNTANT_ROLE, "ADMIN_ACCOUNTANT_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_PROTOCOL_FEE_SETTER_ROLE, "ADMIN_PROTOCOL_FEE_SETTER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_ORACLE_QUOTER_ROLE, "ADMIN_ORACLE_QUOTER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_ENTRY_POINT_ROLE, "ADMIN_ENTRY_POINT_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, "ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE");
        _buf[_n++] = buildLabelRole(address(_am), DEPLOYER_ROLE, "DEPLOYER_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), LP_ROLE_ADMIN_ROLE, "LP_ROLE_ADMIN_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), DEPLOYER_ROLE_ADMIN_ROLE, "DEPLOYER_ROLE_ADMIN_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), GUARDIAN_ROLE, "GUARDIAN_ROLE");
        _buf[_n++] = buildLabelRole(address(_am), TRANSFER_AGENT_ROLE, "TRANSFER_AGENT_ROLE");
        return _n;
    }

    // ── Post-state assertion: guardian wiring ─────────────────────────────────

    /// @dev Custom error so a failure names the offending role id.
    error GuardianWiringMissing(uint64 role, uint64 actualGuardian);

    /// @dev Every WAY-held role that schedules DELAYED ops. The model requires each to be guarded
    ///      by `GUARDIAN_ROLE` so FNDN / FNDN_VETO can cancel a scheduled op (see
    ///      `docs/roles/assignments.md`). The migration sets some of these guardians explicitly
    ///      (entry-point roles, step 4) and INHERITS the rest from the original factory deploy.
    function _delayedWayRoles() internal pure returns (uint64[] memory roles) {
        roles = new uint64[](7);
        roles[0] = ADMIN_KERNEL_ROLE;
        roles[1] = ADMIN_ACCOUNTANT_ROLE;
        roles[2] = ADMIN_PROTOCOL_FEE_SETTER_ROLE;
        roles[3] = ADMIN_ORACLE_QUOTER_ROLE;
        roles[4] = ADMIN_ENTRY_POINT_ROLE;
        roles[5] = DEPLOYER_ROLE_ADMIN_ROLE;
        roles[6] = ADMIN_UPGRADER_ROLE;
    }

    /// @notice Asserts every delayed WAY role is cancellable via `GUARDIAN_ROLE`. Makes the
    ///         "guardians were wired at factory deploy" assumption explicit: generating a batch
    ///         against a factory where it doesn't hold (e.g. a new chain) reverts here instead of
    ///         silently emitting a topology where WAY's scheduled ops aren't FNDN-cancellable.
    function _assertGuardianWiring(IAccessManager _am) internal view {
        uint64[] memory roles = _delayedWayRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            uint64 g = _am.getRoleGuardian(roles[i]);
            if (g != GUARDIAN_ROLE) revert GuardianWiringMissing(roles[i], g);
        }
    }

    function _assertPostState(uint256 _chainId) internal view override {
        // The lockdown-only batch just flips FNDN's ADMIN_ROLE delay; guardian wiring is the
        // main batch's post-state concern (and isn't present until steps 1-7 are executed).
        if (_onlyAdminLockdown) return;
        _assertGuardianWiring(IAccessManager(roycoFactory(_chainId)));
    }

    // ── Step 8: ADMIN_ROLE delay (LAST) ───────────────────────────────────────

    /// @dev Set FNDN's `ADMIN_ROLE` execution delay to Root (72h). This is the last step
    ///      because every prior step relies on FNDN being able to call AM admin functions
    ///      immediately. After this, FNDN's admin ops (grantRole, setRoleAdmin,
    ///      setTargetFunctionRole, etc.) all run at 72h. Default cancel-gate keeps these
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
        _buf[_n++] = buildGrantRole(address(_am), _role, _holder, _desiredDelay);
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
        _buf[_n++] = buildSetTargetFunctionRole(address(_am), _target, missing, _desiredRole);
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

    function _outputPath(uint256 _chainId) internal view override returns (string memory) {
        if (_onlyAdminLockdown) {
            return string.concat("output/migrate/dawn/", _toString(_chainId), "_admin_role_lockdown");
        }
        return string.concat("output/migrate/dawn/", _toString(_chainId), "_apply_security_migration");
    }

    function _batchMeta(
        uint256 /*_chainId*/
    )
        internal
        view
        override
        returns (string memory name, string memory description)
    {
        if (_onlyAdminLockdown) {
            name = "Royco ADMIN_ROLE lockdown (Dawn surface - FINAL step)";
            description =
                "Sets FNDN's ADMIN_ROLE execution delay to 72h. This is the point of no return: after execution, every ADMIN_ROLE-gated op requires schedule -> wait 72h -> execute. Run once every chain has had the main migration (steps 1-7) applied.";
            return (name, description);
        }
        name = "Royco security migration (Dawn surface, WAY-centric)";
        description = string.concat(
            "Diff-based: WAY holds parameter-update + pause + upgrade roles; FNDN holds ADMIN_ROLE, GUARDIAN_ROLE, ADMIN_UNPAUSER_ROLE, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE. Re-running against a fully-applied chain produces a 0-tx batch.",
            _deferAdminLockdown
                ? " NOTE: the ADMIN_ROLE delay flip (72h lockdown) is intentionally EXCLUDED from this batch - apply it at the end via runLockdown."
                : ""
        );
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
