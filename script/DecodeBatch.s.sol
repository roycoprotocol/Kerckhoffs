// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { SafeBatchDecoder } from "../src/safe/SafeBatchDecoder.sol";

/**
 * @title DecodeBatch
 * @notice Standalone verifier for an emitted Safe Transaction Builder JSON. Reads a batch file,
 *         forks the chain it targets, and for every transaction: prints the decoded + labeled
 *         call, asserts the calldata round-trips (decoding then re-encoding reproduces the exact
 *         bytes), and cross-checks the file's own `contractInputsValues` against the values
 *         decoded from `data` (so a hand-edited or mismatched file fails loudly).
 *
 * Usage:
 *   forge script script/DecodeBatch.s.sol --sig "run(string)" -- output/migrate/dawn/1_apply_security_migration.json
 *
 * Works on any batch this repo produces (Dawn / Vaults / Makina), including already-generated
 * files. Read-only: no broadcast, no state change.
 */
contract DecodeBatch is SafeBatchDecoder, Script {
    error InputsValueMismatch(uint256 index, string argName, string fromData, string fromFile);

    function run(string memory _path) external {
        string memory content = vm.readFile(_path);
        uint256 chainId = vm.parseUint(vm.parseJsonString(content, ".chainId"));

        vm.createSelectFork(_getRpcUrl(chainId));

        console2.log("================================================================================");
        console2.log("Decoding batch:", _path);
        console2.log("  chain:", _chainName(chainId), chainId);
        console2.log("  meta.name:", vm.parseJsonString(content, ".meta.name"));
        console2.log("================================================================================");

        uint256 i;
        while (vm.keyExistsJson(content, string.concat(".transactions[", vm.toString(i), "].to"))) {
            string memory p = string.concat(".transactions[", vm.toString(i), "]");
            SafeTransaction memory t = SafeTransaction({
                to: vm.parseJsonAddress(content, string.concat(p, ".to")),
                value: vm.parseUint(vm.parseJsonString(content, string.concat(p, ".value"))),
                data: vm.parseJsonBytes(content, string.concat(p, ".data"))
            });

            // 1. Structural round-trip: decode(data) re-encodes to the exact original bytes.
            _assertRoundTrip(t, chainId, i);

            // 2. Decode + print the human view.
            DecodedTx memory d = _describe(t, chainId);
            console2.log("");
            console2.log(string.concat("  [", vm.toString(i), "] ", d.method, "  ->  ", d.effect));
            console2.log(string.concat("      to: ", _actorName(t.to, chainId), " (", vm.toString(t.to), ")"));
            for (uint256 a = 0; a < d.names.length; a++) {
                console2.log(string.concat("      ", d.names[a], " = ", d.labeled[a]));
            }

            // 3. Cross-check the file's embedded contractInputsValues against the decode.
            for (uint256 a = 0; a < d.names.length; a++) {
                string memory key = string.concat(p, ".contractInputsValues.", d.names[a]);
                if (vm.keyExistsJson(content, key)) {
                    string memory fromFile = vm.parseJsonString(content, key);
                    if (keccak256(bytes(fromFile)) != keccak256(bytes(d.canonical[a]))) {
                        revert InputsValueMismatch(i, d.names[a], d.canonical[a], fromFile);
                    }
                }
            }

            i++;
        }

        console2.log("");
        console2.log("  [OK] Decoded and verified", i, "transactions (round-trip + inputs cross-check).");
    }
}
