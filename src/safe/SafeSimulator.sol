// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { console2 } from "forge-std/console2.sol";

import { SafeBatchUtils } from "./SafeBatchUtils.sol";

/**
 * @title SafeSimulator
 * @notice Replays a Safe transaction batch on a fork by pranking the Safe and executing each
 *         transaction in order. Reverts with a decoded revert reason on the first failure.
 *
 * Mirrors the simulation pattern in
 * `lib/royco-dawn/script/update/access/ApplySecurityMigration.s.sol:_simulateBatch:237-242` and
 * `_decodeRevert:314-319`. Used by every migration script.
 */
abstract contract SafeSimulator is SafeBatchUtils {
    error SafeReplayFailed(uint256 txIndex, bytes returnData);

    /**
     * @notice Pranks `_safe` and executes each tx in order; reverts on the first failure.
     * @dev Each tx is executed via the prank cheatcode (one prank per tx, since prank is consumed).
     */
    function _replayBatch(address _safe, SafeTransaction[] memory _txs) internal {
        for (uint256 i = 0; i < _txs.length; i++) {
            vm.prank(_safe);
            (bool ok, bytes memory ret) = _txs[i].to.call{ value: _txs[i].value }(_txs[i].data);
            if (!ok) {
                console2.log("  [FAIL] tx index:", i);
                if (ret.length >= 4) {
                    console2.logBytes4(bytes4(ret));
                }
                revert SafeReplayFailed(i, ret);
            }
        }
        console2.log("  [OK] All", _txs.length, "txs replayed");
    }

    /**
     * @notice Variant that warps forward by `_warpSeconds` between each tx. Useful for migrations
     *         that schedule + later execute via the AccessManager. Most use-cases want the plain
     *         `_replayBatch` instead.
     */
    function _replayBatchWithWarp(address _safe, SafeTransaction[] memory _txs, uint256 _warpSeconds) internal {
        for (uint256 i = 0; i < _txs.length; i++) {
            vm.prank(_safe);
            (bool ok, bytes memory ret) = _txs[i].to.call{ value: _txs[i].value }(_txs[i].data);
            if (!ok) revert SafeReplayFailed(i, ret);
            vm.warp(vm.getBlockTimestamp() + _warpSeconds);
        }
    }

    function _bytes4ToHex(bytes4 _b) internal pure returns (string memory) {
        bytes memory hexAlphabet = "0123456789abcdef";
        bytes memory out = new bytes(8);
        for (uint256 i = 0; i < 4; i++) {
            uint8 b = uint8(_b[i]);
            out[2 * i] = hexAlphabet[b >> 4];
            out[2 * i + 1] = hexAlphabet[b & 0x0f];
        }
        return string(out);
    }
}
