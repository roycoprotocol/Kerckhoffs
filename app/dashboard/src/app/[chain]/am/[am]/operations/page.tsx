import { chainBySlug } from "@/config/chains";
import { fetchPendingOperations, hasSubgraph } from "@/lib/subgraph";
import { getCatalog, selectorName, shorten } from "@/lib/catalog";
import { resolveLabel } from "@/lib/labels";
import { fmtTime } from "@/lib/format";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddressLabel } from "@/components/AddressLabel";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function OperationsPage({
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
        <PageTitle title="Pending operations" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  const ops = await fetchPendingOperations(cfg.chainId);
  const cat = getCatalog(cfg.chainId);
  const now = Math.floor(Date.now() / 1000);
  const q = param(sp, "q");

  const shown = ops.filter((o) => {
    if (!q) return true;
    const action = selectorName(o.data.slice(0, 10));
    return (
      includesCI(resolveLabel(cfg.chainId, o.target).name, q) ||
      includesCI(action, q) ||
      includesCI(resolveLabel(cfg.chainId, o.caller).name, q)
    );
  });

  return (
    <>
      <PageTitle title="Pending operations" subtitle={`${ops.length} scheduled timelock op(s) · showing ${shown.length}`} />
      <Filters searchPlaceholder="Search target, action or scheduler…" />
      {shown.length === 0 ? (
        <Empty>{ops.length === 0 ? `No scheduled operations pending on ${cfg.name}.` : "No operations match."}</Empty>
      ) : (
        <Panel>
          <Table head={<><Th>Target</Th><Th>Action</Th><Th>Scheduled by</Th><Th>Executable</Th><Th>Op id</Th></>}>
            {shown.map((o) => {
              const schedule = Number(o.schedule);
              const executable = now >= schedule;
              const expired = cat ? now > schedule + cat.expiration : false;
              return (
                <tr key={o.id} className="border-b border-border/50">
                  <Td>
                    <AddressLabel chainId={cfg.chainId} slug={chain} address={o.target} />
                  </Td>
                  <Td>
                    <Mono>{selectorName(o.data.slice(0, 10))}</Mono>
                  </Td>
                  <Td>
                    <AddressLabel chainId={cfg.chainId} slug={chain} address={o.caller} />
                  </Td>
                  <Td>
                    {expired ? (
                      <span className="text-med">expired</span>
                    ) : executable ? (
                      <span className="text-ok">now</span>
                    ) : (
                      <span className="text-muted">{fmtTime(schedule)}</span>
                    )}
                  </Td>
                  <Td>
                    <Mono className="text-muted">{shorten(o.operationId)}</Mono>
                  </Td>
                </tr>
              );
            })}
          </Table>
        </Panel>
      )}
    </>
  );
}
