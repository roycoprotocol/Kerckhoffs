// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { CommonBase } from "forge-std/Base.sol";

/**
 * @title SafeBatchUtils
 * @notice Builders for AccessManager-related Safe transactions and Safe Transaction Builder JSON output.
 *
 * Ported from `lib/royco-dawn/script/utils/AccessManagerConfigUtils.sol:24-222` and extended with
 * additional builders (`buildSetRoleAdmin`, `buildSetRoleGuardian`, `buildSetRoleGrantDelay`,
 * `buildSetTargetAdminDelay`) and a `mergeBatches` helper for combining multiple phase JSONs into
 * one merged batch.
 *
 * The emitted JSON matches Safe Transaction Builder schema v1.0 — operators import it directly
 * into the Safe UI.
 */
abstract contract SafeBatchUtils is CommonBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice A transaction to execute via Safe.
    struct SafeTransaction {
        address to;
        uint256 value;
        bytes data;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESSMANAGER TRANSACTION BUILDERS
    // ═══════════════════════════════════════════════════════════════════════════

    function buildSetTargetFunctionRole(
        address _accessManager,
        address _target,
        bytes4[] memory _selectors,
        uint64 _role
    )
        internal
        pure
        returns (SafeTransaction memory)
    {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setTargetFunctionRole, (_target, _selectors, _role)) });
    }

    function buildGrantRole(address _accessManager, uint64 _role, address _account, uint32 _executionDelay) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.grantRole, (_role, _account, _executionDelay)) });
    }

    function buildRevokeRole(address _accessManager, uint64 _role, address _account) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.revokeRole, (_role, _account)) });
    }

    function buildSetTargetClosed(address _accessManager, address _target, bool _closed) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setTargetClosed, (_target, _closed)) });
    }

    function buildLabelRole(address _accessManager, uint64 _role, string memory _label) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.labelRole, (_role, _label)) });
    }

    function buildSetRoleAdmin(address _accessManager, uint64 _role, uint64 _adminRole) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setRoleAdmin, (_role, _adminRole)) });
    }

    function buildSetRoleGuardian(address _accessManager, uint64 _role, uint64 _guardianRole) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setRoleGuardian, (_role, _guardianRole)) });
    }

    function buildSetRoleGrantDelay(address _accessManager, uint64 _role, uint32 _delay) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setGrantDelay, (_role, _delay)) });
    }

    function buildSetTargetAdminDelay(address _accessManager, address _target, uint32 _delay) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({ to: _accessManager, value: 0, data: abi.encodeCall(IAccessManager.setTargetAdminDelay, (_target, _delay)) });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ARRAY UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    function singleTransaction(SafeTransaction memory _tx) internal pure returns (SafeTransaction[] memory result) {
        result = new SafeTransaction[](1);
        result[0] = _tx;
    }

    function concatTransactions(SafeTransaction[] memory _a, SafeTransaction[] memory _b) internal pure returns (SafeTransaction[] memory result) {
        result = new SafeTransaction[](_a.length + _b.length);
        for (uint256 i = 0; i < _a.length; i++) {
            result[i] = _a[i];
        }
        for (uint256 i = 0; i < _b.length; i++) {
            result[_a.length + i] = _b[i];
        }
    }

    /// @notice Concatenates N batches in order into one merged batch.
    function mergeBatches(SafeTransaction[][] memory _batches) internal pure returns (SafeTransaction[] memory result) {
        uint256 total;
        for (uint256 i = 0; i < _batches.length; i++) {
            total += _batches[i].length;
        }
        result = new SafeTransaction[](total);
        uint256 idx;
        for (uint256 i = 0; i < _batches.length; i++) {
            SafeTransaction[] memory b = _batches[i];
            for (uint256 j = 0; j < b.length; j++) {
                result[idx++] = b[j];
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // JSON OUTPUT (Safe Transaction Builder schema v1.0)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Writes the batch to the given path as Safe Transaction Builder JSON v1.0.
    /// @dev `_outputPath` is a full path relative to the project root, e.g. `"output/migrate/dawn/1.json"`.
    function writeSafeTransactionJson(
        SafeTransaction[] memory _transactions,
        string memory _outputPath,
        string memory _name,
        string memory _description
    )
        internal
    {
        string[] memory txJsons = new string[](_transactions.length);
        for (uint256 i = 0; i < _transactions.length; i++) {
            string memory key = string.concat("tx", vm.toString(i));
            vm.serializeAddress(key, "to", _transactions[i].to);
            vm.serializeString(key, "value", vm.toString(_transactions[i].value));
            txJsons[i] = vm.serializeBytes(key, "data", _transactions[i].data);
        }

        string memory root = string.concat("root_", _outputPath);
        vm.serializeString(root, "version", "1.0");
        vm.serializeString(root, "chainId", vm.toString(block.chainid));
        vm.serializeUint(root, "createdAt", vm.getBlockTimestamp());

        string memory meta = string.concat("meta_", _outputPath);
        vm.serializeString(meta, "name", _name);
        string memory metaJson = vm.serializeString(meta, "description", _description);
        vm.serializeString(root, "meta", metaJson);

        string memory finalJson = vm.serializeString(root, "transactions", txJsons);

        // Ensure the parent directory exists.
        string memory parent = _parentDir(_outputPath);
        if (bytes(parent).length > 0) {
            vm.createDir(parent, true);
        }
        vm.writeJson(finalJson, _outputPath);
    }

    /// @dev Returns everything in `_path` up to (but excluding) the last `/`. Returns "" if no `/` found.
    function _parentDir(string memory _path) private pure returns (string memory) {
        bytes memory b = bytes(_path);
        for (uint256 i = b.length; i > 0; i--) {
            if (
                b[i - 1] == 0x2f /* '/' */
            ) {
                bytes memory out = new bytes(i - 1);
                for (uint256 j = 0; j < i - 1; j++) {
                    out[j] = b[j];
                }
                return string(out);
            }
        }
        return "";
    }
}
