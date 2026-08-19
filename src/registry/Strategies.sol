// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Strategies
 * @notice Makina/Caliber stack per vault + chain. The Caliber is the contract whose setters move
 *         under AccessManager per `authorization/README.md` §2 (its `_allowedInstrRoot` timelock
 *         stays untouched).
 *
 * Makina is hub-and-spoke. On the **hub** (mainnet) the Caliber's `_hubMachineEndpoint` is the
 * Machine; on a **spoke** (Arbitrum / Base) the same-address Caliber points at a local
 * `CaliberMailbox` instead, and there is no Machine, strategy adapter or share token (those live
 * on the hub with the concrete vault). `onlyRiskManager[Timelock]` on the Caliber resolves through
 * `endpoint.riskManager()/riskManagerTimelock()`, so `endpoint` is the contract whose
 * MakinaGovernable slots the migration re-points and whose own risk-manager setters get bound.
 */
abstract contract Strategies is Factory {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    struct StrategyStack {
        address strategy; // concrete-vault strategy adapter (hub only; 0 on spokes)
        address endpoint; // Caliber's `_hubMachineEndpoint`: Machine on hub, CaliberMailbox on spoke
        address caliber;
        address shareToken; // hub only; 0 on spokes
        bool spoke; // true on spoke chains (endpoint is a CaliberMailbox, no local Machine)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev chainId → vaultName → stack
    mapping(uint256 => mapping(string => StrategyStack)) internal _stacks;

    /// @dev chainId → vaultName[] with a Caliber on that chain (for enumeration)
    mapping(uint256 => string[]) internal _strategyVaultsByChain;

    error StrategyNotFound(uint256 chainId, string vaultName);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() {
        _initStrategies();
    }

    function _initStrategies() internal {
        // ── Mainnet (hub) — endpoint = Machine ──────────────────────────────
        _addStrategy(
            MAINNET,
            "srRoyUSDC",
            StrategyStack({
                strategy: 0xc5FeF644d59415cec65049e0653CA10eD9Cba778,
                endpoint: 0xFa097420f0e2C72456B361a1eD85172B9ccd8c38, // Machine
                caliber: 0x5476F4E23dAA093Ce6700e1026013c55F7AF9083,
                shareToken: 0x1004D230aCA4b781d0049AFD6D0b1ee8ed3A6787,
                spoke: false
            })
        );
        _addStrategy(
            MAINNET,
            "roywstETH",
            StrategyStack({
                strategy: 0x185313DBb1f3AA2b3fCc603f0EE4cbA753Ef1DD7,
                endpoint: 0x0FDF9F1920e160ea8Ae267BdE13e725DeF81E5Ee, // Machine
                caliber: 0x3d8E2497497a3e29Ad5391c08dB2a1b3C32598c0,
                shareToken: 0xa102533523b23a448969808Dd2D32f0AAea4257a,
                spoke: false
            })
        );

        // ── Spokes — srRoyUSDC Caliber (same address), endpoint = CaliberMailbox ─
        // roywstETH has no spoke Caliber. `strategy`/`shareToken` live on the hub only.
        StrategyStack memory spokeSrRoyUSDC = StrategyStack({
            strategy: address(0),
            endpoint: 0x81Efb959957B0735A1B25dCF929d4b89579495c6, // CaliberMailbox (same on both spokes)
            caliber: 0x5476F4E23dAA093Ce6700e1026013c55F7AF9083,
            shareToken: address(0),
            spoke: true
        });
        _addStrategy(ARBITRUM, "srRoyUSDC", spokeSrRoyUSDC);
        _addStrategy(BASE, "srRoyUSDC", spokeSrRoyUSDC);
    }

    function _addStrategy(uint256 _chainId, string memory _name, StrategyStack memory _stack) internal {
        _stacks[_chainId][_name] = _stack;
        _strategyVaultsByChain[_chainId].push(_name);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Vault names that have a Caliber (hub or spoke) on the given chain.
    function strategyVaultNames(uint256 _chainId) public view returns (string[] memory) {
        return _strategyVaultsByChain[_chainId];
    }

    function getStrategyStack(uint256 _chainId, string memory _vaultName) public view returns (StrategyStack memory stack) {
        stack = _stacks[_chainId][_vaultName];
        require(stack.caliber != address(0), StrategyNotFound(_chainId, _vaultName));
    }
}
