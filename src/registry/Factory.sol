// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CommonBase } from "forge-std/Base.sol";

/**
 * @title Factory
 * @notice The Royco factory address (the single AccessManager) plus chain IDs and RPC resolution.
 *
 * `ROYCO_FACTORY` is deployed via CREATE2 and is the same address on every chain. Per the
 * security model, this is the single control plane for all role authorization across Dawn,
 * vaults, strategies, and Makina/Caliber.
 */
abstract contract Factory is CommonBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // CHAIN IDs
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant MAINNET = 1;
    uint256 internal constant AVALANCHE = 43_114;
    uint256 internal constant ARBITRUM = 42_161;
    uint256 internal constant BASE = 8453;

    // ═══════════════════════════════════════════════════════════════════════════
    // FACTORY ADDRESS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Deployed via CREATE2 — same address on every chain
    address internal constant ROYCO_FACTORY = 0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C;

    // ═══════════════════════════════════════════════════════════════════════════
    // RPC URL RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════

    error UnknownChain(uint256 chainId);

    function _getRpcUrl(uint256 _chainId) internal view returns (string memory) {
        if (_chainId == MAINNET) return vm.envString("MAINNET_RPC_URL");
        if (_chainId == AVALANCHE) return vm.envString("AVALANCHE_RPC_URL");
        if (_chainId == ARBITRUM) return vm.envString("ARBITRUM_RPC_URL");
        if (_chainId == BASE) return vm.envString("BASE_RPC_URL");
        revert UnknownChain(_chainId);
    }

    function _chainName(uint256 _chainId) internal pure returns (string memory) {
        if (_chainId == MAINNET) return "Ethereum";
        if (_chainId == AVALANCHE) return "Avalanche";
        if (_chainId == ARBITRUM) return "Arbitrum";
        if (_chainId == BASE) return "Base";
        return "Unknown";
    }
}
