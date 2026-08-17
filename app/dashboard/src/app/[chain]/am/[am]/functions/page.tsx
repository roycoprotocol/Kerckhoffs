import { chainBySlug } from "@/config/chains";
import { fetchAllRoles, fetchAllTargetFunctions, hasSubgraph } from "@/lib/subgraph";
import { managerFor, parseAmKind, roleName, selectorName } from "@/lib/catalog";
import { resolveLabel } from "@/lib/labels";
import { warmMarketLabels } from "@/lib/markets";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddressLabel, AddrLink, CategoryBadge } from "@/components/AddressLabel";
import { Callers, holdersByRole } from "@/components/Callers";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

const CATEGORY_OPTS = ["market", "vault", "strategy", "entrypoint", "syncer", "factory"].map((c) => ({ value: c, label: c }));

export default async function FunctionsPage({
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
  const mgr = managerFor(cfg.chainId, kind)!;
  if (!hasSubgraph(cfg.chainId)) {
    return (
      <>
        <PageTitle title="Function map" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  const q = param(sp, "q");
  const cat = param(sp, "category");
  const [fns, roles] = await Promise.all([
    fetchAllTargetFunctions(cfg.chainId, mgr.address),
    fetchAllRoles(cfg.chainId, mgr.address).catch(() => []),
    warmMarketLabels(cfg.chainId).catch(() => {}),
  ]);
  const callersByRole = holdersByRole(roles);

  // Group by target, attach its label.
  const byTarget = new Map<string, { label: ReturnType<typeof resolveLabel>; rows: typeof fns }>();
  for (const f of fns) {
    const t = f.target.address.toLowerCase();
    if (!byTarget.has(t)) byTarget.set(t, { label: resolveLabel(cfg.chainId, t), rows: [] });
    byTarget.get(t)!.rows.push(f);
  }

  const groups = [...byTarget.entries()]
    .map(([addr, g]) => ({ addr, label: g.label, rows: g.rows }))
    .sort((a, b) => a.label.name.localeCompare(b.label.name))
    .filter((g) => !cat || g.label.category === cat)
    .map((g) => ({
      ...g,
      rows: q
        ? g.rows.filter(
            (f) => includesCI(g.label.name, q) || includesCI(selectorName(f.selector), q) || includesCI(f.selector, q),
          )
        : g.rows,
    }))
    .filter((g) => g.rows.length > 0);

  const total = groups.reduce((n, g) => n + g.rows.length, 0);

  return (
    <>
      <PageTitle title="Function map" subtitle={`${total} (target, selector) → role bindings across ${groups.length} contracts`} />
      <Filters
        searchPlaceholder="Search contract, function or selector…"
        selects={[{ key: "category", label: "category", options: CATEGORY_OPTS }]}
      />
      {groups.length === 0 ? (
        <Empty>No bindings match.</Empty>
      ) : (
        <div className="space-y-4">
          {groups.map((g) => (
            <Panel key={g.addr}>
              <div className="flex items-center gap-2 border-b border-border px-3 py-2">
                <AddressLabel chainId={cfg.chainId} slug={chain} address={g.addr} />
                <CategoryBadge category={g.label.category} />
                <AddrLink chainId={cfg.chainId} address={g.addr} short className="ml-auto" />
              </div>
              <Table head={<><Th className="w-72">Function</Th><Th className="w-28">Selector</Th><Th className="w-64">Gated by role</Th><Th>Callable by</Th></>}>
                {g.rows
                  .sort((a, b) => selectorName(a.selector).localeCompare(selectorName(b.selector)))
                  .map((f) => (
                    <tr key={f.selector} className="border-b border-border/50">
                      <Td>
                        <Mono>{selectorName(f.selector)}</Mono>
                      </Td>
                      <Td>
                        <Mono className="text-muted">{f.selector}</Mono>
                      </Td>
                      <Td>
                        <RoleLink slug={chain} am={kind} id={f.role.roleId} name={roleName(cfg.chainId, kind, f.role.roleId)} />
                      </Td>
                      <Td>
                        <Callers
                          chainId={cfg.chainId}
                          slug={chain}
                          roleId={f.role.roleId}
                          callers={callersByRole.get(f.role.roleId)}
                        />
                      </Td>
                    </tr>
                  ))}
              </Table>
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}
