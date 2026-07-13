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

// artifactPath (relative to out/) -> destination abi filename
const SOURCES = [
  { artifact: "IAccessManager.sol/IAccessManager.json", dest: "AccessManager.json" },
  // OZ AccessControl events live on IAccessControl; the concrete vault emits them.
  { artifact: "IAccessControl.sol/IAccessControl.json", dest: "AccessControl.json" },
];

let ok = true;
for (const { artifact, dest } of SOURCES) {
  const p = join(out, artifact);
  if (!existsSync(p)) {
    console.error(`[extract-abis] missing artifact ${p} — run \`forge build\` first`);
    ok = false;
    continue;
  }
  const json = JSON.parse(readFileSync(p, "utf8"));
  const abi = json.abi ?? json;
  writeFileSync(join(root, "abis", dest), JSON.stringify(abi, null, 2) + "\n");
  console.log(`[extract-abis] ${artifact} -> abis/${dest} (${abi.length} entries)`);
}
if (!ok) process.exit(1);
