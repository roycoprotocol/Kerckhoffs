// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CommonBase } from "forge-std/Base.sol";

/**
 * @title Factory
 * @notice The Royco factory address (the per-chain AccessManager) plus chain IDs and RPC
 *         resolution.
 *
 * `ROYCO_FACTORY` is deployed via CREATE2 and is the same address on Mainnet / Avalanche /
 * Arbitrum. Base has its own factory at a different address (`ROYCO_FACTORY_BASE`) — always
 * resolve via `roycoFactory(chainId)` in chain-generic code. Per the security model, the
 * factory is the single control plane for all role authorization across Dawn, vaults,
 * strategies, and Makina/Caliber on its chain.
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

    /// @dev Deployed via CREATE2 — same address on Mainnet / Avalanche / Arbitrum
    address internal constant ROYCO_FACTORY = 0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C;

    /// @dev Base factory — deployed separately, NOT the CREATE2 address. Mirrors
    ///      `lib/royco-dawn/script/config/SyncerDeploymentConfig.sol :: ROYCO_FACTORY_BASE`.
    address internal constant ROYCO_FACTORY_BASE = 0x568c9709DaA2f7B7cc66AbC3E41DA0f0A339551A;

    /// @notice Resolves the RoycoFactory (AccessManager) address for the given chain.
    function roycoFactory(uint256 _chainId) public pure returns (address) {
        if (_chainId == BASE) return ROYCO_FACTORY_BASE;
        return ROYCO_FACTORY;
    }

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
