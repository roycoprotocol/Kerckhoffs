import { redirect } from "next/navigation";

// Chain root -> Overview.
export default async function ChainRoot({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  redirect(`/${chain}/overview`);
}
