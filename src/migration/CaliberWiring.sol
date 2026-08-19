// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Selectors } from "../access/Selectors.sol";
import { SafeBatchDecoder } from "../safe/SafeBatchDecoder.sol";
import { SafeSimulator } from "../safe/SafeSimulator.sol";
import { console2 } from "forge-std/console2.sol";
import { ICaliber } from "makina-core/src/interfaces/ICaliber.sol";
import { IMakinaGovernable } from "makina-core/src/interfaces/IMakinaGovernable.sol";

/**
 * @title CaliberWiring
 * @notice Shared, per-vault Makina/Caliber AM-wiring primitives. Extracted verbatim from
 *         `MigrateMakina` so that both the standalone Makina batch and the consolidated per-chain
 *         srRoyUSDC batch build **byte-identical** Caliber transactions from a single source
 *         (single-source-of-truth — see README "Conventions"). Nothing here writes JSON or forks;
 *         it is pure batch construction plus the simulation-only Makina-governance prerequisites.
 *
 * Two halves, per (chain, vault-with-Caliber):
 *
 *   - `_buildCaliberForVault` — the 9-tx AM batch that binds the Caliber's risk-manager setters +
 *     the endpoint's risk-manager setters (the Machine's on a hub, the CaliberMailbox's on a spoke)
 *     to the vault's `<VAULT>_RISK_MANAGER` (72h) role and `Caliber.setTimelockDuration` to
 *     `<VAULT>_TIMELOCK_MANAGER` (72h); wires GUARDIAN_ROLE as the cancel-gate for both; and grants
 *     both to WAY. The Caliber's on-chain `_allowedInstrRoot` timelock is left untouched.
 *
 *   - `_preSimulateCaliberForVault` — the simulation-only prerequisites that depend on **Makina**
 *     governance and are therefore NOT part of the emitted Safe JSON: re-point BOTH governable
 *     slots (`_riskManager` slot 2 and `_riskManagerTimelock` slot 3) on the endpoint to that
 *     chain's RoycoFactory, and mock FNDN as an `instrRootGuardian` on the Caliber. See
 *     `MigrateMakina`'s header for the full rationale on why both slots are required.
 */
abstract contract CaliberWiring is SafeBatchDecoder, SafeSimulator {
    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BUILDER (emitted)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Builds the 9-tx Caliber AM-wiring batch for one (chain, vault). Pure/view — the
    ///         caller decides how to simulate and where to write it.
    function _buildCaliberForVault(uint256 _chainId, string memory _vault) internal view returns (SafeTransaction[] memory txs) {
        // Resolve the AM per chain (Base has its own factory). Never hardcode ROYCO_FACTORY here —
        // that would silently target the wrong AM off mainnet.
        address factory = roycoFactory(_chainId);
        (uint64 riskRole, uint64 tlRole, string memory riskLabel, string memory tlLabel) = _vaultRoleIds(_vault);
        StrategyStack memory s = getStrategyStack(_chainId, _vault);

        // Per vault: 2 labelRole + 3 setTargetFunctionRole + 2 setRoleGuardian + 2 grantRole = 9 txs
        txs = new SafeTransaction[](9);
        uint256 t;

        txs[t++] = buildLabelRole(factory, riskRole, riskLabel);
        txs[t++] = buildLabelRole(factory, tlRole, tlLabel);

        // Caliber: risk-manager-gated setters + meta-timelock setter
        txs[t++] = buildSetTargetFunctionRole(factory, s.caliber, Selectors.caliberRiskManagerSelectors(), riskRole);
        bytes4[] memory tlSel = new bytes4[](1);
        tlSel[0] = ICaliber.setTimelockDuration.selector;
        txs[t++] = buildSetTargetFunctionRole(factory, s.caliber, tlSel, tlRole);

        // Endpoint risk-manager setters: the Machine's on the hub, the CaliberMailbox's on a spoke
        // (its bridge/cooldown surface). Same target-binding, chain-appropriate list.
        bytes4[] memory endpointSel = s.spoke ? Selectors.mailboxRiskManagerSelectors() : Selectors.machineRiskManagerSelectors();
        txs[t++] = buildSetTargetFunctionRole(factory, s.endpoint, endpointSel, riskRole);

        // Guardian wiring — required so the guardian can cancel the 72h-delayed risk/timelock
        // manager ops. Without this, getRoleGuardian defaults to ADMIN_ROLE and only an admin
        // can cancel.
        txs[t++] = buildSetRoleGuardian(factory, riskRole, GUARDIAN_ROLE);
        txs[t++] = buildSetRoleGuardian(factory, tlRole, GUARDIAN_ROLE);

        // Held by WAY (parameter-update authority). FNDN / FNDN_VETO cancel via GUARDIAN_ROLE.
        txs[t++] = buildGrantRole(factory, riskRole, WAY, DELAY_MIN);
        txs[t++] = buildGrantRole(factory, tlRole, WAY, DELAY_MIN);

        require(t == txs.length, "Caliber tx count mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRE-SIMULATION (Makina-governance prerequisite, NOT in the emitted JSON)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Applies the simulation-only Makina-governance prerequisites for one (chain, vault):
    ///         re-point BOTH governable slots on the endpoint to RoycoFactory + mock FNDN as an
    ///         instrRootGuardian on the Caliber. Both require Makina governance to actually execute
    ///         on-chain; tracked as a separate workstream. NOT included in any emitted Safe JSON.
    function _preSimulateCaliberForVault(uint256 _chainId, string memory _vault) internal {
        StrategyStack memory s = getStrategyStack(_chainId, _vault);
        // Endpoint = Machine on the hub, CaliberMailbox on a spoke — both inherit MakinaGovernable,
        // so the same slot layout / helper applies.
        string memory ep = string.concat(_vault, s.spoke ? " mailbox" : " machine");
        _writeMachineGovernableSlot(s.endpoint, _SLOT_RISK_MANAGER, roycoFactory(_chainId), string.concat(ep, ".riskManager"));
        _writeMachineGovernableSlot(s.endpoint, _SLOT_RISK_MANAGER_TIMELOCK, roycoFactory(_chainId), string.concat(ep, ".riskManagerTimelock"));
        _mockCaliberInstrRootGuardian(s.caliber, FNDN, string.concat(_vault, " caliber"));
    }

    function _mockCaliberInstrRootGuardian(address _caliber, address _guardian, string memory _label) internal {
        vm.mockCall(_caliber, abi.encodeWithSignature("isInstrRootGuardian(address)", _guardian), abi.encode(true));
        require(ICaliber(_caliber).isInstrRootGuardian(_guardian), string.concat(_label, ": isInstrRootGuardian mock did not stick"));
        console2.log(string.concat("    [OK] ", _label, " FNDN recognised as instrRootGuardian (cancelAllowedInstrRootUpdate)"));
    }

    /// @dev MakinaGovernableStorage layout (vendored
    ///      `royco-vault-makina-strategy/lib/makina-core/src/utils/MakinaGovernable.sol:14-22`):
    ///      slot+0 _mechanic, +1 _securityCouncil, +2 _riskManager, +3 _riskManagerTimelock, ...
    ///      ERC-7201 base slot:
    ///      `keccak256(abi.encode(uint256(keccak256("makina.storage.MakinaGovernable")) - 1)) & ~bytes32(uint256(0xff))`
    ///      = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000
    bytes32 private constant _MAKINA_GOVERNABLE_STORAGE_BASE = 0x7e702089668346e906996be6de3dfc0cb2b0c125fc09b3c0391871825913e000;
    uint256 private constant _SLOT_RISK_MANAGER = 2;
    uint256 private constant _SLOT_RISK_MANAGER_TIMELOCK = 3;

    /// @dev Writes either the riskManager (offset 2) or riskManagerTimelock (offset 3) slot
    ///      and verifies the corresponding view returns the new value.
    function _writeMachineGovernableSlot(address _machine, uint256 _offset, address _newAddr, string memory _label) internal {
        bytes32 slot = bytes32(uint256(_MAKINA_GOVERNABLE_STORAGE_BASE) + _offset);
        vm.store(_machine, slot, bytes32(uint256(uint160(_newAddr))));
        address actual = _offset == _SLOT_RISK_MANAGER ? IMakinaGovernable(_machine).riskManager() : IMakinaGovernable(_machine).riskManagerTimelock();
        require(actual == _newAddr, string.concat(_label, ": store did not stick (storage layout drifted?)"));
        console2.log(string.concat("    [OK] ", _label, " -> ROYCO_FACTORY"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE-ID RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════

    function _vaultRoleIds(string memory _vault) internal pure returns (uint64 riskRole, uint64 tlRole, string memory riskLabel, string memory tlLabel) {
        if (_str_eq(_vault, "srRoyUSDC")) {
            return (SRROYUSDC_RISK_MANAGER, SRROYUSDC_TIMELOCK_MANAGER, "SRROYUSDC_RISK_MANAGER", "SRROYUSDC_TIMELOCK_MANAGER");
        } else if (_str_eq(_vault, "roywstETH")) {
            return (ROYWSTETH_RISK_MANAGER, ROYWSTETH_TIMELOCK_MANAGER, "ROYWSTETH_RISK_MANAGER", "ROYWSTETH_TIMELOCK_MANAGER");
        }
        revert("Unknown vault for Makina migration");
    }

    function _str_eq(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(bytes(_a)) == keccak256(bytes(_b));
    }
}
