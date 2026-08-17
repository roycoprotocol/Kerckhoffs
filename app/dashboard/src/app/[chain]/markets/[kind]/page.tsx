import { notFound } from "next/navigation";
import { parseAmKind } from "@/lib/catalog";
import type { SearchParams } from "@/lib/searchParams";
import { MarketsPage, marketsSupported } from "../shared";

export const dynamic = "force-dynamic";

export default async function MarketsListPage(props: {
  params: Promise<{ chain: string; kind: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { chain, kind: kindRaw } = await props.params;
  const kind = parseAmKind(kindRaw);
  if (!kind || !marketsSupported(chain, kind)) notFound();
  return MarketsPage({
    kind,
    title: `${kind === "dawn" ? "Dawn" : "Day"} Markets`,
    params: Promise.resolve({ chain }),
    searchParams: props.searchParams,
  });
}
