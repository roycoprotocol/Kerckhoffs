// Drift detection (main.md §3.4): compare live ACTUAL against catalog EXPECTED, per role.
import type { Drift, HolderView, RoleConfig } from "@/model";
import { actorAddress, expectation, isKnownRole } from "@/lib/catalog";

// Roles whose membership is operational/open (granted to many LPs / operators) — an "unexpected"
// holder there is normal, so we don't flag it. Config/admin/guardian drift is still checked.
const OPEN_MEMBERSHIP = new Set(["ST_LP_ROLE", "JT_LP_ROLE", "SYNC_ROLE", "BURNER_ROLE"]);

interface DriftInput {
  chainId: number;
  id: string;
  name: string;
  adminRoleName: string;
  guardianRoleName: string;
  grantDelaySeconds: number;
  holders: HolderView[];
}

export function computeRoleDrift(input: DriftInput): Drift[] {
  const out: Drift[] = [];

  if (!isKnownRole(input.chainId, input.id)) {
    out.push({
      field: "role",
      expected: "not in canonical model",
      actual: `role ${input.id}`,
      severity: "HIGH",
      note: "An on-chain role the canonical model does not define.",
    });
    return out;
  }

  const exp = expectation(input.name);
  if (!exp) return out; // known role but no authored expectation yet

  if (exp.admin !== input.adminRoleName) {
    out.push({ field: "adminRole", expected: exp.admin, actual: input.adminRoleName, severity: "MEDIUM" });
  }
  if (exp.guardian !== input.guardianRoleName) {
    out.push({ field: "guardianRole", expected: exp.guardian, actual: input.guardianRoleName, severity: "MEDIUM" });
  }
  if (exp.grantDelaySeconds !== input.grantDelaySeconds) {
    out.push({
      field: "grantDelay",
      expected: String(exp.grantDelaySeconds),
      actual: String(input.grantDelaySeconds),
      severity: "LOW",
    });
  }

  // Holder set + per-holder execution delay.
  const expectedByAddr = new Map<string, number>(); // addr -> expected exec delay
  const expectedActorNames = new Set<string>();
  for (const h of exp.holders) {
    expectedActorNames.add(h.actor);
    const addr = actorAddress(input.chainId, h.actor);
    if (addr) expectedByAddr.set(addr, h.executionDelaySeconds);
  }
  const open = OPEN_MEMBERSHIP.has(input.name);

  const actualAddrs = new Set(input.holders.map((h) => h.address.toLowerCase()));
  for (const h of input.holders) {
    const addr = h.address.toLowerCase();
    if (expectedByAddr.has(addr)) {
      const expDelay = expectedByAddr.get(addr)!;
      if (h.executionDelaySeconds < expDelay) {
        out.push({
          field: `holder ${h.actor ?? addr} delay`,
          expected: `>= ${expDelay}s`,
          actual: `${h.executionDelaySeconds}s`,
          severity: "HIGH",
          note: "Execution delay below the canonical floor.",
        });
      }
    } else if (!open) {
      out.push({
        field: "unexpected holder",
        expected: `one of [${[...expectedActorNames].join(", ") || "none"}]`,
        actual: h.actor ?? addr,
        severity: "HIGH",
      });
    }
  }
  // Missing expected holders.
  for (const h of exp.holders) {
    const addr = actorAddress(input.chainId, h.actor);
    if (addr && !actualAddrs.has(addr)) {
      out.push({
        field: "missing holder",
        expected: h.actor,
        actual: "not granted on-chain",
        severity: "MEDIUM",
      });
    }
  }
  return out;
}

export function highestSeverity(drift: Drift[]): "HIGH" | "MEDIUM" | "LOW" | null {
  if (drift.some((d) => d.severity === "HIGH")) return "HIGH";
  if (drift.some((d) => d.severity === "MEDIUM")) return "MEDIUM";
  if (drift.some((d) => d.severity === "LOW")) return "LOW";
  return null;
}

export function severityRank(sev: string): number {
  return sev === "HIGH" ? 0 : sev === "MEDIUM" ? 1 : 2;
}
