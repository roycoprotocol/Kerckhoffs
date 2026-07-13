import Link from "next/link";
import { buildChainMatrix } from "@/lib/multichain";
import { fmtDelay } from "@/lib/format";
import { boolParam, includesCI, param, type SearchParams } from "@/lib/searchParams";
import { Filters } from "@/components/Filters";
import { Empty, Mono, PageTitle, Panel, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function DiffPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const { rows: allRows, chains } = await buildChainMatrix();
  const q = param(sp, "q");
  const divergentOnly = boolParam(sp, "divergentOnly");
  const rows = allRows.filter((r) => {
    if (q && !includesCI(r.name, q)) return false;
    if (divergentOnly && !r.cells.some((c) => c.divergent)) return false;
    return true;
  });
  const anyData = allRows.length > 0;

  return (
    <div className="min-h-screen">
      <header className="flex items-center gap-3 border-b border-border px-4 py-3">
        <Link href="/" className="font-semibold">
          Royco <span className="text-muted">Access Control</span>
        </Link>
        <span className="ml-auto text-sm text-muted">Multi-chain diff</span>
      </header>
      <main className="mx-auto max-w-6xl p-6">
        <PageTitle
          title="Multi-chain diff"
          subtitle="Same role across chains. Cells that diverge from the majority are highlighted; blank = role not configured on that chain."
        />
        {anyData && (
          <Filters searchPlaceholder="Search role…" toggles={[{ key: "divergentOnly", label: "divergent only" }]} />
        )}
        {!anyData ? (
          <Empty>No subgraph data available. Configure SUBGRAPH_URL_&lt;chainId&gt; for at least one chain.</Empty>
        ) : (
          <Panel>
            <Table
              head={
                <>
                  <Th>Role</Th>
                  {chains.map((c) => (
                    <Th key={c.chainId}>{c.name}</Th>
                  ))}
                </>
              }
            >
              {rows.map((row) => (
                <tr key={row.id} className="border-b border-border/50">
                  <Td className="font-medium">{row.name}</Td>
                  {row.cells.map((c) => (
                    <Td
                      key={c.chainId}
                      className={c.divergent ? "bg-high/10" : ""}
                    >
                      {!c.present ? (
                        <span className="text-muted">—</span>
                      ) : (
                        <div className="space-y-0.5">
                          <div className={c.divergent ? "text-high" : ""}>
                            {c.holderLabels.length ? c.holderLabels.slice(0, 3).join(", ") : "no holders"}
                            {c.holderLabels.length > 3 ? " …" : ""}
                          </div>
                          <div className="text-[11px] text-muted">
                            <Mono>{fmtDelay(c.grantDelaySeconds)}</Mono> · guard {c.guardianRoleName}
                          </div>
                        </div>
                      )}
                    </Td>
                  ))}
                </tr>
              ))}
            </Table>
          </Panel>
        )}
      </main>
    </div>
  );
}
