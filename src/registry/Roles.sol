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
 * Delays follow the three-tier taxonomy in `authorization/README.md`:
 *   Immediate (0s), Standard (24h), Critical (48h).
 *
 * `PUBLIC_ROLE` is the OZ AccessManager open role (every address auto-member). Used to leave
 * specific selectors unrestricted at the AM layer.
 */
abstract contract Roles {
    // ═══════════════════════════════════════════════════════════════════════════
    // DELAY TIERS
    // ═══════════════════════════════════════════════════════════════════════════

    uint32 internal constant DELAY_IMMEDIATE = 0;
    uint32 internal constant DELAY_STANDARD = 1 days;
    uint32 internal constant DELAY_CRITICAL = 2 days;

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS MANAGER BUILT-INS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev OZ AccessManager root admin role
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
    // VAULT ROLES (per authorization/README.md §2)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant VAULT_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_VAULT_MANAGER"))));
    uint64 internal constant STRATEGY_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_MANAGER"))));
    uint64 internal constant HOOK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_HOOK_MANAGER"))));

    // ═══════════════════════════════════════════════════════════════════════════
    // STRATEGY ROLES (per authorization/README.md §2 strategy table)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant STRATEGY_PAUSER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_PAUSER"))));
    uint64 internal constant STRATEGY_UNPAUSER = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_UNPAUSER"))));
    uint64 internal constant STRATEGY_RESCUE = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_RESCUE"))));
    uint64 internal constant STRATEGY_ALLOCATOR = uint64(uint256(keccak256(abi.encode("ROYCO_STRATEGY_ALLOCATOR"))));

    // ═══════════════════════════════════════════════════════════════════════════
    // MAKINA / CALIBER ROLES (per-vault, per authorization/README.md §2 makina table)
    // ═══════════════════════════════════════════════════════════════════════════

    uint64 internal constant SRROYUSDC_RISK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_SRROYUSDC_RISK_MANAGER"))));
    uint64 internal constant SRROYUSDC_TIMELOCK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_SRROYUSDC_TIMELOCK_MANAGER"))));
    uint64 internal constant ROYWSTETH_RISK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_ROYWSTETH_RISK_MANAGER"))));
    uint64 internal constant ROYWSTETH_TIMELOCK_MANAGER = uint64(uint256(keccak256(abi.encode("ROYCO_ROYWSTETH_TIMELOCK_MANAGER"))));
}
