import { chainBySlug } from "@/config/chains";
import { parseAmKind } from "@/lib/catalog";
import { fetchMeta, hasSubgraph } from "@/lib/subgraph";
import { buildRoleViews } from "@/lib/merge";
import { fmtDelay } from "@/lib/format";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { Filters } from "@/components/Filters";
import { Empty, Eyebrow, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function RolesPage({
  params,
  searchParams,
}: {
  params: Promise<{ chain: string; am: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain, am } = await params;
  const sp = await searchParams;
  const cfg = chainBySlug(chain)!;
  const kind = parseAmKind(am)!;

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
    [views, meta] = await Promise.all([buildRoleViews(cfg.chainId, kind), fetchMeta(cfg.chainId)]);
  } catch (e) {
    return (
      <>
        <PageTitle title="Roles" />
        <Empty>Failed to load subgraph: <Mono>{(e as Error).message}</Mono></Empty>
      </>
    );
  }

  const q = param(sp, "q");
  const filtered = views.filter(
    (v) => !q || includesCI(v.name, q) || v.holders.some((h) => includesCI(h.actor ?? h.address, q)),
  );

  return (
    <>
      <div className="mb-4 flex items-baseline justify-between">
        <h2 className="font-serif text-[22px] font-semibold">Roles.</h2>
        <Eyebrow>
          {views.length} configured{meta ? ` · block ${meta.block.number}` : ""}
        </Eyebrow>
      </div>
      <Filters searchPlaceholder="Search role or holder…" />
      <Panel>
        <Table
          head={
            <>
              <Th>Role</Th>
              <Th>Holders</Th>
              <Th>Admin</Th>
              <Th>Guardian</Th>
              <Th>Grant delay</Th>
              <Th className="text-right">Gated fns</Th>
            </>
          }
        >
          {filtered.map((v) => (
            <tr key={v.id} className="hover:bg-[rgba(15,14,13,0.015)]">
              <Td>
                <RoleLink slug={chain} am={kind} id={v.id} name={v.name} />
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
              <Td className="text-[13px] text-body">{v.config.adminRoleName}</Td>
              <Td className="text-[13px] text-body">{v.config.guardianRoleName}</Td>
              <Td>
                <Mono>{fmtDelay(v.config.grantDelaySeconds)}</Mono>
              </Td>
              <Td className="text-right font-mono text-xs">{v.capabilities.length || "—"}</Td>
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
