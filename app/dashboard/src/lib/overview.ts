// Overview page data: everything is computed from indexed chain state — no hand-authored numbers.
import type { AmKind } from "@/model";
import { CHAINS } from "@/config/chains";
import { factoryFor, managersFor, selectorName } from "@/lib/catalog";
import { warmMarketLabels } from "@/lib/markets";
import { hasSubgraph } from "@/lib/subgraph";
import {
  fetchAllOperations,
  fetchAllRoles,
  fetchLatestConfigChange,
  fetchMarkets,
  type SgOpFull,
} from "@/lib/subgraph";

export interface LadderTier {
  key: string;
  tier: string;
  delay: string;
  desc: string;
  count: number;
  hero: boolean;
  seconds: number;
  tip?: string;
}

export interface OverviewOp {
  id: string;
  opId: string; // subgraph Operation.id — the op detail page URL segment
  chainId: number;
  chainName: string;
  slug: string;
  am: AmKind;
  fn: string;
  target: string; // raw address — rendered via TargetChip
  scheduledAt: number;
  schedule: number;
  expiresAt: number; // schedule + manager expiration — unexecuted ops lapse after this
}

export interface Overview {
  ladder: LadderTier[];
  gatedFns: number;
  pending: OverviewOp[];
  executedCount: number;
  cancelledCount: number;
  servedFullDelayPct: number | null;
  lastConfigChange: number | null;
  marketCount: number;
  managerCount: number;
}

const PUBLIC_ROLE_ID = "18446744073709551615";

// Tier definitions by the standard operating path's execution delay (the max delay among a role's
// active holders — the non-emergency path). Groups not listed fall into "other".
const TIERS: { key: string; seconds: number; tier: string; desc: string; tip?: string; hero?: boolean }[] = [
  {
    key: "core",
    seconds: 259200,
    tier: "CORE PROTOCOL",
    desc: "Core Protocol Parameter Updates",
    tip: "Kernel & accountant parameters (fees, coverage, YDMs), UUPS implementation upgrades, role grants/revocations and delay changes, Makina risk-manager settings, and token rescue.",
    hero: true,
  },
  {
    key: "periphery",
    seconds: 86400,
    tier: "PERIPHERY",
    desc: "Peripheral Configuration Updates",
    tip: "Entry-point tranche configuration (deposit/redemption routing and limits).",
  },
  {
    key: "immediate",
    seconds: 0,
    tier: "IMMEDIATE",
    desc: "Protocol pausing and maintenance operations",
    tip: "Pause any protocol contract (dedicated pause multisig), unpause (Foundation), guardian veto of scheduled operations, allowlisted LP deposits/redemptions, and accounting sync.",
  },
];

export async function buildOverview(chainId: number): Promise<Overview> {
  const managers = managersFor(chainId);
  const kindByAm = new Map(managers.map((m) => [m.address.toLowerCase(), m.kind]));
  const expirationByAm = new Map(managers.map((m) => [m.address.toLowerCase(), m.expiration]));

  const [rolesPerManager, allOps, lastConfigChange, marketLists] = await Promise.all([
    Promise.all(managers.map((m) => fetchAllRoles(chainId, m.address).catch(() => []))).then((r) => r.flat()),
    fetchAllOperations(chainId).catch(() => [] as SgOpFull[]),
    fetchLatestConfigChange(chainId, managers.map((m) => m.address)).catch(() => null),
    Promise.all(
      managers.map((m) =>
        fetchMarkets(chainId, m.kind)
          .then((ms) => {
            const fac = factoryFor(chainId, m.kind);
            return fac ? ms.filter((x) => x.factory.toLowerCase() === fac) : ms;
          })
          .catch(() => []),
      ),
    ),
  ]);

  // ── delay ladder: classify every gated (target, selector) by its role's standard-path delay ──
  const tierCounts = new Map<string, number>();
  let publicCount = 0;
  let gatedFns = 0;
  for (const r of rolesPerManager) {
    if (!r.functions.length) continue;
    if (r.roleId === PUBLIC_ROLE_ID) {
      publicCount += r.functions.length; // open surfaces — not counted as gated
      continue;
    }
    gatedFns += r.functions.length;
    const activeDelays = r.members.filter((m) => m.active).map((m) => Number(m.executionDelay));
    const stdDelay = activeDelays.length ? Math.max(...activeDelays) : 0;
    const tier = TIERS.find((t) => t.seconds === stdDelay);
    const key = tier ? tier.key : `other-${stdDelay}`;
    tierCounts.set(key, (tierCounts.get(key) ?? 0) + r.functions.length);
  }
  // The ladder is STATIC: always exactly the three standard tiers, delay-descending. Bindings
  // whose current holder delay falls outside a tier (pre-migration history mid-backfill) are
  // counted nowhere rather than surfacing transient rows.
  const ladder: LadderTier[] = TIERS.map((t) => ({
    key: t.key,
    tier: t.tier,
    delay: t.seconds === 0 ? '0H' : `${t.seconds / 3600}H`,
    desc: t.desc,
    tip: t.tip,
    count: tierCounts.get(t.key) ?? 0,
    hero: !!t.hero,
    seconds: t.seconds,
  }));

  // ── operations: pending (both AMs) + track record ─────────────────────────────
  const tracked = allOps.filter((o) => kindByAm.has(o.manager.id.toLowerCase()));
  const chainCfg = CHAINS.find((c) => c.chainId === chainId);
  const pending: OverviewOp[] = tracked
    .filter((o) => o.status === "Scheduled")
    .map((o) => ({
      id: o.id,
      opId: o.id,
      chainId,
      chainName: chainCfg?.name ?? String(chainId),
      slug: chainCfg?.slug ?? "",
      am: kindByAm.get(o.manager.id.toLowerCase())!,
      fn: selectorName(o.data.slice(0, 10)),
      target: o.target,
      scheduledAt: Number(o.scheduledAt),
      schedule: Number(o.schedule),
      expiresAt: Number(o.schedule) + (expirationByAm.get(o.manager.id.toLowerCase()) ?? 0),
    }))
    .sort((a, b) => a.schedule - b.schedule);
  const executed = tracked.filter((o) => o.status === "Executed");
  const served = executed.filter((o) => o.executedAt && Number(o.executedAt) >= Number(o.schedule));

  return {
    ladder,
    gatedFns,
    pending,
    executedCount: executed.length,
    cancelledCount: tracked.filter((o) => o.status === "Canceled").length,
    servedFullDelayPct: executed.length ? Math.round((served.length / executed.length) * 100) : null,
    lastConfigChange,
    marketCount: marketLists.flat().length,
    managerCount: managers.length,
  };
}

// Pending operations across EVERY chain — the Overview's pending section spans the whole
// protocol, not just the selected chain.
export async function buildPendingAllChains(): Promise<OverviewOp[]> {
  const perChain = await Promise.all(
    CHAINS.filter((c) => hasSubgraph(c.chainId)).map(async (c) => {
      const managers = managersFor(c.chainId);
      const kindByAm = new Map(managers.map((m) => [m.address.toLowerCase(), m.kind]));
      const expirationByAm = new Map(managers.map((m) => [m.address.toLowerCase(), m.expiration]));
      // Warm the market-label overlay so pending-op target chips resolve day components too.
      const [ops] = await Promise.all([
        fetchAllOperations(c.chainId).catch(() => [] as SgOpFull[]),
        warmMarketLabels(c.chainId).catch(() => {}),
      ]);
      return ops
        .filter((o) => o.status === "Scheduled" && kindByAm.has(o.manager.id.toLowerCase()))
        .map((o) => ({
          id: `${c.chainId}-${o.id}`,
          opId: o.id,
          chainId: c.chainId,
          chainName: c.name,
          slug: c.slug,
          am: kindByAm.get(o.manager.id.toLowerCase())!,
          fn: selectorName(o.data.slice(0, 10)),
          target: o.target,
          scheduledAt: Number(o.scheduledAt),
          schedule: Number(o.schedule),
          expiresAt: Number(o.schedule) + (expirationByAm.get(o.manager.id.toLowerCase()) ?? 0),
        }));
    }),
  );
  return perChain.flat().sort((a, b) => a.schedule - b.schedule);
}
