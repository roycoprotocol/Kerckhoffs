// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Vaults
 * @notice Registry of concrete vaults under Royco. Currently `srRoyUSDC` and `roywstETH` on
 *         Ethereum only. Each vault entry holds the vault address and its whitelist hook.
 *
 * The Makina/Caliber stack that sits under each vault is registered separately in `Strategies.sol`,
 * keyed by the same vault name.
 */
abstract contract Vaults is Factory {
    // ═══════════════════════════════════════════════════════════════════════════
    // VAULT NAME CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    string internal constant SRROYUSDC = "srRoyUSDC";
    string internal constant ROYWSTETH = "roywstETH";

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    struct VaultAddresses {
        address vault;
        address whitelistHook;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev chainId → vaultName → addresses
    mapping(uint256 => mapping(string => VaultAddresses)) internal _vaults;

    /// @dev chainId → vaultName[] (for enumeration)
    mapping(uint256 => string[]) internal _vaultsByChain;

    error VaultNotFound(uint256 chainId, string vaultName);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() {
        _initVaults();
    }

    function _initVaults() internal {
        // ── Mainnet ─────────────────────────────────────────────────────────
        _addVault(MAINNET, SRROYUSDC, 0xcD9f5907F92818bC06c9Ad70217f089E190d2a32, 0x5c4952751CF5C9D4eA3ad84F3407C56Ba2342F13);
        _addVault(MAINNET, ROYWSTETH, 0x41Ce72E04D349Eb957bdc373baA9c69207032c56, 0xcD6ddfC0520A17dF7bC675fC9B31cb4d7E9e050C);
    }

    function _addVault(uint256 _chainId, string memory _name, address _vault, address _hook) internal {
        _vaults[_chainId][_name] = VaultAddresses({ vault: _vault, whitelistHook: _hook });
        _vaultsByChain[_chainId].push(_name);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    function vaultNames(uint256 _chainId) public view returns (string[] memory) {
        return _vaultsByChain[_chainId];
    }

    function getVaultAddresses(uint256 _chainId, string memory _vaultName) public view returns (VaultAddresses memory addrs) {
        addrs = _vaults[_chainId][_vaultName];
        require(addrs.vault != address(0), VaultNotFound(_chainId, _vaultName));
    }
}
