// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { AccessManagerDumper } from "../src/access/AccessManagerDumper.sol";

/**
 * @title Dump
 * @notice Reads + tabulates the full RoycoFactory AccessManager state on each chain.
 *
 * Usage:
 *   forge script script/Dump.s.sol --sig "run()"
 *   forge script script/Dump.s.sol --sig "dump(uint256)" -- 1
 *
 * `dump(uint256)` is exposed as `public` so other scripts (e.g. migrations) can import this
 * contract and call it for pre/post-state visualization.
 */
contract Dump is AccessManagerDumper, Script {
    function run() external {
        dumpAccessManager(MAINNET);
        dumpAccessManager(AVALANCHE);
        dumpAccessManager(ARBITRUM);
        dumpAccessManager(BASE);
    }

    function dump(uint256 _chainId) public {
        dumpAccessManager(_chainId);
    }
}
