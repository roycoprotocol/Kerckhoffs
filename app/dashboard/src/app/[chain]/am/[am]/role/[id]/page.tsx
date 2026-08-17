import Link from "next/link";
import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { hasSubgraph } from "@/lib/subgraph";
import { buildRoleView } from "@/lib/merge";
import { fmtDelay, fmtTime, shorten } from "@/lib/format";
import { AddressLabel } from "@/components/AddressLabel";
import { DriftBadge, Mono, PageTitle, Panel, SeverityPill, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function RoleDetail({ params }: { params: Promise<{ chain: string; id: string }> }) {
  const { chain, id } = await params;
  const cfg = chainBySlug(chain)!;
  if (!hasSubgraph(cfg.chainId)) return <SubgraphMissing chainName={cfg.name} />;

  const v = await buildRoleView(cfg.chainId, id);
  if (!v) notFound();

  const ec = v.expectedConfig;
  const cmp = (actual: string | number, expected: string | number | undefined, fmt: (x: number) => string = String) => {
    const a = typeof actual === "number" ? fmt(actual) : actual;
    const e = expected === undefined ? null : typeof expected === "number" ? fmt(expected) : expected;
    const mismatch = e !== null && e !== a;
    return (
      <span>
        <Mono className={mismatch ? "text-high" : ""}>{a}</Mono>
        {mismatch && <span className="ml-2 text-[11px] text-muted">expected {e}</span>}
      </span>
    );
  };

  return (
    <>
      <PageTitle
        title={v.name}
        subtitle={
          <>
            <Link href={`/${chain}`} className="text-muted hover:text-fg">
              ← roles
            </Link>{" "}
            · id <Mono>{v.id}</Mono> · {v.presentOnChain ? "configured on-chain" : "not configured on-chain"}
          </>
        }
      />

      {v.description && <p className="mb-5 max-w-3xl text-sm text-muted">{v.description}</p>}

      <div className="grid gap-4 md:grid-cols-3">
        <Panel className="p-4">
          <div className="mb-2 text-[11px] uppercase tracking-wide text-muted">Config</div>
          <dl className="space-y-1 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-muted">admin</dt>
              <dd>{cmp(v.config.adminRoleName, ec?.adminRoleName)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted">guardian</dt>
              <dd>{cmp(v.config.guardianRoleName, ec?.guardianRoleName)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted">grant delay</dt>
              <dd>{cmp(v.config.grantDelaySeconds, ec?.grantDelaySeconds, fmtDelay)}</dd>
            </div>
          </dl>
        </Panel>
        <Panel className="p-4 md:col-span-2">
          <div className="mb-2 flex items-center justify-between">
            <span className="text-[11px] uppercase tracking-wide text-muted">Drift</span>
            <DriftBadge drift={v.drift} />
          </div>
          {v.drift.length === 0 ? (
            <p className="text-sm text-ok">Matches the canonical model.</p>
          ) : (
            <ul className="space-y-1 text-sm">
              {v.drift.map((d, i) => (
                <li key={i} className="flex flex-wrap items-center gap-2">
                  <SeverityPill sev={d.severity} />
                  <span className="text-muted">{d.field}:</span>
                  <Mono className="text-high">{d.actual}</Mono>
                  <span className="text-muted">vs expected</span>
                  <Mono>{d.expected}</Mono>
                  {d.note && <span className="text-[11px] text-muted">— {d.note}</span>}
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>

      <h2 className="mb-2 mt-6 text-sm font-semibold">Holders ({v.holders.length})</h2>
      <Panel>
        <Table
          head={
            <>
              <Th>Holder</Th>
              <Th>Address</Th>
              <Th>Execution delay</Th>
              <Th>Expected</Th>
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
              <Td>{h.expected ? <span className="text-ok">✓</span> : <span className="text-high">unexpected</span>}</Td>
              <Td className="text-muted">{h.grantedAt ? fmtTime(h.grantedAt) : "—"}</Td>
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
              <Td className="whitespace-nowrap text-muted">{fmtTime(e.timestamp)}</Td>
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
