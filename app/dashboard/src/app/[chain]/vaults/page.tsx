import { chainBySlug } from "@/config/chains";
import { shorten } from "@/lib/catalog";
import { fetchMakinaSlots } from "@/lib/makina";
import { buildVaultViews } from "@/lib/vaults";
import { includesCI, param, type SearchParams } from "@/lib/searchParams";
import { AddressLabel, AddrLink } from "@/components/AddressLabel";
import { Filters } from "@/components/Filters";
import { AmBadge, Empty, Mono, PageTitle, Panel, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

// Concrete vaults + their Makina stacks. Each vault shows the AccessManager that currently
// controls it — derived from which AM has its contracts registered as targets, so a vault
// mid-migration (registered on both) surfaces as "migrating".
export default async function VaultsPage({
  params,
  searchParams,
}: {
  params: Promise<{ chain: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain } = await params;
  const sp = await searchParams;
  const cfg = chainBySlug(chain)!;
  const q = param(sp, "q");
  const amFilter = param(sp, "am");

  const [vaults, makina] = await Promise.all([buildVaultViews(cfg.chainId), fetchMakinaSlots(cfg.chainId)]);

  const shown = vaults.filter((v) => {
    if (amFilter && v.controlling !== amFilter) return false;
    if (q && !(includesCI(v.name, q) || v.contracts.some((c) => includesCI(c.name, q) || includesCI(c.address, q))))
      return false;
    return true;
  });

  return (
    <>
      <PageTitle
        title="Vaults"
        subtitle={`${vaults.length} vault stacks (Concrete + Makina) · controlling AM derived from live target registrations`}
      />
      <Filters
        searchPlaceholder="Search vault or address…"
        selects={[
          {
            key: "am",
            label: "controlled by",
            options: [
              { value: "dawn", label: "Dawn AM" },
              { value: "day", label: "Day AM" },
              { value: "migrating", label: "migrating" },
            ],
          },
        ]}
      />
      {shown.length === 0 ? (
        <Empty>
          {vaults.length === 0
            ? `No vaults on ${cfg.name} — Concrete vaults and Makina stacks are mainnet-only today.`
            : "No vaults match."}
        </Empty>
      ) : (
        <div className="space-y-4">
          {shown.map((v) => {
            const slots = v.kind === "makina" ? makina.filter((m) => m.vault === v.name) : [];
            return (
              <Panel key={`${v.name}-${v.kind}`}>
                <div className="flex items-center gap-2 border-b border-border px-3 py-2">
                  <span className="font-medium">{v.name}</span>
                  <span className="text-[11px] text-muted">{v.kind === "concrete" ? "Concrete vault" : "Makina stack"}</span>
                  <AmBadge kind={v.controlling} />
                </div>
                <Table head={<><Th>Contract</Th><Th>Type</Th><Th>Address</Th></>}>
                  {v.contracts.map((c) => (
                    <tr key={c.address} className="border-b border-border/50">
                      <Td>
                        <AddressLabel chainId={cfg.chainId} slug={chain} address={c.address} />
                      </Td>
                      <Td className="text-muted">{c.subtype ?? "—"}</Td>
                      <Td>
                        <AddrLink chainId={cfg.chainId} address={c.address} short />
                      </Td>
                    </tr>
                  ))}
                </Table>
                {slots.length > 0 && (
                  <div className="border-t border-border px-3 py-2">
                    <div className="mb-1 text-[11px] uppercase tracking-wide text-muted">Makina governance slots</div>
                    <ul className="space-y-1 text-sm">
                      {slots.map((s) => (
                        <li key={s.slot} className="flex flex-wrap items-center gap-2">
                          <span className="text-muted">{s.slot}:</span>
                          {s.actual ? <AddrLink chainId={cfg.chainId} address={s.actual} short /> : <Mono>unreadable</Mono>}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </Panel>
            );
          })}
        </div>
      )}
    </>
  );
}
