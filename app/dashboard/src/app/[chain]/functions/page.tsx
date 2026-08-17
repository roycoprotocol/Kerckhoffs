import { redirect } from "next/navigation";

// Legacy pre-dual-AM URL — the function map is now AM-scoped.
export default async function LegacyFunctionsRedirect({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  redirect(`/${chain}/am/dawn/functions`);
}
