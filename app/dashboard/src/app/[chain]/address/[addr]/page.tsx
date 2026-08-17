import Link from "next/link";
import { chainBySlug } from "@/config/chains";
import { fetchAccount, fetchTarget, hasSubgraph, type SgAccount, type SgTarget } from "@/lib/subgraph";
import { amLabel, managersFor, roleName, selectorName } from "@/lib/catalog";
import { resolveLabel } from "@/lib/labels";
import { warmMarketLabels } from "@/lib/markets";
import { fmtDelay } from "@/lib/format";
import { AddrLink, CategoryBadge } from "@/components/AddressLabel";
import { AmBadge, Empty, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";
import type { AmKind } from "@/model";

export const dynamic = "force-dynamic";

// Unified address page, spanning BOTH AccessManagers: roles held are grouped per AM, and the
// target view renders one panel per AM that gates this address (a vault mid-migration shows both).
export default async function AddressPage({ params }: { params: Promise<{ chain: string; addr: string }> }) {
  const { chain, addr } = await params;
  const cfg = chainBySlug(chain)!;
  await warmMarketLabels(cfg.chainId).catch(() => {});
  const label = resolveLabel(cfg.chainId, addr);
  const managers = managersFor(cfg.chainId);

  let account: SgAccount | null = null;
  let targets: { kind: AmKind; target: SgTarget }[] = [];
  if (hasSubgraph(cfg.chainId)) {
    const [acct, ...perManager] = await Promise.all([
      fetchAccount(cfg.chainId, addr).catch(() => null),
      ...managers.map((m) =>
        fetchTarget(cfg.chainId, m.address, addr)
          .then((t) => ({ kind: m.kind, target: t }))
          .catch(() => ({ kind: m.kind, target: null })),
      ),
    ]);
    account = acct;
    targets = perManager.filter((x): x is { kind: AmKind; target: SgTarget } => !!x.target);
  }

  // Roles held, grouped per AM (role ids collide across AMs, so grouping is by manager address).
  // Only managers in the catalog are shown: grafted subgraph stores retain rows from retired
  // deployments (e.g. the pre-production Day AM), which are history, not the tracked control plane.
  const kindByManagerAddr = new Map(managers.map((m) => [m.address.toLowerCase(), m.kind]));
  const rolesByKind = new Map<AmKind, { roleId: string; executionDelay: string }[]>();
  for (const r of account?.roles ?? []) {
    const kind = kindByManagerAddr.get(r.role.manager.id.toLowerCase());
    if (!kind) continue;
    if (!rolesByKind.has(kind)) rolesByKind.set(kind, []);
    rolesByKind.get(kind)!.push({ roleId: r.role.roleId, executionDelay: r.executionDelay });
  }

  const holdsRoles = rolesByKind.size > 0;
  const isTarget = targets.length > 0;

  return (
    <>
      <PageTitle
        title={label.name}
        subtitle={
          <span className="inline-flex flex-wrap items-center gap-2">
            <Link href={`/${chain}/contracts`} className="text-muted hover:text-fg">
              ← directory
            </Link>
            <CategoryBadge category={label.category} />
            {label.parent && <span className="text-muted">{label.parent} › {label.subtype}</span>}
            <AddrLink chainId={cfg.chainId} address={addr} />
            {label.pendingDeployment && <span className="text-med">pending deployment</span>}
            {label.isExternal && !label.known && <span className="text-muted">unlabeled</span>}
            {label.tags.map((t) => (
              <span key={t} className="rounded bg-border px-1.5 py-0.5 text-[11px] text-muted">
                {t}
              </span>
            ))}
          </span>
        }
      />

      {!hasSubgraph(cfg.chainId) ? (
        <SubgraphMissing chainName={cfg.name} />
      ) : !holdsRoles && !isTarget ? (
        <Empty>Holds no active AccessManager roles and is not an AM-gated target on {cfg.name}.</Empty>
      ) : (
        <div className="space-y-6">
          {[...rolesByKind.entries()].map(([kind, roles]) => (
            <div key={kind}>
              <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                Roles held — {amLabel(kind)} ({roles.length}) <AmBadge kind={kind} />
              </h2>
              <Panel>
                <Table head={<><Th>Role</Th><Th>Execution delay</Th></>}>
                  {roles.map((r) => (
                    <tr key={r.roleId} className="border-b border-border/50">
                      <Td>
                        <RoleLink slug={chain} am={kind} id={r.roleId} name={roleName(cfg.chainId, kind, r.roleId)} />
                      </Td>
                      <Td>
                        <Mono>{fmtDelay(Number(r.executionDelay))}</Mono>
                      </Td>
                    </tr>
                  ))}
                </Table>
              </Panel>
            </div>
          ))}

          {targets.map(({ kind, target }) => {
            const fnsByRole = new Map<string, string[]>();
            for (const f of target.functions) {
              if (!fnsByRole.has(f.role.roleId)) fnsByRole.set(f.role.roleId, []);
              fnsByRole.get(f.role.roleId)!.push(f.selector);
            }
            return (
              <div key={kind}>
                <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                  Gated by {amLabel(kind)} · {target.functions.length} functions <AmBadge kind={kind} />
                  {target.closed && <span className="text-med">closed</span>}
                  {Number(target.adminDelay) > 0 && (
                    <span className="text-muted">admin delay {fmtDelay(Number(target.adminDelay))}</span>
                  )}
                </h2>
                <Panel>
                  <Table head={<><Th>Gated by role</Th><Th>Functions</Th></>}>
                    {[...fnsByRole.entries()].map(([roleId, selectors]) => (
                      <tr key={roleId} className="border-b border-border/50">
                        <Td>
                          <RoleLink slug={chain} am={kind} id={roleId} name={roleName(cfg.chainId, kind, roleId)} />
                        </Td>
                        <Td>
                          <span className="flex flex-wrap gap-1">
                            {selectors.map((s) => (
                              <Mono key={s} className="rounded bg-border/60 px-1.5 py-0.5 text-[12px]">
                                {selectorName(s)}
                              </Mono>
                            ))}
                          </span>
                        </Td>
                      </tr>
                    ))}
                  </Table>
                </Panel>
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}
