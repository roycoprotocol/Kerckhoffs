import { chainBySlug } from "@/config/chains";
import { hasSubgraph } from "@/lib/subgraph";
import { buildRoleViews } from "@/lib/merge";
import { fetchMakinaSlots } from "@/lib/makina";
import { severityRank } from "@/lib/drift";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import type { Drift } from "@/model";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, RoleLink, SeverityPill, SubgraphMissing } from "@/components/ui";

export const dynamic = "force-dynamic";

interface Row {
  context: string;
  contextId?: string;
  drift: Drift;
}

export default async function DriftPage({
  params,
  searchParams,
}: {
  params: Promise<{ chain: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain } = await params;
  const sp = await searchParams;
  const cfg = chainBySlug(chain)!;
  if (!hasSubgraph(cfg.chainId)) {
    return (
      <>
        <PageTitle title="Drift" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  const [views, makina] = await Promise.all([buildRoleViews(cfg.chainId), fetchMakinaSlots(cfg.chainId)]);

  let rows: Row[] = [];
  for (const v of views) for (const d of v.drift) rows.push({ context: v.name, contextId: v.id, drift: d });
  for (const m of makina) if (m.drift) rows.push({ context: `${m.vault} · Makina`, drift: m.drift });
  rows.sort((a, b) => severityRank(a.drift.severity) - severityRank(b.drift.severity));

  const counts = {
    HIGH: rows.filter((r) => r.drift.severity === "HIGH").length,
    MEDIUM: rows.filter((r) => r.drift.severity === "MEDIUM").length,
    LOW: rows.filter((r) => r.drift.severity === "LOW").length,
  };

  const q = param(sp, "q");
  const sev = param(sp, "sev");
  const shown = rows.filter((r) => {
    if (sev && r.drift.severity !== sev) return false;
    if (q && !(includesCI(r.context, q) || includesCI(r.drift.field, q) || includesCI(r.drift.actual, q) || includesCI(r.drift.expected, q)))
      return false;
    return true;
  });

  return (
    <>
      <PageTitle
        title="Drift"
        subtitle={`Live state vs canonical model · ${counts.HIGH} high · ${counts.MEDIUM} medium · ${counts.LOW} low · showing ${shown.length}`}
      />
      <Filters
        searchPlaceholder="Search role or field…"
        selects={[{ key: "sev", label: "severity", options: [{ value: "HIGH", label: "high" }, { value: "MEDIUM", label: "medium" }, { value: "LOW", label: "low" }] }]}
      />
      {shown.length === 0 ? (
        <Empty>{rows.length === 0 ? `No drift — ${cfg.name} matches the canonical model. ✓` : "No drift matches the filter."}</Empty>
      ) : (
        <Panel className="divide-y divide-border">
          {shown.map((r, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2 px-4 py-2 text-sm">
              <SeverityPill sev={r.drift.severity} />
              <span className="font-medium">
                {r.contextId ? <RoleLink slug={chain} id={r.contextId} name={r.context} /> : r.context}
              </span>
              <span className="text-muted">·</span>
              <span className="text-muted">{r.drift.field}:</span>
              <Mono className="text-high">{r.drift.actual}</Mono>
              <span className="text-muted">vs</span>
              <Mono>{r.drift.expected}</Mono>
              {r.drift.note && <span className="w-full pl-14 text-[11px] text-muted">{r.drift.note}</span>}
            </div>
          ))}
        </Panel>
      )}
    </>
  );
}
