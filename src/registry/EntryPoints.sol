// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Factory } from "./Factory.sol";

/**
 * @title EntryPoints
 * @notice Royco entry-point proxy address per chain. Same CREATE3 address on every chain
 *         per `lib/royco-dawn/script/independent/DeployEntryPoint.s.sol` (salt
 *         `keccak256("ROYCO_ENTRY_POINT_PRODUCTION")`).
 */
abstract contract EntryPoints is Factory {
    /// @dev Per `contracts.txt` and the dawn deploy script — same address on every chain.
    address internal constant ENTRY_POINT = 0x63dA1229be88Fb4D20210147954a1a3e05f2581B;

    /// @dev chainId → entry point address (zero if entry point not deployed on that chain).
    mapping(uint256 => address) internal _entryPoints;

    constructor() {
        _entryPoints[MAINNET] = ENTRY_POINT;
        _entryPoints[AVALANCHE] = ENTRY_POINT;
        _entryPoints[ARBITRUM] = ENTRY_POINT;
    }

    function entryPoint(uint256 _chainId) public view returns (address) {
        return _entryPoints[_chainId];
    }
}
