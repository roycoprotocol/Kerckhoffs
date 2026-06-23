// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { AccessManagerDumper } from "../../src/access/AccessManagerDumper.sol";
import { Selectors } from "../../src/access/Selectors.sol";
import { SafeSimulator } from "../../src/safe/SafeSimulator.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";
import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";

/// @dev Minimal interface for native vault AccessControl operations.
interface IConcreteVault {
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/**
 * @title MigrateVaults
 * @notice Migrates the concrete vaults (`srRoyUSDC`, `roywstETH`) to the canonical security
 *         model in `authorization/README.md` §2.
 *
 * Per vault, the script generates THREE Safe transaction batches:
 *
 *   - **Phase 1 (native)**: target = the concrete vault. Grants every native `AccessControl`
 *     role on the vault to the AccessManager (`ROYCO_FACTORY`) and revokes from the current
 *     holder(s).
 *
 *   - **Phase 2 (AM-side)**: target = `ROYCO_FACTORY`. Labels every new role,
 *     `setTargetFunctionRole`s the vault selectors per `authorization/README.md` §2, and
 *     grants the AM-side roles to FNDN / DIAL with the model's delays.
 *
 *   - **Merged**: phase 1 + phase 2 concatenated via `mergeBatches`. Reference / one-shot
 *     execution batch. Two-phase remains the recommended path.
 *
 * Native-side current holders are read from the fork at script run time
 * (`getRoleMemberCount` + `getRoleMember`); the resulting revoke list lands in the JSON.
 *
 * Output:
 *   `output/migrate/vaults/{vaultName}_phase1_native.json`
 *   `output/migrate/vaults/{vaultName}_phase2_am.json`
 *   `output/migrate/vaults/{vaultName}_merged.json`
 */
contract MigrateVaults is AccessManagerDumper, SafeSimulator, Script {
    // ═══════════════════════════════════════════════════════════════════════════
    // ENTRY POINT
    // ═══════════════════════════════════════════════════════════════════════════

    function run() external {
        _assertProductionMultisigs();
        // Vaults are Ethereum-only.
        _processChain(MAINNET);
    }

    function _processChain(uint256 _chainId) internal {
        vm.createSelectFork(_getRpcUrl(_chainId));

        console2.log("");
        console2.log("################################################################################");
        console2.log("Vaults migration | chain:", _chainName(_chainId), _chainId);
        console2.log("################################################################################");

        console2.log("");
        console2.log(">>> Pre-state");
        dumpAccessManager(_chainId);

        string[] memory names = vaultNames(_chainId);
        for (uint256 i = 0; i < names.length; i++) {
            _processVault(_chainId, names[i]);
        }
    }

    function _processVault(uint256 _chainId, string memory _vaultName) internal {
        VaultAddresses memory v = getVaultAddresses(_chainId, _vaultName);

        console2.log("");
        console2.log("================================================================================");
        console2.log("Vault:", _vaultName);
        console2.log("  address:", v.vault);
        console2.log("================================================================================");

        StrategyStack memory s = getStrategyStack(_chainId, _vaultName);
        SafeTransaction[] memory phase1 = _buildPhase1Native(v.vault);
        SafeTransaction[] memory phase2 = _buildPhase2AM(v.vault, s.strategy, _vaultName);

        SafeTransaction[][] memory both = new SafeTransaction[][](2);
        both[0] = phase1;
        both[1] = phase2;
        SafeTransaction[] memory merged = mergeBatches(both);

        // Simulate the merged batch.
        // - Phase 1 txs target the vault directly; the existing native role-admin must run them.
        // - Phase 2 txs target the AM (RoycoFactory); FNDN runs them with role 0 (currently 0 delay).
        console2.log("");
        console2.log(">>> Simulating phase 1 (native)");
        _simulateNative(v.vault, phase1);

        console2.log("");
        console2.log(">>> Simulating phase 2 (AM)");
        _replayBatch(FNDN, phase2);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);

        // Write the three JSONs.
        string memory base = string.concat("output/migrate/vaults/", _vaultName);
        writeSafeTransactionJson(
            phase1,
            string.concat(base, "_phase1_native.json"),
            string.concat("Royco vault migration ", _vaultName, " (phase 1 native)"),
            "Native-side: grant AccessControl roles to AccessManager + revoke from current holders."
        );
        writeSafeTransactionJson(
            phase2,
            string.concat(base, "_phase2_am.json"),
            string.concat("Royco vault migration ", _vaultName, " (phase 2 AM)"),
            "AM-side: label roles + setTargetFunctionRole for vault selectors + grant AM-side roles with delays."
        );
        writeSafeTransactionJson(
            merged,
            string.concat(base, "_merged.json"),
            string.concat("Royco vault migration ", _vaultName, " (merged)"),
            "Phase 1 + Phase 2 in a single batch (reference; two-phase path recommended)."
        );

        console2.log("");
        console2.log("  Wrote:", base, "_{phase1_native,phase2_am,merged}.json");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 1 — NATIVE
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildPhase1Native(address _vault) internal view returns (SafeTransaction[] memory) {
        IConcreteVault vault = IConcreteVault(_vault);
        bytes32[] memory roles = _nativeRoles();

        // Count: per-role, 1 grant for AM (skip if AM is already a member) + N revokes for non-AM holders.
        uint256 totalTxs;
        uint256[] memory holderCounts = new uint256[](roles.length);
        for (uint256 i = 0; i < roles.length; i++) {
            holderCounts[i] = vault.getRoleMemberCount(roles[i]);
            bool amAlreadyMember = vault.hasRole(roles[i], ROYCO_FACTORY);
            uint256 nonAmHolders;
            for (uint256 j = 0; j < holderCounts[i]; j++) {
                if (vault.getRoleMember(roles[i], j) != ROYCO_FACTORY) nonAmHolders++;
            }
            totalTxs += (amAlreadyMember ? 0 : 1) + nonAmHolders;
        }

        SafeTransaction[] memory txs = new SafeTransaction[](totalTxs);
        uint256 t;

        // Per-role: grant to AM (if not already a member) + revoke from non-AM holders.
        for (uint256 i = 0; i < roles.length; i++) {
            bool amAlreadyMember = vault.hasRole(roles[i], ROYCO_FACTORY);
            if (!amAlreadyMember) {
                txs[t++] = SafeTransaction({ to: _vault, value: 0, data: abi.encodeCall(IConcreteVault.grantRole, (roles[i], ROYCO_FACTORY)) });
            }
            uint256 mc = holderCounts[i];
            for (uint256 j = 0; j < mc; j++) {
                address holder = vault.getRoleMember(roles[i], j);
                if (holder == ROYCO_FACTORY) continue;
                txs[t++] = SafeTransaction({ to: _vault, value: 0, data: abi.encodeCall(IConcreteVault.revokeRole, (roles[i], holder)) });
            }
        }

        require(t == totalTxs, "phase1 tx count mismatch");
        return txs;
    }

    /// @dev Roles to grant the AM + revoke from current holders on the vault.
    ///
    ///      Primary roles migrated: `VAULT_MANAGER`, `STRATEGY_MANAGER`, `HOOK_MANAGER`.
    ///      `ALLOCATOR` / `WITHDRAWAL_MANAGER` stay native (Immediate operations roles held by
    ///      DIAL); current primary holders untouched.
    ///
    ///      ALL admin slots (`*_ADMIN`) are migrated, even for the ALLOCATOR/WITHDRAWAL_MANAGER
    ///      pairs whose primary role we leave alone. This collapses the entire concrete
    ///      grant/revoke surface onto the AM root admin (FNDN with Critical delay) per
    ///      `authorization/README.md` §2 — without it, a current `*_ADMIN` holder could re-grant
    ///      the primary role to anyone, bypassing the AM gate.
    function _nativeRoles() internal pure returns (bytes32[] memory roles) {
        roles = new bytes32[](8);
        // Primary roles
        roles[0] = Selectors.nativeVaultManager();
        roles[1] = Selectors.nativeStrategyManager();
        roles[2] = Selectors.nativeHookManager();
        // Admin roles (also for ALLOCATOR/WITHDRAWAL_MANAGER, whose primary roles stay native)
        roles[3] = Selectors.nativeVaultManagerAdmin();
        roles[4] = Selectors.nativeStrategyManagerAdmin();
        roles[5] = Selectors.nativeHookManagerAdmin();
        roles[6] = Selectors.nativeAllocatorAdmin();
        roles[7] = Selectors.nativeWithdrawalManagerAdmin();
    }

    /// @dev Phase 1 grant/revoke txs each need to be sent by the role's admin holder. We resolve
    ///      that at simulation time by reading `vault.getRoleAdmin(role)` and pranking the first
    ///      member of that admin role. Real execution will be done by whoever actually holds
    ///      the role-admin slot.
    function _simulateNative(address _vault, SafeTransaction[] memory _txs) internal {
        for (uint256 i = 0; i < _txs.length; i++) {
            address caller = _resolveNativeCaller(_vault, _txs[i]);
            if (caller == address(0)) {
                console2.log("  [SKIP] native tx index unable to resolve caller:", i);
                continue;
            }
            vm.prank(caller);
            (bool ok, bytes memory ret) = _txs[i].to.call(_txs[i].data);
            if (!ok) {
                console2.log("  [WARN] native tx reverted at index:", i);
                if (ret.length >= 4) console2.logBytes4(bytes4(ret));
            }
        }
    }

    /// @dev Pick the caller for a phase-1 simulation tx by looking up the role-admin's first
    ///      member on-chain.
    function _resolveNativeCaller(address _vault, SafeTransaction memory _tx) internal view returns (address) {
        bytes memory data = _tx.data;
        if (data.length < 4 + 32) return address(0);
        bytes4 sel;
        bytes32 role;
        assembly {
            sel := mload(add(data, 32))
            role := mload(add(data, 36))
        }
        if (sel != IConcreteVault.grantRole.selector && sel != IConcreteVault.revokeRole.selector) {
            return address(0);
        }

        IConcreteVault vault = IConcreteVault(_vault);
        bytes32 admin = vault.getRoleAdmin(role);
        if (vault.getRoleMemberCount(admin) == 0) return address(0);
        return vault.getRoleMember(admin, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 2 — ACCESS MANAGER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Phase 2 covers two surfaces:
    ///   (a) **Vault-level**: each migrated concrete role gets its own AM role:
    ///         - `VAULT_MANAGER` ← `vaultManagerSelectors`
    ///         - `STRATEGY_MANAGER` ← `strategyManagerSelectors`
    ///         - `HOOK_MANAGER` ← `hookManagerSelectors`
    ///       All three held by WAY at 60h, guardian = `GUARDIAN_ROLE` (FNDN-cancellable).
    ///       The native `vault.grantRole` / `vault.revokeRole` paths are not bound to any
    ///       specific AM role and fall through to the default (`ADMIN_ROLE`), so adding new
    ///       holders to a native vault role requires FNDN's 7d ADMIN_ROLE flow.
    ///       `ALLOCATOR` / `WITHDRAWAL_MANAGER` stay native (Immediate, DIAL).
    ///   (b) **Strategy-level** wiring for the makina-strategy adapter:
    ///         - `STRATEGY_PAUSER` → WAY_PAUSE @ Immediate (WAY revoked)
    ///         - `STRATEGY_UNPAUSER` → FNDN @ Immediate
    ///         - `STRATEGY_RESCUE` → FNDN @ 30d (single AM-side delay; `rescueToken` is
    ///           `restricted` with no internal timelock, so this is the only gate)
    ///         - `STRATEGY_ALLOCATOR` → DIAL @ Immediate
    ///       Guardian explicitly set to `GUARDIAN_ROLE` for the only delayed strategy role
    ///       (`STRATEGY_RESCUE`) so its scheduled op is FNDN-cancellable.
    function _buildPhase2AM(address _vault, address _strategy, string memory _vaultName) internal pure returns (SafeTransaction[] memory) {
        require(DIAL != address(0), "DIAL multisig must be set before applying vault migration");

        // Vault: 3 labels + 3 setTargetFunctionRole + 3 setRoleGuardian + 3 grants = 12
        // Strategy: 4 labels + 4 setTargetFunctionRole + 1 setRoleGuardian (RESCUE) + 4 grants
        //           + 1 revoke (WAY from STRATEGY_PAUSER) = 14
        uint256 vaultTxs = 12;
        uint256 strategyTxs = 4 + 4 + 1 + 4 + 1;
        SafeTransaction[] memory txs = new SafeTransaction[](vaultTxs + strategyTxs);
        uint256 t;

        // ── Vault: per-concrete-role AM setup ─────────────────────────────────
        txs[t++] = buildLabelRole(ROYCO_FACTORY, VAULT_MANAGER, string.concat(_vaultName, "_VAULT_MANAGER"));
        txs[t++] = buildLabelRole(ROYCO_FACTORY, STRATEGY_MANAGER, string.concat(_vaultName, "_STRATEGY_MANAGER"));
        txs[t++] = buildLabelRole(ROYCO_FACTORY, HOOK_MANAGER, string.concat(_vaultName, "_HOOK_MANAGER"));

        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _vault, Selectors.vaultManagerSelectors(), VAULT_MANAGER);
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _vault, Selectors.strategyManagerSelectors(), STRATEGY_MANAGER);
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _vault, Selectors.hookManagerSelectors(), HOOK_MANAGER);

        txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, VAULT_MANAGER, GUARDIAN_ROLE);
        txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, STRATEGY_MANAGER, GUARDIAN_ROLE);
        txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, HOOK_MANAGER, GUARDIAN_ROLE);

        txs[t++] = buildGrantRole(ROYCO_FACTORY, VAULT_MANAGER, WAY, DELAY_MIN);
        txs[t++] = buildGrantRole(ROYCO_FACTORY, STRATEGY_MANAGER, WAY, DELAY_MIN);
        txs[t++] = buildGrantRole(ROYCO_FACTORY, HOOK_MANAGER, WAY, DELAY_MIN);

        // ── Strategy labels ──────────────────────────────────────────────────
        txs[t++] = buildLabelRole(ROYCO_FACTORY, STRATEGY_PAUSER, string.concat(_vaultName, "_STRATEGY_PAUSER"));
        txs[t++] = buildLabelRole(ROYCO_FACTORY, STRATEGY_UNPAUSER, string.concat(_vaultName, "_STRATEGY_UNPAUSER"));
        txs[t++] = buildLabelRole(ROYCO_FACTORY, STRATEGY_RESCUE, string.concat(_vaultName, "_STRATEGY_RESCUE"));
        txs[t++] = buildLabelRole(ROYCO_FACTORY, STRATEGY_ALLOCATOR, string.concat(_vaultName, "_STRATEGY_ALLOCATOR"));

        // ── Strategy selector bindings ───────────────────────────────────────
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _strategy, _one(IRoycoAuth.pause.selector), STRATEGY_PAUSER);
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _strategy, _one(IRoycoAuth.unpause.selector), STRATEGY_UNPAUSER);
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _strategy, _one(IStrategyTemplate.rescueToken.selector), STRATEGY_RESCUE);
        txs[t++] = buildSetTargetFunctionRole(ROYCO_FACTORY, _strategy, Selectors.strategyAllocatorSelectors(), STRATEGY_ALLOCATOR);

        // ── Strategy guardian wiring (delayed role only) ──────────────────────
        // STRATEGY_PAUSER, STRATEGY_UNPAUSER, STRATEGY_ALLOCATOR are all Immediate; only
        // STRATEGY_RESCUE has a delay (30d) so only it needs cancel-gate wiring.
        txs[t++] = buildSetRoleGuardian(ROYCO_FACTORY, STRATEGY_RESCUE, GUARDIAN_ROLE);

        // ── Strategy grants ──────────────────────────────────────────────────
        // Pause goes to the dedicated WAY_PAUSE multisig; WAY is revoked below. (The revoke is a
        // safe no-op if WAY was never granted STRATEGY_PAUSER — OZ `_revokeRole` returns false.)
        txs[t++] = buildGrantRole(ROYCO_FACTORY, STRATEGY_PAUSER, WAY_PAUSE, DELAY_IMMEDIATE);
        txs[t++] = buildRevokeRole(ROYCO_FACTORY, STRATEGY_PAUSER, WAY);
        txs[t++] = buildGrantRole(ROYCO_FACTORY, STRATEGY_UNPAUSER, FNDN, DELAY_IMMEDIATE);
        txs[t++] = buildGrantRole(ROYCO_FACTORY, STRATEGY_RESCUE, FNDN, DELAY_RESCUE);
        txs[t++] = buildGrantRole(ROYCO_FACTORY, STRATEGY_ALLOCATOR, DIAL, DELAY_IMMEDIATE);

        require(t == txs.length, "phase2 tx count mismatch");
        return txs;
    }

    /// @dev Tiny helper: wrap a single selector in a `bytes4[1]`.
    function _one(bytes4 _sel) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = _sel;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ASSERTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Moved to `test/VaultsMigration.t.sol`.

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST HOOK
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test-only entry point: applies the migration to a forked chain without writing
    ///         JSON or dumping state. Tests chain Dawn → Vaults → Makina migrations via this.
    function applyToFork(uint256 _chainId) public {
        if (block.chainid != _chainId) {
            vm.createSelectFork(_getRpcUrl(_chainId));
        }
        string[] memory names = vaultNames(_chainId);
        for (uint256 i = 0; i < names.length; i++) {
            VaultAddresses memory v = getVaultAddresses(_chainId, names[i]);
            StrategyStack memory s = getStrategyStack(_chainId, names[i]);
            SafeTransaction[] memory phase1 = _buildPhase1Native(v.vault);
            SafeTransaction[] memory phase2 = _buildPhase2AM(v.vault, s.strategy, names[i]);
            _simulateNative(v.vault, phase1);
            _replayBatch(FNDN, phase2);
        }
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
    }
}
