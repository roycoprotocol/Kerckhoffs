import {
  assert,
  describe,
  test,
  clearStore,
  beforeEach,
  afterEach,
  newMockEvent,
  createMockedFunction,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  RoleGranted,
  RoleRevoked,
  RoleAdminChanged,
  RoleGuardianChanged,
  RoleGrantDelayChanged,
  TargetFunctionRoleUpdated,
  TargetClosed,
  TargetAdminDelayUpdated,
  OperationScheduled,
  OperationExecuted,
  OperationCanceled,
} from "../generated/AccessManager/AccessManager";
import { RoleMember } from "../generated/schema";
import {
  handleRoleGranted,
  handleRoleRevoked,
  handleRoleAdminChanged,
  handleRoleGuardianChanged,
  handleRoleGrantDelayChanged,
  handleTargetFunctionRoleUpdated,
  handleTargetClosed,
  handleTargetAdminDelayUpdated,
  handleOperationScheduled,
  handleOperationExecuted,
  handleOperationCanceled,
} from "../src/accessManager";

// Default address that newMockEvent() stamps as event.address (the AccessManager).
const MANAGER = Address.fromString("0xA16081F360e3847006dB660bae1c6d1b2e17eC2A");
const ACCOUNT = Address.fromString("0x84d37A25e46029CE161111420E07cEb78880119e");
const TARGET = Address.fromString("0x0aE0978B868804929fd4C06B3B22D9197B8cd3c6");
const ROLE = BigInt.fromI32(42);
const OP_ID = Bytes.fromHexString(
  "0x1111111111111111111111111111111111111111111111111111111111111111"
);
const SELECTOR = Bytes.fromHexString("0x8456cb59"); // pause()

// newMockEvent() reuses the same tx hash + logIndex for every event, which would collide our
// "{txHash}-{logIndex}" RoleEvent ids. Stamp a unique logIndex per constructed event.
let _idx: i32 = 0;
function nextIdx(): BigInt {
  _idx = _idx + 1;
  return BigInt.fromI32(_idx);
}

function mockManagerConfig(): void {
  createMockedFunction(MANAGER, "expiration", "expiration():(uint32)").returns([
    ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(604800)),
  ]);
  createMockedFunction(MANAGER, "minSetback", "minSetback():(uint32)").returns([
    ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(432000)),
  ]);
}

function roleGranted(
  roleId: BigInt,
  account: Address,
  delay: BigInt,
  since: BigInt,
  newMember: boolean
): RoleGranted {
  const e = changetype<RoleGranted>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  e.parameters.push(new ethereum.EventParam("account", ethereum.Value.fromAddress(account)));
  e.parameters.push(new ethereum.EventParam("delay", ethereum.Value.fromUnsignedBigInt(delay)));
  e.parameters.push(new ethereum.EventParam("since", ethereum.Value.fromUnsignedBigInt(since)));
  e.parameters.push(new ethereum.EventParam("newMember", ethereum.Value.fromBoolean(newMember)));
  return e;
}

function roleRevoked(roleId: BigInt, account: Address): RoleRevoked {
  const e = changetype<RoleRevoked>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  e.parameters.push(new ethereum.EventParam("account", ethereum.Value.fromAddress(account)));
  return e;
}

function roleAdminChanged(roleId: BigInt, admin: BigInt): RoleAdminChanged {
  const e = changetype<RoleAdminChanged>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  e.parameters.push(new ethereum.EventParam("admin", ethereum.Value.fromUnsignedBigInt(admin)));
  return e;
}

function roleGuardianChanged(roleId: BigInt, guardian: BigInt): RoleGuardianChanged {
  const e = changetype<RoleGuardianChanged>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  e.parameters.push(new ethereum.EventParam("guardian", ethereum.Value.fromUnsignedBigInt(guardian)));
  return e;
}

function roleGrantDelayChanged(roleId: BigInt, delay: BigInt, since: BigInt): RoleGrantDelayChanged {
  const e = changetype<RoleGrantDelayChanged>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  e.parameters.push(new ethereum.EventParam("delay", ethereum.Value.fromUnsignedBigInt(delay)));
  e.parameters.push(new ethereum.EventParam("since", ethereum.Value.fromUnsignedBigInt(since)));
  return e;
}

function targetFunctionRoleUpdated(
  target: Address,
  selector: Bytes,
  roleId: BigInt
): TargetFunctionRoleUpdated {
  const e = changetype<TargetFunctionRoleUpdated>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("target", ethereum.Value.fromAddress(target)));
  e.parameters.push(new ethereum.EventParam("selector", ethereum.Value.fromFixedBytes(selector)));
  e.parameters.push(new ethereum.EventParam("roleId", ethereum.Value.fromUnsignedBigInt(roleId)));
  return e;
}

function targetClosed(target: Address, closed: boolean): TargetClosed {
  const e = changetype<TargetClosed>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("target", ethereum.Value.fromAddress(target)));
  e.parameters.push(new ethereum.EventParam("closed", ethereum.Value.fromBoolean(closed)));
  return e;
}

function targetAdminDelayUpdated(target: Address, delay: BigInt, since: BigInt): TargetAdminDelayUpdated {
  const e = changetype<TargetAdminDelayUpdated>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("target", ethereum.Value.fromAddress(target)));
  e.parameters.push(new ethereum.EventParam("delay", ethereum.Value.fromUnsignedBigInt(delay)));
  e.parameters.push(new ethereum.EventParam("since", ethereum.Value.fromUnsignedBigInt(since)));
  return e;
}

function operationScheduled(
  operationId: Bytes,
  nonce: BigInt,
  schedule: BigInt,
  caller: Address,
  target: Address,
  data: Bytes
): OperationScheduled {
  const e = changetype<OperationScheduled>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("operationId", ethereum.Value.fromFixedBytes(operationId)));
  e.parameters.push(new ethereum.EventParam("nonce", ethereum.Value.fromUnsignedBigInt(nonce)));
  e.parameters.push(new ethereum.EventParam("schedule", ethereum.Value.fromUnsignedBigInt(schedule)));
  e.parameters.push(new ethereum.EventParam("caller", ethereum.Value.fromAddress(caller)));
  e.parameters.push(new ethereum.EventParam("target", ethereum.Value.fromAddress(target)));
  e.parameters.push(new ethereum.EventParam("data", ethereum.Value.fromBytes(data)));
  return e;
}

function operationExecuted(operationId: Bytes, nonce: BigInt): OperationExecuted {
  const e = changetype<OperationExecuted>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("operationId", ethereum.Value.fromFixedBytes(operationId)));
  e.parameters.push(new ethereum.EventParam("nonce", ethereum.Value.fromUnsignedBigInt(nonce)));
  return e;
}

function operationCanceled(operationId: Bytes, nonce: BigInt): OperationCanceled {
  const e = changetype<OperationCanceled>(newMockEvent());
  e.logIndex = nextIdx();
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("operationId", ethereum.Value.fromFixedBytes(operationId)));
  e.parameters.push(new ethereum.EventParam("nonce", ethereum.Value.fromUnsignedBigInt(nonce)));
  return e;
}

describe("AccessManager mappings", () => {
  beforeEach(() => {
    mockManagerConfig();
  });
  afterEach(() => {
    clearStore();
  });

  test("grant new member", () => {
    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(0), BigInt.fromI32(100), true));
    const mid = "42-" + ACCOUNT.toHexString();
    assert.fieldEquals("RoleMember", mid, "active", "true");
    assert.fieldEquals("RoleMember", mid, "executionDelay", "0");
    // grantTx is set for a new member.
    const m = RoleMember.load(mid)!;
    assert.assertTrue(m.grantTx !== null);
    assert.entityCount("RoleEvent", 1);
    assert.entityCount("Account", 1);
    assert.entityCount("Manager", 1);
  });

  test("execution-delay change (newMember=false) keeps grantedAt", () => {
    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(0), BigInt.fromI32(100), true));
    const mid = "42-" + ACCOUNT.toHexString();
    const grantedAtBefore = RoleMember.load(mid)!.grantedAt!;

    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(216000), BigInt.fromI32(500), false));
    const m = RoleMember.load(mid)!;
    assert.bigIntEquals(grantedAtBefore, m.grantedAt!);
    assert.stringEquals("216000", m.executionDelay.toString());
    assert.stringEquals("500", m.pendingDelayEffective!.toString());
    assert.entityCount("RoleEvent", 2);
  });

  test("revoke deactivates member and retains row", () => {
    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(0), BigInt.fromI32(100), true));
    handleRoleRevoked(roleRevoked(ROLE, ACCOUNT));
    const mid = "42-" + ACCOUNT.toHexString();
    assert.fieldEquals("RoleMember", mid, "active", "false");
    assert.fieldEquals("RoleMember", mid, "executionDelay", "0");
    const m = RoleMember.load(mid)!;
    assert.assertTrue(m.revokedAt !== null);
    assert.entityCount("RoleMember", 1);
  });

  test("admin / guardian / grant-delay changes record old->new", () => {
    handleRoleAdminChanged(roleAdminChanged(ROLE, BigInt.fromI32(7)));
    assert.fieldEquals("Role", "42", "adminRole", "7");
    handleRoleGuardianChanged(roleGuardianChanged(ROLE, BigInt.fromI32(9)));
    assert.fieldEquals("Role", "42", "guardianRole", "9");
    handleRoleGrantDelayChanged(roleGrantDelayChanged(ROLE, BigInt.fromI32(3600), BigInt.fromI32(1)));
    assert.fieldEquals("Role", "42", "grantDelay", "3600");
    assert.entityCount("RoleEvent", 3);
  });

  test("target function binding upserts in place", () => {
    handleTargetFunctionRoleUpdated(targetFunctionRoleUpdated(TARGET, SELECTOR, ROLE));
    const id = TARGET.toHexString() + "-" + SELECTOR.toHexString();
    assert.fieldEquals("TargetFunction", id, "role", "42");
    // Re-bind to a different role — must update the same row, not create a second.
    handleTargetFunctionRoleUpdated(targetFunctionRoleUpdated(TARGET, SELECTOR, BigInt.fromI32(99)));
    assert.fieldEquals("TargetFunction", id, "role", "99");
    assert.entityCount("TargetFunction", 1);
  });

  test("target closed / adminDelay set on TargetContract", () => {
    handleTargetClosed(targetClosed(TARGET, true));
    assert.fieldEquals("TargetContract", TARGET.toHexString(), "closed", "true");
    handleTargetAdminDelayUpdated(targetAdminDelayUpdated(TARGET, BigInt.fromI32(216000), BigInt.fromI32(1)));
    assert.fieldEquals("TargetContract", TARGET.toHexString(), "adminDelay", "216000");
  });

  test("operation lifecycle scheduled -> executed", () => {
    handleOperationScheduled(
      operationScheduled(OP_ID, BigInt.fromI32(1), BigInt.fromI32(1000), ACCOUNT, TARGET, Bytes.fromHexString("0xdeadbeef"))
    );
    const id = OP_ID.toHexString() + "-1";
    assert.fieldEquals("Operation", id, "status", "Scheduled");
    handleOperationExecuted(operationExecuted(OP_ID, BigInt.fromI32(1)));
    assert.fieldEquals("Operation", id, "status", "Executed");
    assert.fieldEquals("Operation", id, "nonce", "1");
  });

  test("operation lifecycle scheduled -> canceled", () => {
    handleOperationScheduled(
      operationScheduled(OP_ID, BigInt.fromI32(2), BigInt.fromI32(1000), ACCOUNT, TARGET, Bytes.fromHexString("0xbeef"))
    );
    const id = OP_ID.toHexString() + "-2";
    handleOperationCanceled(operationCanceled(OP_ID, BigInt.fromI32(2)));
    assert.fieldEquals("Operation", id, "status", "Canceled");
  });

  test("deterministic ids: same (role, account) upserts one member", () => {
    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(0), BigInt.fromI32(100), true));
    handleRoleGranted(roleGranted(ROLE, ACCOUNT, BigInt.fromI32(10), BigInt.fromI32(200), false));
    // Two grants for the same (role, account) => still exactly one RoleMember row.
    assert.entityCount("RoleMember", 1);
    assert.fieldEquals("RoleMember", "42-" + ACCOUNT.toHexString(), "executionDelay", "10");
  });
});
