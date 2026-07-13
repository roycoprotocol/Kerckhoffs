#!/usr/bin/env node
// Dump the CURRENT (target, selector) -> role bindings by scanning TargetFunctionRoleUpdated logs
// on the factory and keeping the latest event per (target, selector). Complements
// dump-roles-onchain.mjs. Writes dumps/target-functions.<chainId>.json (subgraph-shaped) + a .md.
//
// Usage: MAINNET_RPC_URL=... node scripts/dump-bindings-onchain.mjs [rpcUrl] [chainId] [factory]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const RPC = process.argv[2] || process.env.MAINNET_RPC_URL;
const chainId = process.argv[3] || "1";
const FACTORY = (process.argv[4] || "0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C").toLowerCase();
if (!RPC) { console.error("no RPC url (arg or MAINNET_RPC_URL)"); process.exit(1); }

const TFRU_TOPIC = "0x9ea6790c7dadfd01c9f8b9762b3682607af2c7e79e05a9f9fdf5580dde949151";
const CREATION_BLOCK = { "1": 24650849, "43114": 80312789, "42161": 441493793, "8453": 48111449 };

// optional enrichment maps
function tryLoad(p) { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; } }
const names = tryLoad(join(root, "..", "metadata", "role-names.json")) ?? { roles: {} };
const selectors = tryLoad(join(root, "..", "metadata", "selectors.json")) ?? {};
const catalog = tryLoad(join(root, "..", "metadata", `catalog.${chainId}.json`)) ?? { targets: [] };
const targetByAddr = new Map(catalog.targets.map((t) => [t.address.toLowerCase(), t]));
const roleName = (id) => (id === "0" ? "ADMIN_ROLE" : names.roles[id] ?? `role_${id}`);
const fnName = (sel) => selectors[sel]?.name ?? sel;

let rpcId = 0;
async function rpc(method, params) {
  const r = await fetch(RPC, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
  });
  const j = await r.json();
  if (j.error) throw new Error(`${method}: ${j.error.message}`);
  return j.result;
}

console.error(`[bindings] scanning TargetFunctionRoleUpdated on ${FACTORY} ...`);
const head = Number(BigInt(await rpc("eth_blockNumber", [])));
const latest = new Map(); // "target-selector" -> {target, selector, roleId, block, logIndex}
let from = CREATION_BLOCK[chainId] ?? 0;
let step = 50000;
while (from <= head) {
  const to = Math.min(from + step - 1, head);
  try {
    const logs = await rpc("eth_getLogs", [{
      address: FACTORY, topics: [TFRU_TOPIC],
      fromBlock: "0x" + from.toString(16), toBlock: "0x" + to.toString(16),
    }]);
    for (const l of logs) {
      const target = "0x" + l.topics[1].slice(-40);
      const roleId = BigInt(l.topics[2]).toString();
      const selector = "0x" + l.data.slice(2, 10); // bytes4, left-aligned in the data word
      const key = `${target}-${selector}`;
      const block = Number(BigInt(l.blockNumber));
      const logIndex = Number(BigInt(l.logIndex));
      const prev = latest.get(key);
      if (!prev || block > prev.block || (block === prev.block && logIndex > prev.logIndex)) {
        latest.set(key, { target, selector, roleId, block, logIndex });
      }
    }
    from = to + 1;
  } catch (e) {
    if (step > 1000) { step = Math.floor(step / 2); continue; }
    throw e;
  }
}

const bindings = [...latest.values()].sort((a, b) => a.target.localeCompare(b.target) || a.selector.localeCompare(b.selector));
console.error(`[bindings] ${bindings.length} current (target, selector) -> role bindings`);

// subgraph-shaped targetFunctions (so a mock/consumer can serve them directly)
const targetFunctions = bindings.map((b) => ({
  id: `${b.target}-${b.selector}`,
  selector: b.selector,
  role: { id: b.roleId },
  target: { id: b.target },
}));

mkdirSync(join(root, "dumps"), { recursive: true });
writeFileSync(
  join(root, "dumps", `target-functions.${chainId}.json`),
  JSON.stringify({ chainId: Number(chainId), factory: FACTORY, atBlock: head, targetFunctions }, null, 2) + "\n",
);

// human-readable md grouped by target
const byTarget = new Map();
for (const b of bindings) {
  if (!byTarget.has(b.target)) byTarget.set(b.target, []);
  byTarget.get(b.target).push(b);
}
let md = `# Function bindings — chain ${chainId} (on-chain read @ block ${head})\n\nFactory \`${FACTORY}\` · ${bindings.length} bindings across ${byTarget.size} contracts\n`;
for (const [target, rows] of [...byTarget.entries()].sort((a, b) => (targetByAddr.get(a[0])?.name ?? a[0]).localeCompare(targetByAddr.get(b[0])?.name ?? b[0]))) {
  const ti = targetByAddr.get(target);
  md += `\n## ${ti?.name ?? target} ${ti ? `(${ti.type})` : ""}\n\n| function | selector | role |\n|---|---|---|\n`;
  for (const b of rows) md += `| ${fnName(b.selector)} | ${b.selector} | ${roleName(b.roleId)} |\n`;
}
writeFileSync(join(root, "dumps", `target-functions.${chainId}.md`), md);

console.error(`[bindings] wrote dumps/target-functions.${chainId}.json (+ .md)`);
