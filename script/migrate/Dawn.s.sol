// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Selectors } from "../../src/access/Selectors.sol";
import { MigrationBase } from "../../src/migration/MigrationBase.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Script } from "forge-std/Script.sol";
import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

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
 *   4. **`ADMIN_MANAGER` role + cancel-gate wiring**:
 *        - Label `ADMIN_MANAGER`, set its guardian to `GUARDIAN_ROLE` (WAY can cancel).
 *        - Grant `ADMIN_MANAGER` to FNDN at Critical (48h).
 *        - `setRoleAdmin(R, ADMIN_MANAGER)` for every operational role across Dawn / vaults /
 *          strategy / makina — so `grantRole(R, ...)` requires `ADMIN_MANAGER` (FNDN @ 48h)
 *          instead of `ADMIN_ROLE`. Keeps grants delayed AND cancellable.
 *        - `setTargetFunctionRole(AM, [10 admin selectors], ADMIN_MANAGER)` — purely the
 *          cancel-path storage write so WAY can cancel any scheduled `setRoleAdmin` /
 *          `setRoleGuardian` / `setTargetFunctionRole` / `setGrantDelay` / etc. The OZ AM
 *          call-gate for these is hardcoded to `ADMIN_ROLE` and isn't (and can't be)
 *          changed; this only re-routes the cancel guardian lookup.
 *
 *   5. **Critical (48h) execution delay on `ADMIN_ROLE`** (LAST). After this every
 *      `ADMIN_ROLE`-gated call requires schedule + 48h + execute.
 * Output: `output/migrate/dawn/{chainId}_apply_security_migration.json` (one per chain).
 */
contract MigrateDawn is MigrationBase, Script {
    /// @dev Upper bound on diff'd batch size. Mainnet (7 markets × 2 tranches × ~8 selector
    ///      groups + entry-point + admin-manager wiring) tops out around 200 tx if every tranche
    ///      binding is missing; clean re-runs produce 0 txs.
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

        n = _diffFNDNRoleGrants(buf, n, am);
        n = _diffEntryPointConfig(buf, n, am, _chainId);
        n = _diffTrancheBindings(buf, n, am, _chainId);
        n = _diffUnpauseRebind(buf, n, am, _chainId);
        n = _diffAdminManager(buf, n, am);
        n = _diffAdminRoleDelay(buf, n, am);

        return _trim(buf, n);
    }

    // ── Step 1 ────────────────────────────────────────────────────────────────

    /// @dev Several roles are co-held by FNDN and WAY at the same delay so WAY can also
    ///      schedule/execute the corresponding ops. The complete dual-holder set:
    ///        Immediate:    ADMIN_PAUSER_ROLE, LP_ROLE_ADMIN_ROLE, SYNC_ROLE
    ///        Critical 48h: ADMIN_KERNEL_ROLE, ADMIN_ACCOUNTANT_ROLE, ADMIN_PROTOCOL_FEE_SETTER_ROLE
    ///      WAY also holds GUARDIAN_ROLE solo (Immediate) — that grant is here too.
    function _diffFNDNRoleGrants(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Immediate (0)
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, DEPLOYER_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_PAUSER_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, LP_ROLE_ADMIN_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, FNDN, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, SYNC_ROLE, WAY, DELAY_IMMEDIATE);
        _n = _maybeGrantRole(_buf, _n, _am, GUARDIAN_ROLE, WAY, DELAY_IMMEDIATE);
        // Standard (24h)
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
        // Root (48h) for ADMIN_ROLE is set last in step 4
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

        // Bring BURNER_ROLE's guardian in line with the rest of the model.
        if (_am.getRoleGuardian(BURNER_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, BURNER_ROLE, GUARDIAN_ROLE);
        }

        // Bring ADMIN_ENTRY_POINT_ROLE / ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE's guardian in line with the rest of the model.
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE, GUARDIAN_ROLE);
        }
        if (_am.getRoleGuardian(ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE) != GUARDIAN_ROLE) {
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE, GUARDIAN_ROLE);
        }
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

    // ── Step 3.5 ──────────────────────────────────────────────────────────────

    /// @dev Ensures every tranche on every market has the canonical role bindings from the
    ///      `royco-dawn` deploy (`Deploy.s.sol::_buildTrancheRolesConfig`). Pre-existing
    ///      markets may have been deployed before some bindings (notably `BURNER_ROLE`) were
    ///      added — this step diffs and rebinds anything missing so role coverage is uniform
    ///      across the entire surface. `unpause()` is intentionally skipped here because
    ///      `_diffUnpauseRebind` re-binds it to `ADMIN_UNPAUSER_ROLE`.
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

            // BURNER_ROLE on burn/burnFrom — both tranches.
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, burnSel, BURNER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, burnSel, BURNER_ROLE);

            // TRANSFER_AGENT_ROLE on seizeShares/seizeAndRedeemShares — both tranches.
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, seizeSel, TRANSFER_AGENT_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, seizeSel, TRANSFER_AGENT_ROLE);

            // LP roles on deposit/redeem (per-tranche role).
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, lpSel, ST_LP_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, lpSel, JT_LP_ROLE);

            // Pause / upgrade (unpause handled by _diffUnpauseRebind).
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, pauseSel, ADMIN_PAUSER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.seniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
            _n = _maybeSetTargetFunctionRole(_buf, _n, _am, m.juniorTranche, upgradeSel, ADMIN_UPGRADER_ROLE);
        }
        return _n;
    }

    // ── Step 4 ────────────────────────────────────────────────────────────────

    /// @dev Wires the ADMIN_MANAGER role and the AM-self cancel-gate.
    ///
    ///   - Label + guardian (GUARDIAN_ROLE) so WAY can cancel any op resolved via this role.
    ///   - Grant ADMIN_MANAGER to FNDN at Critical 48h.
    ///   - Re-admin every operational role from ADMIN_ROLE → ADMIN_MANAGER. After this,
    ///     `grantRole(R, ...)` requires ADMIN_MANAGER (FNDN @ 48h) — both the call-gate
    ///     and the cancel-gate route through ADMIN_MANAGER's guardian (= GUARDIAN_ROLE).
    ///   - Cancel-gate the 10 AM-self admin selectors to ADMIN_MANAGER. The OZ AM
    ///     call-gate hardcodes ADMIN_ROLE for these (line 631-650 in AccessManager.sol),
    ///     so this storage write only affects the cancel path's guardian lookup —
    ///     `cancel()` reads `getRoleGuardian(getTargetFunctionRole(AM, sel))` which
    ///     becomes `getRoleGuardian(ADMIN_MANAGER) = GUARDIAN_ROLE`.
    function _diffAdminManager(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        // Labels (idempotent on-chain; emit only once by checking if ADMIN_MANAGER's guardian
        // is already set — that's the cheapest "are we already wired?" probe available without
        // a labels view)
        bool needsLabel = _am.getRoleGuardian(ADMIN_MANAGER) != GUARDIAN_ROLE;
        if (needsLabel) {
            _buf[_n++] = buildLabelRole(ROYCO_FACTORY, ADMIN_MANAGER, "ADMIN_MANAGER");
            _buf[_n++] = buildSetRoleGuardian(ROYCO_FACTORY, ADMIN_MANAGER, GUARDIAN_ROLE);
            // Backfill labels for every Dawn role.
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
        }

        // Grant ADMIN_MANAGER to FNDN @ Critical
        _n = _maybeGrantRole(_buf, _n, _am, ADMIN_MANAGER, FNDN, DELAY_CRITICAL);

        // Re-admin every operational role
        uint64[] memory roles = _adminManagerRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            if (_am.getRoleAdmin(roles[i]) != ADMIN_MANAGER) {
                _buf[_n++] = buildSetRoleAdmin(ROYCO_FACTORY, roles[i], ADMIN_MANAGER);
            }
        }

        // Cancel-gate the AM-self admin selectors
        _n = _maybeSetTargetFunctionRole(_buf, _n, _am, ROYCO_FACTORY, Selectors.accessManagerAdminSelectors(), ADMIN_MANAGER);
        return _n;
    }

    /// @dev Every operational role whose admin should be ADMIN_MANAGER instead of ADMIN_ROLE.
    ///      Includes Dawn / vault / strategy / makina roles — admin gating is system-wide,
    ///      not per-surface. Excluded:
    ///        - PUBLIC_ROLE, ADMIN_ROLE, ADMIN_MANAGER itself
    ///        - ST_LP_ROLE, JT_LP_ROLE — admin stays LP_ROLE_ADMIN_ROLE so FNDN/WAY can
    ///          onboard LPs at Immediate (rather than 48h via ADMIN_MANAGER)
    ///        - DEPLOYER_ROLE — admin stays DEPLOYER_ROLE_ADMIN_ROLE for the same reason
    function _adminManagerRoles() internal pure returns (uint64[] memory roles) {
        roles = new uint64[](23);
        // Dawn
        roles[0] = ADMIN_PAUSER_ROLE;
        roles[1] = ADMIN_UNPAUSER_ROLE;
        roles[2] = ADMIN_UPGRADER_ROLE;
        roles[3] = BURNER_ROLE;
        roles[4] = SYNC_ROLE;
        roles[5] = ADMIN_KERNEL_ROLE;
        roles[6] = TRANSFER_AGENT_ROLE;
        roles[7] = ADMIN_ENTRY_POINT_ROLE;
        roles[8] = ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE;
        roles[9] = ADMIN_ACCOUNTANT_ROLE;
        roles[10] = ADMIN_PROTOCOL_FEE_SETTER_ROLE;
        roles[11] = ADMIN_ORACLE_QUOTER_ROLE;
        roles[12] = LP_ROLE_ADMIN_ROLE;
        roles[13] = DEPLOYER_ROLE_ADMIN_ROLE;
        roles[14] = GUARDIAN_ROLE;
        // Strategy (vault-level management collapsed onto ADMIN_MANAGER, no separate roles)
        roles[15] = STRATEGY_PAUSER;
        roles[16] = STRATEGY_UNPAUSER;
        roles[17] = STRATEGY_RESCUE;
        roles[18] = STRATEGY_ALLOCATOR;
        // Makina (per-vault)
        roles[19] = SRROYUSDC_RISK_MANAGER;
        roles[20] = SRROYUSDC_TIMELOCK_MANAGER;
        roles[21] = ROYWSTETH_RISK_MANAGER;
        roles[22] = ROYWSTETH_TIMELOCK_MANAGER;
    }

    // ── Step 5 ────────────────────────────────────────────────────────────────

    /// @dev grantRole(ADMIN_ROLE, FNDN, Critical 48h) — LAST. The 48h tier (instead of the
    ///      previous 7d Root) is sufficient because every admin op is now WAY-cancellable
    ///      via the cancel-gate wiring in step 4.
    function _diffAdminRoleDelay(SafeTransaction[] memory _buf, uint256 _n, IAccessManager _am) internal view returns (uint256) {
        return _maybeGrantRole(_buf, _n, _am, ADMIN_ROLE, FNDN, DELAY_CRITICAL);
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
