// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title Roles
 * @notice Canonical role IDs and delay tiers for the Royco security model.
 *
 * Role IDs are uint64 values derived via keccak256 of a tag string, matching the convention used
 * by `lib/royco-dawn/src/factory/RolesConfiguration.sol`. Re-deriving here (rather than importing)
 * keeps this repo independent of the dawn solc/optimizer settings.
 *
 * Delays follow:
 *   Immediate (0s) — user-facing / pause / cancel / sync
 *   Minimum (60h)  — uniform floor for all delayed ops (parameter changes, operational tuning).
 *                    Every execution delay below 60h is raised to this floor.
 *   Root (7d)      — `ADMIN_ROLE` itself + UUPS upgrades
 *   Rescue (30d)   — strategy rescue, on top of the on-chain 30d timelock
 *
 * Authority topology:
 *   FNDN      — `ADMIN_ROLE` (7d, root; rarely transacts), `GUARDIAN_ROLE`,
 *               `ADMIN_UNPAUSER_ROLE`, `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE`. Only FNDN can
 *               grant/revoke roles (call-gate hardcoded to ADMIN_ROLE in OZ AM). FNDN's admin
 *               ops run at 7d and are intentionally non-cancellable by any other party.
 *   WAY       — every parameter-update role (`ADMIN_KERNEL_ROLE`, `ADMIN_ACCOUNTANT_ROLE`,
 *               etc.) at the 60h floor, plus `ADMIN_UPGRADER_ROLE` (Root 7d). Schedules all
 *               delayed ops; each is cancellable via `GUARDIAN_ROLE`. No longer holds pause.
 *   WAY_PAUSE — dedicated 1/4 multisig; sole holder of `ADMIN_PAUSER_ROLE` / `STRATEGY_PAUSER`
 *               (Immediate). Can pause every protocol contract.
 *   FNDN_VETO — dedicated 1/4 multisig; co-holds `GUARDIAN_ROLE` with FNDN (Immediate). Can
 *               cancel any WAY-scheduled op.
 *   DIAL      — strategy `STRATEGY_ALLOCATOR` + native vault `ALLOCATOR` / `WITHDRAWAL_MANAGER`.
 */
abstract contract Roles {
    // ═══════════════════════════════════════════════════════════════════════════
    // DELAY TIERS
    // ═══════════════════════════════════════════════════════════════════════════

    uint32 internal constant DELAY_IMMEDIATE = 0;
    /// @dev Uniform minimum delay floor (60h) for every delayed op. Replaces the former
    ///      Standard (24h) / Critical (48h) tiers — all sub-60h delays are raised to this.
    uint32 internal constant DELAY_MIN = 60 hours;
    /// @dev Used by `ADMIN_ROLE` (FNDN role-management) and `ADMIN_UPGRADER_ROLE` (UUPS upgrades).
    uint32 internal constant DELAY_ROOT = 7 days;
    /// @dev Reserved for `STRATEGY_RESCUE`. The Royco strategy's `rescueToken` is `restricted`
    ///      with no internal timelock — this AM execution delay is the only gate; FNDN-cancellable
    ///      via `GUARDIAN_ROLE` during the 30d window.
    uint32 internal constant DELAY_RESCUE = 30 days;

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS MANAGER BUILT-INS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev OZ AccessManager root admin role. Default admin of every other role
    ///      (`getRoleAdmin(R) = ADMIN_ROLE`), so `grantRole`/`revokeRole` for any operational
    ///      role goes through ADMIN_ROLE. FNDN holds this at Root (7d).
    uint64 internal constant ADMIN_ROLE = 0;

    /// @dev OZ AccessManager open role (every address is auto-member)
    uint64 internal constant PUBLIC_ROLE = type(uint64).max;

    // ═══════════════════════════════════════════════════════════════════════════
    // DAWN ROLES (mirror lib/royco-dawn/src/factory/RolesConfiguration.sol)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant ADMIN_PAUSER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_PAUSER_ROLE"))));
    uint64 internal constant ADMIN_UNPAUSER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_UNPAUSER_ROLE"))));
    uint64 internal constant ADMIN_UPGRADER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_UPGRADER_ROLE"))));

    uint64 internal constant ST_LP_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ST_LP_ROLE"))));
    uint64 internal constant JT_LP_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_JT_LP_ROLE"))));
    uint64 internal constant BURNER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_BURNER_ROLE"))));

    uint64 internal constant SYNC_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_SYNC_ROLE"))));
    uint64 internal constant ADMIN_KERNEL_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_KERNEL_ROLE"))));
    uint64 internal constant TRANSFER_AGENT_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_TRANSFER_AGENT_ROLE"))));

    uint64 internal constant ADMIN_ENTRY_POINT_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ENTRY_POINT_ROLE"))));
    uint64 internal constant ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE"))));

    uint64 internal constant ADMIN_ACCOUNTANT_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ACCOUNTANT_ROLE"))));
    uint64 internal constant ADMIN_PROTOCOL_FEE_SETTER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_PROTOCOL_FEE_SETTER_ROLE"))));

    uint64 internal constant ADMIN_ORACLE_QUOTER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_ADMIN_ORACLE_QUOTER_ROLE"))));

    uint64 internal constant DEPLOYER_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_DEPLOYER_ROLE"))));

    uint64 internal constant LP_ROLE_ADMIN_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_LP_ROLE_ADMIN_ROLE"))));
    uint64 internal constant DEPLOYER_ROLE_ADMIN_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_DEPLOYER_ROLE_ADMIN_ROLE"))));

    uint64 internal constant GUARDIAN_ROLE = uint64(uint256(keccak256(abi.encode("ROYCO_GUARDIAN_ROLE"))));

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCRETE VAULT ROLES — one AM role per migrated concrete role
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // `ALLOCATOR` / `WITHDRAWAL_MANAGER` are NOT mapped — those stay native (DIAL holds
    // them on the vault directly) and aren't gated by any AM role.

    /// @dev Mirrors concrete `VAULT_MANAGER`. WAY @ 60h, guardian = GUARDIAN_ROLE.
    uint64 internal constant VAULT_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_VAULT_MANAGER"))));
    /// @dev Mirrors concrete `STRATEGY_MANAGER`. WAY @ 60h, guardian = GUARDIAN_ROLE.
    uint64 internal constant STRATEGY_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_MANAGER"))));
    /// @dev Mirrors concrete `HOOK_MANAGER`. WAY @ 60h, guardian = GUARDIAN_ROLE.
    uint64 internal constant HOOK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_HOOK_MANAGER"))));

    // ═══════════════════════════════════════════════════════════════════════════
    // STRATEGY ROLES (per concrete-vault strategy adapter)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant STRATEGY_PAUSER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_PAUSER"))));
    uint64 internal constant STRATEGY_UNPAUSER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_UNPAUSER"))));
    uint64 internal constant STRATEGY_RESCUE = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_RESCUE"))));
    uint64 internal constant STRATEGY_ALLOCATOR = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_ALLOCATOR"))));

    // ═══════════════════════════════════════════════════════════════════════════
    // MAKINA / CALIBER ROLES (per-vault)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant SRROYUSDC_RISK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_SRROYUSDC_RISK_MANAGER"))));
    uint64 internal constant SRROYUSDC_TIMELOCK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_SRROYUSDC_TIMELOCK_MANAGER"))));
    uint64 internal constant ROYWSTETH_RISK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_ROYWSTETH_RISK_MANAGER"))));
    uint64 internal constant ROYWSTETH_TIMELOCK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_ROYWSTETH_TIMELOCK_MANAGER"))));
}
