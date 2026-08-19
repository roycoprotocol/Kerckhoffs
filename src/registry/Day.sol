// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title Day
 * @notice The Royco Day control-plane addresses — the second AccessManager alongside the Dawn
 *         RoycoFactory (`Factory.sol`).
 *
 * All addresses are CREATE2/CREATE3-deterministic and identical on Mainnet / Avalanche /
 * Arbitrum / Base. These are the FINAL production addresses per
 * https://docs.royco.org/key-addresses (verified on-chain 2026-08-17; bootstrap blocks:
 * mainnet 25759227, avalanche 93024169, arbitrum ~494738482, base ~Aug 2026). An earlier pre-production deployment
 * (AM 0x87aED465…, factory 0xaaAaaaaa01…) exists on the same chains and is intentionally NOT
 * tracked; its rows may linger in grafted subgraph stores.
 *
 * The Day AM (`RoycoAccessManager`) will control every Day market plus — post-migration — the
 * srRoyUSDC / roywstETH Concrete vaults and their Makina stacks, which move over from the Dawn
 * AM. `DAY_GATEKEEPER` (RoycoFactoryGatekeeper) holds `ADMIN_ROLE` on the Day AM and enforces
 * fresh-target-only configuration; markets are deployed permissionlessly through `DAY_FACTORY`.
 */
abstract contract Day {
    // ═══════════════════════════════════════════════════════════════════════════
    // DAY CONTROL PLANE (all four chains)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev royco-day `RoycoAccessManager` — the Day AccessManager.
    address internal constant DAY_ACCESS_MANAGER = 0x82EecE4a736db0767370d2DfFdE9BDF6e38AaeB8;

    /// @dev royco-day `RoycoFactory` (CREATE3 proxy). Emits `MarketDeploymentCompleted`.
    address internal constant DAY_FACTORY = 0xaAAaaAAAaE46cA12Bf3810DF8C13c5E8A4400812;

    /// @dev royco-day `RoycoFactoryGatekeeper` — holds `ADMIN_ROLE` on the Day AM.
    address internal constant DAY_GATEKEEPER = 0x716fFB13728Aec2F376883d00689679A418537f6;

    /// @dev royco-day `RoycoDayEntryPoint` (proxy). Holds ST/JT/LPT LP roles.
    address internal constant DAY_ENTRY_POINT = 0xaF55a0c251690d9322b5F94b7e50EE895750262c;

    /// @dev royco-day `RoycoMarketSyncer` (CREATE2 proxy).
    address internal constant DAY_MARKET_SYNCER = 0x387e025306cb1C41fe7AB752D9C04607E03Bb8CE;

    /// @notice Whether Royco Day (and thus the Day AccessManager) exists on the given chain.
    ///         True everywhere since the 2026-08-17 Avalanche deployment.
    function hasDay(uint256) public pure returns (bool) {
        return true;
    }

    /// @notice Resolves the Day AccessManager for the given chain.
    function dayAccessManager(uint256) public pure returns (address) {
        return DAY_ACCESS_MANAGER;
    }
}
