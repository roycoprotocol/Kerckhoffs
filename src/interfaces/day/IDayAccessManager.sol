// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

/**
 * @title IDayAccessManager
 * @notice Thin ABI mirror of royco-day's `RoycoAccessManager` — the Royco Day AccessManager.
 *
 * Mirrors `royco-day/src/interfaces/factory/IRoycoAccessManager.sol`. The Day AM is a stock OZ
 * AccessManager plus a monotonic `wasEverConfigured[target]` flag; `TargetConfiguredAtGenesis`
 * fires on the first target-scoped write (`setTargetFunctionRole` / `setTargetAdminDelay` /
 * `setTargetClosed`) for a target. Kept in this repo (rather than importing royco-day) so
 * `extract-abis.mjs` can produce the subgraph ABI from our own `forge build` output; inheriting
 * `IAccessManager` puts the full OZ event set in the compiled ABI alongside the genesis event.
 */
interface IDayAccessManager is IAccessManager {
    event TargetConfiguredAtGenesis(address indexed target);

    function wasEverConfigured(address _target) external view returns (bool);
}
