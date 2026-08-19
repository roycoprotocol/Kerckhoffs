// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Script } from "forge-std/Script.sol";

import { AccessManagerDumper } from "../src/access/AccessManagerDumper.sol";
import { Day } from "../src/registry/Day.sol";

/**
 * @title ExportCatalog
 * @notice Emits the machine-readable canonical catalog consumed by the dashboard (the EXPECTED /
 *         name-resolution side of the model — see app/docs/spec/main.md §5). Reuses the registry
 *         single-source-of-truth already inherited by `AccessManagerDumper` so addresses are never
 *         duplicated.
 *
 * Per chain writes `app/metadata/catalog.<chainId>.json` (v2, one entry per AccessManager):
 *   { chainId, chainName, generatedAtBlock,
 *     factory, expiration, minSetback,            // DEPRECATED aliases of managers[kind=dawn]
 *     managers: [{ kind, address, name, expiration, minSetback,
 *                  roles[{id,name}], actors[{address,name,category,pendingDeployment}],
 *                  targets[{address,name,type,category,parent}] }],
 *     makinaSlots[{vault,caliber,machine,expected*}] }
 *
 * The dawn manager is the Dawn RoycoFactory; on chains where Royco Day is deployed (all but
 * Avalanche) a second "day" manager entry covers the Day RoycoAccessManager. Day markets are
 * deployed permissionlessly and are NOT listed here — the subgraph's `Market` entities (from the
 * Day factory's MarketDeploymentCompleted) are the enumeration source; only static Day infra
 * appears as targets.
 *
 * Role descriptions + expected holders/delays live in the hand-authored per-manager
 * `app/metadata/roles.descriptions.{dawn,day}.json` (main.md §5.2); the frontend joins the two.
 *
 * Usage:
 *   forge script script/ExportCatalog.s.sol --sig "run()"                 # all chains
 *   forge script script/ExportCatalog.s.sol --sig "exportCatalog(uint256)" -- 1
 */
contract ExportCatalog is AccessManagerDumper, Day, Script {
    string internal constant _OUT = "app/metadata/";

    function run() external {
        exportCatalog(MAINNET);
        exportCatalog(AVALANCHE);
        exportCatalog(ARBITRUM);
        exportCatalog(BASE);
    }

    function exportCatalog(uint256 _chainId) public {
        if (block.chainid != _chainId) {
            vm.createSelectFork(_getRpcUrl(_chainId));
        }
        IAccessManager am = IAccessManager(roycoFactory(_chainId));

        string memory root = string.concat("cat", vm.toString(_chainId));
        vm.serializeUint(root, "chainId", _chainId);
        vm.serializeString(root, "chainName", _chainName(_chainId));
        vm.serializeUint(root, "generatedAtBlock", block.number);
        // DEPRECATED: kept one release for consumers not yet on managers[] (dashboard v1
        // fallback, snapshot-onchain.mjs). Aliases of the dawn manager entry.
        vm.serializeAddress(root, "factory", roycoFactory(_chainId));
        vm.serializeUint(root, "expiration", am.expiration());
        vm.serializeUint(root, "minSetback", am.minSetback());
        vm.serializeString(root, "managers", _managersJson(_chainId));
        string memory finalJson = vm.serializeString(root, "makinaSlots", _makinaJson(_chainId));

        vm.writeJson(finalJson, string.concat(_OUT, "catalog.", vm.toString(_chainId), ".json"));
    }

    // ── managers: one entry per AccessManager on this chain ───────────────────────

    function _managersJson(uint256 _chainId) internal returns (string[] memory out) {
        out = new string[](hasDay(_chainId) ? 2 : 1);
        out[0] = _dawnManagerJson(_chainId);
        if (hasDay(_chainId)) {
            out[1] = _dayManagerJson(_chainId);
        }
    }

    function _dawnManagerJson(uint256 _chainId) internal returns (string memory) {
        IAccessManager am = IAccessManager(roycoFactory(_chainId));
        string memory k = string.concat("mgr", vm.toString(_chainId), "_dawn");
        vm.serializeString(k, "kind", "dawn");
        vm.serializeAddress(k, "address", roycoFactory(_chainId));
        vm.serializeString(k, "name", "RoycoFactory (Dawn)");
        vm.serializeUint(k, "expiration", am.expiration());
        vm.serializeUint(k, "minSetback", am.minSetback());
        vm.serializeString(k, "roles", _rolesJson(_chainId, "dawn"));
        vm.serializeString(k, "actors", _actorsJson(_chainId));
        return vm.serializeString(k, "targets", _targetsJson(_chainId));
    }

    function _dayManagerJson(uint256 _chainId) internal returns (string memory) {
        IAccessManager am = IAccessManager(DAY_ACCESS_MANAGER);
        string memory k = string.concat("mgr", vm.toString(_chainId), "_day");
        vm.serializeString(k, "kind", "day");
        vm.serializeAddress(k, "address", DAY_ACCESS_MANAGER);
        vm.serializeString(k, "name", "RoycoAccessManager (Day)");
        vm.serializeUint(k, "expiration", am.expiration());
        vm.serializeUint(k, "minSetback", am.minSetback());
        vm.serializeString(k, "roles", _rolesJson(_chainId, "day"));
        vm.serializeString(k, "actors", _dayActorsJson(_chainId));
        return vm.serializeString(k, "targets", _dayTargetsJson(_chainId));
    }

    // ── roles: id (decimal, matches subgraph Role.roleId) + human name ────────────

    function _rolesJson(uint256 _chainId, string memory _kind) internal returns (string[] memory out) {
        (uint64[] memory roles, string[] memory labels) = keccak256(bytes(_kind)) == keccak256("day") ? _allDayRoles() : _allRoles();
        out = new string[](roles.length + 1); // + PUBLIC_ROLE
        for (uint256 i = 0; i < roles.length; i++) {
            string memory k = string.concat("role", vm.toString(_chainId), _kind, "_", vm.toString(i));
            vm.serializeString(k, "id", vm.toString(uint256(roles[i])));
            out[i] = vm.serializeString(k, "name", labels[i]);
        }
        string memory pk = string.concat("role", vm.toString(_chainId), _kind, "_pub");
        vm.serializeString(pk, "id", vm.toString(uint256(PUBLIC_ROLE)));
        out[roles.length] = vm.serializeString(pk, "name", "PUBLIC_ROLE");
    }

    // ── actors: known principals + pending-deployment sentinels ───────────────────

    function _actorsJson(uint256 _chainId) internal returns (string[] memory out) {
        out = new string[](7);
        out[0] = _actor(_chainId, "a0", "FNDN", "multisig", FNDN, false);
        out[1] = _actor(_chainId, "a1", "WAY", "multisig", WAY, false);
        out[2] = _actor(_chainId, "a2", "DIAL", "multisig", DIAL, false);
        out[3] = _actor(_chainId, "a3", "WAY_PAUSE", "multisig", WAY_PAUSE, !MULTISIGS_DEPLOYED);
        out[4] = _actor(_chainId, "a4", "FNDN_VETO", "multisig", FNDN_VETO, !MULTISIGS_DEPLOYED);
        out[5] = _actor(_chainId, "a5", "EntryPoint", "entrypoint", entryPoint(_chainId), false);
        // AUTO (Autonomous, service provider) — LP_ROLE_ADMIN_ROLE co-holder. Not deployed on Base.
        out[6] = _actor(_chainId, "a6", "AUTO", "multisig", AUTO, _chainId == BASE);
    }

    // Actor names must match `roles.descriptions.day.json` holders[].actor entries.
    function _dayActorsJson(uint256 _chainId) internal returns (string[] memory out) {
        out = new string[](8);
        out[0] = _actor(_chainId, "d0", "FNDN", "multisig", FNDN, false);
        out[1] = _actor(_chainId, "d1", "WAY", "multisig", WAY, false);
        out[2] = _actor(_chainId, "d2", "WAY_PAUSE", "multisig", WAY_PAUSE, false);
        out[3] = _actor(_chainId, "d3", "FNDN_VETO", "multisig", FNDN_VETO, false);
        out[4] = _actor(_chainId, "d4", "AUTO", "multisig", AUTO, _chainId == BASE);
        out[5] = _actor(_chainId, "d5", "Gatekeeper", "factory", DAY_GATEKEEPER, false);
        out[6] = _actor(_chainId, "d6", "DayEntryPoint", "entrypoint", DAY_ENTRY_POINT, false);
        // The Day factory is an actor (holds LPT_LP_ROLE) as well as a target.
        out[7] = _actor(_chainId, "d7", "DayFactory", "factory", DAY_FACTORY, false);
    }

    function _actor(
        uint256 _chainId,
        string memory _tag,
        string memory _name,
        string memory _category,
        address _addr,
        bool _pending
    )
        internal
        returns (string memory)
    {
        string memory k = string.concat("act", vm.toString(_chainId), _tag);
        vm.serializeString(k, "name", _name);
        vm.serializeString(k, "category", _category);
        vm.serializeBool(k, "pendingDeployment", _pending);
        return vm.serializeAddress(k, "address", _addr);
    }

    // ── targets: every AM-gated contract, with a human name + type ────────────────

    function _targetsJson(uint256 _chainId) internal returns (string[] memory out) {
        string[] memory markets = marketNames(_chainId);
        string[] memory vaults = vaultNames(_chainId);

        uint256 n = markets.length * 4 + vaults.length * 4;
        if (syncer(_chainId) != address(0)) n += 1;
        if (entryPoint(_chainId) != address(0)) n += 1;
        out = new string[](n);
        uint256 idx;

        for (uint256 i = 0; i < markets.length; i++) {
            MarketAddresses memory m = getMarketAddresses(_chainId, markets[i]);
            out[idx] = _target(_chainId, idx, string.concat(markets[i], ".kernel"), "kernel", "market", markets[i], m.kernel);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(markets[i], ".accountant"), "accountant", "market", markets[i], m.accountant);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(markets[i], ".seniorTranche"), "seniorTranche", "market", markets[i], m.seniorTranche);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(markets[i], ".juniorTranche"), "juniorTranche", "market", markets[i], m.juniorTranche);
            idx++;
        }
        if (syncer(_chainId) != address(0)) {
            out[idx] = _target(_chainId, idx, "syncer", "syncer", "syncer", "", syncer(_chainId));
            idx++;
        }
        if (entryPoint(_chainId) != address(0)) {
            out[idx] = _target(_chainId, idx, "entryPoint", "entryPoint", "entrypoint", "", entryPoint(_chainId));
            idx++;
        }
        for (uint256 i = 0; i < vaults.length; i++) {
            VaultAddresses memory v = getVaultAddresses(_chainId, vaults[i]);
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);
            out[idx] = _target(_chainId, idx, vaults[i], "vault", "vault", vaults[i], v.vault);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(vaults[i], ".strategy"), "strategy", "strategy", vaults[i], s.strategy);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(vaults[i], ".caliber"), "caliber", "strategy", vaults[i], s.caliber);
            idx++;
            out[idx] = _target(_chainId, idx, string.concat(vaults[i], ".machine"), "machine", "strategy", vaults[i], s.endpoint);
            idx++;
        }
    }

    // Static Day infrastructure only — Day markets are enumerated dynamically from the subgraph's
    // MarketDeploymentCompleted-derived `Market` entities, never from this catalog.
    function _dayTargetsJson(uint256 _chainId) internal returns (string[] memory out) {
        out = new string[](4);
        out[0] = _target(_chainId, 1000, "dayFactory", "factory", "factory", "", DAY_FACTORY);
        out[1] = _target(_chainId, 1001, "dayGatekeeper", "gatekeeper", "factory", "", DAY_GATEKEEPER);
        out[2] = _target(_chainId, 1002, "dayEntryPoint", "entryPoint", "entrypoint", "", DAY_ENTRY_POINT);
        out[3] = _target(_chainId, 1003, "dayMarketSyncer", "syncer", "syncer", "", DAY_MARKET_SYNCER);
    }

    function _target(
        uint256 _chainId,
        uint256 _idx,
        string memory _name,
        string memory _type,
        string memory _category,
        string memory _parent,
        address _addr
    )
        internal
        returns (string memory)
    {
        string memory k = string.concat("t", vm.toString(_chainId), "_", vm.toString(_idx));
        vm.serializeString(k, "name", _name);
        vm.serializeString(k, "type", _type);
        vm.serializeString(k, "category", _category);
        vm.serializeString(k, "parent", _parent);
        return vm.serializeAddress(k, "address", _addr);
    }

    // ── makina slots: read live via viem in the frontend; expected = RoycoFactory ─

    function _makinaJson(uint256 _chainId) internal returns (string[] memory out) {
        string[] memory vaults = vaultNames(_chainId);
        out = new string[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            StrategyStack memory s = getStrategyStack(_chainId, vaults[i]);
            string memory k = string.concat("mk", vm.toString(_chainId), "_", vm.toString(i));
            vm.serializeString(k, "vault", vaults[i]);
            vm.serializeAddress(k, "caliber", s.caliber);
            vm.serializeAddress(k, "machine", s.endpoint);
            vm.serializeAddress(k, "expectedRiskManager", roycoFactory(_chainId));
            out[i] = vm.serializeAddress(k, "expectedRiskManagerTimelock", roycoFactory(_chainId));
        }
    }
}
