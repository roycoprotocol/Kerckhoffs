import { chainBySlug } from "@/config/chains";
import { SearchPanel } from "@/components/SearchPanel";
import { Eyebrow } from "@/components/ui";

export const dynamic = "force-dynamic";

// Search-first entry point: jump to the live state of any contract or role. The address page
// renders arbitrary contracts (roles held + gated functions on both AMs), so a pasted 0x address
// always resolves.
export default async function SearchPage({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  const cfg = chainBySlug(chain)!;

  return (
    <div>
      <div className="text-center">
        <Eyebrow>Search · {cfg.name}</Eyebrow>
        <h1 className="mt-2 font-serif text-[34px] font-semibold leading-tight">
          <span className="text-ok">Inspect</span> any contract or role.
        </h1>
      </div>
      <SearchPanel chainId={cfg.chainId} slug={chain} />
    </div>
  );
}
