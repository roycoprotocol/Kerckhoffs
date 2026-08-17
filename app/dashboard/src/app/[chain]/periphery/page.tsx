import { chainBySlug } from "@/config/chains";
import type { Label } from "@/model";
import { allLabels } from "@/lib/labels";
import { fetchMakinaSlots } from "@/lib/makina";
import { humanize } from "@/lib/format";
import { AddressLabel, AddrLink } from "@/components/AddressLabel";
import { AmBadge, Empty, Eyebrow, Mono, PageTitle, Panel, Table, Td, Th } from "@/components/ui";

export const dynamic = "force-dynamic";

// Peripheral (non-market) protocol contracts: control plane, entry points, syncer, agents and
// the Makina strategy stacks — everything from the catalog, with live Makina governance slots.
const GROUPS: { category: string; title: string }[] = [
  { category: "factory", title: "Control plane" },
  { category: "entrypoint", title: "Entry points" },
  { category: "syncer", title: "Syncers" },
  { category: "agent", title: "Agents" },
  { category: "strategy", title: "Strategies (Makina)" },
];

export default async function PeripheryPage({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  const cfg = chainBySlug(chain)!;

  const labels = allLabels(cfg.chainId);
  const groups = GROUPS.map((g) => ({
    ...g,
    entries: labels
      .filter((l) => l.category === g.category)
      .sort((a, b) => a.name.localeCompare(b.name)),
  })).filter((g) => g.entries.length > 0);

  const makinaSlots = await fetchMakinaSlots(cfg.chainId).catch(() => []);

  const total = groups.reduce((n, g) => n + g.entries.length, 0);

  return (
    <>
      <PageTitle
        eyebrow={`Periphery · ${cfg.name}`}
        accent="Peripheral"
        title="contracts."
        subtitle={`${total} non-market protocol contracts — control plane, entry points, syncers, agents and strategy stacks.`}
      />
      {groups.length === 0 ? (
        <Empty>No peripheral contracts in the catalog for {cfg.name}.</Empty>
      ) : (
        groups.map((g) => (
          <div key={g.category} className="mt-7">
            <Eyebrow className="mb-2.5">{g.title}</Eyebrow>
            <Panel>
              <Table>
                {g.entries.map((l: Label) => (
                  <tr key={l.address}>
                    <Td className="w-72 text-[13px] font-medium">
                      <AddressLabel chainId={cfg.chainId} slug={chain} address={l.address} />
                    </Td>
                    <Td className="w-40 text-[12.5px] text-muted">{l.subtype ? humanize(l.subtype) : ""}</Td>
                    <Td className="w-24">{l.manager && <AmBadge kind={l.manager} />}</Td>
                    <Td>
                      <AddrLink chainId={cfg.chainId} address={l.address} />
                    </Td>
                  </tr>
                ))}
              </Table>
            </Panel>
          </div>
        ))
      )}

      {makinaSlots.length > 0 && (
        <div className="mt-7">
          <Eyebrow className="mb-2.5">Makina governance slots · live RPC</Eyebrow>
          <Panel>
            <Table head={<><Th>Vault</Th><Th>Slot</Th><Th>Current holder</Th></>}>
              {makinaSlots.map((s) => (
                <tr key={`${s.vault}-${s.slot}`}>
                  <Td className="w-52 text-[13px] font-medium">{s.vault}</Td>
                  <Td className="w-64">
                    <Mono className="text-muted">{s.slot}</Mono>
                  </Td>
                  <Td>
                    {s.actual ? (
                      <span className="inline-flex items-center gap-2.5">
                        <AddressLabel chainId={cfg.chainId} slug={chain} address={s.actual} />
                        <AddrLink chainId={cfg.chainId} address={s.actual} short />
                      </span>
                    ) : (
                      <span className="text-xs text-muted">unreadable</span>
                    )}
                  </Td>
                </tr>
              ))}
            </Table>
          </Panel>
        </div>
      )}
    </>
  );
}
