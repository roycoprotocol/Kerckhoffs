import { Address, Bytes, ethereum } from "@graphprotocol/graph-ts";
// Both vault data sources (AccessControl_srRoyUSDC / _roywstETH) share the identical `AccessControl`
// ABI and these handlers, so the generated event classes are structurally identical across their
// per-data-source folders. Importing from one is intentional; if the first vault is renamed in
// config, update this import path.
import {
  RoleGranted,
  RoleRevoked,
  RoleAdminChanged,
} from "../generated/AccessControl_srRoyUSDC/AccessControl";
import { NativeRole, NativeRoleMember, NativeRoleEvent } from "../generated/schema";
import { eventId, loadOrCreateAccount } from "./helpers";

function nativeRoleId(vault: Address, roleHash: Bytes): string {
  return vault.toHexString() + "-" + roleHash.toHexString();
}

function nativeMemberId(vault: Address, roleHash: Bytes, account: Address): string {
  return vault.toHexString() + "-" + roleHash.toHexString() + "-" + account.toHexString();
}

function loadOrCreateNativeRole(vault: Address, roleHash: Bytes): NativeRole {
  const id = nativeRoleId(vault, roleHash);
  let r = NativeRole.load(id);
  if (r == null) {
    r = new NativeRole(id);
    r.vault = vault;
    r.roleHash = roleHash;
    // OZ AccessControl default admin is DEFAULT_ADMIN_ROLE (bytes32 zero) until RoleAdminChanged.
    r.adminRoleHash = Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
    r.save();
  }
  return r;
}

function appendNativeEvent(
  event: ethereum.Event,
  nativeRoleKey: string,
  account: Bytes,
  sender: Bytes,
  kind: string
): void {
  const e = new NativeRoleEvent(eventId(event));
  e.nativeRole = nativeRoleKey;
  e.account = account;
  e.sender = sender;
  e.kind = kind;
  e.blockNumber = event.block.number;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleNativeRoleGranted(event: RoleGranted): void {
  const vault = event.address;
  const roleHash = event.params.role;
  const account = event.params.account;

  const role = loadOrCreateNativeRole(vault, roleHash);
  loadOrCreateAccount(account);

  const mid = nativeMemberId(vault, roleHash, account);
  let m = NativeRoleMember.load(mid);
  if (m == null) {
    m = new NativeRoleMember(mid);
    m.nativeRole = role.id;
    m.account = account.toHexString();
  }
  m.active = true;
  m.grantedAt = event.block.timestamp;
  m.save();

  appendNativeEvent(event, role.id, account, event.params.sender, "Granted");
}

export function handleNativeRoleRevoked(event: RoleRevoked): void {
  const vault = event.address;
  const roleHash = event.params.role;
  const account = event.params.account;

  const role = loadOrCreateNativeRole(vault, roleHash);
  loadOrCreateAccount(account);

  const mid = nativeMemberId(vault, roleHash, account);
  let m = NativeRoleMember.load(mid);
  if (m == null) {
    m = new NativeRoleMember(mid);
    m.nativeRole = role.id;
    m.account = account.toHexString();
  }
  m.active = false;
  m.revokedAt = event.block.timestamp;
  m.save();

  appendNativeEvent(event, role.id, account, event.params.sender, "Revoked");
}

export function handleNativeRoleAdminChanged(event: RoleAdminChanged): void {
  const vault = event.address;
  const roleHash = event.params.role;
  const role = loadOrCreateNativeRole(vault, roleHash);
  role.adminRoleHash = event.params.newAdminRole;
  role.save();
}
