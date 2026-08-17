import Link from "next/link";
import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { parseAmKind } from "@/lib/catalog";
import { hasSubgraph } from "@/lib/subgraph";
import { buildRoleView } from "@/lib/merge";
import { fmtDelay, shorten } from "@/lib/format";
import { LocalTime } from "@/components/LocalTime";
import { AddressLabel } from "@/components/AddressLabel";
import { Mono, PageTitle, Panel, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function RoleDetail({ params }: { params: Promise<{ chain: string; am: string; id: string }> }) {
  const { chain, am, id } = await params;
  const cfg = chainBySlug(chain)!;
  const kind = parseAmKind(am)!;
  if (!hasSubgraph(cfg.chainId)) return <SubgraphMissing chainName={cfg.name} />;

  const v = await buildRoleView(cfg.chainId, kind, id);
  if (!v) notFound();

  return (
    <>
      <PageTitle
        title={v.name}
        subtitle={
          <>
            <Link href={`/${chain}/am/${am}`} className="text-muted hover:text-fg">
              ← roles
            </Link>{" "}
            · id <Mono>{v.id}</Mono>
          </>
        }
      />

      <Panel className="p-4 max-w-md">
        <div className="mb-2 text-[11px] uppercase tracking-wide text-muted">Config</div>
        <dl className="space-y-1 text-sm">
          <div className="flex justify-between gap-4">
            <dt className="text-muted">admin</dt>
            <dd><Mono>{v.config.adminRoleName}</Mono></dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-muted">guardian</dt>
            <dd><Mono>{v.config.guardianRoleName}</Mono></dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-muted">grant delay</dt>
            <dd><Mono>{fmtDelay(v.config.grantDelaySeconds)}</Mono></dd>
          </div>
        </dl>
      </Panel>

      <h2 className="mb-2 mt-6 text-sm font-semibold">Holders ({v.holders.length})</h2>
      <Panel>
        <Table
          head={
            <>
              <Th>Holder</Th>
              <Th>Address</Th>
              <Th>Execution delay</Th>
              <Th>Granted</Th>
            </>
          }
        >
          {v.holders.length === 0 && (
            <tr>
              <Td className="text-muted">— no active holders —</Td>
            </tr>
          )}
          {v.holders.map((h) => (
            <tr key={h.address} className="border-b border-border/50">
              <Td>
                <AddressLabel chainId={cfg.chainId} slug={chain} address={h.address} />
                {h.pendingDeployment && <span className="ml-2 text-[11px] text-med">pending deploy</span>}
              </Td>
              <Td>
                <Mono className="text-muted">{shorten(h.address)}</Mono>
              </Td>
              <Td>
                <Mono>{fmtDelay(h.executionDelaySeconds)}</Mono>
              </Td>
              <Td className="text-muted">{h.grantedAt ? <LocalTime unix={h.grantedAt} /> : "—"}</Td>
            </tr>
          ))}
        </Table>
      </Panel>

      <h2 className="mb-2 mt-6 text-sm font-semibold">Gated functions ({v.capabilities.length})</h2>
      <Panel>
        <Table head={<><Th>Target</Th><Th>Type</Th><Th>Function</Th><Th>Selector</Th></>}>
          {v.capabilities.length === 0 && (
            <tr>
              <Td className="text-muted">— no (target, selector) bindings —</Td>
            </tr>
          )}
          {v.capabilities.map((c) => (
            <tr key={`${c.target}-${c.selector}`} className="border-b border-border/50">
              <Td>{c.targetName}</Td>
              <Td className="text-muted">{c.targetType}</Td>
              <Td>
                <Mono>{c.fnName}</Mono>
              </Td>
              <Td>
                <Mono className="text-muted">{c.selector}</Mono>
              </Td>
            </tr>
          ))}
        </Table>
      </Panel>

      <h2 className="mb-2 mt-6 text-sm font-semibold">History ({v.history.length})</h2>
      <Panel>
        <Table head={<><Th>When</Th><Th>Event</Th><Th>Account</Th><Th>Change</Th><Th>Tx</Th></>}>
          {v.history.length === 0 && (
            <tr>
              <Td className="text-muted">— no events —</Td>
            </tr>
          )}
          {v.history.map((e, i) => (
            <tr key={i} className="border-b border-border/50">
              <Td className="whitespace-nowrap text-muted"><LocalTime unix={e.timestamp} /></Td>
              <Td>
                <Mono>{e.kind}</Mono>
              </Td>
              <Td>{e.account ? <AddressLabel chainId={cfg.chainId} slug={chain} address={e.account} /> : <span className="text-muted">—</span>}</Td>
              <Td className="text-muted">
                {e.oldValue != null || e.newValue != null ? (
                  <Mono>
                    {e.oldValue ?? "∅"} → {e.newValue ?? "∅"}
                  </Mono>
                ) : (
                  "—"
                )}
              </Td>
              <Td>
                <Mono className="text-muted">{shorten(e.txHash)}</Mono>
              </Td>
            </tr>
          ))}
        </Table>
      </Panel>
    </>
  );
}
