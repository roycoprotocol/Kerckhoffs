#!/usr/bin/env node
// Extract the minimal event ABIs the subgraph needs from Foundry's compiled artifacts
// under ../../out, keeping the subgraph ABI in lockstep with the audited Solidity.
// Run after `forge build`. Usage: node scripts/extract-abis.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const out = join(root, "..", "..", "out"); // repo out/

// artifactPath (relative to out/) -> destination abi filename.
// `merge` concatenates additional artifacts' entries into the same destination — the Dawn
// RoycoFactory is BOTH the AccessManager and the market deployer at one address, and graph-cli
// requires every eventHandler's event to live in the data source's main ABI.
const SOURCES = [
  {
    artifact: "IAccessManager.sol/IAccessManager.json",
    dest: "AccessManager.json",
    merge: ["IDawnFactory.sol/IDawnFactory.json"],
  },
  // OZ AccessControl events live on IAccessControl; the concrete vault emits them.
  { artifact: "IAccessControl.sol/IAccessControl.json", dest: "AccessControl.json" },
  // Day AM = OZ AccessManager superset + TargetConfiguredAtGenesis (src/interfaces/day/).
  { artifact: "IDayAccessManager.sol/IDayAccessManager.json", dest: "RoycoAccessManager.json" },
  // Day RoycoFactory MarketDeploymentCompleted, incl. named DeploymentResult tuple components.
  { artifact: "IDayFactory.sol/IDayFactory.json", dest: "DayFactory.json" },
];

let ok = true;
function loadAbi(artifact) {
  const p = join(out, artifact);
  if (!existsSync(p)) {
    console.error(`[extract-abis] missing artifact ${p} — run \`forge build\` first`);
    ok = false;
    return [];
  }
  const json = JSON.parse(readFileSync(p, "utf8"));
  return json.abi ?? json;
}
for (const { artifact, dest, merge = [] } of SOURCES) {
  const abi = [...loadAbi(artifact), ...merge.flatMap(loadAbi)];
  writeFileSync(join(root, "abis", dest), JSON.stringify(abi, null, 2) + "\n");
  console.log(`[extract-abis] ${artifact}${merge.length ? ` +${merge.length} merged` : ""} -> abis/${dest} (${abi.length} entries)`);
}
if (!ok) process.exit(1);
