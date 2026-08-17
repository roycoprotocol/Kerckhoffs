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
  roleEntityId,
  roleMemberId,
  targetEntityId,
  targetFnId,
  operationRowId,
} from "./helpers";

// Shared by every AccessManager data source (Dawn RoycoFactory + Day RoycoAccessManager — the Day
// data source references this module via ./src/dayAccessManager.ts, which re-exports these
// handlers). Each handler resolves its Manager from event.address, so the same code indexes both
// AMs into disjoint, manager-prefixed entity rows.

// The Dawn factory IS the Dawn AM address, so its MarketDeployed handler rides this data source.
export { handleMarketDeployed } from "./dawnFactory";

export function handleRoleGranted(event: RoleGranted): void {
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const account = event.params.account;
  const delay = event.params.delay; // uint32 -> BigInt
  const since = event.params.since; // uint48 -> BigInt
  const newMember = event.params.newMember;

  loadOrCreateRole(am, roleId);
  loadOrCreateAccount(account);

  const mid = roleMemberId(am, roleId, account);
  let m = RoleMember.load(mid);
  if (m == null) {
    m = new RoleMember(mid);
    m.manager = am;
    m.role = roleEntityId(am, roleId);
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
    am,
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
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const account = event.params.account;

  loadOrCreateRole(am, roleId);
  loadOrCreateAccount(account);

  const mid = roleMemberId(am, roleId, account);
  let m = RoleMember.load(mid);
  if (m == null) {
    m = new RoleMember(mid);
    m.manager = am;
    m.role = roleEntityId(am, roleId);
    m.account = account.toHexString();
    m.executionDelay = BigInt.zero();
  }
  m.active = false;
  m.revokedAt = event.block.timestamp;
  m.executionDelay = BigInt.zero();
  m.save();

  appendRoleEvent(am, event, roleId, account, "Revoked", null, null, null);
}

export function handleRoleAdminChanged(event: RoleAdminChanged): void {
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(am, roleId);
  const oldValue = role.adminRole.toString();
  role.adminRole = event.params.admin;
  role.save();
  appendRoleEvent(am, event, roleId, null, "AdminChanged", oldValue, event.params.admin.toString(), null);
}

export function handleRoleGuardianChanged(event: RoleGuardianChanged): void {
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(am, roleId);
  const oldValue = role.guardianRole.toString();
  role.guardianRole = event.params.guardian;
  role.save();
  appendRoleEvent(am, event, roleId, null, "GuardianChanged", oldValue, event.params.guardian.toString(), null);
}

export function handleRoleGrantDelayChanged(event: RoleGrantDelayChanged): void {
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(am, roleId);
  const oldValue = role.grantDelay.toString();
  role.grantDelay = event.params.delay;
  role.save();
  appendRoleEvent(
    am,
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
  const am = getOrInitManager(event).id;
  const roleId = event.params.roleId;
  const role = loadOrCreateRole(am, roleId);
  role.onChainLabel = event.params.label;
  role.save();
  appendRoleEvent(am, event, roleId, null, "Labeled", null, event.params.label, null);
}

export function handleTargetFunctionRoleUpdated(event: TargetFunctionRoleUpdated): void {
  const am = getOrInitManager(event).id;
  const target = event.params.target;
  const selector = event.params.selector; // NOTE: non-indexed; read from event data
  const roleId = event.params.roleId;

  loadOrCreateTarget(am, target);
  loadOrCreateRole(am, roleId);

  const id = targetFnId(am, target, selector);
  let tf = TargetFunction.load(id);
  if (tf == null) {
    tf = new TargetFunction(id);
    tf.manager = am;
    tf.target = targetEntityId(am, target);
    tf.selector = selector;
  }
  tf.role = roleEntityId(am, roleId);
  tf.updatedAt = event.block.timestamp;
  tf.txHash = event.transaction.hash;
  tf.save();
}

export function handleTargetAdminDelayUpdated(event: TargetAdminDelayUpdated): void {
  const am = getOrInitManager(event).id;
  const t = loadOrCreateTarget(am, event.params.target);
  t.adminDelay = event.params.delay;
  t.save();
}

export function handleTargetClosed(event: TargetClosed): void {
  const am = getOrInitManager(event).id;
  const t = loadOrCreateTarget(am, event.params.target);
  t.closed = event.params.closed;
  t.save();
}

export function handleOperationScheduled(event: OperationScheduled): void {
  const am = getOrInitManager(event).id;
  const opHash = event.params.operationId.toHexString();
  const id = operationRowId(am, opHash, event.params.nonce);
  let op = Operation.load(id);
  if (op == null) {
    op = new Operation(id);
    op.manager = am;
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
  const am = getOrInitManager(event).id;
  const id = operationRowId(am, event.params.operationId.toHexString(), event.params.nonce);
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
  const am = getOrInitManager(event).id;
  const id = operationRowId(am, event.params.operationId.toHexString(), event.params.nonce);
  const op = Operation.load(id);
  if (op == null) {
    return;
  }
  op.status = "Canceled";
  op.canceledAt = event.block.timestamp;
  op.cancelTx = event.transaction.hash;
  op.save();
}
