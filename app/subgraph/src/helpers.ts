import { BigInt, Bytes, Address, ethereum, dataSource } from "@graphprotocol/graph-ts";
import { AccessManager } from "../generated/AccessManager/AccessManager";
import {
  Manager,
  Role,
  RoleMember,
  RoleEvent,
  TargetContract,
  TargetFunction,
  Account,
} from "../generated/schema";

// OZ AccessManager built-in role ids.
export const ADMIN_ROLE: BigInt = BigInt.zero();
// type(uint64).max
export const PUBLIC_ROLE: BigInt = BigInt.fromString("18446744073709551615");

// ── ID builders (see docs/spec/main.md §1 keying conventions) ──────────────────
//
// Every AM-scoped id is prefixed with the lowercased manager address: the Dawn and Day AMs derive
// role ids from the same keccak tag strings, so unprefixed ids would silently merge the two AMs.

export function managerId(event: ethereum.Event): string {
  return event.address.toHexString();
}

export function eventId(event: ethereum.Event): string {
  return event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
}

export function roleEntityId(am: string, roleId: BigInt): string {
  return am + "-" + roleId.toString();
}

export function roleMemberId(am: string, roleId: BigInt, account: Address): string {
  return am + "-" + roleId.toString() + "-" + account.toHexString();
}

export function targetEntityId(am: string, target: Address): string {
  return am + "-" + target.toHexString();
}

export function targetFnId(am: string, target: Address, selector: Bytes): string {
  return am + "-" + target.toHexString() + "-" + selector.toHexString();
}

export function operationRowId(am: string, operationId: string, nonce: BigInt): string {
  return am + "-" + operationId + "-" + nonce.toString();
}

// ── loadOrCreate helpers ───────────────────────────────────────────────────────

export function loadOrCreateRole(am: string, roleId: BigInt): Role {
  const id = roleEntityId(am, roleId);
  let role = Role.load(id);
  if (role == null) {
    role = new Role(id);
    role.manager = am;
    role.roleId = roleId;
    role.adminRole = ADMIN_ROLE; // every role's admin defaults to ADMIN_ROLE in OZ AM
    role.guardianRole = ADMIN_ROLE;
    role.grantDelay = BigInt.zero();
    role.save();
  }
  return role;
}

export function loadOrCreateAccount(account: Address): Account {
  const id = account.toHexString();
  let a = Account.load(id);
  if (a == null) {
    a = new Account(id);
    a.save();
  }
  return a;
}

export function loadOrCreateTarget(am: string, target: Address): TargetContract {
  const id = targetEntityId(am, target);
  let t = TargetContract.load(id);
  if (t == null) {
    t = new TargetContract(id);
    t.manager = am;
    t.address = target;
    t.closed = false;
    t.adminDelay = BigInt.zero();
    t.everConfigured = false;
    t.save();
  }
  return t;
}

// Managers have no dedicated creation event; lazily create the row on the first AM event, reading
// expiration()/minSetback() from the contract once. Keyed by event.address — one row per AM.
export function getOrInitManager(event: ethereum.Event): Manager {
  const id = managerId(event);
  let mgr = Manager.load(id);
  if (mgr == null) {
    mgr = new Manager(id);
    mgr.address = event.address;
    // "dawn" | "day" from the data-source context set in subgraph.template.yaml; default to
    // "dawn" when absent (matchstick mock events carry no context).
    const ctx = dataSource.context();
    const kind = ctx.isSet("kind") ? ctx.getString("kind") : "dawn";
    mgr.kind = kind;
    const c = AccessManager.bind(event.address);
    const exp = c.try_expiration();
    mgr.expiration = exp.reverted ? BigInt.zero() : exp.value;
    const setback = c.try_minSetback();
    mgr.minSetback = setback.reverted ? BigInt.zero() : setback.value;
    mgr.save();
  }
  return mgr;
}

// Append an immutable RoleEvent row.
export function appendRoleEvent(
  am: string,
  event: ethereum.Event,
  roleId: BigInt,
  account: Bytes | null,
  kind: string,
  oldValue: string | null,
  newValue: string | null,
  effectiveAt: BigInt | null
): void {
  const e = new RoleEvent(eventId(event));
  e.manager = am;
  e.role = roleEntityId(am, roleId);
  if (account !== null) {
    e.account = (account as Bytes).toHexString();
  }
  e.kind = kind;
  e.oldValue = oldValue;
  e.newValue = newValue;
  e.effectiveAt = effectiveAt;
  e.blockNumber = event.block.number;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}
