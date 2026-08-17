import Link from "next/link";
import { chainBySlug } from "@/config/chains";
import { fetchPendingOperations, hasSubgraph } from "@/lib/subgraph";
import { managerFor, parseAmKind, selectorName } from "@/lib/catalog";
import { warmMarketLabels } from "@/lib/markets";
import { resolveLabel } from "@/lib/labels";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddressLabel, TargetChip } from "@/components/AddressLabel";
import { LocalTime } from "@/components/LocalTime";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function OperationsPage({
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
        <PageTitle title="Pending operations" />
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  const [ops] = await Promise.all([
    fetchPendingOperations(cfg.chainId, mgr.address),
    warmMarketLabels(cfg.chainId).catch(() => {}),
  ]);
  const now = Math.floor(Date.now() / 1000);
  const q = param(sp, "q");
  // Expiry filter: scheduled ops lapse `expiration` after unlock. Default view = Active.
  const f = param(sp, "f") || "active";
  const isExpired = (o: (typeof ops)[number]) => now > Number(o.schedule) + mgr.expiration;
  const activeCount = ops.filter((o) => !isExpired(o)).length;
  const expiredCount = ops.length - activeCount;

  const shown = ops.filter((o) => {
    if (f === "active" && isExpired(o)) return false;
    if (f === "expired" && !isExpired(o)) return false;
    if (!q) return true;
    const action = selectorName(o.data.slice(0, 10));
    return (
      includesCI(resolveLabel(cfg.chainId, o.target).name, q) ||
      includesCI(action, q) ||
      includesCI(resolveLabel(cfg.chainId, o.caller).name, q)
    );
  });

  const chip = (key: string, label: string) => (
    <Link
      key={key}
      href={key === "active" ? "?" : `?f=${key}`}
      className={`rounded-md border px-2.5 py-1 text-xs ${
        f === key ? "border-ok bg-ok-tint !text-ok" : "border-border bg-panel text-body hover:border-ok hover:!text-ok"
      }`}
    >
      {label}
    </Link>
  );

  return (
    <>
      <PageTitle title="Pending operations" subtitle={`${ops.length} scheduled timelock op(s) · showing ${shown.length}`} />
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex-1">
          <Filters searchPlaceholder="Search target, action or scheduler…" />
        </div>
        <div className="flex items-center gap-1.5">
          {chip("active", `Active (${activeCount})`)}
          {chip("expired", `Expired (${expiredCount})`)}
          {chip("all", `All (${ops.length})`)}
        </div>
      </div>
      {shown.length === 0 ? (
        <Empty>
          {ops.length === 0
            ? `No scheduled operations pending on ${cfg.name}.`
            : f === "active" && activeCount === 0
              ? `No active operations — ${expiredCount} expired op(s) hidden.`
              : "No operations match."}
        </Empty>
      ) : (
        <Panel>
          <Table head={<><Th>Target</Th><Th>Action</Th><Th>Scheduled by</Th><Th>Executable</Th><Th /></>}>
            {shown.map((o) => {
              const schedule = Number(o.schedule);
              const executable = now >= schedule;
              const expired = now > schedule + mgr.expiration;
              return (
                <tr key={o.id} className="border-b border-border/50">
                  <Td>
                    <TargetChip chainId={cfg.chainId} slug={chain} address={o.target} />
                  </Td>
                  <Td>
                    <Link href={`/${chain}/am/${am}/operations/${o.id}`} className="hover:text-ok">
                      <Mono>{selectorName(o.data.slice(0, 10))}</Mono>
                    </Link>
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
                      <span className="text-muted">
                        <LocalTime unix={schedule} />
                      </span>
                    )}
                  </Td>
                  <Td className="text-right">
                    <Link href={`/${chain}/am/${am}/operations/${o.id}`} className="text-xs !text-ok">
                      Details ↗
                    </Link>
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
