import Link from "next/link";
import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { managerFor, parseAmKind, selectorName } from "@/lib/catalog";
import { warmMarketLabels } from "@/lib/markets";
import { decodeCalldata } from "@/lib/decode";
import { explorerAddress, explorerTx } from "@/lib/format";
import { fetchOperation, hasSubgraph } from "@/lib/subgraph";
import { AddressLabel, TargetChip } from "@/components/AddressLabel";
import { LocalTime } from "@/components/LocalTime";
import { AmBadge, Eyebrow, Mono, Panel, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

const STATUS_STYLE: Record<string, string> = {
  Scheduled: "bg-med-tint text-med",
  Executed: "bg-ok-tint text-ok",
  Canceled: "bg-high-tint text-high",
};

function ExplorerLink({ href }: { href: string }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="font-mono text-[11px] !text-muted hover:!text-ok">
      ↗
    </a>
  );
}

function TxRow({ label, hash, chainId }: { label: string; hash: string | null; chainId: number }) {
  if (!hash) return null;
  return (
    <tr>
      <Td className="w-44 text-[13px] text-muted">{label}</Td>
      <Td>
        <a
          href={explorerTx(chainId, hash)}
          target="_blank"
          rel="noreferrer"
          className="font-mono text-xs text-body hover:!text-ok"
        >
          {hash} ↗
        </a>
      </Td>
    </tr>
  );
}

// Full detail for one timelocked operation: timing, target/caller, decoded calldata, provenance.
export default async function OperationDetailPage({
  params,
}: {
  params: Promise<{ chain: string; am: string; id: string }>;
}) {
  const { chain, am, id } = await params;
  const cfg = chainBySlug(chain)!;
  const kind = parseAmKind(am);
  if (!kind || !hasSubgraph(cfg.chainId)) notFound();
  const mgr = managerFor(cfg.chainId, kind);
  if (!mgr) notFound();

  const [op] = await Promise.all([
    fetchOperation(cfg.chainId, decodeURIComponent(id)).catch(() => null),
    warmMarketLabels(cfg.chainId).catch(() => {}),
  ]);
  if (!op || op.manager.kind !== kind) notFound();

  const now = Math.floor(Date.now() / 1000);
  const schedule = Number(op.schedule);
  const expiresAt = schedule + mgr.expiration;
  const decoded = decodeCalldata(op.data);
  const fn = selectorName(op.data.slice(0, 10));
  const statusLabel =
    op.status === "Scheduled" && now > expiresAt ? "Expired" : op.status === "Scheduled" && now >= schedule ? "Ready" : op.status;

  return (
    <div>
      <Link href={`/${chain}/am/${am}/operations`} className="text-xs !text-muted hover:!text-fg">
        ← Pending operations
      </Link>
      <div className="mt-2.5 flex items-center gap-3.5">
        <h1 className="font-serif text-3xl font-semibold">
          <Mono className="font-sans">{fn}</Mono>
        </h1>
        <span className={`rounded-md px-2 py-0.5 text-xs font-medium ${STATUS_STYLE[op.status]}`}>{statusLabel}</span>
        <AmBadge kind={kind} />
      </div>

      <Eyebrow className="mb-2.5 mt-7">Timeline</Eyebrow>
      <Panel>
        <Table>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Scheduled</Td>
            <Td className="text-[13px] text-body">
              <LocalTime unix={Number(op.scheduledAt)} />
            </Td>
          </tr>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Executable</Td>
            <Td className="text-[13px] text-body">
              <LocalTime unix={schedule} />{" "}
              {op.status === "Scheduled" && (
                <span className="text-muted">{now >= schedule ? "· ready now" : ""}</span>
              )}
            </Td>
          </tr>
          {op.status === "Scheduled" && (
            <tr>
              <Td className="w-44 text-[13px] text-muted">Expires</Td>
              <Td className="text-[13px] text-body">
                <LocalTime unix={expiresAt} />
                <span className="text-muted"> · unexecuted operations lapse {mgr.expiration / 3600}h after unlock</span>
              </Td>
            </tr>
          )}
          {op.executedAt && (
            <tr>
              <Td className="w-44 text-[13px] text-muted">Executed</Td>
              <Td className="text-[13px] text-body">
                <LocalTime unix={Number(op.executedAt)} />
              </Td>
            </tr>
          )}
          {op.canceledAt && (
            <tr>
              <Td className="w-44 text-[13px] text-muted">Cancelled</Td>
              <Td className="text-[13px] text-body">
                <LocalTime unix={Number(op.canceledAt)} />
              </Td>
            </tr>
          )}
        </Table>
      </Panel>

      <Eyebrow className="mb-2.5 mt-7">Call</Eyebrow>
      <Panel>
        <Table>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Target</Td>
            <Td>
              <TargetChip chainId={cfg.chainId} slug={chain} address={op.target} />
            </Td>
            <Td className="w-[400px]">
              <Mono className="text-muted">{op.target}</Mono> <ExplorerLink href={explorerAddress(cfg.chainId, op.target)} />
            </Td>
          </tr>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Scheduled by</Td>
            <Td>
              <AddressLabel chainId={cfg.chainId} slug={chain} address={op.caller} />
            </Td>
            <Td className="w-[400px]">
              <Mono className="text-muted">{op.caller}</Mono> <ExplorerLink href={explorerAddress(cfg.chainId, op.caller)} />
            </Td>
          </tr>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Function</Td>
            <Td colSpan={2}>
              <Mono className="text-body">{decoded?.signature ?? fn}</Mono>
            </Td>
          </tr>
        </Table>
      </Panel>

      <Eyebrow className="mb-2.5 mt-7">Decoded calldata</Eyebrow>
      <Panel>
        {decoded ? (
          decoded.args.length === 0 ? (
            <div className="p-5 text-sm text-muted">No arguments.</div>
          ) : (
            <Table head={<><Th className="w-44">Parameter</Th><Th className="w-64">Type</Th><Th>Value</Th></>}>
              {decoded.args.map((a, i) => (
                <tr key={i}>
                  <Td className="text-[13px] text-muted">{a.name}</Td>
                  <Td>
                    <Mono className="text-muted">{a.type}</Mono>
                  </Td>
                  <Td>
                    {a.isAddress ? (
                      <span className="inline-flex items-center gap-2">
                        <AddressLabel chainId={cfg.chainId} slug={chain} address={a.value} />
                        <Mono className="text-[11px] text-muted">{a.value}</Mono>
                      </span>
                    ) : (
                      <Mono className="break-all text-xs text-body">{a.value}</Mono>
                    )}
                  </Td>
                </tr>
              ))}
            </Table>
          )
        ) : (
          <div className="p-5 text-sm text-muted">
            Unknown selector <Mono>{op.data.slice(0, 10)}</Mono> — showing raw calldata only.
          </div>
        )}
        <div className="border-t border-border2 px-5 py-4">
          <div className="mb-1.5 font-mono text-[10px] tracking-[0.12em] text-muted">RAW CALLDATA</div>
          <Mono className="break-all text-[11px] leading-relaxed text-muted">{op.data}</Mono>
        </div>
      </Panel>

      <Eyebrow className="mb-2.5 mt-7">Provenance</Eyebrow>
      <Panel>
        <Table>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Operation id</Td>
            <Td>
              <Mono className="break-all text-xs text-body">{op.operationId}</Mono>
            </Td>
          </tr>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Nonce</Td>
            <Td>
              <Mono className="text-xs text-body">{op.nonce}</Mono>
            </Td>
          </tr>
          <tr>
            <Td className="w-44 text-[13px] text-muted">Access manager</Td>
            <Td>
              <Mono className="text-xs text-body">{op.manager.id}</Mono>{" "}
              <ExplorerLink href={explorerAddress(cfg.chainId, op.manager.id)} />
            </Td>
          </tr>
          <TxRow label="Schedule tx" hash={op.scheduleTx} chainId={cfg.chainId} />
          <TxRow label="Execute tx" hash={op.executeTx} chainId={cfg.chainId} />
          <TxRow label="Cancel tx" hash={op.cancelTx} chainId={cfg.chainId} />
        </Table>
      </Panel>
    </div>
  );
}
