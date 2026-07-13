import { chainBySlug } from "@/config/chains";
import { fetchAllTargetFunctions, hasSubgraph } from "@/lib/subgraph";
import { roleName, selectorName, shorten } from "@/lib/catalog";
import { resolveLabel } from "@/lib/labels";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddressLabel, CategoryBadge } from "@/components/AddressLabel";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

const CATEGORY_OPTS = ["market", "vault", "strategy", "entrypoint", "syncer", "factory"].map((c) => ({ value: c, label: c }));

export default async function FunctionsPage({
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
        <PageTitle title="Function map" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  const q = param(sp, "q");
  const cat = param(sp, "category");
  const fns = await fetchAllTargetFunctions(cfg.chainId);

  // Group by target, attach its label.
  const byTarget = new Map<string, { label: ReturnType<typeof resolveLabel>; rows: typeof fns }>();
  for (const f of fns) {
    const t = f.target.id.toLowerCase();
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
                <Mono className="ml-auto text-[11px] text-muted">{shorten(g.addr)}</Mono>
              </div>
              <Table head={<><Th>Function</Th><Th>Selector</Th><Th>Gated by role</Th></>}>
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
                        <RoleLink slug={chain} id={f.role.id} name={roleName(cfg.chainId, f.role.id)} />
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
