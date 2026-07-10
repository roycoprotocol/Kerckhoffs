// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { MigrateDawn } from "../script/migrate/Dawn.s.sol";
import { Selectors } from "../src/access/Selectors.sol";

/**
 * @title AuditableOutputTest
 * @notice Verifies the human-auditable Safe JSON: every tx round-trips (decoded args re-encode
 *         to the exact calldata), the emitted file is valid JSON carrying decoded
 *         `contractMethod` + `contractInputsValues` alongside the raw `data`, and labels resolve
 *         to human names. Uses the Dawn batch (widest method coverage) on mainnet + Base, plus a
 *         synthetic native-vault grant.
 */
contract AuditableOutputTest is Test, MigrateDawn {
    function setUp() public {
        vm.createSelectFork(_getRpcUrl(MAINNET));
    }

    function test_RoundTrip_AllTxs_Mainnet() public view {
        SafeTransaction[] memory txs = _buildBatch(MAINNET);
        require(txs.length > 0, "empty batch");
        for (uint256 i = 0; i < txs.length; i++) {
            _assertRoundTrip(txs[i], MAINNET, i); // reverts on any mismatch
        }
    }

    function test_Write_ProducesValidDecodedJson() public {
        SafeTransaction[] memory txs = _buildBatch(MAINNET);
        string memory path = "output/test/auditable_dawn_1.json";
        writeAuditableSafeTransactionJson(txs, MAINNET, path, "unit-test batch", "base description");

        string memory content = vm.readFile(path);
        vm.parseJson(content); // reverts if the emitted JSON is malformed

        // Raw calldata is preserved (existing consumers unaffected)...
        string memory data0 = vm.parseJsonString(content, ".transactions[0].data");
        require(keccak256(bytes(data0)) == keccak256(bytes(vm.toString(txs[0].data))), "data0 not preserved");

        // ...and decoded fields are present and correct.
        string memory method0 = vm.parseJsonString(content, ".transactions[0].contractMethod.name");
        require(bytes(method0).length > 0, "contractMethod.name empty");
        require(keccak256(bytes(method0)) == keccak256(bytes(_describe(txs[0], MAINNET).method)), "method name mismatch");

        // meta carries the human summary.
        string memory desc = vm.parseJsonString(content, ".meta.description");
        require(bytes(desc).length > 0, "meta.description empty");
    }

    function test_ContractInputsValues_ReencodeToData() public {
        SafeTransaction[] memory txs = _buildBatch(MAINNET);
        string memory path = "output/test/auditable_dawn_1b.json";
        writeAuditableSafeTransactionJson(txs, MAINNET, path, "unit-test batch", "base");
        string memory content = vm.readFile(path);

        // For every tx, each embedded contractInputsValues equals the canonical value decoded
        // from `data` (the same cross-check DecodeBatch runs).
        for (uint256 i = 0; i < txs.length; i++) {
            DecodedTx memory d = _describe(txs[i], MAINNET);
            string memory p = string.concat(".transactions[", vm.toString(i), "]");
            for (uint256 a = 0; a < d.names.length; a++) {
                string memory fromFile = vm.parseJsonString(content, string.concat(p, ".contractInputsValues.", d.names[a]));
                require(keccak256(bytes(fromFile)) == keccak256(bytes(d.canonical[a])), "inputsValues mismatch vs decode");
            }
        }
    }

    function test_Describe_Labels_AdminRoleGrant() public view {
        // The Dawn batch's last step grants ADMIN_ROLE to FNDN at 72h. Find and label-check it.
        SafeTransaction[] memory txs = _buildBatch(MAINNET);
        bool found;
        for (uint256 i = 0; i < txs.length; i++) {
            DecodedTx memory d = _describe(txs[i], MAINNET);
            if (keccak256(bytes(d.method)) == keccak256(bytes("grantRole")) && keccak256(bytes(d.canonical[0])) == keccak256(bytes("0"))) {
                // roleId 0 == ADMIN_ROLE
                require(keccak256(bytes(d.labeled[0])) == keccak256(bytes("ADMIN_ROLE (0)")), "role label");
                require(keccak256(bytes(d.labeled[1])) == keccak256(bytes("FNDN")), "account label");
                require(keccak256(bytes(d.labeled[2])) == keccak256(bytes("72h")), "delay label");
                require(keccak256(bytes(d.effect)) == keccak256(bytes("Grant ADMIN_ROLE (0) to FNDN at execution delay 72h")), "effect");
                found = true;
            }
        }
        require(found, "ADMIN_ROLE grant not found in batch");
    }

    function test_Describe_NativeVaultGrant() public view {
        // Synthetic native AccessControl grant: grantRole(VAULT_MANAGER, RoycoFactory) on the vault.
        address vault = getVaultAddresses(MAINNET, "srRoyUSDC").vault;
        bytes memory data = abi.encodeWithSignature("grantRole(bytes32,address)", Selectors.nativeVaultManager(), ROYCO_FACTORY);
        SafeTransaction memory t = SafeTransaction({ to: vault, value: 0, data: data });

        DecodedTx memory d = _describe(t, MAINNET);
        require(keccak256(bytes(d.method)) == keccak256(bytes("grantRole")), "native method");
        require(keccak256(bytes(d.types[0])) == keccak256(bytes("bytes32")), "native role type is bytes32");
        require(keccak256(bytes(d.labeled[0])) == keccak256(bytes("VAULT_MANAGER")), "native role label");
        require(keccak256(bytes(d.labeled[1])) == keccak256(bytes("RoycoFactory(AM)")), "native account label");
        _assertRoundTrip(t, MAINNET, 0);
    }

    function test_Base_Write_RoundTrips() public {
        vm.createSelectFork(_getRpcUrl(BASE));
        SafeTransaction[] memory txs = _buildBatch(BASE);
        require(txs.length > 0, "empty Base batch");
        // The writer asserts round-trip internally for every tx.
        writeAuditableSafeTransactionJson(txs, BASE, "output/test/auditable_dawn_base.json", "base batch", "base");
        string memory content = vm.readFile("output/test/auditable_dawn_base.json");
        vm.parseJson(content);
    }
}
