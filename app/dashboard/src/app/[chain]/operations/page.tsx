import { redirect } from "next/navigation";

// Legacy pre-dual-AM URL — pending operations are now AM-scoped.
export default async function LegacyOperationsRedirect({ params }: { params: Promise<{ chain: string }> }) {
  const { chain } = await params;
  redirect(`/${chain}/am/dawn/operations`);
}
