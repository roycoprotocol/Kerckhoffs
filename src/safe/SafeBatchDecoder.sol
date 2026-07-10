// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { console2 } from "forge-std/console2.sol";

import { IConcreteStandardVaultImpl } from "concrete-earn/src/interface/IConcreteStandardVaultImpl.sol";
import { IBridgeController } from "makina-core/src/interfaces/IBridgeController.sol";
import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IStrategyTemplate } from "makina-strategy/lib/concrete-earn-v2-bug-bounty/src/interface/IStrategyTemplate.sol";
import { IRoycoAuth } from "royco-dawn/src/interfaces/IRoycoAuth.sol";
import { IRoycoEntryPoint } from "royco-dawn/src/interfaces/IRoycoEntryPoint.sol";
import { IRoycoVaultTranche } from "royco-dawn/src/interfaces/IRoycoVaultTranche.sol";

import { AccessManagerDumper } from "../access/AccessManagerDumper.sol";
import { IMachineRiskManagerSetters, Selectors } from "../access/Selectors.sol";
import { SafeBatchUtils } from "./SafeBatchUtils.sol";

/// @dev Native AccessControl (concrete vault) — grant/revoke take a bytes32 role, distinct from
///      the AccessManager's uint64-role grant/revoke.
interface INativeAccessControl {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
}

/**
 * @title SafeBatchDecoder
 * @notice Single source of truth for turning an emitted `SafeTransaction` back into a
 *         human-readable, self-describing form. Every migration batch is a closed vocabulary of
 *         AccessManager methods (grantRole / revokeRole / setTargetFunctionRole / setRoleGuardian
 *         / labelRole / setRoleAdmin / setGrantDelay / setTargetAdminDelay / setTargetClosed) plus
 *         native vault grant/revoke, so exact decoding + labeling is deterministic.
 *
 * The same decoder feeds (a) the Safe Transaction Builder JSON — `contractMethod` +
 * `contractInputsValues`, so the Safe UI decodes each call at signing time — and (b) the
 * human `meta` narration. Because the Safe UI validates `contractInputsValues` by re-encoding
 * them back to `data`, per-transaction values stay canonical (role as decimal, address as hex);
 * the human labels (role/actor names, "72h", effect sentences) live in `meta`.
 *
 * Validation is layered — no single check covers everything:
 *   - `_assertRoundTrip` (write time) proves the calldata itself is a canonical ABI encoding of
 *     the matched selector's tuple with no trailing bytes. It re-encodes from the values decoded
 *     out of `data`, so it catches corrupt/non-canonical calldata and branch/selector mismatches
 *     — but it does NOT, by construction, prove the human labels or the `contractInputsValues`
 *     strings are correct (those are rendered separately in `_describe`).
 *   - `DecodeBatch.s.sol` (verify time) re-reads an emitted file and cross-checks each
 *     `contractInputsValues` against a fresh decode of `data`, closing the gap above.
 *   - `test/AuditableOutput.t.sol` independently re-encodes `contractInputsValues` back to `data`
 *     for every tx (the same check the Safe UI performs on import).
 * Rely on all three together; do not read `_assertRoundTrip` alone as a guarantee that a label is
 * correct.
 */
abstract contract SafeBatchDecoder is AccessManagerDumper, SafeBatchUtils {
    struct DecodedTx {
        string method; // solidity method name, e.g. "grantRole"
        string[] names; // ABI param names
        string[] types; // ABI param types (== internalType for these elementary types)
        string[] canonical; // canonical string values (for contractInputsValues)
        string[] labeled; // human-labeled values (for the meta narration)
        string effect; // one-line plain-English description
    }

    error RoundTripMismatch(uint256 index, bytes4 selector);

    // ═══════════════════════════════════════════════════════════════════════════
    // CENTRAL DECODER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Decodes one Safe transaction into its method, typed args, labeled args, and effect.
    /// @dev Branches on the AccessManager method set when `_tx.to` is the chain's factory, else on
    ///      the native vault grant/revoke set. Reverts on an unrecognized (target, selector) pair
    ///      so an unexpected op can never be silently mislabeled.
    function _describe(SafeTransaction memory _tx, uint256 _chainId) internal view returns (DecodedTx memory d) {
        bytes4 sel = _selectorOf(_tx.data);
        bytes memory tail = _tail(_tx.data);
        bool isAm = _tx.to == roycoFactory(_chainId);

        if (isAm && sel == IAccessManager.grantRole.selector) {
            (uint64 role, address account, uint32 delay) = abi.decode(tail, (uint64, address, uint32));
            d = _mk3(
                "grantRole",
                "roleId",
                "uint64",
                _uintToString(role),
                _formatRole(role),
                "account",
                "address",
                vm.toString(account),
                _actorName(account, _chainId),
                "executionDelay",
                "uint32",
                _uintToString(delay),
                _formatDelay(delay)
            );
            d.effect = string.concat("Grant ", _formatRole(role), " to ", _actorName(account, _chainId), " at execution delay ", _formatDelay(delay));
        } else if (isAm && sel == IAccessManager.revokeRole.selector) {
            (uint64 role, address account) = abi.decode(tail, (uint64, address));
            d = _mk2(
                "revokeRole",
                "roleId",
                "uint64",
                _uintToString(role),
                _formatRole(role),
                "account",
                "address",
                vm.toString(account),
                _actorName(account, _chainId)
            );
            d.effect = string.concat("Revoke ", _formatRole(role), " from ", _actorName(account, _chainId));
        } else if (isAm && sel == IAccessManager.setTargetFunctionRole.selector) {
            (address target, bytes4[] memory sels, uint64 role) = abi.decode(tail, (address, bytes4[], uint64));
            d = _mk3(
                "setTargetFunctionRole",
                "target",
                "address",
                vm.toString(target),
                _actorName(target, _chainId),
                "selectors",
                "bytes4[]",
                _selectorArrayCanonical(sels),
                _selectorArrayLabeled(sels),
                "roleId",
                "uint64",
                _uintToString(role),
                _formatRole(role)
            );
            d.effect = string.concat(
                "Bind ",
                _uintToString(sels.length),
                " selector(s) [",
                _selectorArrayLabeled(sels),
                "] on ",
                _actorName(target, _chainId),
                " to ",
                _formatRole(role)
            );
        } else if (isAm && sel == IAccessManager.setRoleGuardian.selector) {
            (uint64 role, uint64 guardian) = abi.decode(tail, (uint64, uint64));
            d = _mk2(
                "setRoleGuardian",
                "roleId",
                "uint64",
                _uintToString(role),
                _formatRole(role),
                "guardian",
                "uint64",
                _uintToString(guardian),
                _formatRole(guardian)
            );
            d.effect = string.concat("Set guardian of ", _formatRole(role), " to ", _formatRole(guardian));
        } else if (isAm && sel == IAccessManager.setRoleAdmin.selector) {
            (uint64 role, uint64 admin) = abi.decode(tail, (uint64, uint64));
            d = _mk2("setRoleAdmin", "roleId", "uint64", _uintToString(role), _formatRole(role), "admin", "uint64", _uintToString(admin), _formatRole(admin));
            d.effect = string.concat("Set admin of ", _formatRole(role), " to ", _formatRole(admin));
        } else if (isAm && sel == IAccessManager.setGrantDelay.selector) {
            (uint64 role, uint32 delay) = abi.decode(tail, (uint64, uint32));
            d = _mk2(
                "setGrantDelay", "roleId", "uint64", _uintToString(role), _formatRole(role), "newDelay", "uint32", _uintToString(delay), _formatDelay(delay)
            );
            d.effect = string.concat("Set grant delay of ", _formatRole(role), " to ", _formatDelay(delay));
        } else if (isAm && sel == IAccessManager.setTargetAdminDelay.selector) {
            (address target, uint32 delay) = abi.decode(tail, (address, uint32));
            d = _mk2(
                "setTargetAdminDelay",
                "target",
                "address",
                vm.toString(target),
                _actorName(target, _chainId),
                "newDelay",
                "uint32",
                _uintToString(delay),
                _formatDelay(delay)
            );
            d.effect = string.concat("Set admin delay of ", _actorName(target, _chainId), " to ", _formatDelay(delay));
        } else if (isAm && sel == IAccessManager.setTargetClosed.selector) {
            (address target, bool closed) = abi.decode(tail, (address, bool));
            string memory cs = closed ? "true" : "false";
            d = _mk2("setTargetClosed", "target", "address", vm.toString(target), _actorName(target, _chainId), "closed", "bool", cs, cs);
            d.effect = string.concat("Set ", _actorName(target, _chainId), " closed=", cs);
        } else if (isAm && sel == IAccessManager.labelRole.selector) {
            (uint64 role, string memory label) = abi.decode(tail, (uint64, string));
            d = _mk2("labelRole", "roleId", "uint64", _uintToString(role), _formatRole(role), "label", "string", label, label);
            d.effect = string.concat("Label ", _formatRole(role), " as \"", label, "\"");
        } else if (!isAm && sel == INativeAccessControl.grantRole.selector) {
            (bytes32 role, address account) = abi.decode(tail, (bytes32, address));
            d = _mk2(
                "grantRole",
                "role",
                "bytes32",
                vm.toString(role),
                _nativeRoleName(role),
                "account",
                "address",
                vm.toString(account),
                _actorName(account, _chainId)
            );
            d.effect = string.concat("Grant native ", _nativeRoleName(role), " to ", _actorName(account, _chainId), " on ", _actorName(_tx.to, _chainId));
        } else if (!isAm && sel == INativeAccessControl.revokeRole.selector) {
            (bytes32 role, address account) = abi.decode(tail, (bytes32, address));
            d = _mk2(
                "revokeRole",
                "role",
                "bytes32",
                vm.toString(role),
                _nativeRoleName(role),
                "account",
                "address",
                vm.toString(account),
                _actorName(account, _chainId)
            );
            d.effect = string.concat("Revoke native ", _nativeRoleName(role), " from ", _actorName(account, _chainId), " on ", _actorName(_tx.to, _chainId));
        } else {
            revert(string.concat("SafeBatchDecoder: unrecognized (target, selector) ", vm.toString(_tx.to), " ", vm.toString(bytes.concat(sel))));
        }
    }

    /// @notice Reverts unless decoding then re-encoding `_tx` reproduces the exact calldata.
    function _assertRoundTrip(SafeTransaction memory _tx, uint256 _chainId, uint256 _index) internal view {
        DecodedTx memory d = _describe(_tx, _chainId);
        if (keccak256(_reencode(_tx, _chainId, d)) != keccak256(_tx.data)) {
            revert RoundTripMismatch(_index, _selectorOf(_tx.data));
        }
    }

    /// @dev Re-encodes the decoded transaction from the ORIGINAL typed values (not the strings),
    ///      so the check is a true structural round-trip of the calldata.
    function _reencode(
        SafeTransaction memory _tx,
        uint256 _chainId,
        DecodedTx memory /*_d*/
    )
        private
        view
        returns (bytes memory)
    {
        bytes4 sel = _selectorOf(_tx.data);
        bytes memory tail = _tail(_tx.data);
        bool isAm = _tx.to == roycoFactory(_chainId);

        if (isAm && sel == IAccessManager.grantRole.selector) {
            (uint64 r, address a, uint32 dl) = abi.decode(tail, (uint64, address, uint32));
            return abi.encodeCall(IAccessManager.grantRole, (r, a, dl));
        } else if (isAm && sel == IAccessManager.revokeRole.selector) {
            (uint64 r, address a) = abi.decode(tail, (uint64, address));
            return abi.encodeCall(IAccessManager.revokeRole, (r, a));
        } else if (isAm && sel == IAccessManager.setTargetFunctionRole.selector) {
            (address t, bytes4[] memory s, uint64 r) = abi.decode(tail, (address, bytes4[], uint64));
            return abi.encodeCall(IAccessManager.setTargetFunctionRole, (t, s, r));
        } else if (isAm && sel == IAccessManager.setRoleGuardian.selector) {
            (uint64 r, uint64 g) = abi.decode(tail, (uint64, uint64));
            return abi.encodeCall(IAccessManager.setRoleGuardian, (r, g));
        } else if (isAm && sel == IAccessManager.setRoleAdmin.selector) {
            (uint64 r, uint64 a) = abi.decode(tail, (uint64, uint64));
            return abi.encodeCall(IAccessManager.setRoleAdmin, (r, a));
        } else if (isAm && sel == IAccessManager.setGrantDelay.selector) {
            (uint64 r, uint32 dl) = abi.decode(tail, (uint64, uint32));
            return abi.encodeCall(IAccessManager.setGrantDelay, (r, dl));
        } else if (isAm && sel == IAccessManager.setTargetAdminDelay.selector) {
            (address t, uint32 dl) = abi.decode(tail, (address, uint32));
            return abi.encodeCall(IAccessManager.setTargetAdminDelay, (t, dl));
        } else if (isAm && sel == IAccessManager.setTargetClosed.selector) {
            (address t, bool c) = abi.decode(tail, (address, bool));
            return abi.encodeCall(IAccessManager.setTargetClosed, (t, c));
        } else if (isAm && sel == IAccessManager.labelRole.selector) {
            (uint64 r, string memory l) = abi.decode(tail, (uint64, string));
            return abi.encodeCall(IAccessManager.labelRole, (r, l));
        } else if (!isAm && sel == INativeAccessControl.grantRole.selector) {
            (bytes32 r, address a) = abi.decode(tail, (bytes32, address));
            return abi.encodeCall(INativeAccessControl.grantRole, (r, a));
        } else if (!isAm && sel == INativeAccessControl.revokeRole.selector) {
            (bytes32 r, address a) = abi.decode(tail, (bytes32, address));
            return abi.encodeCall(INativeAccessControl.revokeRole, (r, a));
        }
        revert("SafeBatchDecoder: unrecognized selector (reencode)");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENRICHED WRITER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Writes a Safe Transaction Builder v1.0 JSON with per-tx `contractMethod` +
    ///         `contractInputsValues` (so the Safe UI self-decodes) and a human `meta`
    ///         (base description + auto summary + numbered labeled effects). Asserts every tx
    ///         round-trips before writing.
    /// @dev INVARIANT: every tx in `_txs` must target `_chainId` — the single `_chainId` drives
    ///      the `isAm` (factory) test and all actor lookups. Do NOT pass a cross-chain
    ///      `mergeBatches` result here; a foreign-chain factory tx would misroute `isAm` (and, for
    ///      a mainnet-vs-Base mix, fail closed in `_describe`'s final revert).
    function writeAuditableSafeTransactionJson(
        SafeTransaction[] memory _txs,
        uint256 _chainId,
        string memory _outputPath,
        string memory _name,
        string memory _baseDescription
    )
        internal
    {
        // Pass 1: assert round-trip, decode once per tx (reused when streaming tx bodies), and
        // accumulate the numbered effect list for the meta narration.
        // NOTE: `effects` is built by repeated string.concat, which is O(n^2) in memory (Solidity
        // memory never shrinks). This is bounded and fine because the meta narration is small
        // (one short line per tx) and callers cap batch size (Dawn: _MAX_BATCH_SIZE = 256). Only
        // the per-tx BODIES — the large part — are streamed below; do not move body-building here.
        DecodedTx[] memory decoded = new DecodedTx[](_txs.length);
        string memory effects = "";
        for (uint256 i = 0; i < _txs.length; i++) {
            _assertRoundTrip(_txs[i], _chainId, i);
            decoded[i] = _describe(_txs[i], _chainId);
            effects = string.concat(effects, "\n", _uintToString(i + 1), ". ", decoded[i].effect);
        }

        string memory description = string.concat(
            _baseDescription,
            "\n\n=== Decoded batch (human-auditable) ===",
            "\nChain: ",
            _chainName(_chainId),
            " (",
            _uintToString(_chainId),
            ")   Transactions: ",
            _uintToString(_txs.length),
            "\nBatch hash: ",
            vm.toString(keccak256(abi.encode(_txs))),
            "\n",
            effects
        );

        // Stream the transaction BODIES to the file one line per tx, so we never hold the whole
        // batch (the large part) as a single string — Solidity memory never shrinks, so a
        // monolithic build is quadratic and OOMs on large batches.
        string memory parent = _parentDir(_outputPath);
        if (bytes(parent).length > 0) vm.createDir(parent, true);

        vm.writeFile(_outputPath, ""); // truncate / create
        vm.writeLine(
            _outputPath,
            string.concat(
                "{\"version\":\"1.0\",\"chainId\":\"",
                _uintToString(_chainId),
                "\",\"createdAt\":",
                _uintToString(vm.getBlockTimestamp()),
                ",\"meta\":{\"name\":\"",
                _jsonEscape(_name),
                "\",\"description\":\"",
                _jsonEscape(description),
                "\"},\"transactions\":["
            )
        );
        for (uint256 i = 0; i < _txs.length; i++) {
            vm.writeLine(_outputPath, string.concat(_txObjectJson(_txs[i], decoded[i]), i + 1 < _txs.length ? "," : ""));
        }
        vm.writeLine(_outputPath, "]}");
        console2.log("  Wrote auditable batch:", _outputPath);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LABELERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Reverse lookup: address → known actor / contract name, else checksummed hex.
    /// @dev First match wins (fixed priority). The `address(0)` early return is load-bearing:
    ///      on a chain with no syncer, `syncer(chainId) == address(0)`, and without this guard a
    ///      zero-valued arg would mislabel as "Syncer". Keep it first.
    function _actorName(address _a, uint256 _chainId) internal view returns (string memory) {
        if (_a == address(0)) return "0x0";
        if (_a == FNDN) return "FNDN";
        if (_a == WAY) return "WAY";
        if (_a == DIAL) return "DIAL";
        if (_a == WAY_PAUSE) return "WAY_PAUSE";
        if (_a == FNDN_VETO) return "FNDN_VETO";
        if (_a == roycoFactory(_chainId)) return "RoycoFactory(AM)";
        if (_a == entryPoint(_chainId)) return "EntryPoint";
        if (_a == syncer(_chainId)) return "Syncer";

        // Markets (kernel + derived sub-addresses)
        string[] memory markets = marketNames(_chainId);
        for (uint256 i = 0; i < markets.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, markets[i]);
            if (_a == m.kernel) return string.concat(markets[i], ".kernel");
            if (_a == m.accountant) return string.concat(markets[i], ".accountant");
            if (_a == m.seniorTranche) return string.concat(markets[i], ".ST");
            if (_a == m.juniorTranche) return string.concat(markets[i], ".JT");
        }

        // Vaults + strategy stacks
        string[] memory vaults = vaultNames(_chainId);
        for (uint256 i = 0; i < vaults.length; i++) {
            VaultAddresses memory v = getVaultAddresses(_chainId, vaults[i]);
            if (_a == v.vault) return string.concat(vaults[i], ".vault");
            if (_a == v.whitelistHook) return string.concat(vaults[i], ".hook");
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);
            if (_a == s.strategy) return string.concat(vaults[i], ".strategy");
            if (_a == s.machine) return string.concat(vaults[i], ".machine");
            if (_a == s.caliber) return string.concat(vaults[i], ".caliber");
            if (_a == s.shareToken) return string.concat(vaults[i], ".shareToken");
        }
        return vm.toString(_a);
    }

    /// @notice Native concrete-vault role hash → name.
    function _nativeRoleName(bytes32 _role) internal pure returns (string memory) {
        if (_role == Selectors.nativeVaultManager()) return "VAULT_MANAGER";
        if (_role == Selectors.nativeStrategyManager()) return "STRATEGY_MANAGER";
        if (_role == Selectors.nativeHookManager()) return "HOOK_MANAGER";
        if (_role == Selectors.nativeVaultManagerAdmin()) return "VAULT_MANAGER_ADMIN";
        if (_role == Selectors.nativeStrategyManagerAdmin()) return "STRATEGY_MANAGER_ADMIN";
        if (_role == Selectors.nativeHookManagerAdmin()) return "HOOK_MANAGER_ADMIN";
        if (_role == Selectors.nativeAllocatorAdmin()) return "ALLOCATOR_ADMIN";
        if (_role == Selectors.nativeWithdrawalManagerAdmin()) return "WITHDRAWAL_MANAGER_ADMIN";
        return "";
    }

    /// @notice Human-readable execution/grant delay. Every delayed op uses the uniform 72h delay
    ///         (`DELAY_MIN == DELAY_ROOT == DELAY_RESCUE`), so a single branch covers all of them.
    function _formatDelay(uint32 _delay) internal pure returns (string memory) {
        if (_delay == DELAY_IMMEDIATE) return "immediate";
        if (_delay == DELAY_MIN) return "72h";
        return string.concat(_uintToString(_delay), "s");
    }

    /// @notice Selector → method name; hex fallback for anything unrecognized.
    function _selectorName(bytes4 _sel) internal pure returns (string memory) {
        // Pause / upgrade
        if (_sel == IRoycoAuth.pause.selector) return "pause";
        if (_sel == IRoycoAuth.unpause.selector) return "unpause";
        if (_sel == UUPSUpgradeable.upgradeToAndCall.selector) return "upgradeToAndCall";
        // Entry point
        if (_sel == IRoycoEntryPoint.modifyTrancheConfigs.selector) return "modifyTrancheConfigs";
        if (_sel == IRoycoEntryPoint.collectProtocolFees.selector) return "collectProtocolFees";
        if (_sel == IRoycoEntryPoint.requestDeposit.selector) return "requestDeposit";
        if (_sel == IRoycoEntryPoint.executeDeposit.selector) return "executeDeposit";
        if (_sel == IRoycoEntryPoint.executeDeposits.selector) return "executeDeposits";
        if (_sel == IRoycoEntryPoint.cancelDepositRequest.selector) return "cancelDepositRequest";
        if (_sel == IRoycoEntryPoint.cancelDepositRequests.selector) return "cancelDepositRequests";
        if (_sel == IRoycoEntryPoint.requestRedemption.selector) return "requestRedemption";
        if (_sel == IRoycoEntryPoint.executeRedemption.selector) return "executeRedemption";
        if (_sel == IRoycoEntryPoint.executeRedemptions.selector) return "executeRedemptions";
        if (_sel == IRoycoEntryPoint.cancelRedemptionRequest.selector) return "cancelRedemptionRequest";
        if (_sel == IRoycoEntryPoint.cancelRedemptionRequests.selector) return "cancelRedemptionRequests";
        // Tranche
        if (_sel == IRoycoVaultTranche.deposit.selector) return "deposit";
        if (_sel == IRoycoVaultTranche.redeem.selector) return "redeem";
        if (_sel == IRoycoVaultTranche.burn.selector) return "burn";
        if (_sel == IRoycoVaultTranche.burnFrom.selector) return "burnFrom";
        if (_sel == IRoycoVaultTranche.seizeShares.selector) return "seizeShares";
        if (_sel == IRoycoVaultTranche.seizeAndRedeemShares.selector) return "seizeAndRedeemShares";
        // Concrete vault
        if (_sel == IConcreteStandardVaultImpl.updateManagementFee.selector) return "updateManagementFee";
        if (_sel == IConcreteStandardVaultImpl.updatePerformanceFee.selector) return "updatePerformanceFee";
        if (_sel == IConcreteStandardVaultImpl.setDepositLimits.selector) return "setDepositLimits";
        if (_sel == IConcreteStandardVaultImpl.setWithdrawLimits.selector) return "setWithdrawLimits";
        if (_sel == IConcreteStandardVaultImpl.addStrategy.selector) return "addStrategy";
        if (_sel == IConcreteStandardVaultImpl.removeStrategy.selector) return "removeStrategy";
        if (_sel == IConcreteStandardVaultImpl.toggleStrategyStatus.selector) return "toggleStrategyStatus";
        if (_sel == IConcreteStandardVaultImpl.setHooks.selector) return "setHooks";
        // Strategy adapter
        if (_sel == IStrategyTemplate.allocateFunds.selector) return "allocateFunds";
        if (_sel == IStrategyTemplate.deallocateFunds.selector) return "deallocateFunds";
        if (_sel == IStrategyTemplate.rescueToken.selector) return "rescueToken";
        // Caliber
        if (_sel == ICaliber.setPositionStaleThreshold.selector) return "setPositionStaleThreshold";
        if (_sel == ICaliber.setMaxPositionIncreaseLossBps.selector) return "setMaxPositionIncreaseLossBps";
        if (_sel == ICaliber.setMaxPositionDecreaseLossBps.selector) return "setMaxPositionDecreaseLossBps";
        if (_sel == ICaliber.setMaxSwapLossBps.selector) return "setMaxSwapLossBps";
        if (_sel == ICaliber.setCooldownDuration.selector) return "setCooldownDuration";
        if (_sel == ICaliber.addBaseToken.selector) return "addBaseToken";
        if (_sel == ICaliber.removeBaseToken.selector) return "removeBaseToken";
        if (_sel == ICaliber.scheduleAllowedInstrRootUpdate.selector) return "scheduleAllowedInstrRootUpdate";
        if (_sel == ICaliber.setTimelockDuration.selector) return "setTimelockDuration";
        // Machine (risk-manager setters)
        if (_sel == IMachineRiskManagerSetters.setShareLimit.selector) return "setShareLimit";
        if (_sel == IMachineRiskManagerSetters.setCaliberStaleThreshold.selector) return "setCaliberStaleThreshold";
        if (_sel == IMachineRiskManagerSetters.setMaxFixedFeeAccrualRate.selector) return "setMaxFixedFeeAccrualRate";
        if (_sel == IMachineRiskManagerSetters.setMaxPerfFeeAccrualRate.selector) return "setMaxPerfFeeAccrualRate";
        if (_sel == IMachineRiskManagerSetters.setFeeMintCooldown.selector) return "setFeeMintCooldown";
        if (_sel == IMachineRiskManagerSetters.setMaxSharePriceChangeRate.selector) return "setMaxSharePriceChangeRate";
        if (_sel == IBridgeController.setOutTransferEnabled.selector) return "setOutTransferEnabled";
        if (_sel == IBridgeController.setMaxBridgeLossBps.selector) return "setMaxBridgeLossBps";
        return _hex4(_sel);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // JSON / STRING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _txObjectJson(SafeTransaction memory _tx, DecodedTx memory _d) private pure returns (string memory) {
        return string.concat(
            "{\"to\":\"",
            vm.toString(_tx.to),
            "\",\"value\":\"",
            _uintToString(_tx.value),
            "\",\"data\":\"",
            vm.toString(_tx.data),
            "\",\"contractMethod\":",
            _contractMethodJson(_d),
            ",\"contractInputsValues\":",
            _contractInputsValuesJson(_d),
            "}"
        );
    }

    function _contractMethodJson(DecodedTx memory _d) private pure returns (string memory) {
        string memory inputs = "[";
        for (uint256 i = 0; i < _d.names.length; i++) {
            inputs = string.concat(
                inputs, i == 0 ? "" : ",", "{\"internalType\":\"", _d.types[i], "\",\"name\":\"", _d.names[i], "\",\"type\":\"", _d.types[i], "\"}"
            );
        }
        inputs = string.concat(inputs, "]");
        return string.concat("{\"inputs\":", inputs, ",\"name\":\"", _d.method, "\",\"payable\":false}");
    }

    function _contractInputsValuesJson(DecodedTx memory _d) private pure returns (string memory) {
        string memory obj = "{";
        for (uint256 i = 0; i < _d.names.length; i++) {
            obj = string.concat(obj, i == 0 ? "" : ",", "\"", _d.names[i], "\":\"", _jsonEscape(_d.canonical[i]), "\"");
        }
        return string.concat(obj, "}");
    }

    function _selectorArrayCanonical(bytes4[] memory _sels) private pure returns (string memory) {
        string memory s = "[";
        for (uint256 i = 0; i < _sels.length; i++) {
            s = string.concat(s, i == 0 ? "" : ",", "\"", _hex4(_sels[i]), "\"");
        }
        return string.concat(s, "]");
    }

    function _selectorArrayLabeled(bytes4[] memory _sels) private pure returns (string memory) {
        string memory s = "";
        for (uint256 i = 0; i < _sels.length; i++) {
            s = string.concat(s, i == 0 ? "" : ", ", _selectorName(_sels[i]));
        }
        return s;
    }

    function _hex4(bytes4 _sel) private pure returns (string memory) {
        return vm.toString(bytes.concat(_sel));
    }

    function _selectorOf(bytes memory _data) private pure returns (bytes4 sel) {
        require(_data.length >= 4, "SafeBatchDecoder: calldata too short");
        assembly {
            sel := mload(add(_data, 32))
        }
    }

    /// @dev Returns `_data` with the leading 4-byte selector removed.
    function _tail(bytes memory _data) private pure returns (bytes memory out) {
        require(_data.length >= 4, "SafeBatchDecoder: calldata too short");
        out = new bytes(_data.length - 4);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = _data[i + 4];
        }
    }

    /// @dev JSON string escaper (RFC 8259): `"`, `\`, and EVERY control char U+0000–U+001F.
    ///      Common controls use short escapes (`\n \t \r`); the rest use `\u00XX`. O(n): fills a
    ///      pre-sized buffer (worst case 6 bytes/char) and truncates.
    function _jsonEscape(string memory _s) internal pure returns (string memory) {
        bytes memory b = bytes(_s);
        bytes memory out = new bytes(b.length * 6);
        uint256 n;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == '"') {
                out[n++] = "\\";
                out[n++] = '"';
            } else if (c == "\\") {
                out[n++] = "\\";
                out[n++] = "\\";
            } else if (c == "\n") {
                out[n++] = "\\";
                out[n++] = "n";
            } else if (c == "\t") {
                out[n++] = "\\";
                out[n++] = "t";
            } else if (c == "\r") {
                out[n++] = "\\";
                out[n++] = "r";
            } else if (uint8(c) < 0x20) {
                // Any other C0 control char must be \u-escaped or the JSON is invalid.
                out[n++] = "\\";
                out[n++] = "u";
                out[n++] = "0";
                out[n++] = "0";
                out[n++] = _hexDigit(uint8(c) >> 4);
                out[n++] = _hexDigit(uint8(c) & 0x0f);
            } else {
                out[n++] = c;
            }
        }
        assembly {
            mstore(out, n)
        }
        return string(out);
    }

    /// @dev Lowercase hex digit for a nibble (0–15).
    function _hexDigit(uint8 _v) private pure returns (bytes1) {
        return bytes1(_v < 10 ? 48 + _v : 87 + _v);
    }

    // ── DecodedTx constructors (fixed 2- and 3-arg shapes) ────────────────────

    function _mk2(
        string memory _method,
        string memory _n0,
        string memory _t0,
        string memory _c0,
        string memory _l0,
        string memory _n1,
        string memory _t1,
        string memory _c1,
        string memory _l1
    )
        private
        pure
        returns (DecodedTx memory d)
    {
        d.method = _method;
        d.names = new string[](2);
        d.types = new string[](2);
        d.canonical = new string[](2);
        d.labeled = new string[](2);
        (d.names[0], d.types[0], d.canonical[0], d.labeled[0]) = (_n0, _t0, _c0, _l0);
        (d.names[1], d.types[1], d.canonical[1], d.labeled[1]) = (_n1, _t1, _c1, _l1);
    }

    function _mk3(
        string memory _method,
        string memory _n0,
        string memory _t0,
        string memory _c0,
        string memory _l0,
        string memory _n1,
        string memory _t1,
        string memory _c1,
        string memory _l1,
        string memory _n2,
        string memory _t2,
        string memory _c2,
        string memory _l2
    )
        private
        pure
        returns (DecodedTx memory d)
    {
        d.method = _method;
        d.names = new string[](3);
        d.types = new string[](3);
        d.canonical = new string[](3);
        d.labeled = new string[](3);
        (d.names[0], d.types[0], d.canonical[0], d.labeled[0]) = (_n0, _t0, _c0, _l0);
        (d.names[1], d.types[1], d.canonical[1], d.labeled[1]) = (_n1, _t1, _c1, _l1);
        (d.names[2], d.types[2], d.canonical[2], d.labeled[2]) = (_n2, _t2, _c2, _l2);
    }
}
