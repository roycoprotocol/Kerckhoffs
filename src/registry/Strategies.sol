// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title Strategies
 * @notice Makina/Caliber stack per vault: the strategy contract (which sits under the concrete
 *         vault), the Makina machine, the Caliber, and the share token.
 *
 * Caliber is the contract whose setters move under AccessManager per `authorization/README.md` §2.
 * The on-chain `_allowedInstrRoot` timelock on Caliber stays untouched.
 */
abstract contract Strategies is Factory {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    struct StrategyStack {
        address strategy;
        address machine;
        address caliber;
        address shareToken;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev chainId → vaultName → stack
    mapping(uint256 => mapping(string => StrategyStack)) internal _stacks;

    error StrategyNotFound(uint256 chainId, string vaultName);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() {
        _initStrategies();
    }

    function _initStrategies() internal {
        // ── Mainnet — srRoyUSDC ─────────────────────────────────────────────
        _stacks[MAINNET]["srRoyUSDC"] = StrategyStack({
            strategy: 0xc5FeF644d59415cec65049e0653CA10eD9Cba778,
            machine: 0xFa097420f0e2C72456B361a1eD85172B9ccd8c38,
            caliber: 0x5476F4E23dAA093Ce6700e1026013c55F7AF9083,
            shareToken: 0x1004D230aCA4b781d0049AFD6D0b1ee8ed3A6787
        });

        // ── Mainnet — roywstETH ─────────────────────────────────────────────
        _stacks[MAINNET]["roywstETH"] = StrategyStack({
            strategy: 0x185313DBb1f3AA2b3fCc603f0EE4cbA753Ef1DD7,
            machine: 0x0FDF9F1920e160ea8Ae267BdE13e725DeF81E5Ee,
            caliber: 0x3d8E2497497a3e29Ad5391c08dB2a1b3C32598c0,
            shareToken: 0xa102533523b23a448969808Dd2D32f0AAea4257a
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    function getStrategyStack(uint256 _chainId, string memory _vaultName) public view returns (StrategyStack memory stack) {
        stack = _stacks[_chainId][_vaultName];
        require(stack.strategy != address(0), StrategyNotFound(_chainId, _vaultName));
    }
}
