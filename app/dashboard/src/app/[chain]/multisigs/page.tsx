import { chainBySlug } from "@/config/chains";
import type { AmKind } from "@/model";
import { actorDisplayName, managersFor, roleName, type CatalogActor } from "@/lib/catalog";
import { fmtDelay } from "@/lib/format";
import { AddrLink } from "@/components/AddressLabel";
import { fetchSafeQuorum, safeAppUrl } from "@/lib/safe";
import { fetchAccount, hasSubgraph } from "@/lib/subgraph";
import { AmBadge, Eyebrow, Mono, PageTitle, Panel, RoleLink } from "@/components/ui";
import multisigMeta from "@/metadata/multisigs.json";

export const dynamic = "force-dynamic";

const META = multisigMeta as Record<string, { title: string; description: string }>;
const ORDER = Object.keys(META); // governance-first curated order

interface HeldRole {
  am: AmKind;
  roleId: string;
  delay: number;
}

// Every multisig in the security model: who it is, what it can do, and its live Safe quorum.
export default async function MultisigsPage({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  const cfg = chainBySlug(chain)!;

  // Multisig actors across both managers, deduped by address (FNDN etc. appear on both AMs).
  const byName = new Map<string, CatalogActor>();
  for (const mgr of managersFor(cfg.chainId)) {
    for (const a of mgr.actors) {
      if (a.category === "multisig" && !byName.has(a.name)) byName.set(a.name, a);
    }
  }
  const sigs = [...byName.values()].sort((a, b) => {
    const ia = ORDER.indexOf(a.name);
    const ib = ORDER.indexOf(b.name);
    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
  });

  const detailed = await Promise.all(
    sigs.map(async (a) => {
      const [quorum, account] = await Promise.all([
        fetchSafeQuorum(cfg.chainId, a.address),
        hasSubgraph(cfg.chainId) ? fetchAccount(cfg.chainId, a.address).catch(() => null) : Promise.resolve(null),
      ]);
      const roles: HeldRole[] = (account?.roles ?? []).map((r) => ({
        am: (r.role.manager.kind === "day" ? "day" : "dawn") as AmKind,
        roleId: r.role.roleId,
        delay: Number(r.executionDelay),
      }));
      roles.sort((x, y) => x.am.localeCompare(y.am) || y.delay - x.delay);
      return { ...a, quorum, roles };
    }),
  );

  return (
    <>
      <PageTitle
        eyebrow={`Multisigs · ${cfg.name}`}
        accent="Signers"
        title="Multisigs."
        subtitle="Every multisig in the security model, its live signer quorum, and the roles it holds on each access manager."
      />
      <div className="mt-6 flex flex-col gap-4">
        {detailed.map((s) => {
          const meta = META[s.name];
          return (
            <Panel key={s.address} className="p-5">
              <div className="flex flex-wrap items-baseline gap-3">
                <h2 className="font-serif text-xl font-semibold">{meta?.title ?? actorDisplayName(s.name)}</h2>
                <Mono className="text-xs text-muted">{actorDisplayName(s.name)}</Mono>
                <div className="flex-1" />
                <a
                  href={safeAppUrl(cfg.chainId, s.address)}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-md bg-bronze-tint px-2 py-0.5 font-mono text-xs !text-bronze"
                >
                  {s.quorum ? `${s.quorum.threshold} of ${s.quorum.owners} signers · ` : ""}Safe ↗
                </a>
              </div>
              <div className="mt-1.5">
                <AddrLink chainId={cfg.chainId} address={s.address} />
              </div>
              {meta && <p className="mt-3 max-w-3xl text-[13.5px] leading-relaxed text-body">{meta.description}</p>}
              {s.roles.length > 0 && (
                <div className="mt-4 border-t border-border2 pt-3.5">
                  <Eyebrow className="mb-2.5">Roles held</Eyebrow>
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                    {s.roles.map((r) => (
                      <span key={`${r.am}-${r.roleId}`} className="inline-flex items-center gap-1.5">
                        <AmBadge kind={r.am} />
                        <RoleLink slug={chain} am={r.am} id={r.roleId} name={roleName(cfg.chainId, r.am, r.roleId)} />
                        <span className="font-mono text-[11px] text-muted">
                          {r.delay ? fmtDelay(r.delay) : "immediate"}
                        </span>
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </Panel>
          );
        })}
      </div>
    </>
  );
}
