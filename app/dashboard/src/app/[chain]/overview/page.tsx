import Link from 'next/link';
import { chainBySlug } from '@/config/chains';
import { amKindsFor, managerFor } from '@/lib/catalog';
import { buildOverview, buildPendingAllChains } from '@/lib/overview';
import { fetchSafeQuorum, safeAppUrl } from '@/lib/safe';
import { fetchMeta, hasSubgraph } from '@/lib/subgraph';
import { TargetChip } from '@/components/AddressLabel';
import { LocalTime } from '@/components/LocalTime';
import { Pipeline } from '@/components/Pipeline';
import {
  AmBadge,
  Empty,
  Eyebrow,
  Mono,
  Panel,
  SubgraphMissing,
  Table,
  Td,
  Th,
} from '@/components/ui';

export const dynamic = 'force-dynamic';

function fmtEta(schedule: number, expiresAt: number, now: number): string {
  if (now > expiresAt) return 'expired';
  const s = schedule - now;
  if (s <= 0) return 'ready';
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `in ${h}h ${String(m).padStart(2, '0')}m` : `in ${m}m`;
}

export default async function OverviewPage({
  params,
  searchParams,
}: {
  params: Promise<{ chain: string }>;
  searchParams: Promise<{ ops?: string }>;
}) {
  const { chain } = await params;
  const { ops: opsFilterRaw } = await searchParams;
  const opsFilter = opsFilterRaw || 'active';
  const cfg = chainBySlug(chain)!;
  if (!hasSubgraph(cfg.chainId)) {
    return (
      <>
        <Eyebrow>Overview · {cfg.name}</Eyebrow>
        <SubgraphMissing chainName={cfg.name} />
      </>
    );
  }

  // WAY is the proposer — the multisig that schedules operations into the timelock.
  const way = managerFor(cfg.chainId, 'dawn')?.actors.find((a) => a.name === 'WAY')?.address;
  let ov, meta, quorum, pending;
  try {
    [ov, meta, quorum, pending] = await Promise.all([
      buildOverview(cfg.chainId),
      fetchMeta(cfg.chainId).catch(() => null),
      way ? fetchSafeQuorum(cfg.chainId, way) : Promise.resolve(null),
      buildPendingAllChains(),
    ]);
  } catch (e) {
    return (
      <>
        <Eyebrow>Overview · {cfg.name}</Eyebrow>
        <Empty>
          Failed to load subgraph: <Mono>{(e as Error).message}</Mono>
        </Empty>
      </>
    );
  }
  const now = Math.floor(Date.now() / 1000);
  const hasDay = amKindsFor(cfg.chainId).includes('day');

  const activeOps = pending.filter((o) => now <= o.expiresAt);
  const expiredOps = pending.filter((o) => now > o.expiresAt);
  const shownOps = opsFilter === 'active' ? activeOps : opsFilter === 'expired' ? expiredOps : pending;
  const opsChip = (key: string, label: string) => (
    <Link
      key={key}
      href={key === 'active' ? '?' : `?ops=${key}`}
      className={`rounded-md border px-2 py-0.5 text-xs ${
        opsFilter === key
          ? 'border-ok bg-ok-tint !text-ok'
          : 'border-border bg-panel text-body hover:border-ok hover:!text-ok'
      }`}
    >
      {label}
    </Link>
  );

  const stats: { label: string; value: string; unit?: string; right?: boolean }[] = [
    { label: 'Gated functions', value: String(ov.gatedFns) },
    { label: 'Pending ops', value: String(pending.length) },
    ...(ov.lastConfigChange
      ? [
          (() => {
            const h = Math.round((now - ov.lastConfigChange) / 3600);
            return h >= 48
              ? { label: 'Last config change', value: String(Math.round(h / 24)), unit: 'd ago' }
              : { label: 'Last config change', value: String(h), unit: 'h ago' };
          })(),
        ]
      : []),
    ...(ov.servedFullDelayPct !== null
      ? [{ label: 'Served full delay', value: String(ov.servedFullDelayPct), unit: '%' }]
      : []),
    { label: 'Markets', value: String(ov.marketCount), right: true },
    { label: 'Access managers', value: String(ov.managerCount), right: true },
  ];

  return (
    <div>
      <div className="flex items-baseline justify-between">
        <Eyebrow>Overview · {cfg.name}</Eyebrow>
        {meta && (
          <div className="flex items-center gap-2">
            <span className="h-[7px] w-[7px] animate-dotPulse rounded-full bg-ok" />
            <Eyebrow>Live · block {meta.block.number}</Eyebrow>
          </div>
        )}
      </div>
      <h1 className="mt-2 max-w-2xl font-serif text-[26px] font-semibold leading-tight md:text-[34px]">
        Every privileged action, <span className="text-ok">gated</span> and timelocked.
      </h1>
      <p className="mt-2.5 max-w-xl text-sm text-body">
        Every core protocol change is proposed by a signer quorum, held in a 72-hour public
        timelock, and screened for the full window. Guardians can cancel it at any moment.
      </p>

      <Pipeline safeUrl={way ? safeAppUrl(cfg.chainId, way) : null} quorum={quorum ?? null} />

      {/* compact pipeline summary — stands in for the diagram on phones */}
      <div className="mt-5 rounded-xl border border-border bg-panel px-4 py-3 text-[13px] leading-relaxed text-body md:hidden">
        Proposed <span className="text-muted">→</span>{' '}
        <span className="font-medium text-fg">
          {quorum ? `${quorum.threshold}-of-${quorum.owners} multisig` : 'multisig quorum'}
        </span>{' '}
        <span className="text-muted">→</span> <span className="font-medium text-ok">72h screened timelock</span>{' '}
        <span className="text-muted">→</span> executed, or <span className="text-high">guardian-cancelled</span> at
        any point in the window.
      </div>

      {/* delay ladder — computed from live bindings × role holder delays */}
      <div className="mt-6 rounded-xl border border-border bg-panel">
        <div className="flex items-center px-4 py-2.5">
          <span className="font-mono text-[10px] tracking-[0.12em] text-fg">DELAY LADDER</span>
          <div className="flex-1" />
          <span className="font-mono text-[10px] tracking-[0.06em] text-muted">
            {ov.gatedFns} GATED FUNCTIONS
          </span>
        </div>
        {ov.ladder.map((t) => (
          <div
            key={t.key}
            className={`flex flex-wrap items-center gap-x-3.5 gap-y-1 border-t border-border2 px-4 py-3 ${t.hero ? 'bg-[rgba(60,194,123,0.05)]' : ''}`}
          >
            <div className="w-[130px] shrink-0 font-mono text-[10px] tracking-[0.1em] text-muted max-md:order-first max-md:w-full">
              {t.tier}
            </div>
            <div
              className={`w-16 shrink-0 font-mono text-base ${t.hero ? 'text-ok' : 'text-fg'}`}
            >
              {t.delay}
            </div>
            <div className="min-w-0 flex-1 text-[12.5px] text-body">
              {t.tip ? (
                <span className="group relative cursor-help underline decoration-[#D6D2C6] decoration-dotted underline-offset-4">
                  {t.desc}
                  <span className="pointer-events-none absolute left-0 top-full z-20 mt-2 w-[420px] max-w-[85vw] rounded-lg border border-border bg-panel p-3 text-xs leading-relaxed text-body opacity-0 shadow-[0_8px_24px_rgba(15,14,13,0.08)] transition-opacity duration-100 group-hover:opacity-100">
                    {t.tip}
                  </span>
                </span>
              ) : (
                t.desc
              )}
            </div>
            <div className="shrink-0 font-mono text-[11px] text-muted">{t.count} fns</div>
          </div>
        ))}
      </div>

      {/* pending operations across every chain and both AMs */}
      <div className="mb-3 mt-8 flex flex-wrap items-baseline gap-x-3 gap-y-2">
        <Eyebrow>Pending operations · All chains</Eyebrow>
        <div className="ml-1 flex items-center gap-1.5">
          {opsChip('active', `Active (${activeOps.length})`)}
          {opsChip('expired', `Expired (${expiredOps.length})`)}
          {opsChip('all', `All (${pending.length})`)}
        </div>
        <div className="flex-1" />
        {hasDay && (
          <Link
            href={`/${chain}/am/day/operations`}
            className="rounded-md bg-ok-tint px-2 py-0.5 text-xs font-medium !text-ok"
          >
            Day AM →
          </Link>
        )}
        <Link
          href={`/${chain}/am/dawn/operations`}
          className="rounded-md bg-bronze-tint px-2 py-0.5 text-xs font-medium !text-bronze"
        >
          Dawn AM →
        </Link>
      </div>
      {shownOps.length === 0 ? (
        <Empty>
          {pending.length === 0
            ? 'No pending privileged operations on any chain. Nothing in the core protocol can change for at least 72 hours from now.'
            : opsFilter === 'active'
              ? `No active operations on any chain. ${expiredOps.length} expired op(s) hidden; nothing in the core protocol can change for at least 72 hours from now.`
              : 'No operations match this filter.'}
        </Empty>
      ) : (
        <Panel>
          <Table
            head={
              <>
                <Th className="w-[110px]">Chain</Th>
                <Th className="w-[90px]">AM</Th>
                <Th>Operation</Th>
                <Th>Target</Th>
                <Th>Scheduled</Th>
                <Th className="text-right">Executable</Th>
              </>
            }
          >
            {shownOps.map((o) => (
              <tr key={o.id}>
                <Td>
                  <Link href={`/${o.slug}/am/${o.am}/operations`} className="text-[13px] text-body hover:text-ok">
                    {o.chainName}
                  </Link>
                </Td>
                <Td>
                  <AmBadge kind={o.am} />
                </Td>
                <Td>
                  <Link href={`/${o.slug}/am/${o.am}/operations/${o.opId}`} className="hover:text-ok">
                    <Mono>{o.fn}</Mono>
                  </Link>
                </Td>
                <Td>
                  <TargetChip chainId={o.chainId} slug={o.slug} address={o.target} />
                </Td>
                <Td className="text-[13px] text-body">
                  <LocalTime unix={o.scheduledAt} />
                </Td>
                <Td className="text-right">
                  <Mono className={now > o.expiresAt ? 'text-muted' : 'text-med'}>
                    {fmtEta(o.schedule, o.expiresAt, now)}
                  </Mono>
                </Td>
              </tr>
            ))}
          </Table>
        </Panel>
      )}

      {/* the meta-invariant */}
      <div className="mt-6 flex items-baseline justify-center gap-2.5 border-y border-border py-3.5">
        <span className="relative top-px h-2 w-2 shrink-0 rounded-full bg-ok" />
        <div className="text-center text-[13px] text-body">
          <span className="font-semibold text-fg">The rules gate themselves.</span> Changing any
          role, delay, or guardian is itself an admin operation, subject to the same{' '}
          <span className="rounded-md bg-ok-tint px-1.5 py-px font-mono text-xs text-ok">
            72h delay
          </span>
          .
        </div>
      </div>

      {/* stats — control-plane numbers left, inventory (markets / AMs) pushed right */}
      <div className="mt-10 grid grid-cols-2 gap-y-5 border-y border-border py-4 md:flex md:flex-wrap md:items-stretch md:py-0">
        {stats.map((s, i) => (
          <div
            key={s.label}
            className={`md:px-6 md:py-4 ${i === 0 ? 'md:pl-0' : 'md:border-l md:border-border'} ${
              s.label === 'Markets' ? 'md:ml-auto' : ''
            } ${s.right ? 'md:text-right' : ''}`}
          >
            <div className="whitespace-nowrap font-mono text-[11px] uppercase tracking-[0.1em] text-muted">
              {s.label}
            </div>
            <div className="mt-0.5 whitespace-nowrap font-mono text-2xl text-fg md:text-3xl">
              {s.value}
              {s.unit && <span className="text-[15px] text-muted"> {s.unit}</span>}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
