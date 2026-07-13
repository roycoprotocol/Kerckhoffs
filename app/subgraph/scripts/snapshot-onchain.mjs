#!/usr/bin/env node
// Fast per-chain role snapshot: reads each role's config (admin/guardian/grantDelay) and checks the
// KNOWN actors (from the catalog) via hasRole — no log scan, so it's fast on high-block chains where
// dump-roles-onchain.mjs's full holder discovery is slow. Misses non-actor holders (e.g. individual
// LPs), which is an acceptable tradeoff for the non-mainnet chains.
//
// Usage: node scripts/snapshot-onchain.mjs <rpcUrl> <chainId> <factory>
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const RPC = process.argv[2];
const chainId = process.argv[3];
const FACTORY = (process.argv[4] || "0x7cC6fB28eC7b5e7afC3cB3986141797ffc27253C").toLowerCase();
if (!RPC || !chainId) { console.error("usage: snapshot-onchain.mjs <rpc> <chainId> <factory>"); process.exit(1); }

const SEL = { admin: "0x530dd456", guardian: "0x0b0a93ba", grantDelay: "0x12be8727", hasRole: "0xd1f856ee" };
const names = JSON.parse(readFileSync(join(root, "..", "metadata", "role-names.json"), "utf8"));
const catalog = JSON.parse(readFileSync(join(root, "..", "metadata", `catalog.${chainId}.json`), "utf8"));
const roleName = (id) => (id === "0" ? "ADMIN_ROLE" : names.roles[id] ?? `role_${id}`);
const actors = catalog.actors.filter((a) => a.address !== "0x0000000000000000000000000000000000000000");

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

const head = Number(BigInt(await rpc("eth_blockNumber", [])));
const roleIds = Object.keys(names.roles).filter((id) => id !== "18446744073709551615"); // skip PUBLIC
console.error(`[snapshot ${chainId}] ${roleIds.length} roles × ${actors.length} actors @ block ${head}`);

const roles = [];
for (const id of roleIds) {
  const [admin, guardian, gd] = await Promise.all([
    call(SEL.admin + roleWord(id)),
    call(SEL.guardian + roleWord(id)),
    call(SEL.grantDelay + roleWord(id)),
  ]);
  const holders = [];
  for (const a of actors) {
    const res = await call(SEL.hasRole + roleWord(id) + addrWord(a.address));
    const b = res.replace(/^0x/, "");
    if (BigInt("0x" + b.slice(0, 64)) === 1n) {
      holders.push({ address: a.address.toLowerCase(), actor: a.name, executionDelaySeconds: Number(BigInt("0x" + b.slice(64, 128))) });
    }
  }
  const adminId = BigInt(admin).toString();
  const guardianId = BigInt(guardian).toString();
  roles.push({
    id,
    name: roleName(id),
    adminRole: adminId,
    adminRoleName: roleName(adminId),
    guardianRole: guardianId,
    guardianRoleName: roleName(guardianId),
    grantDelaySeconds: Number(BigInt(gd)),
    holders,
  });
}

const withHolders = roles.filter((r) => r.holders.length > 0);
writeFileSync(
  join(root, "dumps", `role-distribution.${chainId}.json`),
  JSON.stringify({ chainId: Number(chainId), source: `onchain snapshot via ${new URL(RPC).host}`, factory: FACTORY, atBlock: head, roles: withHolders }, null, 2) + "\n",
);
console.error(`[snapshot ${chainId}] wrote dumps/role-distribution.${chainId}.json (${withHolders.length} roles with known holders)`);
