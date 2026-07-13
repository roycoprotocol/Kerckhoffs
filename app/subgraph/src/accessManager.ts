import { BigInt } from "@graphprotocol/graph-ts";
import {
  RoleGranted,
  RoleRevoked,
  RoleAdminChanged,
  RoleGuardianChanged,
  RoleGrantDelayChanged,
  RoleLabel,
  TargetFunctionRoleUpdated,
  TargetAdminDelayUpdated,
  TargetClosed,
  OperationScheduled,
  OperationExecuted,
  OperationCanceled,
} from "../generated/AccessManager/AccessManager";
import { RoleMember, TargetFunction, Operation } from "../generated/schema";
import {
  appendRoleEvent,
  getOrInitManager,
  loadOrCreateAccount,
  loadOrCreateRole,
  loadOrCreateTarget,
  roleMemberId,
  targetFnId,
} from "./helpers";

function operationRowId(operationId: string, nonce: BigInt): string {
  return operationId + "-" + nonce.toString();
}

export function handleRoleGranted(event: RoleGranted): void {
  getOrInitManager(event);
  const roleId = event.params.roleId;
  const account = event.params.account;
  const delay = event.params.delay; // uint32 -> BigInt
  const since = event.params.since; // uint48 -> BigInt
  const newMember = event.params.newMember;

  loadOrCreateRole(roleId);
  loadOrCreateAccount(account);

  const mid = roleMemberId(roleId, account);
  let m = RoleMember.load(mid);
  if (m == null) {
    m = new RoleMember(mid);
    m.role = roleId.toString();
    m.account = account.toHexString();
  }
  m.active = true;
  m.executionDelay = delay;
  // `newMember` disambiguates the dual semantics of this event (IAccessManager.sol:37-39):
  //   true  -> brand-new membership starting at `since`
  //   false -> an execution-delay change on an existing member, effective at `since`
  if (newMember) {
    m.grantedAt = event.block.timestamp;
    m.grantTx = event.transaction.hash;
  } else {
    m.pendingDelayEffective = since;
  }
  m.save();

  appendRoleEvent(
    event,
    roleId,
    account,
    newMember ? "Granted" : "ExecutionDelayChanged",
    null,
    delay.toString(),
    since
  );
}

export function handleRoleRevoked(event: RoleRevoked): void {
  getOrInitManager(event);
  const roleId = event.params.roleId;
  const account = event.params.account;

  loadOrCreateRole(roleId);
  loadOrCreateAccount(account);

  const mid = roleMemberId(roleId, account);
  let m = RoleMember.load(mid);
  if (m == null) {
    m = new RoleMember(mid);
    m.role = roleId.toString();
    m.account = account.toHexString();
    m.executionDelay = BigInt.zero();
  }
  m.active = false;
  m.revokedAt = event.block.timestamp;
  m.executionDelay = BigInt.zero();
  m.save();

  appendRoleEvent(event, roleId, account, "Revoked", null, null, null);
}

export function handleRoleAdminChanged(event: RoleAdminChanged): void {
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(roleId);
  const oldValue = role.adminRole.toString();
  role.adminRole = event.params.admin;
  role.save();
  appendRoleEvent(event, roleId, null, "AdminChanged", oldValue, event.params.admin.toString(), null);
}

export function handleRoleGuardianChanged(event: RoleGuardianChanged): void {
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(roleId);
  const oldValue = role.guardianRole.toString();
  role.guardianRole = event.params.guardian;
  role.save();
  appendRoleEvent(event, roleId, null, "GuardianChanged", oldValue, event.params.guardian.toString(), null);
}

export function handleRoleGrantDelayChanged(event: RoleGrantDelayChanged): void {
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(roleId);
  const oldValue = role.grantDelay.toString();
  role.grantDelay = event.params.delay;
  role.save();
  appendRoleEvent(
    event,
    roleId,
    null,
    "GrantDelayChanged",
    oldValue,
    event.params.delay.toString(),
    event.params.since
  );
}

export function handleRoleLabel(event: RoleLabel): void {
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(roleId);
  role.onChainLabel = event.params.label;
  role.save();
  appendRoleEvent(event, roleId, null, "Labeled", null, event.params.label, null);
}

export function handleTargetFunctionRoleUpdated(event: TargetFunctionRoleUpdated): void {
  const target = event.params.target;
  const selector = event.params.selector; // NOTE: non-indexed; read from event data
  const roleId = event.params.roleId;

  loadOrCreateTarget(target);
  loadOrCreateRole(roleId);

  const id = targetFnId(target, selector);
  let tf = TargetFunction.load(id);
  if (tf == null) {
    tf = new TargetFunction(id);
    tf.target = target.toHexString();
    tf.selector = selector;
  }
  tf.role = roleId.toString();
  tf.updatedAt = event.block.timestamp;
  tf.txHash = event.transaction.hash;
  tf.save();
}

export function handleTargetAdminDelayUpdated(event: TargetAdminDelayUpdated): void {
  const t = loadOrCreateTarget(event.params.target);
  t.adminDelay = event.params.delay;
  t.save();
}

export function handleTargetClosed(event: TargetClosed): void {
  const t = loadOrCreateTarget(event.params.target);
  t.closed = event.params.closed;
  t.save();
}

export function handleOperationScheduled(event: OperationScheduled): void {
  const opHash = event.params.operationId.toHexString();
  const id = operationRowId(opHash, event.params.nonce);
  let op = Operation.load(id);
  if (op == null) {
    op = new Operation(id);
  }
  op.operationId = event.params.operationId;
  op.nonce = event.params.nonce;
  op.caller = event.params.caller;
  op.target = event.params.target;
  op.data = event.params.data;
  op.schedule = event.params.schedule;
  op.status = "Scheduled";
  op.scheduledAt = event.block.timestamp;
  op.scheduleTx = event.transaction.hash;
  op.save();
}

export function handleOperationExecuted(event: OperationExecuted): void {
  const id = operationRowId(event.params.operationId.toHexString(), event.params.nonce);
  const op = Operation.load(id);
  if (op == null) {
    return;
  }
  op.status = "Executed";
  op.executedAt = event.block.timestamp;
  op.executeTx = event.transaction.hash;
  op.save();
}

export function handleOperationCanceled(event: OperationCanceled): void {
  const id = operationRowId(event.params.operationId.toHexString(), event.params.nonce);
  const op = Operation.load(id);
  if (op == null) {
    return;
  }
  op.status = "Canceled";
  op.canceledAt = event.block.timestamp;
  op.cancelTx = event.transaction.hash;
  op.save();
}
