import { chainBySlug } from "@/config/chains";
import { fetchMeta, hasSubgraph } from "@/lib/subgraph";
import { buildRoleViews } from "@/lib/merge";
import { highestSeverity } from "@/lib/drift";
import { fmtDelay } from "@/lib/format";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { Filters } from "@/components/Filters";
import { DriftBadge, Empty, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function RolesPage({
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
        <PageTitle title="Roles" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  let views, meta;
  try {
    [views, meta] = await Promise.all([buildRoleViews(cfg.chainId), fetchMeta(cfg.chainId)]);
  } catch (e) {
    return (
      <>
        <PageTitle title="Roles" />
        <Empty>Failed to load subgraph: <Mono>{(e as Error).message}</Mono></Empty>
      </>
    );
  }

  const q = param(sp, "q");
  const sev = param(sp, "sev");
  const state = param(sp, "state");
  const filtered = views.filter((v) => {
    if (q && !(includesCI(v.name, q) || v.holders.some((h) => includesCI(h.actor ?? h.address, q)))) return false;
    if (sev && highestSeverity(v.drift) !== sev) return false;
    if (state === "configured" && !v.presentOnChain) return false;
    if (state === "unconfigured" && v.presentOnChain) return false;
    return true;
  });

  const configured = views.filter((v) => v.presentOnChain);
  const drifting = configured.filter((v) => v.drift.length).length;

  return (
    <>
      <PageTitle
        title="Roles"
        subtitle={
          <>
            {configured.length} configured · {drifting} with drift ·{" "}
            {meta ? <>indexed block {meta.block.number}</> : "no index status"} · showing {filtered.length}
          </>
        }
      />
      <Filters
        searchPlaceholder="Search role or holder…"
        selects={[
          { key: "sev", label: "drift", options: [{ value: "HIGH", label: "high" }, { value: "MEDIUM", label: "medium" }, { value: "LOW", label: "low" }] },
          { key: "state", label: "state", options: [{ value: "configured", label: "configured" }, { value: "unconfigured", label: "not configured" }] },
        ]}
      />
      <Panel>
        <Table
          head={
            <>
              <Th>Role</Th>
              <Th>Holders</Th>
              <Th>Admin</Th>
              <Th>Guardian</Th>
              <Th>Grant delay</Th>
              <Th>Gated fns</Th>
              <Th>Drift</Th>
            </>
          }
        >
          {filtered.map((v) => (
            <tr key={v.id} className={`border-b border-border/50 ${v.presentOnChain ? "" : "opacity-50"}`}>
              <Td>
                <RoleLink slug={chain} id={v.id} name={v.name} />
                {!v.presentOnChain && <span className="ml-2 text-[11px] text-muted">not configured</span>}
              </Td>
              <Td>
                {v.holders.length === 0 ? (
                  <span className="text-muted">—</span>
                ) : (
                  <span>
                    {v.holders.length}
                    <span className="ml-2 text-muted">
                      {v.holders.slice(0, 3).map((h) => h.actor ?? "ext").join(", ")}
                      {v.holders.length > 3 ? " …" : ""}
                    </span>
                  </span>
                )}
              </Td>
              <Td className="text-muted">{v.config.adminRoleName}</Td>
              <Td className="text-muted">{v.config.guardianRoleName}</Td>
              <Td>
                <Mono>{fmtDelay(v.config.grantDelaySeconds)}</Mono>
              </Td>
              <Td className="text-muted">{v.capabilities.length || "—"}</Td>
              <Td>
                <DriftBadge drift={v.drift} />
              </Td>
            </tr>
          ))}
          {filtered.length === 0 && (
            <tr>
              <Td className="text-muted">— no roles match —</Td>
            </tr>
          )}
        </Table>
      </Panel>
    </>
  );
}
