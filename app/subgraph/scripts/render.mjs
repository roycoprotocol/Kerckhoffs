#!/usr/bin/env node
// Render subgraph.yaml from subgraph.template.yaml + config/<chainId>.json using mustache.
// Usage: node scripts/render.mjs <chainId>
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Mustache from "mustache";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const chainId = process.argv[2];
if (!chainId) {
  console.error("usage: node scripts/render.mjs <chainId>");
  process.exit(1);
}

const configPath = join(root, "config", `${chainId}.json`);
const config = JSON.parse(readFileSync(configPath, "utf8"));
if (config.startBlocksResolved === false) {
  console.warn(
    `[render] WARNING: config/${chainId}.json still has placeholder start blocks ` +
      `(startBlocksResolved=false). Resolve real contract-creation blocks before deploying.`,
  );
}

// Mustache is logic-less and has no `../` parent access, so denormalize `network` onto each vault
// entry and onto the optional Day sections (all data sources must share the top-level network).
// Chains without Royco Day (Avalanche) simply omit `dayManager`/`dayFactory` and the falsy
// sections render to nothing.
// Grafting is a LOCAL-graph-node optimization: the graft base hashes in config/*.json exist only
// on the local node's IPFS/store. Hosted deploys (Goldsky) must sync from scratch — strip the
// graft with NO_GRAFT=1 (the deploy:* scripts set it).
if (process.env.NO_GRAFT === "1") delete config.graft;

const view = {
  ...config,
  vaults: (config.vaults || []).map((v) => ({ ...v, network: config.network })),
  dayManager: config.dayManager ? { ...config.dayManager, network: config.network } : null,
  dayFactory: config.dayFactory ? { ...config.dayFactory, network: config.network } : null,
};

const template = readFileSync(join(root, "subgraph.template.yaml"), "utf8");
// Disable HTML escaping — addresses/values must render verbatim.
const rendered = Mustache.render(template, view, {}, { escape: (v) => v });

writeFileSync(join(root, "subgraph.yaml"), rendered);
console.log(`[render] wrote subgraph.yaml for chain ${chainId} (${config.network})`);
