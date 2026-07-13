import { BigInt, Bytes, Address, ethereum } from "@graphprotocol/graph-ts";
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

export function eventId(event: ethereum.Event): string {
  return event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
}

export function roleMemberId(roleId: BigInt, account: Address): string {
  return roleId.toString() + "-" + account.toHexString();
}

export function targetFnId(target: Address, selector: Bytes): string {
  return target.toHexString() + "-" + selector.toHexString();
}

// ── loadOrCreate helpers ───────────────────────────────────────────────────────

export function loadOrCreateRole(roleId: BigInt): Role {
  const id = roleId.toString();
  let role = Role.load(id);
  if (role == null) {
    role = new Role(id);
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

export function loadOrCreateTarget(target: Address): TargetContract {
  const id = target.toHexString();
  let t = TargetContract.load(id);
  if (t == null) {
    t = new TargetContract(id);
    t.address = target;
    t.closed = false;
    t.adminDelay = BigInt.zero();
    t.save();
  }
  return t;
}

// The Manager singleton has no dedicated event; lazily create it on the first AM event,
// reading expiration()/minSetback() from the contract once.
export function getOrInitManager(event: ethereum.Event): Manager {
  // Singleton per subgraph — id is stable ("manager"); one deployment == one chain.
  let mgr = Manager.load("manager");
  if (mgr == null) {
    mgr = new Manager("manager");
    mgr.address = event.address;
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
  event: ethereum.Event,
  roleId: BigInt,
  account: Bytes | null,
  kind: string,
  oldValue: string | null,
  newValue: string | null,
  effectiveAt: BigInt | null
): void {
  const e = new RoleEvent(eventId(event));
  e.role = roleId.toString();
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
