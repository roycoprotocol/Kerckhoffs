#!/usr/bin/env node
/**
 * Offline GraphQL stand-in for the deployed subgraph, backed by the on-chain dumps in
 * `app/subgraph/dumps/`. Lets the dashboard be run and verified end-to-end without a synced
 * graph-node (local sync OOMs under amd64 emulation) or a Goldsky deployment.
 *
 * Serves exactly the query set in `app/dashboard/src/lib/subgraph.ts` — dispatch is by operation
 * shape, not a real GraphQL engine, so adding a fetcher there means adding a branch here.
 *
 * Dual-AM aware: dumps are loaded per manager kind and every AM-scoped query is filtered by its
 * `$am` variable (the lowercased manager address). Manager addresses come from
 * `app/metadata/catalog.<chainId>.json` managers[], so entity ids match the real subgraph's
 * "{am}-…" keying. `markets` is always empty (no Day markets dump yet); `roleEvents` and
 * `operations` are always empty too — those need the real subgraph.
 *
 * Usage:
 *   PORT=8111 node app/subgraph/scripts/mock-server.mjs \
 *     --dawn dumps/role-distribution.1.json [dumps/target-functions.1.json] \
 *     [--day dumps/role-distribution.1.day.json [dumps/target-functions.1.day.json]]
 *
 * Back-compat: bare positional args are treated as `--dawn <roles> [<fns>]`.
 */
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

// ── CLI ──────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const paths = { dawn: [], day: [] };
let bucket = "dawn";
for (const a of args) {
  if (a === "--dawn") bucket = "dawn";
  else if (a === "--day") bucket = "day";
  else paths[bucket].push(a);
}
if (paths.dawn.length === 0 && paths.day.length === 0) {
  console.error(
    "usage: PORT=<p> mock-server.mjs --dawn <role-distribution.json> [<target-functions.json>] [--day <roles> [<fns>]]",
  );
  process.exit(1);
}

// ── load dumps per manager kind ──────────────────────────────────────────────

function loadKind(kind) {
  const [rolesPath, fnsPath] = paths[kind];
  if (!rolesPath) return null;
  const dump = JSON.parse(readFileSync(rolesPath, "utf8"));
  const fnDump = fnsPath ? JSON.parse(readFileSync(fnsPath, "utf8")) : { targetFunctions: [] };
  return { kind, dump, fns: fnDump.targetFunctions ?? [], atBlock: Math.max(dump.atBlock ?? 0, fnDump.atBlock ?? 0) };
}
const kinds = [loadKind("dawn"), loadKind("day")].filter(Boolean);
const chainId = kinds[0].dump.chainId;

// Manager addresses from the catalog so mock entity ids match the real "{am}-…" keying.
const catalog = JSON.parse(readFileSync(join(here, "..", "..", "metadata", `catalog.${chainId}.json`), "utf8"));
const managerByKind = new Map((catalog.managers ?? []).map((m) => [m.kind, m.address.toLowerCase()]));

// ── dump → subgraph entity shapes, per manager ───────────────────────────────

const managers = []; // { id, kind, roles, roleById, targets, fns }
const accounts = new Map(); // global: address -> { id, roles: [] }

for (const k of kinds) {
  const am = managerByKind.get(k.kind);
  if (!am) {
    console.error(`mock-server: catalog.${chainId}.json has no "${k.kind}" manager — skipping that dump`);
    continue;
  }
  // Old dump shape {role:{id}, target:{id}} -> new query shape {role:{roleId}, target:{address}}.
  const fns = k.fns.map((f) => ({
    id: `${am}-${f.target.id.toLowerCase()}-${f.selector}`,
    selector: f.selector,
    role: { roleId: f.role.id },
    target: { address: f.target.id.toLowerCase() },
  }));
  const fnsByRole = new Map();
  for (const f of fns) {
    if (!fnsByRole.has(f.role.roleId)) fnsByRole.set(f.role.roleId, []);
    fnsByRole.get(f.role.roleId).push(f);
  }

  // `onChainLabel` is null on purpose: no RoleLabel events have ever been emitted on any chain
  // (the step-7 label backfill never landed), so names must come from the catalog, not the chain.
  const roles = k.dump.roles.map((r) => ({
    id: `${am}-${r.id}`,
    roleId: r.id,
    onChainLabel: null,
    adminRole: r.adminRole,
    guardianRole: r.guardianRole,
    grantDelay: String(r.grantDelaySeconds ?? 0),
    members: (r.holders ?? []).map((h) => ({
      account: { id: h.address.toLowerCase() },
      executionDelay: String(h.executionDelaySeconds ?? 0),
      active: true,
      grantedAt: null, // dumps are a point-in-time read, not an event log
    })),
    functions: fnsByRole.get(r.id) ?? [],
  }));

  // Targets derived from the selector bindings; `closed`/`adminDelay`/`everConfigured` aren't in
  // the dump, so they report defaults. Drift depending on those needs the real subgraph.
  const targets = new Map();
  for (const f of fns) {
    const addr = f.target.address;
    const id = `${am}-${addr}`;
    if (!targets.has(id)) {
      targets.set(id, { id, address: addr, closed: false, adminDelay: "0", everConfigured: false, functions: [] });
    }
    targets.get(id).functions.push({ selector: f.selector, role: { roleId: f.role.roleId } });
  }

  for (const r of roles) {
    for (const m of r.members) {
      const id = m.account.id;
      if (!accounts.has(id)) accounts.set(id, { id, roles: [] });
      accounts.get(id).roles.push({
        role: { roleId: r.roleId, manager: { id: am, kind: k.kind } },
        executionDelay: m.executionDelay,
        active: true,
      });
    }
  }

  managers.push({ id: am, kind: k.kind, roles, roleById: new Map(roles.map((r) => [r.id, r])), targets, fns });
}

const byAm = new Map(managers.map((m) => [m.id, m]));
const atBlock = Math.max(...kinds.map((k) => k.atBlock));

// ── dispatch ─────────────────────────────────────────────────────────────────

function resolve(query, vars) {
  const am = vars.am ? String(vars.am).toLowerCase() : null;
  if (query.includes("_meta")) return { _meta: { block: { number: atBlock }, hasIndexingErrors: false } };
  if (query.includes("query Role(")) {
    const mgr = managers.find((m) => String(vars.id).startsWith(`${m.id}-`));
    return { role: mgr?.roleById.get(vars.id) ?? null, roleEvents: [] };
  }
  if (query.includes("query ManagedTargets(")) {
    return { targetContracts: [...(byAm.get(am)?.targets.values() ?? [])].map((t) => ({ address: t.address })) };
  }
  if (query.includes("query Target(")) {
    const mgr = managers.find((m) => String(vars.id).startsWith(`${m.id}-`));
    return { targetContract: mgr?.targets.get(String(vars.id).toLowerCase()) ?? null };
  }
  if (query.includes("query Account(")) return { account: accounts.get(String(vars.id).toLowerCase()) ?? null };
  if (query.includes("targetFunctions(")) return { targetFunctions: byAm.get(am)?.fns ?? [] };
  if (query.includes("operations(")) return { operations: [] };
  if (query.includes("markets(")) return { markets: [] };
  if (query.includes("managers")) {
    return { managers: managers.map((m) => ({ id: m.id, kind: m.kind, expiration: "604800", minSetback: "0" })) };
  }
  if (query.includes("roles(")) return { roles: byAm.get(am)?.roles ?? [] };
  return null; // unknown query → surface as a GraphQL error rather than silently empty data
}

createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    let payload;
    try {
      const { query, variables } = JSON.parse(body);
      const data = resolve(query, variables ?? {});
      payload = data ? { data } : { errors: [{ message: `mock-server: unhandled query: ${query.slice(0, 120)}` }] };
    } catch (e) {
      payload = { errors: [{ message: `mock-server: ${e.message}` }] };
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(payload));
  });
}).listen(process.env.PORT ?? 8111, () => {
  const desc = managers.map((m) => `${m.kind}: ${m.roles.length} roles, ${m.fns.length} bindings`).join(" · ");
  console.log(`mock subgraph chain ${chainId} on :${process.env.PORT ?? 8111} — ${desc} @ block ${atBlock}`);
});
