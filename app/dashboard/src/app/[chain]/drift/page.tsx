import { redirect } from "next/navigation";

// Legacy URL — the drift view was removed (state is presented as-is); land on the AM roles view.
export default async function LegacyDriftRedirect({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  redirect(`/${chain}/am/dawn`);
}
