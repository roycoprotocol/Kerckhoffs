import {
  assert,
  describe,
  test,
  clearStore,
  afterEach,
  newMockEvent,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  RoleGranted,
  RoleRevoked,
  RoleAdminChanged,
} from "../generated/AccessControl_srRoyUSDC/AccessControl";
import {
  handleNativeRoleGranted,
  handleNativeRoleRevoked,
  handleNativeRoleAdminChanged,
} from "../src/accessControl";

const VAULT = Address.fromString("0xcD9f5907F92818bC06c9Ad70217f089E190d2a32");
const ACCOUNT = Address.fromString("0x84d37A25e46029CE161111420E07cEb78880119e");
const SENDER = Address.fromString("0x7c405bbD131e42af506d14e752f2e59B19D49997");
const ROLE_HASH = Bytes.fromHexString(
  "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"
);
const ZERO_ROLE = Bytes.fromHexString(
  "0x0000000000000000000000000000000000000000000000000000000000000000"
);
const NEW_ADMIN = Bytes.fromHexString(
  "0x0000000000000000000000000000000000000000000000000000000000000001"
);

let _idx: i32 = 0;
function nextIdx(): BigInt {
  _idx = _idx + 1;
  return BigInt.fromI32(_idx);
}

function nativeGranted(role: Bytes, account: Address, sender: Address): RoleGranted {
  const e = changetype<RoleGranted>(newMockEvent());
  e.address = VAULT;
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)));
  e.parameters.push(new ethereum.EventParam("account", ethereum.Value.fromAddress(account)));
  e.parameters.push(new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)));
  return e;
}

function nativeRevoked(role: Bytes, account: Address, sender: Address): RoleRevoked {
  const e = changetype<RoleRevoked>(newMockEvent());
  e.address = VAULT;
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)));
  e.parameters.push(new ethereum.EventParam("account", ethereum.Value.fromAddress(account)));
  e.parameters.push(new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)));
  return e;
}

function nativeAdminChanged(role: Bytes, prev: Bytes, next: Bytes): RoleAdminChanged {
  const e = changetype<RoleAdminChanged>(newMockEvent());
  e.address = VAULT;
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)));
  e.parameters.push(new ethereum.EventParam("previousAdminRole", ethereum.Value.fromFixedBytes(prev)));
  e.parameters.push(new ethereum.EventParam("newAdminRole", ethereum.Value.fromFixedBytes(next)));
  return e;
}

describe("Native AccessControl mappings", () => {
  afterEach(() => {
    clearStore();
  });

  test("native grant captures member + sender", () => {
    handleNativeRoleGranted(nativeGranted(ROLE_HASH, ACCOUNT, SENDER));
    const roleId = VAULT.toHexString() + "-" + ROLE_HASH.toHexString();
    const mid = roleId + "-" + ACCOUNT.toHexString();
    assert.fieldEquals("NativeRoleMember", mid, "active", "true");
    assert.entityCount("NativeRoleEvent", 1);
    assert.entityCount("NativeRole", 1);
    assert.entityCount("Account", 1);
  });

  test("native revoke deactivates member", () => {
    handleNativeRoleGranted(nativeGranted(ROLE_HASH, ACCOUNT, SENDER));
    handleNativeRoleRevoked(nativeRevoked(ROLE_HASH, ACCOUNT, SENDER));
    const roleId = VAULT.toHexString() + "-" + ROLE_HASH.toHexString();
    const mid = roleId + "-" + ACCOUNT.toHexString();
    assert.fieldEquals("NativeRoleMember", mid, "active", "false");
  });

  test("native admin change updates adminRoleHash", () => {
    handleNativeRoleAdminChanged(nativeAdminChanged(ROLE_HASH, ZERO_ROLE, NEW_ADMIN));
    const roleId = VAULT.toHexString() + "-" + ROLE_HASH.toHexString();
    assert.fieldEquals("NativeRole", roleId, "adminRoleHash", NEW_ADMIN.toHexString());
  });
});
