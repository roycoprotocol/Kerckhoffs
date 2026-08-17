#!/usr/bin/env node
// Dump the CURRENT role distribution by reading the AccessManager directly over JSON-RPC.
// Complements dump-roles.mjs (which reads a synced subgraph); this needs only an RPC and is always
// current. Discovers every holder via a RoleGranted log scan, then verifies present membership with
// hasRole (so revoked holders drop out).
//
// Usage: MAINNET_RPC_URL=... node scripts/dump-roles-onchain.mjs [rpcUrl] [chainId] [factory]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const RPC = process.argv[2] || process.env.MAINNET_RPC_URL;
const chainId = process.argv[3] || "1";
const FACTORY = (process.argv[4] || "0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C").toLowerCase();
if (!RPC) { console.error("no RPC url (arg or MAINNET_RPC_URL)"); process.exit(1); }

// Selectors / topics (from `cast sig` / `cast keccak`)
const SEL = { admin: "0x530dd456", guardian: "0x0b0a93ba", grantDelay: "0x12be8727", hasRole: "0xd1f856ee" };
const ROLE_GRANTED_TOPIC = "0xf98448b987f1428e0e230e1f3c6e2ce15b5693eaf31827fbd0b1ec4b424ae7cf";
// Factory creation block per chain (see app/subgraph/config/<chainId>.json)
const CREATION_BLOCK = { "1": 24650849, "43114": 80312789, "42161": 441493793, "8453": 48111449 };
// Day RoycoAccessManager (0x87aE…B12e) creation blocks — used when the factory arg is the Day AM.
const DAY_AM = "0x87aed46566cb28c8375cfcc9971090882a0fb12e";
const DAY_CREATION_BLOCK = { "1": 25734830, "42161": 493570035, "8453": 49849492 };
const isDay = FACTORY === DAY_AM;
const suffix = isDay ? ".day" : "";

let names = { roles: {}, actors: {} };
try { names = JSON.parse(readFileSync(join(root, "..", "metadata", "role-names.json"), "utf8")); } catch {}
const roleName = (id) => names.roles[id] || `role_${id}`;
const actorName = (a) => names.actors[(a || "").toLowerCase()] || null;

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
const pad = (h) => h.replace(/^0x/, "").padStart(64, "0");
const roleWord = (id) => pad(BigInt(id).toString(16));
const addrWord = (a) => pad(a.toLowerCase().replace(/^0x/, ""));
const call = (data) => rpc("eth_call", [{ to: FACTORY, data }, "latest"]);

async function getRoleConfig(id) {
  const [admin, guardian, gd] = await Promise.all([
    call(SEL.admin + roleWord(id)), call(SEL.guardian + roleWord(id)), call(SEL.grantDelay + roleWord(id)),
  ]);
  return { adminRole: BigInt(admin).toString(), guardianRole: BigInt(guardian).toString(), grantDelay: Number(BigInt(gd)) };
}
async function hasRole(id, account) {
  const res = await call(SEL.hasRole + roleWord(id) + addrWord(account));
  const b = res.replace(/^0x/, "");
  return { isMember: BigInt("0x" + b.slice(0, 64)) === 1n, executionDelay: Number(BigInt("0x" + b.slice(64, 128))) };
}

// Discover every (roleId, account) ever granted, via a chunked RoleGranted log scan.
async function scanGrants() {
  const head = Number(BigInt(await rpc("eth_blockNumber", [])));
  const from0 = (isDay ? DAY_CREATION_BLOCK[chainId] : CREATION_BLOCK[chainId]) ?? 0;
  const pairs = new Map(); // "roleId-account" -> {roleId, account}
  let from = from0, step = 50000;
  while (from <= head) {
    const to = Math.min(from + step - 1, head);
    try {
      const logs = await rpc("eth_getLogs", [{
        address: FACTORY, topics: [ROLE_GRANTED_TOPIC],
        fromBlock: "0x" + from.toString(16), toBlock: "0x" + to.toString(16),
      }]);
      for (const l of logs) {
        const roleId = BigInt(l.topics[1]).toString();
        const account = "0x" + l.topics[2].slice(-40);
        pairs.set(`${roleId}-${account}`, { roleId, account });
      }
      from = to + 1;
    } catch (e) {
      if (step > 1000) { step = Math.floor(step / 2); continue; } // Ankr "range too large" -> shrink
      throw e;
    }
  }
  return { head, pairs: [...pairs.values()] };
}

console.error(`[onchain] scanning RoleGranted logs on ${FACTORY} ...`);
const { head, pairs } = await scanGrants();
console.error(`[onchain] ${pairs.length} distinct (role, account) grants found; verifying current membership...`);

// Group by role; verify each holder is still a member.
const byRole = new Map();
for (const { roleId, account } of pairs) {
  if (!byRole.has(roleId)) byRole.set(roleId, []);
  byRole.get(roleId).push(account);
}

const roles = [];
for (const [roleId, accounts] of byRole) {
  const cfg = await getRoleConfig(roleId);
  const holders = [];
  for (const account of accounts) {
    const hr = await hasRole(roleId, account);
    if (hr.isMember) holders.push({ address: account, actor: actorName(account), executionDelaySeconds: hr.executionDelay });
  }
  roles.push({
    id: roleId, name: roleName(roleId),
    adminRole: cfg.adminRole, adminRoleName: roleName(cfg.adminRole),
    guardianRole: cfg.guardianRole, guardianRoleName: roleName(cfg.guardianRole),
    grantDelaySeconds: cfg.grantDelay,
    holders: holders.sort((a, b) => (a.actor || "z").localeCompare(b.actor || "z")),
  });
}
roles.sort((a, b) => b.holders.length - a.holders.length || a.name.localeCompare(b.name));

const out = {
  chainId: Number(chainId), source: `onchain read via ${new URL(RPC).host}`, factory: FACTORY,
  atBlock: head, generatedRoles: roles.length, roles,
};
mkdirSync(join(root, "dumps"), { recursive: true });
const jsonPath = join(root, "dumps", `role-distribution.${chainId}${suffix}.json`);
writeFileSync(jsonPath, JSON.stringify(out, null, 2) + "\n");

const secs = (s) => (s === 0 ? "immediate" : s % 86400 === 0 ? `${s / 86400}d` : s % 3600 === 0 ? `${s / 3600}h` : `${s}s`);
let md = `# Role distribution — chain ${chainId} (on-chain read @ block ${head})\n\n`;
md += `Factory \`${FACTORY}\` · ${roles.length} roles with current holders\n\n`;
md += `| Role | id | admin | guardian | grantDelay | current holders |\n|---|---|---|---|---|---|\n`;
for (const r of roles) {
  const h = r.holders.map((x) => `${x.actor || x.address.slice(0, 10)}${x.executionDelaySeconds ? ` @${secs(x.executionDelaySeconds)}` : ""}`).join(", ") || "— (none active)";
  md += `| ${r.name} | ${r.id} | ${r.adminRoleName} | ${r.guardianRoleName} | ${secs(r.grantDelaySeconds)} | ${h} |\n`;
}
writeFileSync(join(root, "dumps", `role-distribution.${chainId}${suffix}.md`), md);

console.error(`[onchain] wrote ${jsonPath} (${roles.length} roles, block ${head})`);
console.log(md);
