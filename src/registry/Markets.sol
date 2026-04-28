// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/// @dev Minimal kernel interface for deriving market sub-addresses at runtime.
interface IRoycoKernelLike {
    function ACCOUNTANT() external view returns (address);
    function SENIOR_TRANCHE() external view returns (address);
    function JUNIOR_TRANCHE() external view returns (address);
}

/**
 * @title Markets
 * @notice Registry of Royco Dawn markets: per `(chainId, marketName)` kernel address, plus the
 *         per-chain syncer. All other market sub-addresses (accountant, senior/junior tranche)
 *         are derived from the kernel at runtime to avoid stale duplication.
 *
 * Mirrors `lib/royco-dawn/script/update/base/UpdateConfig.sol:107-120`. Update by adding entries
 * to `_initMarkets()` / `_initSyncers()` rather than introducing per-chain files.
 */
abstract contract Markets is Factory {
    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET NAME CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    string internal constant STCUSD = "stcUSD";
    string internal constant SNUSD = "sNUSD";
    string internal constant SAVUSD = "savUSD";
    string internal constant AUTOUSD = "autoUSD";
    string internal constant ACRED = "ACRED";
    string internal constant SUSDAI = "sUSDai";
    string internal constant SMOKEHOUSE_USDC = "SmokehouseUSDC";
    string internal constant SYRUP_USDC = "syrupUSDC";
    string internal constant APYUSD = "ApyUSD";
    string internal constant PARETO_FALCONX = "ParetoFalconX";

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    struct MarketAddresses {
        address kernel;
        address accountant;
        address seniorTranche;
        address juniorTranche;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev chainId → marketName → kernel address
    mapping(uint256 => mapping(string => address)) internal _kernels;

    /// @dev chainId → marketName[] (for enumeration)
    mapping(uint256 => string[]) internal _marketsByChain;

    /// @dev chainId → syncer address
    mapping(uint256 => address) internal _syncers;

    error MarketNotFound(uint256 chainId, string marketName);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() {
        _initMarkets();
        _initSyncers();
    }

    function _initMarkets() internal {
        // ── Mainnet ─────────────────────────────────────────────────────────
        _addMarket(MAINNET, SNUSD, 0x0aE0978B868804929fd4C06B3B22D9197B8cd3c6);
        _addMarket(MAINNET, AUTOUSD, 0x8748D1c21CC550B435487F473d9Aaf6C84dA46A6);
        _addMarket(MAINNET, SMOKEHOUSE_USDC, 0x6dBdf6EBdF02F50ec6a7d6F782850996928176F9);
        _addMarket(MAINNET, SYRUP_USDC, 0xde1Ce2cF64808e50d000F93058784270E412B3A4);
        _addMarket(MAINNET, STCUSD, 0x9911F227E9428964D8A35B852513919C8DF92038);
        _addMarket(MAINNET, PARETO_FALCONX, 0x15bb63C07740ff972F76716cAcC5766f0C641791);
        _addMarket(MAINNET, APYUSD, 0xcFbdEA0990F21b103c8D123d0D5273B4ea269cb4);

        // ── Avalanche ────────────────────────────────────────────────────────
        _addMarket(AVALANCHE, SAVUSD, 0x7240FF91b471217FF93349184ABE9f102Ca1955C);

        // ── Arbitrum ─────────────────────────────────────────────────────────
        _addMarket(ARBITRUM, SUSDAI, 0xFdb17E53eA5d342124b8473188BCB9F05F1949CA);
    }

    /// @dev Per-chain syncer addresses, mirrored from
    function _initSyncers() internal {
        _syncers[MAINNET] = 0xc46367BBdbC62F1825a46549062a3A88D8668D52;
        _syncers[AVALANCHE] = 0x2E9fCb5Ea139d2fDb5CcDc5BdF16357Da68d872C;
        _syncers[ARBITRUM] = 0x8DCC7107e3AD82B60144bE68bE9C4809c84b9E06;
    }

    function _addMarket(uint256 _chainId, string memory _name, address _kernel) internal {
        _kernels[_chainId][_name] = _kernel;
        _marketsByChain[_chainId].push(_name);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns the list of market names deployed on the given chain.
    function marketNames(uint256 _chainId) public view returns (string[] memory) {
        return _marketsByChain[_chainId];
    }

    /// @notice Returns the syncer address for the given chain (zero if none).
    function syncer(uint256 _chainId) public view returns (address) {
        return _syncers[_chainId];
    }

    /// @notice Resolves all market sub-addresses (accountant, ST, JT) from the kernel.
    /// @dev Must be called on a fork that includes the deployed kernel (i.e., after `vm.createSelectFork`).
    function getMarketAddresses(uint256 _chainId, string memory _marketName) public view returns (MarketAddresses memory addrs) {
        addrs.kernel = _kernels[_chainId][_marketName];
        require(addrs.kernel != address(0), MarketNotFound(_chainId, _marketName));

        IRoycoKernelLike kernel = IRoycoKernelLike(addrs.kernel);
        addrs.accountant = kernel.ACCOUNTANT();
        addrs.seniorTranche = kernel.SENIOR_TRANCHE();
        addrs.juniorTranche = kernel.JUNIOR_TRANCHE();
    }
}
