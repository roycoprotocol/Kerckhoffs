import Link from "next/link";
import { chainBySlug } from "@/config/chains";
import { fetchAccount, fetchTarget, hasSubgraph, type SgTarget } from "@/lib/subgraph";
import { roleName, selectorName } from "@/lib/catalog";
import { resolveLabel } from "@/lib/labels";
import { fmtDelay } from "@/lib/format";
import { CategoryBadge } from "@/components/AddressLabel";
import { Empty, Mono, PageTitle, Panel, RoleLink, SubgraphMissing, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function AddressPage({ params }: { params: Promise<{ chain: string; addr: string }> }) {
  const { chain, addr } = await params;
  const cfg = chainBySlug(chain)!;
  const label = resolveLabel(cfg.chainId, addr);

  let account = null;
  let target: SgTarget | null = null;
  if (hasSubgraph(cfg.chainId)) {
    [account, target] = await Promise.all([
      fetchAccount(cfg.chainId, addr).catch(() => null),
      fetchTarget(cfg.chainId, addr).catch(() => null),
    ]);
  }

  const holdsRoles = (account?.roles.length ?? 0) > 0;
  const isTarget = !!target;

  // group target functions by gating role
  const fnsByRole = new Map<string, string[]>();
  for (const f of target?.functions ?? []) {
    if (!fnsByRole.has(f.role.id)) fnsByRole.set(f.role.id, []);
    fnsByRole.get(f.role.id)!.push(f.selector);
  }

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
            <Mono className="text-muted">{addr}</Mono>
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
          {holdsRoles && (
            <div>
              <h2 className="mb-2 text-sm font-semibold">Roles held ({account!.roles.length})</h2>
              <Panel>
                <Table head={<><Th>Role</Th><Th>Execution delay</Th></>}>
                  {account!.roles.map((r) => (
                    <tr key={r.role.id} className="border-b border-border/50">
                      <Td>
                        <RoleLink slug={chain} id={r.role.id} name={roleName(cfg.chainId, r.role.id)} />
                      </Td>
                      <Td>
                        <Mono>{fmtDelay(Number(r.executionDelay))}</Mono>
                      </Td>
                    </tr>
                  ))}
                </Table>
              </Panel>
            </div>
          )}

          {isTarget && (
            <div>
              <h2 className="mb-2 text-sm font-semibold">
                AM-gated target · {target!.functions.length} functions
                {target!.closed && <span className="ml-2 text-med">closed</span>}
                {Number(target!.adminDelay) > 0 && (
                  <span className="ml-2 text-muted">admin delay {fmtDelay(Number(target!.adminDelay))}</span>
                )}
              </h2>
              <Panel>
                <Table head={<><Th>Gated by role</Th><Th>Functions</Th></>}>
                  {[...fnsByRole.entries()].map(([roleId, selectors]) => (
                    <tr key={roleId} className="border-b border-border/50">
                      <Td>
                        <RoleLink slug={chain} id={roleId} name={roleName(cfg.chainId, roleId)} />
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
          )}
        </div>
      )}
    </>
  );
}
