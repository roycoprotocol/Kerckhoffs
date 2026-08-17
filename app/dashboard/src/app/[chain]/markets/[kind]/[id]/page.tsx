import Link from "next/link";
import { notFound } from "next/navigation";
import { chainBySlug } from "@/config/chains";
import { isVerifiedMarket, managerFor, parseAmKind, roleName, selectorName } from "@/lib/catalog";
import { fetchAllRoles, fetchTarget, hasSubgraph } from "@/lib/subgraph";
import { fetchCurrentMarkets, marketDisplay, MARKET_COMPONENTS, roycoMarketUrl, warmMarketLabels, ZERO_ADDR } from "@/lib/markets";
import { AddressLabel, AddrLink, AM_COLOR } from "@/components/AddressLabel";
import { Callers, holdersByRole } from "@/components/Callers";
import { LocalTime } from "@/components/LocalTime";
import { UnverifiedBadge } from "../../shared";
import { AmBadge, Eyebrow, Mono, Panel, RoleLink, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

// Market detail: one section per component contract, its AM-gated functions listed beneath —
// each with the required role and every address currently able to call it.
export default async function MarketDetailPage({
  params,
}: {
  params: Promise<{ chain: string; kind: string; id: string }>;
}) {
  const { chain, kind: kindRaw, id } = await params;
  const cfg = chainBySlug(chain)!;
  const kind = parseAmKind(kindRaw);
  if (!kind || !hasSubgraph(cfg.chainId)) notFound();
  const mgr = managerFor(cfg.chainId, kind);
  if (!mgr) notFound();

  await warmMarketLabels(cfg.chainId).catch(() => {});
  const [markets, roles] = await Promise.all([
    fetchCurrentMarkets(cfg.chainId, kind).catch(() => []),
    fetchAllRoles(cfg.chainId, mgr.address).catch(() => []),
  ]);
  const m = markets.find((x) => x.id.toLowerCase() === id.toLowerCase());
  if (!m) notFound();
  const callersByRole = holdersByRole(roles);

  const components = MARKET_COMPONENTS.filter((c) => m[c.key] && m[c.key] !== ZERO_ADDR).map((c) => ({
    type: c.label,
    address: String(m[c.key]).toLowerCase(),
  }));

  // Gated functions per component, from the owning AM's target rows (one fetch per component).
  const sections = await Promise.all(
    components.map(async (c) => ({
      ...c,
      functions: await fetchTarget(cfg.chainId, mgr.address, c.address)
        .then((t) => t?.functions ?? [])
        .catch(() => []),
    })),
  );

  const verified = isVerifiedMarket(cfg.chainId, m.kernel);

  return (
    <div>
      <Link href={`/${chain}/markets/${kind}`} className="text-xs !text-muted hover:!text-fg">
        ← All markets
      </Link>
      <div className="mt-2.5 flex flex-wrap items-baseline justify-between gap-y-1.5">
        <div className="flex flex-wrap items-center gap-x-3.5 gap-y-1.5">
          <span
            className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
            style={{ backgroundColor: AM_COLOR[kind] }}
          />
          <h1 className="font-serif text-2xl font-semibold md:text-3xl">{marketDisplay(cfg.chainId, m).title}.</h1>
          {marketDisplay(cfg.chainId, m).hint && (
            <Mono className="text-xs text-muted">{marketDisplay(cfg.chainId, m).hint}</Mono>
          )}
          <AmBadge kind={kind} />
          {!verified && <UnverifiedBadge />}
          {kind === "dawn" && verified && (
            <a
              href={roycoMarketUrl(cfg.chainId, m.kernel)}
              target="_blank"
              rel="noreferrer"
              className="text-xs !text-bronze"
            >
              royco.org ↗
            </a>
          )}
        </div>
        <div className="flex flex-wrap items-baseline gap-x-5 gap-y-1 max-md:w-full">
          <span className="text-xs text-muted">
            deployed <LocalTime unix={Number(m.timestamp)} />
          </span>
          {m.deployer && (
            <span className="font-mono text-xs text-muted">
              by <AddressLabel chainId={cfg.chainId} slug={chain} address={m.deployer} />
            </span>
          )}
        </div>
      </div>

      {sections.map((s) => (
        <div key={s.address} className="mt-8">
          <div className="mb-2.5 flex flex-wrap items-baseline gap-x-3.5 gap-y-1">
            <Eyebrow>{s.type}</Eyebrow>
            <AddrLink chainId={cfg.chainId} address={s.address} />
          </div>
          <Panel>
            {s.functions.length === 0 ? (
              <div className="p-5 text-center text-sm text-muted">
                No AM-gated functions indexed on this contract.
              </div>
            ) : (
              <Table
                head={
                  <>
                    <Th className="w-72">Function</Th>
                    <Th className="w-28">Selector</Th>
                    <Th className="w-64">Role</Th>
                    <Th>Callable by</Th>
                  </>
                }
              >
                {s.functions.map((f) => (
                  <tr key={f.selector}>
                    <Td>
                      <Mono className="text-body">{selectorName(f.selector)}</Mono>
                    </Td>
                    <Td>
                      <Mono className="text-muted">{f.selector}</Mono>
                    </Td>
                    <Td>
                      <RoleLink
                        slug={chain}
                        am={kind}
                        id={f.role.roleId}
                        name={roleName(cfg.chainId, kind, f.role.roleId)}
                      />
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
            )}
          </Panel>
        </div>
      ))}
    </div>
  );
}
