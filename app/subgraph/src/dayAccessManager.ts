// Mapping module for the Day RoycoAccessManager data source. It shares every OZ AccessManager
// handler with the Dawn data source (re-exported from ./accessManager — each handler scopes rows
// by event.address) and adds the Day-only TargetConfiguredAtGenesis handler.
//
// This lives in its own module (rather than in accessManager.ts) because the generated
// `DayAccessManager` types only exist when the manifest contains the Day data source — Avalanche
// is Dawn-only, and its build must not compile an import of a non-existent generated path.
import { TargetConfiguredAtGenesis } from "../generated/DayAccessManager/RoycoAccessManager";
import { getOrInitManager, loadOrCreateTarget } from "./helpers";

export {
  handleRoleGranted,
  handleRoleRevoked,
  handleRoleAdminChanged,
  handleRoleGuardianChanged,
  handleRoleGrantDelayChanged,
  handleRoleLabel,
  handleTargetFunctionRoleUpdated,
  handleTargetAdminDelayUpdated,
  handleTargetClosed,
  handleOperationScheduled,
  handleOperationExecuted,
  handleOperationCanceled,
} from "./accessManager";

// Mirrors the Day AM's monotonic `wasEverConfigured[target]` flag: fired once, on the first
// target-scoped configuration write for a target.
export function handleTargetConfiguredAtGenesis(event: TargetConfiguredAtGenesis): void {
  const am = getOrInitManager(event).id;
  const t = loadOrCreateTarget(am, event.params.target);
  t.everConfigured = true;
  t.firstConfiguredAt = event.block.timestamp;
  t.firstConfiguredTx = event.transaction.hash;
  t.save();
}
