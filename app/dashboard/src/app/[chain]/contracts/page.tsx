import { chainBySlug } from "@/config/chains";
import { buildDirectory } from "@/lib/labels";
import { shorten } from "@/lib/catalog";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import type { Label } from "@/model";
import { AddressLabel, CategoryBadge } from "@/components/AddressLabel";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel } from "@/components/ui";

export const dynamic = "force-dynamic";

const CATEGORY_OPTS = ["factory", "multisig", "market", "vault", "strategy", "entrypoint", "syncer", "external"].map((c) => ({
  value: c,
  label: c,
}));

export default async function ContractsPage({
  params,
  searchParams,
}: {
  params: Promise<{ chain: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain } = await params;
  const sp = await searchParams;
  const cfg = chainBySlug(chain)!;

  const q = param(sp, "q");
  const cat = param(sp, "category");
  const match = (l: Label) => !q || includesCI(l.name, q) || l.address.includes(q.toLowerCase()) || includesCI(l.parent ?? "", q);

  const groups = buildDirectory(cfg.chainId)
    .filter((g) => !cat || g.category === cat)
    .map((g) => ({
      ...g,
      entries: g.entries
        .map((e) => (e.children ? { ...e, children: e.children.filter(match) } : e))
        .filter((e) => (e.children ? e.children.length > 0 : match(e.label))),
    }))
    .filter((g) => g.entries.length > 0);

  const total = groups.reduce((n, g) => n + g.entries.reduce((m, e) => m + (e.children?.length ?? 1), 0), 0);

  return (
    <>
      <PageTitle title="Directory" subtitle={`${total} labeled address(es) on ${cfg.name}, by category & hierarchy`} />
      <Filters searchPlaceholder="Search address or label…" selects={[{ key: "category", label: "category", options: CATEGORY_OPTS }]} />
      {groups.length === 0 ? (
        <Empty>No addresses match.</Empty>
      ) : (
        <div className="space-y-4">
          {groups.map((g) => (
            <Panel key={g.category}>
              <div className="flex items-center gap-2 border-b border-border px-3 py-2">
                <CategoryBadge category={g.category} />
                <span className="text-sm font-medium">{g.title}</span>
              </div>
              <div className="divide-y divide-border/50">
                {g.entries.map((e, i) =>
                  e.children ? (
                    <div key={i} className="px-3 py-2">
                      <div className="mb-1 text-sm font-medium">{e.label.name}</div>
                      <div className="ml-3 grid gap-1 sm:grid-cols-2">
                        {e.children.map((c) => (
                          <div key={c.address} className="flex items-center gap-2 text-sm">
                            <AddressLabel chainId={cfg.chainId} slug={chain} address={c.address} />
                            <span className="text-[11px] text-muted">{c.subtype}</span>
                            <Mono className="ml-auto text-[11px] text-muted">{shorten(c.address)}</Mono>
                          </div>
                        ))}
                      </div>
                    </div>
                  ) : (
                    <div key={i} className="flex items-center gap-2 px-3 py-2 text-sm">
                      <AddressLabel chainId={cfg.chainId} slug={chain} address={e.label.address} />
                      {e.label.pendingDeployment && <span className="text-[11px] text-med">pending</span>}
                      <Mono className="ml-auto text-[11px] text-muted">{shorten(e.label.address)}</Mono>
                    </div>
                  ),
                )}
              </div>
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}
